"""MedSim Studio: scenario authoring, the scenario library, and the runtime adapter.

A scenario is a CONFIGURATION of one reviewed clinical case (the "template"): where the
encounter happens, how hard it is, what equipment is there, who else is in the room.
It never contains or changes clinical ground truth: findings, investigation results, the
diagnosis and the rubric stay in scenarios/<case_id>.json and are read from there at runtime.
`clinical_rules.findings_sha256` pins the case content a scenario was generated against.

Everything selectable comes from backend/studio_templates/<template_id>.json. Anything else
is a validation error with a reason, never a silent substitution.

REVIEW STATES: draft -> experimental -> clinician_reviewed. Only `review()` with a named
reviewer and an explicit attestation sets clinician_reviewed. Every edit creates a new
version that starts as draft again. Imports always arrive as draft.

SCORING is not changed by a scenario. `assessability()` only reports which management and
fitting criteria cannot be earned with the resources of the scenario, so that a score can
be read against what was achievable.
"""
import hashlib
import json
import os
import random
import secrets
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, Field

from .evaluation import _hit
from .models import CasePublic
from .sessions import now_iso

TEMPLATES_DIR = Path(__file__).resolve().parents[1] / "studio_templates"
ReviewState = Literal["draft", "experimental", "clinician_reviewed"]
IMMUTABLE_FACTS = ["patient history (voice context)", "examination findings and pain levels",
                   "investigation results", "diagnosis", "fitting reference and outcomes", "scoring rubric"]


# MARK: Models

class Narrative(BaseModel):
    """Free text. Checked for clinical claims; never a source of findings or points."""
    description: str = Field("", max_length=600)
    patient_personality: str = Field("", max_length=300)
    bystander_lines: list[str] = Field(default_factory=list, max_length=6)
    source: Literal["template", "instructor", "llm"] = "template"


class ScenarioConfig(BaseModel):
    """What the instructor chooses. Every id must exist in the template."""
    template_id: str
    title: str = Field(min_length=3, max_length=80)
    environment: str
    difficulty: str
    crowdedness: str
    tools: list[str]
    bystander: str = "none"
    teammate: str = "none"
    learning_objectives: list[str]
    narrative: Narrative = Narrative()
    seed: int | None = Field(None, ge=0, le=2**31 - 1)


class Issue(BaseModel):
    field: str
    severity: Literal["error", "warning"]
    message: str


class Review(BaseModel):
    state: ReviewState = "draft"
    reviewer_name: str | None = None
    reviewer_role: str | None = None
    reviewed_at: str | None = None
    notes: str | None = None


class EquipmentItem(BaseModel):
    id: str
    label: str
    kind: str
    available: bool
    deliverable: bool           # not there at the start, but the instructor may have it delivered
    unsupported_reason: str | None = None


class DimensionRule(BaseModel):
    id: str
    title: str
    max_score: int
    achievable_max: int
    not_assessable: list[dict]  # id, label, points, reason


class ScenarioDefinition(BaseModel):
    schema_version: int = 1
    scenario_id: str
    version: int
    code: str
    title: str
    created_at: str
    source_template: dict       # template_id, case_id, case_schema_version
    seed: int
    review: Review = Review()
    published: bool = False
    config: ScenarioConfig
    environment: dict           # id, label, ambient_level, brief, setting_context, crowd{id,label,figures[]}
    resources: list[EquipmentItem]
    companions: dict            # bystander | None, teammate | None
    difficulty: dict            # id, label, hint_policy, hints[{id,text}]
    clinical_rules: dict        # case_id, immutable_facts, findings_sha256, statement, constraints[]
    assessment: dict            # dimensions[DimensionRule], learning_objectives[{id,label}], note
    narrative: dict             # description, patient_personality, source, ai_generated
    origin: dict | None = None  # set on import / duplicate


