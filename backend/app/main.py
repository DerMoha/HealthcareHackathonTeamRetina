"""FastAPI app: routes only; logic lives in sessions/examination/evaluation."""
import os
from pathlib import Path

import httpx
from fastapi import FastAPI, HTTPException

from . import evaluation, examination
from .models import (DiagnoseRequest, ExamineRequest, ExamineResult, Feedback, Health,
                     InteractionCount, InteractionRequest, SessionCreate, SessionInfo,
                     TokenResponse, CasePublic)
from .sessions import SESSIONS, Session, create_session, load_scenarios, now_iso, public_case

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


def _session(session_id: str) -> Session:
    s = SESSIONS.get(session_id)
    if s is None:
        raise HTTPException(404, f"Unknown session '{session_id}'")
    return s


def _info(s: Session) -> SessionInfo:
    return SessionInfo(session_id=s.id, started_at=s.started_at, case=public_case(SCENARIOS[s.case_id]))


@app.get("/health", response_model=Health)
def health():
    return Health(status="ok", version=VERSION, cases=len(SCENARIOS))


@app.get("/cases", response_model=list[CasePublic])
def cases():
    return [public_case(s) for s in SCENARIOS.values()]


@app.post("/sessions", response_model=SessionInfo, status_code=201)
def new_session(req: SessionCreate):
    if req.case_id not in SCENARIOS:
        raise HTTPException(404, f"Unknown case '{req.case_id}'")
    return _info(create_session(req.case_id))


@app.post("/sessions/{session_id}/reset", response_model=SessionInfo)
def reset(session_id: str):
    s = _session(session_id)
    s.reset()
    return _info(s)


@app.post("/sessions/{session_id}/examine", response_model=ExamineResult)
def examine(session_id: str, req: ExamineRequest):
    s = _session(session_id)
    result = examination.examine(SCENARIOS[s.case_id], s, req.body_part, req.action)
    if result is None:
        raise HTTPException(404, f"Unknown examination zone '{req.body_part}'")
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
