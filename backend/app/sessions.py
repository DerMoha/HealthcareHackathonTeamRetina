"""Scenario loading and the in-memory session store (no database)."""
import json
import os
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

from .models import CasePublic


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def scenarios_dir() -> Path:
    env = os.environ.get("MEDSIM_SCENARIOS_DIR")
    return Path(env) if env else Path(__file__).resolve().parents[2] / "scenarios"


def load_scenarios() -> dict[str, dict]:
    """Raw scenario dicts by case_id (includes `hidden`; never return these directly)."""
    out = {}
    for path in sorted(scenarios_dir().glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        out[data["case_id"]] = data
    return out


def public_case(s: dict) -> CasePublic:
    """Whitelist of visible fields: no zone `result`, no `hidden`."""
    return CasePublic(
        case_id=s["case_id"], title=s["title"], learner_brief=s["learner_brief"],
        patient=s["patient"], voice_context=s["voice_context"],
        zones=[{k: z[k] for k in ("id", "label", "attach_to", "offset", "radius")}
               for z in s["examination_zones"]],
        scripted_dialogue=s["scripted_dialogue"],
        investigations=[{"id": i["id"], "label": i["label"]} for i in s.get("investigations", [])],
    )


@dataclass
class Session:
    id: str
    case_id: str
    started_at: str = field(default_factory=now_iso)
    seq: int = 0  # shared by interactions and examinations
    interactions: list[dict] = field(default_factory=list)  # seq, role, text, timestamp
    examinations: list[dict] = field(default_factory=list)  # seq, zone_id, action, pain_level
    investigations: list[dict] = field(default_factory=list)  # seq, investigation_id, ordered_at
    diagnosis: str | None = None
    notes: dict | None = None  # see models.Notes (set on diagnose)

    def next_seq(self) -> int:
        self.seq += 1
        return self.seq

    def reset(self) -> None:
        self.__init__(self.id, self.case_id)  # type: ignore[misc]


SESSIONS: dict[str, Session] = {}


def create_session(case_id: str) -> Session:
    s = Session(uuid.uuid4().hex, case_id)
    SESSIONS[s.id] = s
    return s