class ScenarioRuntime(BaseModel):
    """What the Vision Pro app gets with a session. No rubric, no findings."""
    scenario_id: str
    version: int
    code: str
    title: str
    review_state: ReviewState
    seed: int
    environment_id: str
    environment_label: str
    difficulty: str
    hint_policy: Literal["auto", "on_request", "off"]
    noise_level: float
    crowd_figures: list[dict]   # angle_deg, distance_m
    bystander: dict | None      # name, role_label, mood, lines
    teammate: dict | None       # name, role_label, present
    equipment: list[dict]       # id, label, kind, available


class ReviewRequest(BaseModel):
    reviewer_name: str = Field(min_length=2, max_length=80)
    reviewer_role: str = Field(min_length=2, max_length=80)
    attestation: bool           # "I am a qualified clinician and I reviewed this scenario"
    notes: str = Field("", max_length=600)


class StudioError(Exception):
    def __init__(self, status: int, detail):
        self.status, self.detail = status, detail


# MARK: Catalogue

def template(template_id: str) -> dict | None:
    path = TEMPLATES_DIR / f"{Path(template_id).name}.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else None


def templates() -> list[dict]:
    return [json.loads(p.read_text(encoding="utf-8")) for p in sorted(TEMPLATES_DIR.glob("*.json"))]


def catalog(cases: dict[str, dict]) -> list[dict]:
    """Templates whose clinical case is loaded, with the reference size marked for the UI."""
    out = []
    for t in templates():
        case = cases.get(t["case_id"])
        if case is None:
            continue
        keys = ("template_id", "case_id", "label", "summary", "clinical_review", "environments",
                "unsupported_environments", "equipment", "difficulties", "crowdedness",
                "bystander_behaviors", "teammate_behaviors", "learning_objectives")
        out.append({k: t[k] for k in keys} | {"hints": [h["text"] for h in t["hints"]],
                                              "dimensions": [d.model_dump() for d in assessability(case, t, {e["id"] for e in t["equipment"]})]})
    return out


def forbidden_terms(case: dict, t: dict) -> list[str]:
    d = case["hidden"]["diagnosis"]
    return d["accepted_keywords"] + d["partial_keywords"] + t.get("forbidden_terms", [])


def clinical_claim(text: str, case: dict, t: dict) -> str | None:
    """The first forbidden term in `text`, if any: free text must not state clinical facts."""
    return next((k for k in forbidden_terms(case, t) if _hit(text, [k])), None)


# MARK: What the resources allow

def _refs(t: dict, available: set[str], kind: str) -> set[str]:
    return {e.get("ref", e["id"]) for e in t["equipment"] if e["kind"] == kind and e["id"] in available}


def _management_possible(check: dict, invs: set[str]) -> bool:
    kind = check["type"]
    if kind == "ordered_any":
        return any(i in invs for i in check["investigations"])
    if kind == "any_of":
        return any(_management_possible(c, invs) for c in check["checks"])
    need = check.get("requires_ordered")
    return not need or any(i in invs for i in need)


def _fitting_possible(check: dict, sizes: set[str], tape: bool, ref: dict) -> bool:
    kind = check["type"]
    if kind == "measured":
        return tape
    if kind == "final_fit":
        return bool(sizes) and ("size" not in check["fields"] or ref["size"] in sizes)
    if kind == "checked_after_final_fit":
        return bool(sizes)
    return True


def assessability(case: dict, t: dict, available: set[str]) -> list[DimensionRule]:
    """Per scoring dimension: what can be earned with `available` equipment ids."""
    hidden = case["hidden"]
    invs, sizes = _refs(t, available, "investigation"), _refs(t, available, "orthosis_size")
    tape = bool(_refs(t, available, "measurement_tool"))
    core = sum(c["max_score"] for c in hidden["rubric"]["categories"])
    out = [DimensionRule(id="core", title="History, examination, communication, reasoning", max_score=core,
                         achievable_max=core, not_assessable=[])]
    for dim, possible, reason in (
        ("management", lambda c: _management_possible(c, invs), "The investigation it depends on is not available in this scenario."),
        ("fitting", lambda c: _fitting_possible(c, sizes, tape, hidden["fitting"]["reference"]),
         "The equipment it depends on is not available in this scenario."),
    ):
        spec = hidden[dim] if dim == "management" else hidden[dim]["rubric"]
        blocked = [{"id": c["id"], "label": c["label"], "points": c["points"], "reason": reason}
                   for c in spec["criteria"] if not possible(c["check"])]
        out.append(DimensionRule(id=dim, title=spec["title"], max_score=spec["max_score"],
                                 achievable_max=spec["max_score"] - sum(b["points"] for b in blocked),
                                 not_assessable=blocked))
    return out


