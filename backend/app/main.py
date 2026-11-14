"""FastAPI app: routes only; logic lives in sessions/examination/evaluation."""
import os
import re
import time
from pathlib import Path

import httpx
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.staticfiles import StaticFiles
from starlette.concurrency import run_in_threadpool

from . import director, evaluation, examination, fitting, journey, studio, studio_routes, tracelog, ultrasound
from .models import (ConversationSummary, DiagnoseRequest, ExamineRequest, ExamineResult, Feedback, Health,
                     InteractionCount, InteractionRequest, FitAck, FitRequest, FittingCheckRequest,
                     FittingCheckResult, GelResult, MeasurementRequest, ScanRequest, ScanResult, MeasurementResult, InvestigationRequest, InvestigationResult, SessionCreate, SessionInfo,
                     StageRequest, StageResult, TeamActionRequest, TeamActionResult,
                     TokenResponse, TranscriptionResponse, CasePublic, VoiceUsage)
from .sessions import SESSIONS, Session, create_session, load_scenarios, now_iso, public_case, resolve_config

VERSION = "0.1.0"


def _load_dotenv() -> None:
    """Tiny .env reader (repo root); real environment variables win."""
    path = Path(__file__).resolve().parents[2] / ".env"
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip("\"'"))


_load_dotenv()
SCENARIOS = load_scenarios()
app = FastAPI(title="MedSim XR clinical backend", version=VERSION)
_studio_router, LIBRARY = studio_routes.build(SCENARIOS)
app.include_router(_studio_router)
_STUDIO_UI = Path(__file__).resolve().parents[2] / "studio" / "dist"
if _STUDIO_UI.is_dir():  # built instructor interface (cd studio && npm run build)
    app.mount("/app", StaticFiles(directory=_STUDIO_UI, html=True), name="studio-ui")


@app.middleware("http")
async def trace(request: Request, call_next):
    """Test-run trace (tracelog.py): request and response bodies, timing, and a session snapshot."""
    path = request.url.path
    if not tracelog.enabled() or path == "/health" or path.startswith("/app"):
        return await call_next(request)
    started = time.perf_counter()
    raw = await request.body()
    try:
        response = await call_next(request)
    except Exception as e:
        tracelog.event("http_error", method=request.method, path=path, error=f"{type(e).__name__}: {e}",
                       request=tracelog.body(raw, request.headers.get("content-type")))
        raise
    out = b"".join([chunk async for chunk in response.body_iterator])
    tracelog.event("http", method=request.method, path=path, query=str(request.url.query) or None,
                   client=request.client.host if request.client else None, status=response.status_code,
                   ms=round((time.perf_counter() - started) * 1000, 1),
                   request=tracelog.body(raw, request.headers.get("content-type")),
                   response=tracelog.body(out, response.headers.get("content-type")))
    m = re.match(r"/sessions/([^/]+)", path)
    s = SESSIONS.get(m.group(1)) if m else None
    if s is not None:  # after diagnosis the snapshot also keeps the scored debrief
        tracelog.snapshot(s, studio.LIVE.get(s.id),
                          debrief=director.debrief(SCENARIOS[s.case_id], s) if s.diagnosis is not None else None)
    return Response(out, status_code=response.status_code, headers=dict(response.headers),
                    media_type=response.media_type)


def _session(session_id: str) -> Session:
    s = SESSIONS.get(session_id)
    if s is None:
        raise HTTPException(404, f"Unknown session '{session_id}'")
    return s


def _info(s: Session) -> SessionInfo:
    info = SessionInfo(session_id=s.id, started_at=s.started_at, case=public_case(SCENARIOS[s.case_id], s.config),
                       config=s.config)
    live = studio.LIVE.get(s.id)
    if live:  # a published scenario: its setting and equipment, same clinical case
        info.case, info.scenario = studio.shape_case(info.case, live), studio.runtime(live).model_dump()
    return info


