"""Scenario loading and the in-memory session store (no database)."""
import json
import os
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

from .models import CaseCatalog, CasePublic, JourneyInfo, SessionConfig, UltrasoundInfo


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


def catalog_of(s: dict) -> CaseCatalog | None:
    """Whitelisted dashboard metadata with defaults applied, or None for a case without `catalog`.
    Mirrors CaseCatalog in visionos/MedSimXR/Models/Contracts.swift."""
    raw = s.get("catalog")
    if raw is None:
        return None
    moods = raw.get("allowed_moods") or ["calm"]
    avatars = raw.get("allowed_avatars") or ["male"]
    mood = raw.get("default_mood")
    avatar = raw.get("default_avatar")
    return CaseCatalog(
        summary=raw.get("summary", ""), icon=raw.get("icon"), setting=raw.get("setting"),
        skills=raw.get("skills", []), allowed_moods=moods, allowed_avatars=avatars,
        default_mood=mood if mood in moods else moods[0],
        default_avatar=avatar if avatar in avatars else avatars[0],
        avatar_model=raw.get("avatar_model"),
    )


def ultrasound_of(s: dict) -> UltrasoundInfo | None:
    """Public scan regions (id, label, anchor, radius), or None for a case without ultrasound.
    Which views a region yields is never exposed."""
    us = s.get("ultrasound")
    if us is None:
        return None
    return UltrasoundInfo(regions=[{k: r[k] for k in ("id", "label", "attach_to", "radius")} for r in us["regions"]])


def journey_of(s: dict) -> JourneyInfo | None:
    """Public team and places of a journey case: no responses, results or prerequisites (journey.py)."""
    j = s.get("journey")
    if j is None:
        return None
    names = {m["id"]: m["name"] for m in j["team"]}
    return JourneyInfo(
        team=[{k: m[k] for k in ("id", "name", "role")} for m in j["team"]],
        stages=[{"id": st["id"], "label": st["label"], "setting": st["setting"], "brief": st["brief"],
                 "team": st["team"], "noise": st.get("noise", 0.0),
                 "arrival": [{"member": a["member"], "speaker": names.get(a["member"], a["member"]), "text": a["text"]}
                             for a in st.get("arrival", [])],
                 "actions": [{k: a[k] for k in ("id", "label", "member")} for a in st["actions"]],
                 "investigations": st.get("investigations", [])} for st in j["stages"]])


def resolve_config(s: dict, mood: str | None, avatar: str | None) -> SessionConfig:
    """Requested values validated against the case; omitted ones come from the case defaults.
    Raises ValueError (-> HTTP 422) for a value the case does not allow."""
    cat = catalog_of(s) or CaseCatalog()
    mood = mood or cat.default_mood
    avatar = avatar or cat.default_avatar
    if mood not in cat.allowed_moods:
        raise ValueError(f"Mood '{mood}' is not available for this case. Allowed: {', '.join(cat.allowed_moods)}.")
    if avatar not in cat.allowed_avatars:
        raise ValueError(f"Avatar '{avatar}' is not available for this case. Allowed: {', '.join(cat.allowed_avatars)}.")
    return SessionConfig(mood=mood, avatar=avatar)


def voice_context_for(s: dict, config: SessionConfig) -> str:
    """Case facts plus how the patient comes across. Must stay identical to
    OfflineClinicalEngine.voiceContext(for:) (backend/tests/fixtures/session_config_expected.json)."""
    persona = s.get("persona", {})
    lines = [t for t in (persona.get("avatars", {}).get(config.avatar), persona.get("moods", {}).get(config.mood)) if t]
    if not lines:
        return s["voice_context"]
    return (s["voice_context"] + "\n\nHOW YOU COME ACROSS (manner only; it never changes the facts above):\n"
            + "\n".join(f"- {t}" for t in lines))


def dialogue_for(s: dict, config: SessionConfig) -> list[dict]:
    """Scripted lines with the patient's mood-specific wording where the case has one."""
    return [{"id": d["id"], "learner": d["learner"], "patient": d.get("patient_by_mood", {}).get(config.mood, d["patient"])}
            for d in s["scripted_dialogue"]]


def public_case(s: dict, config: SessionConfig | None = None) -> CasePublic:
    """Whitelist of visible fields: no zone `result`, no `hidden`, no `persona`.
    With a session `config`, voice context and scripted lines carry the patient's mood."""
    return CasePublic(
        case_id=s["case_id"], title=s["title"], learner_brief=s["learner_brief"],
        patient=s["patient"],
        voice_context=voice_context_for(s, config) if config else s["voice_context"],
        zones=[{k: z[k] for k in ("id", "label", "attach_to", "offset", "radius")}
               for z in s["examination_zones"]],
        scripted_dialogue=dialogue_for(s, config) if config else [
            {k: d[k] for k in ("id", "learner", "patient")} for d in s["scripted_dialogue"]],
        orthotics=s.get("orthotics", {}),
        investigations=[{"id": i["id"], "label": i["label"]} for i in s.get("investigations", [])],
        catalog=catalog_of(s),
        ultrasound=ultrasound_of(s),
        journey=journey_of(s),
    )


@dataclass
class Session:
    id: str
    case_id: str
    config: SessionConfig | None = None
    started_at: str = field(default_factory=now_iso)
    seq: int = 0  # shared by interactions and examinations
    interactions: list[dict] = field(default_factory=list)  # seq, role, text, timestamp
    examinations: list[dict] = field(default_factory=list)  # seq, zone_id, action, pain_level
    investigations: list[dict] = field(default_factory=list)  # seq, investigation_id, ordered_at
    measurements: list[dict] = field(default_factory=list)  # seq, measurement_id, value_cm
    fittings: list[dict] = field(default_factory=list)      # seq, fit (dict or None = removed)
    checks: list[dict] = field(default_factory=list)        # seq, check
    gels: list[dict] = field(default_factory=list)          # seq
    scans: list[dict] = field(default_factory=list)         # seq, region_id, view_id (or None), gel, quality
    stages: list[dict] = field(default_factory=list)        # seq, stage_id (moves after the first stage)
    team_actions: list[dict] = field(default_factory=list)  # seq, stage_id, action_id, done
    diagnosis: str | None = None
    notes: dict | None = None  # see models.Notes (set on diagnose)

    def next_seq(self) -> int:
        self.seq += 1
        return self.seq

    def reset(self) -> None:
        self.__init__(self.id, self.case_id, self.config)  # type: ignore[misc]


SESSIONS: dict[str, Session] = {}


def create_session(case_id: str, config: SessionConfig | None = None) -> Session:
    s = Session(uuid.uuid4().hex, case_id, config)
    SESSIONS[s.id] = s
    return s