# MARK: Validation

def validate(config: ScenarioConfig, cases: dict[str, dict]) -> list[Issue]:
    issues: list[Issue] = []

    def err(field: str, message: str):
        issues.append(Issue(field=field, severity="error", message=message))

    def warn(field: str, message: str):
        issues.append(Issue(field=field, severity="warning", message=message))

    t = template(config.template_id)
    case = cases.get(t["case_id"]) if t else None
    if t is None or case is None:
        err("template_id", f"'{config.template_id}' is not a supported clinical case template.")
        return issues

    def known(field: str, value: str, options: list[dict], what: str) -> dict | None:
        hit = next((o for o in options if o["id"] == value), None)
        if hit is None:
            err(field, f"'{value}' is not a supported {what}. Supported: {', '.join(o['id'] for o in options)}.")
        return hit

    env = next((e for e in t["environments"] if e["id"] == config.environment), None)
    if env is None:
        no = next((e for e in t["unsupported_environments"] if e["id"] == config.environment), None)
        err("environment", f"{no['label']} is not supported for this case. {no['reason']}" if no
            else f"'{config.environment}' is not a supported environment. "
                 f"Supported: {', '.join(e['id'] for e in t['environments'])}.")
    known("difficulty", config.difficulty, t["difficulties"], "difficulty")
    known("crowdedness", config.crowdedness, t["crowdedness"], "crowdedness level")
    known("bystander", config.bystander, t["bystander_behaviors"], "bystander behaviour")
    known("teammate", config.teammate, t["teammate_behaviors"], "teammate behaviour")

    if len(set(config.tools)) != len(config.tools):
        err("tools", "A tool is listed more than once.")
    for tool in dict.fromkeys(config.tools):
        item = known("tools", tool, t["equipment"], "equipment identifier")
        if item and env and tool in env["unsupported_equipment"]:
            err("tools", f"{item['label']} is not available in '{env['label']}'. Remove it or choose another environment.")

    if not config.learning_objectives:
        err("learning_objectives", "Choose at least one learning objective.")
    available = set(config.tools)
    for oid in config.learning_objectives:
        o = known("learning_objectives", oid, t["learning_objectives"], "learning objective")
        if o and o.get("needs_kind") and not _refs(t, available, o["needs_kind"]):
            warn("learning_objectives", f"'{o['label']}' needs equipment that is not in this scenario.")

    n = config.narrative
    for name, text in [("title", config.title), ("narrative.description", n.description),
                       ("narrative.patient_personality", n.patient_personality),
                       *[("narrative.bystander_lines", line) for line in n.bystander_lines]]:
        term = clinical_claim(text, case, t)
        if term:
            err(name, f"Contains '{term.rstrip('*')}': free text must not state or hint at clinical findings, "
                      f"results or the diagnosis. Those come only from the reviewed case.")
    if any(len(line) > 160 for line in n.bystander_lines):
        err("narrative.bystander_lines", "A bystander line is longer than 160 characters.")
    if n.bystander_lines and config.bystander == "none":
        warn("narrative.bystander_lines", "Bystander lines are set but no bystander is in the scenario.")

    if not any(i.severity == "error" for i in issues):
        for d in assessability(case, t, available):
            for b in d.not_assessable:
                warn("tools", f"'{b['label']}' ({b['points']} pts, {d.title}) cannot be earned: {b['reason']}")
    return issues


# MARK: Generation

def _code(scenario_id: str) -> str:
    digest = hashlib.sha256(scenario_id.encode()).digest()
    return "".join("ABCDEFGHJKLMNPQRSTUVWXYZ23456789"[b % 32] for b in digest[:6])