def _need(s: Session, kind: str, ref: str | None, what: str) -> None:
    if not studio.allowed(s.id, kind, ref):
        raise HTTPException(409, f"{what} is not available in this scenario.")


@app.get("/health", response_model=Health)
def health():
    return Health(status="ok", version=VERSION, cases=len(SCENARIOS))


@app.get("/cases", response_model=list[CasePublic])
def cases():
    return [public_case(s) for s in SCENARIOS.values()]


@app.post("/sessions", response_model=SessionInfo, status_code=201)
def new_session(req: SessionCreate):
    definition = None
    if req.scenario_code:
        try:
            definition = LIBRARY.by_code(req.scenario_code)
        except studio.StudioError as e:
            raise HTTPException(e.status, e.detail)
    case_id = definition.source_template["case_id"] if definition else req.case_id
    if case_id not in SCENARIOS:
        raise HTTPException(404, f"Unknown case '{case_id}'")
    asked = req.config
    try:
        config = resolve_config(SCENARIOS[case_id], asked.mood if asked else None, asked.avatar if asked else None)
    except ValueError as e:
        raise HTTPException(422, str(e))
    s = create_session(case_id, config)
    if definition:
        studio.attach(s.id, definition)
    return _info(s)


@app.post("/sessions/{session_id}/reset", response_model=SessionInfo)
def reset(session_id: str):
    s = _session(session_id)
    s.reset()
    studio.reset(s.id)
    return _info(s)


@app.post("/sessions/{session_id}/examine", response_model=ExamineResult)
def examine(session_id: str, req: ExamineRequest):
    s = _session(session_id)
    result = examination.examine(SCENARIOS[s.case_id], s, req.body_part, req.action)
    if result is None:
        raise HTTPException(404, f"Unknown examination zone '{req.body_part}'")
    return result


@app.post("/sessions/{session_id}/investigations", response_model=InvestigationResult)
def investigations(session_id: str, req: InvestigationRequest):
    s = _session(session_id)
    _need(s, "investigation", req.investigation_id, "That investigation")
    blocked = journey.investigation_error(SCENARIOS[s.case_id], s, req.investigation_id)
    if blocked:
        raise HTTPException(409, blocked)
    result = examination.investigate(SCENARIOS[s.case_id], s, req.investigation_id)
    if result is None:
        raise HTTPException(404, f"Unknown investigation '{req.investigation_id}'")
    return result


@app.post("/sessions/{session_id}/stage", response_model=StageResult)
def stage(session_id: str, req: StageRequest):
    s = _session(session_id)
    try:
        return journey.advance(SCENARIOS[s.case_id], s, req.stage_id)
    except journey.JourneyError as e:
        raise HTTPException(e.status, e.detail)


@app.post("/sessions/{session_id}/team-actions", response_model=TeamActionResult)
def team_actions(session_id: str, req: TeamActionRequest):
    s = _session(session_id)
    try:
        return journey.team_action(SCENARIOS[s.case_id], s, req.action_id)
    except journey.JourneyError as e:
        raise HTTPException(e.status, e.detail)


@app.post("/sessions/{session_id}/measurements", response_model=MeasurementResult)
def measurements(session_id: str, req: MeasurementRequest):
    s = _session(session_id)
    _need(s, "measurement_tool", None, "A measuring tape")
    result = fitting.measure(SCENARIOS[s.case_id], s, req.measurement_id, req.value_cm)
    if result is None:
        raise HTTPException(404, f"Unknown measurement '{req.measurement_id}'")
    if not result:
        raise HTTPException(422, f"Measurement '{req.measurement_id}' needs value_cm from the avatar")
    return result


@app.post("/sessions/{session_id}/fitting", response_model=FitAck)
def fit(session_id: str, req: FitRequest):
    s = _session(session_id)
    data = req.fit.model_dump() if req.fit else None
    if data:
        _need(s, "orthosis_size", data["size"], "That wrist support")
    if not fitting.valid(SCENARIOS[s.case_id], data):
        raise HTTPException(404, "Unknown orthosis size or tightness")
    return fitting.record_fit(SCENARIOS[s.case_id], s, data)


