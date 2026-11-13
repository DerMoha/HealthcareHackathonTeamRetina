"""Routes for MedSim Studio, the scenario library, the Live Director and the debrief."""
import asyncio
import uuid

from fastapi import APIRouter, Body, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field

from . import assist, director, studio, tracelog
from .sessions import SESSIONS, Session
from .studio import ReviewRequest, ScenarioConfig, ScenarioDefinition, StudioError


class StateRequest(BaseModel):
    state: str


class DirectorEvent(BaseModel):
    event_id: str = Field(default_factory=lambda: uuid.uuid4().hex, min_length=1, max_length=64)
    kind: str
    params: dict = {}


def build(scenarios: dict[str, dict]) -> APIRouter:
    router = APIRouter()
    library = studio.Library(scenarios)

    def guard(call, *args):
        try:
            return call(*args)
        except StudioError as e:
            raise HTTPException(e.status, e.detail)

    def live_session(session_id: str) -> Session:
        s = SESSIONS.get(session_id)
        if s is None:
            raise HTTPException(404, f"Unknown session '{session_id}'")
        if s.id not in studio.LIVE:
            raise HTTPException(409, "This session runs the fixed default case. Launch a published scenario to use the director.")
        return s

    def summary(d: ScenarioDefinition) -> dict:
        return {"code": d.code, "scenario_id": d.scenario_id, "version": d.version, "title": d.title,
                "description": d.narrative["description"], "review_state": d.review.state,
                "environment": d.environment["label"], "difficulty": d.difficulty["label"],
                "crowdedness": d.environment["crowd"]["label"], "case_id": d.source_template["case_id"],
                "kind": "journey" if d.journey else "single",
                "stages": [st["label"] for st in (d.journey or {}).get("stages", [])]}

    # Authoring
    @router.get("/studio/catalog")
    def catalog():
        return studio.catalog(scenarios)

    @router.post("/studio/validate")
    def validate(config: ScenarioConfig):
        issues = studio.validate(config, scenarios)
        return {"valid": not any(i.severity == "error" for i in issues), "issues": issues}

    @router.post("/studio/preview", response_model=ScenarioDefinition)
    def preview(config: ScenarioConfig):
        """The ScenarioDefinition this configuration would produce; nothing is saved."""
        return guard(studio.generate, config, scenarios, "scn_preview")

    @router.post("/studio/assist", response_model=assist.AssistResult)
    def assist_draft(req: assist.AssistRequest):
        return guard(assist.draft, req, scenarios)

    # Library
    @router.get("/studio/scenarios")
    def list_scenarios():
        return library.list()

    @router.post("/studio/scenarios", response_model=ScenarioDefinition, status_code=201)
    def create(config: ScenarioConfig):
        return guard(library.create, config)

    @router.post("/studio/import", response_model=ScenarioDefinition, status_code=201)
    def import_scenario(document: dict = Body(...)):
        return guard(library.import_, document)

    @router.post("/studio/marketplace/{code}/download", response_model=ScenarioDefinition, status_code=201)
    def download(code: str):
        return guard(library.download, code)

    @router.get("/studio/scenarios/{scenario_id}", response_model=ScenarioDefinition)
    def get(scenario_id: str, version: int | None = None):
        return guard(library.get, scenario_id, version)

    @router.get("/studio/scenarios/{scenario_id}/versions")
    def versions(scenario_id: str):
        return guard(library.history, scenario_id)

    @router.put("/studio/scenarios/{scenario_id}", response_model=ScenarioDefinition)
    def update(scenario_id: str, config: ScenarioConfig):
        return guard(library.update, scenario_id, config)

    @router.post("/studio/scenarios/{scenario_id}/duplicate", response_model=ScenarioDefinition, status_code=201)
    def duplicate(scenario_id: str):
        return guard(library.duplicate, scenario_id)

    @router.post("/studio/scenarios/{scenario_id}/state", response_model=ScenarioDefinition)
    def set_state(scenario_id: str, req: StateRequest):
        return guard(library.set_state, scenario_id, req.state)

    @router.post("/studio/scenarios/{scenario_id}/review", response_model=ScenarioDefinition)
    def review(scenario_id: str, req: ReviewRequest):
        return guard(library.review, scenario_id, req)

    @router.post("/studio/scenarios/{scenario_id}/publish", response_model=ScenarioDefinition)
    def publish(scenario_id: str):
        return guard(library.publish, scenario_id, True)

    @router.post("/studio/scenarios/{scenario_id}/unpublish", response_model=ScenarioDefinition)
    def unpublish(scenario_id: str):
        return guard(library.publish, scenario_id, False)

    # Launch (used by the Vision Pro app)
    @router.get("/scenarios/published")
    def published():
        return [summary(d) for d in library.published()]

    @router.get("/scenarios/launch/{code}")
    def launch(code: str):
        return summary(guard(library.by_code, code))

    # Director
    @router.get("/sessions/active")
    def active():
        """Sessions that run a scenario, newest first, for the director panel."""
        rows = [{"session_id": sid, "started_at": SESSIONS[sid].started_at, "title": live.definition.title,
                 "code": live.definition.code, "runtime_connected": bool(director._sockets(sid, "runtime")),
                 "submitted": SESSIONS[sid].diagnosis is not None}
                for sid, live in studio.LIVE.items() if sid in SESSIONS]
        return sorted(rows, key=lambda r: r["started_at"], reverse=True)

    @router.get("/sessions/{session_id}/director")
    def director_state(session_id: str):
        s = live_session(session_id)
        return director.state(scenarios[s.case_id], s)

    @router.post("/sessions/{session_id}/director/events")
    async def director_event(session_id: str, event: DirectorEvent):
        s = live_session(session_id)
        result = await director.submit(scenarios[s.case_id], s, event.event_id, event.kind, event.params)
        if not result["accepted"]:
            raise HTTPException(409, result["reason"])
        return result

    @router.get("/sessions/{session_id}/hint")
    def hint(session_id: str):
        return director.next_hint(live_session(session_id))

    @router.get("/sessions/{session_id}/debrief")
    def debrief(session_id: str):
        s = SESSIONS.get(session_id)
        if s is None:
            raise HTTPException(404, f"Unknown session '{session_id}'")
        return director.debrief(scenarios[s.case_id], s)

    @router.websocket("/ws/sessions/{session_id}")
    async def socket(ws: WebSocket, session_id: str, role: str = "director"):
        s = SESSIONS.get(session_id)
        if s is None or s.id not in studio.LIVE or role not in ("runtime", "director"):
            await ws.close(code=4404)
            return
        scenario = scenarios[s.case_id]
        await ws.accept()
        await director.connect(scenario, s, role, ws)
        try:
            while True:
                try:  # directors also get the student's progress, which arrives over HTTP
                    msg = await asyncio.wait_for(ws.receive_json(), timeout=2.0 if role == "director" else None)
                except asyncio.TimeoutError:
                    await ws.send_json({"type": "state", **director.state(scenario, s)})
                    continue
                tracelog.event("ws_in", session_id=s.id, role=role, message=msg)
                if msg.get("type") == "ack" and role == "runtime":
                    await director.acknowledge(scenario, s, str(msg.get("event_id")), bool(msg.get("applied")),
                                               str(msg.get("detail", ""))[:200])
                elif msg.get("type") == "event" and role == "director":
                    try:
                        event = DirectorEvent(**{k: msg[k] for k in ("event_id", "kind", "params") if k in msg})
                    except Exception:  # noqa: BLE001 - malformed frame from a client
                        await ws.send_json({"type": "rejected", "event_id": msg.get("event_id"), "reason": "Malformed event."})
                        continue
                    result = await director.submit(scenario, s, event.event_id, event.kind, event.params)
                    if not result["accepted"]:
                        await ws.send_json({"type": "rejected", "event_id": event.event_id, "reason": result["reason"]})
        except (WebSocketDisconnect, RuntimeError):
            pass
        finally:
            await director.disconnect(scenario, s, role, ws)

    return router, library