def findings_hash(case: dict) -> str:
    """Pins the clinical content: zones with results, investigations, everything hidden."""
    pinned = {k: case.get(k) for k in ("voice_context", "examination_zones", "investigations", "orthotics", "hidden")}
    return hashlib.sha256(json.dumps(pinned, sort_keys=True).encode()).hexdigest()


def generate(config: ScenarioConfig, cases: dict[str, dict], scenario_id: str | None = None,
             version: int = 1, origin: dict | None = None) -> ScenarioDefinition:
    """Deterministic for a given config and seed. Raises StudioError(422) with the issues."""
    issues = validate(config, cases)
    if any(i.severity == "error" for i in issues):
        raise StudioError(422, {"message": "The scenario is not valid.", "issues": [i.model_dump() for i in issues]})
    t = template(config.template_id)
    case = cases[t["case_id"]]
    seed = config.seed if config.seed is not None else secrets.randbelow(2**31 - 1)
    config = config.model_copy(update={"seed": seed})
    rng = random.Random(seed)
    pick = lambda options, value: next(o for o in options if o["id"] == value)  # noqa: E731

    env, crowd = pick(t["environments"], config.environment), pick(t["crowdedness"], config.crowdedness)
    level = pick(t["difficulties"], config.difficulty)
    available = set(config.tools)
    resources = [EquipmentItem(
        id=e["id"], label=e["label"], kind=e["kind"], available=e["id"] in available,
        deliverable=e["id"] not in available and e["id"] not in env["unsupported_equipment"],
        unsupported_reason=f"Not available in '{env['label']}'." if e["id"] in env["unsupported_equipment"] else None,
    ) for e in t["equipment"]]

    n = config.narrative
    mood = pick(t["bystander_behaviors"], config.bystander).get("mood")
    bystander = None
    if mood:
        b = t["bystander"]
        lines = {m: rng.sample(v, len(v)) for m, v in b["lines"].items()}  # seeded order
        if n.bystander_lines:
            lines[mood] = list(n.bystander_lines)
        bystander = {"name": b["name"], "role_label": b["role_label"], "mood": mood, "lines": lines,
                     "interject_every_s": rng.choice([20, 25, 30])}
    figures = [{"angle_deg": round(rng.uniform(100, 260)), "distance_m": round(rng.uniform(2.2, 3.4), 1)}
               for _ in range(crowd["figures"])]
    dims = assessability(case, t, available)
    hints = [{"id": h["id"], "text": h["text"]} for h in t["hints"] if _hint_fits(h, t, available)]

    scenario_id = scenario_id or f"scn_{uuid.uuid4().hex[:8]}"
    return ScenarioDefinition(
        scenario_id=scenario_id, version=version, code=_code(scenario_id), title=config.title, created_at=now_iso(),
        source_template={"template_id": t["template_id"], "case_id": case["case_id"],
                         "case_schema_version": case.get("schema_version")},
        seed=seed, config=config,
        environment={"id": env["id"], "label": env["label"], "brief": env["brief"],
                     "setting_context": env["setting_context"],
                     "ambient_level": round(min(1.0, env["ambient_level"] + crowd["noise"]), 2),
                     "crowd": {"id": crowd["id"], "label": crowd["label"], "figures": figures}},
        resources=resources,
        companions={"bystander": bystander,
                    "teammate": {"name": t["teammate"]["name"], "role_label": t["teammate"]["role_label"],
                                 "present": config.teammate == "nurse_present"}},
        difficulty={"id": level["id"], "label": level["label"], "hint_policy": level["hint_policy"],
                    "description": level["description"], "hints": hints},
        clinical_rules={
            "case_id": case["case_id"], "immutable_facts": IMMUTABLE_FACTS, "findings_sha256": findings_hash(case),
            "statement": "All clinical facts come from the case file at runtime. This scenario and live "
                         "instructor events can change the setting, resources and companions only.",
            "constraints": [f"{b['label']} ({b['points']} pts): {b['reason']}" for d in dims for b in d.not_assessable]},
        assessment={"dimensions": [d.model_dump() for d in dims],
                    "learning_objectives": [{"id": o["id"], "label": o["label"]} for o in t["learning_objectives"]
                                            if o["id"] in config.learning_objectives],
                    "note": "Scores use the unchanged case rubric. 'achievable_max' is what the resources of this "
                            "scenario allow; criteria listed as not assessable cannot be earned here."},
        narrative={"description": n.description or t["summary"],
                   "patient_personality": n.patient_personality or t["personalities"][level["id"]],
                   "source": n.source, "ai_generated": n.source == "llm"},
        origin=origin,
    )