@app.post("/sessions/{session_id}/checks", response_model=FittingCheckResult)
def checks(session_id: str, req: FittingCheckRequest):
    s = _session(session_id)
    return fitting.check(SCENARIOS[s.case_id], s, req.check)


@app.post("/sessions/{session_id}/gel", response_model=GelResult)
def gel(session_id: str):
    s = _session(session_id)
    result = ultrasound.apply_gel(SCENARIOS[s.case_id], s)
    if result is None:
        raise HTTPException(404, "This case has no ultrasound")
    return result


@app.post("/sessions/{session_id}/scans", response_model=ScanResult)
def scans(session_id: str, req: ScanRequest):
    s = _session(session_id)
    result = ultrasound.scan(SCENARIOS[s.case_id], s, req.region_id, req.gel_applied)
    if result is None:
        raise HTTPException(404, f"Unknown scan region '{req.region_id}'")
    return result


@app.post("/sessions/{session_id}/interactions", response_model=InteractionCount)
def interactions(session_id: str, req: InteractionRequest):
    s = _session(session_id)
    ts = req.timestamp.isoformat() if req.timestamp else now_iso()
    s.interactions.append({"seq": s.next_seq(), "role": req.role, "text": req.text, "timestamp": ts})
    return InteractionCount(count=len(s.interactions))


@app.post("/sessions/{session_id}/diagnose", response_model=Feedback)
def diagnose(session_id: str, req: DiagnoseRequest):
    s = _session(session_id)
    s.diagnosis = req.diagnosis
    s.notes = req.notes.model_dump() if req.notes else None
    return evaluation.evaluate(SCENARIOS[s.case_id], s)


@app.get("/sessions/{session_id}/feedback", response_model=Feedback)
def feedback(session_id: str):
    s = _session(session_id)
    return evaluation.evaluate(SCENARIOS[s.case_id], s)


@app.get("/elevenlabs/conversation-token", response_model=TokenResponse)
def conversation_token():
    key, agent = os.environ.get("ELEVENLABS_API_KEY"), os.environ.get("ELEVENLABS_AGENT_ID")
    if not key or not agent:
        raise HTTPException(503, "ElevenLabs is not configured: set ELEVENLABS_API_KEY and ELEVENLABS_AGENT_ID.")
    try:
        r = httpx.get("https://api.elevenlabs.io/v1/convai/conversation/token",
                      params={"agent_id": agent}, headers={"xi-api-key": key}, timeout=10)
    except httpx.HTTPError as e:
        raise HTTPException(502, f"Could not reach ElevenLabs ({type(e).__name__}).")
    if r.status_code != 200 or not r.json().get("token"):
        # Never echo the upstream body or key; status code is enough to debug.
        raise HTTPException(502, f"ElevenLabs rejected the token request (HTTP {r.status_code}).")
    return TokenResponse(token=r.json()["token"])


@app.get("/elevenlabs/usage", response_model=VoiceUsage)
def voice_usage():
    """Credits used and left on the ElevenLabs account, for the app's Settings. Needs only ELEVENLABS_API_KEY."""
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        raise HTTPException(503, "ElevenLabs is not configured: set ELEVENLABS_API_KEY.")
    try:
        r = httpx.get("https://api.elevenlabs.io/v1/user/subscription", headers={"xi-api-key": key}, timeout=10)
    except httpx.HTTPError as e:
        raise HTTPException(502, f"Could not reach ElevenLabs ({type(e).__name__}).")
    if r.status_code != 200:
        # Never echo the upstream body or key; status code is enough to debug.
        raise HTTPException(502, f"ElevenLabs rejected the usage request (HTTP {r.status_code}).")
    try:
        body = r.json()
        used, limit = int(body["character_count"]), int(body["character_limit"])
        reset = body.get("next_character_count_reset_unix")
        reset = int(reset) if reset is not None else None
    except (ValueError, KeyError, TypeError):
        raise HTTPException(502, "ElevenLabs sent an unexpected usage response.")
    tier = body.get("tier") if isinstance(body.get("tier"), str) else None
    return VoiceUsage(tier=tier, used=used, limit=limit, remaining=max(0, limit - used), next_reset_unix=reset)