def _hint_fits(h: dict, t: dict, available: set[str]) -> bool:
    if h.get("needs_kind") and not _refs(t, available, h["needs_kind"]):
        return False
    return not (h.get("unless_kind") and _refs(t, available, h["unless_kind"]))


# MARK: Library (one JSON file)

def _db_path() -> Path:
    env = os.environ.get("MEDSIM_STUDIO_DB")
    return Path(env) if env else Path(__file__).resolve().parents[1] / "data" / "studio_library.json"


SEEDS = [
    ("scn_demo_clinic", ScenarioConfig(
        template_id="wrist_trauma_001", title="Quiet clinic, full kit (guided)", environment="outpatient_clinic",
        difficulty="guided", crowdedness="quiet", seed=101,
        tools=["measuring_tape", "wrist_support_small", "wrist_support_medium", "wrist_support_large",
               "imaging_xray", "imaging_mri", "imaging_ct"],
        learning_objectives=["focused_history", "systematic_examination", "imaging_reasoning", "support_fitting"])),
    ("scn_demo_walkin", ScenarioConfig(
        template_id="wrist_trauma_001", title="Busy walk-in, limited kit (challenging)", environment="community_clinic",
        difficulty="challenging", crowdedness="busy", bystander="anxious_relative", seed=202,
        tools=["measuring_tape", "wrist_support_small", "wrist_support_large"],
        learning_objectives=["consent_and_empathy", "systematic_examination", "safe_plan_without_imaging",
                             "communication_under_pressure"])),
]


class Library:
    """scenario_id -> {"versions": [ScenarioDefinition dicts], "published_version": int | None}.
    shortcut: whole file rewritten on every change, no locking; move to SQLite when more than one
    instructor edits at once."""

    def __init__(self, cases: dict[str, dict]):
        self.cases = cases

    def _load(self) -> dict:
        path = _db_path()
        if path.is_file():
            return json.loads(path.read_text(encoding="utf-8"))
        data = {}
        for sid, config in SEEDS:  # two variants of the same case, published as experimental
            if template(config.template_id) and template(config.template_id)["case_id"] in self.cases:
                d = generate(config, self.cases, scenario_id=sid)
                d.review.state = "experimental"
                data[sid] = {"versions": [d.model_dump()], "published_version": 1}
        self._save(data)
        return data

    def _save(self, data: dict) -> None:
        path = _db_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, indent=1), encoding="utf-8")
        tmp.replace(path)

    @staticmethod
    def _view(rec: dict, version: int | None = None) -> ScenarioDefinition:
        raw = rec["versions"][-1] if version is None else next(
            (v for v in rec["versions"] if v["version"] == version), None)
        if raw is None:
            raise StudioError(404, f"No version {version}.")
        return ScenarioDefinition(**raw | {"published": raw["version"] == rec["published_version"]})

    def _rec(self, data: dict, scenario_id: str) -> dict:
        if scenario_id not in data:
            raise StudioError(404, f"Unknown scenario '{scenario_id}'.")
        return data[scenario_id]

    def list(self) -> list[dict]:
        out = []
        for rec in self._load().values():
            d = self._view(rec)
            out.append({"scenario_id": d.scenario_id, "code": d.code, "title": d.title, "version": d.version,
                        "versions": len(rec["versions"]), "review_state": d.review.state,
                        "published_version": rec["published_version"], "template_id": d.config.template_id,
                        "environment": d.environment["label"], "difficulty": d.difficulty["label"],
                        "crowdedness": d.environment["crowd"]["label"], "created_at": d.created_at,
                        "ai_generated": d.narrative["ai_generated"]})
        return sorted(out, key=lambda s: s["created_at"], reverse=True)

    def get(self, scenario_id: str, version: int | None = None) -> ScenarioDefinition:
        return self._view(self._rec(self._load(), scenario_id), version)

    def history(self, scenario_id: str) -> list[dict]:
        rec = self._rec(self._load(), scenario_id)
        return [{"version": v["version"], "created_at": v["created_at"], "review_state": v["review"]["state"],
                 "published": v["version"] == rec["published_version"]} for v in rec["versions"]]

    def create(self, config: ScenarioConfig, origin: dict | None = None) -> ScenarioDefinition:
        d = generate(config, self.cases, origin=origin)
        data = self._load()
        data[d.scenario_id] = {"versions": [d.model_dump()], "published_version": None}
        self._save(data)
        return d

    def update(self, scenario_id: str, config: ScenarioConfig) -> ScenarioDefinition:
        """A new draft version. The published version, if any, stays live until published again."""
        data = self._load()
        rec = self._rec(data, scenario_id)
        last = rec["versions"][-1]
        if config.seed is None:
            config = config.model_copy(update={"seed": last["seed"]})
        d = generate(config, self.cases, scenario_id=scenario_id, version=last["version"] + 1, origin=last.get("origin"))
        rec["versions"].append(d.model_dump())
        self._save(data)
        return self._view(rec)

    def duplicate(self, scenario_id: str) -> ScenarioDefinition:
        src = self.get(scenario_id)
        config = src.config.model_copy(update={"title": f"Copy of {src.title}"[:80]})
        return self.create(config, origin={"duplicated_from": src.scenario_id, "version": src.version})

    def import_(self, document: dict) -> ScenarioDefinition:
        """Only the configuration is taken; everything derived is regenerated here and the
        review state starts over, whatever the document claims."""
        try:
            config = ScenarioConfig(**document["config"])
        except Exception as e:  # noqa: BLE001 - any malformed document is the same user error
            raise StudioError(422, f"Not a scenario document: {type(e).__name__}.")
        claimed = (document.get("review") or {}).get("state")
        return self.create(config, origin={"imported_from": document.get("scenario_id"),
                                           "version": document.get("version"),
                                           "claimed_review_state": claimed})

    def _edit_latest(self, scenario_id: str, change) -> ScenarioDefinition:
        data = self._load()
        rec = self._rec(data, scenario_id)
        change(rec, rec["versions"][-1])
        self._save(data)
        return self._view(rec)

    def set_state(self, scenario_id: str, state: str) -> ScenarioDefinition:
        if state not in ("draft", "experimental"):
            raise StudioError(409, "clinician_reviewed can only be set by recording a review "
                                   "(POST /studio/scenarios/{id}/review).")

        def change(rec, latest):
            latest["review"] = Review(state=state).model_dump()
            if state == "draft" and rec["published_version"] == latest["version"]:
                rec["published_version"] = None  # drafts are not launchable
        return self._edit_latest(scenario_id, change)

    def review(self, scenario_id: str, req: ReviewRequest) -> ScenarioDefinition:
        if not req.attestation:
            raise StudioError(422, "A review needs the reviewer's attestation.")

        def change(rec, latest):
            latest["review"] = Review(state="clinician_reviewed", reviewer_name=req.reviewer_name,
                                      reviewer_role=req.reviewer_role, reviewed_at=now_iso(),
                                      notes=req.notes or None).model_dump()
        return self._edit_latest(scenario_id, change)

    def publish(self, scenario_id: str, on: bool = True) -> ScenarioDefinition:
        """Publishing a draft marks it experimental. It never marks anything clinician-reviewed."""
        def change(rec, latest):
            if not on:
                rec["published_version"] = None
                return
            if latest["review"]["state"] == "draft":
                latest["review"] = Review(state="experimental").model_dump()
            rec["published_version"] = latest["version"]
        return self._edit_latest(scenario_id, change)

    def published(self) -> list[ScenarioDefinition]:
        return [self._view(r, r["published_version"]) for r in self._load().values() if r["published_version"]]

    def by_code(self, code: str) -> ScenarioDefinition:
        code = code.strip().upper()
        hit = next((d for d in self.published() if d.code == code), None)
        if hit is None:
            raise StudioError(404, f"No published scenario with code '{code}'.")
        return hit