_CONVERSATION_ID = re.compile(r"^[A-Za-z0-9_-]{1,128}$")
# ElevenLabs conversation status -> ours. Anything not finished yet is "pending".
_SUMMARY_STATUS = {"initiated": "pending", "in-progress": "pending", "processing": "pending",
                   "done": "done", "failed": "failed"}


@app.get("/elevenlabs/conversations/{conversation_id}/summary", response_model=ConversationSummary)
def conversation_summary(conversation_id: str):
    """ElevenLabs' generated summary of a finished voice conversation, for the notebook draft.

    Needs ELEVENLABS_API_KEY and ELEVENLABS_AGENT_ID (public agents too): the key reads the
    account's conversations, so only conversations of the configured agent are returned.
    """
    key, agent = os.environ.get("ELEVENLABS_API_KEY"), os.environ.get("ELEVENLABS_AGENT_ID")
    if not key or not agent:
        raise HTTPException(503, "ElevenLabs is not configured: set ELEVENLABS_API_KEY and ELEVENLABS_AGENT_ID.")
    if not _CONVERSATION_ID.match(conversation_id):
        raise HTTPException(422, "Invalid conversation id")
    try:
        r = httpx.get(f"https://api.elevenlabs.io/v1/convai/conversations/{conversation_id}/summary",
                      headers={"xi-api-key": key}, timeout=10)
    except httpx.HTTPError as e:
        raise HTTPException(502, f"Could not reach ElevenLabs ({type(e).__name__}).")
    if r.status_code == 404:
        raise HTTPException(404, f"Unknown conversation '{conversation_id}'")
    if r.status_code != 200:
        # Never echo the upstream body or key; status code is enough to debug.
        raise HTTPException(502, f"ElevenLabs rejected the summary request (HTTP {r.status_code}).")
    body = r.json()
    if body.get("agent_id") != agent:
        raise HTTPException(404, f"Unknown conversation '{conversation_id}'")
    status = _SUMMARY_STATUS.get(body.get("status"), "pending")
    summary = (body.get("transcript_summary") or "").strip() or None
    return ConversationSummary(status=status, summary=summary if status == "done" else None)


MAX_DICTATION_BYTES = 25 * 1024 * 1024


@app.post("/elevenlabs/transcribe", response_model=TranscriptionResponse)
async def transcribe(request: Request):
    """Notebook dictation: the raw audio body (e.g. audio/mp4) goes to ElevenLabs Scribe.
    Needs only ELEVENLABS_API_KEY. 503 tells the app to use Apple speech recognition instead."""
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        raise HTTPException(503, "ElevenLabs is not configured: set ELEVENLABS_API_KEY.")
    audio = await request.body()
    if not audio:
        raise HTTPException(400, "No audio received.")
    if len(audio) > MAX_DICTATION_BYTES:
        raise HTTPException(413, "Dictation too long.")
    content_type = request.headers.get("content-type") or "application/octet-stream"
    try:
        r = await run_in_threadpool(
            httpx.post, "https://api.elevenlabs.io/v1/speech-to-text",
            headers={"xi-api-key": key}, data={"model_id": "scribe_v2", "tag_audio_events": "false"},
            files={"file": ("dictation.m4a", audio, content_type)}, timeout=60)
    except httpx.HTTPError as e:
        raise HTTPException(502, f"Could not reach ElevenLabs ({type(e).__name__}).")
    if r.status_code != 200:
        raise HTTPException(502, f"ElevenLabs rejected the transcription request (HTTP {r.status_code}).")
    return TranscriptionResponse(text=(r.json().get("text") or "").strip())