# MARK: Runtime adapter (scenario -> running session)

@dataclass
class Live:
    """Per-session scenario state. Changed only by director events (director.py)."""
    definition: ScenarioDefinition
    template: dict
    available: set[str]
    noise: float
    mood: str | None
    teammate_present: bool
    hint_policy: str
    interventions: list[dict] = field(default_factory=list)  # seq, event_id, kind, label, params, at, acknowledged, ack_detail
    hints: list[dict] = field(default_factory=list)          # seq, id, text, at
    delivered: dict[str, int] = field(default_factory=dict)  # equipment id -> seq


LIVE: dict[str, Live] = {}


def attach(session_id: str, d: ScenarioDefinition) -> Live:
    b = d.companions["bystander"]
    live = Live(definition=d, template=template(d.config.template_id),
                available={r.id for r in d.resources if r.available}, noise=d.environment["ambient_level"],
                mood=b["mood"] if b else None, teammate_present=d.companions["teammate"]["present"],
                hint_policy=d.difficulty["hint_policy"])
    LIVE[session_id] = live
    return live


def reset(session_id: str) -> None:
    """A new encounter of the same scenario: instructor events of the last one are gone."""
    if session_id in LIVE:
        attach(session_id, LIVE[session_id].definition)


def runtime(live: Live) -> ScenarioRuntime:
    d = live.definition
    b = d.companions["bystander"]
    return ScenarioRuntime(
        scenario_id=d.scenario_id, version=d.version, code=d.code, title=d.title, review_state=d.review.state,
        seed=d.seed, environment_id=d.environment["id"], environment_label=d.environment["label"],
        difficulty=d.difficulty["id"], hint_policy=live.hint_policy, noise_level=live.noise,
        crowd_figures=d.environment["crowd"]["figures"],
        bystander=b | {"mood": live.mood} if b else None,
        teammate=d.companions["teammate"] | {"present": live.teammate_present},
        equipment=[{"id": r.id, "label": r.label, "kind": r.kind, "available": r.id in live.available}
                   for r in d.resources])


def allowed(session_id: str, kind: str, ref: str | None = None) -> bool:
    """False when the scenario of this session does not have that equipment (right now)."""
    live = LIVE.get(session_id)
    if live is None:
        return True
    refs = _refs(live.template, live.available, kind)
    return bool(refs) if ref is None else ref in refs


def shape_case(case: CasePublic, live: Live) -> CasePublic:
    """The case as this scenario presents it: only available equipment, the setting in the
    brief, and setting, companions and manner appended to the voice context. Facts untouched."""
    d, t = live.definition, live.template
    invs, sizes = _refs(t, live.available, "investigation"), _refs(t, live.available, "orthosis_size")
    tape = bool(_refs(t, live.available, "measurement_tool"))
    have = [r.label for r in d.resources if r.id in live.available]
    brief = " ".join([t["brief_base"], d.environment["brief"],
                      f"Available: {', '.join(have)}." if have else "No equipment is available."])
    context = [d.environment["setting_context"]]
    if live.mood:
        context.append(t["bystander"]["anxious_context" if live.mood == "anxious" else "context"])
    if live.teammate_present:
        context.append(t["teammate"]["context"])
    context.append(f"Your manner: {d.narrative['patient_personality']}")
    return case.model_copy(update={
        "learner_brief": brief,
        "voice_context": case.voice_context + "\n\nENCOUNTER SETTING (manner and surroundings only; "
                                              "it never changes the facts above):\n" + "\n".join(f"- {c}" for c in context),
        "investigations": [i for i in case.investigations if i.id in invs],
        "orthotics": case.orthotics.model_copy(update={
            "sizes": [s for s in case.orthotics.sizes if s.id in sizes],
            "measurements": case.orthotics.measurements if tape else [],
            "tightness": case.orthotics.tightness if sizes else []}),
    })
