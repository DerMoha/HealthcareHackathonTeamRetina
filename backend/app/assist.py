"""Optional AI drafting help for instructors: description, patient personality, bystander
lines and a choice of learning objectives. Narrative only.

The model is given the public case brief and the template's lists, and returns an
`AssistDraft` through structured output. Its text is then checked with the same rule as
instructor text (studio.clinical_claim): anything that names a finding, a result or the
diagnosis is rejected and the deterministic template draft is returned instead, with the
reason. Objectives outside the template's list are dropped. A draft is never clinical
ground truth and a scenario that uses one is marked `ai_generated`.

Without ANTHROPIC_API_KEY (or without the `anthropic` package) the draft is built from the
template alone and is the same every time.
"""
import os
from typing import Literal

from pydantic import BaseModel, Field

from . import studio

MODEL = "claude-opus-5-5"


class AssistRequest(BaseModel):
    template_id: str
    environment: str
    difficulty: str
    crowdedness: str
    tools: list[str] = []
    bystander: str = "none"
    focus: str = Field("", max_length=300)  # what the instructor wants the session to train


class AssistDraft(BaseModel):
    description: str = Field(max_length=600)
    patient_personality: str = Field(max_length=300)
    bystander_lines: list[str] = Field(max_length=4)
    learning_objectives: list[str]


class AssistResult(AssistDraft):
    source: Literal["llm", "template"]
    model: str | None = None
    notes: list[str] = []
    requires_review: bool = True


def template_draft(req: AssistRequest, t: dict) -> AssistDraft:
    """Deterministic: template text for the chosen options."""
    pick = lambda options, value, key: next((o[key] for o in options if o["id"] == value), value)  # noqa: E731
    available = set(req.tools)
    mood = next((b.get("mood") for b in t["bystander_behaviors"] if b["id"] == req.bystander), None)
    objectives = [o["id"] for o in t["learning_objectives"]
                  if not o.get("needs_kind") or studio._refs(t, available, o["needs_kind"])]
    if studio._refs(t, available, "investigation"):
        objectives.remove("safe_plan_without_imaging")
    if not mood and req.crowdedness == "quiet":
        objectives.remove("communication_under_pressure")
    description = (f"{t['summary']} Setting: {pick(t['environments'], req.environment, 'label')}, "
                   f"{pick(t['crowdedness'], req.crowdedness, 'label').lower()}. "
                   f"Difficulty: {pick(t['difficulties'], req.difficulty, 'label').lower()}.")
    return AssistDraft(description=description[:600],
                       patient_personality=t["personalities"].get(req.difficulty, ""),
                       bystander_lines=t["bystander"]["lines"][mood][:4] if mood else [],
                       learning_objectives=objectives)


def _prompt(req: AssistRequest, t: dict, case: dict) -> str:
    objectives = "\n".join(f"- {o['id']}: {o['label']}" for o in t["learning_objectives"])
    return f"""You help a clinical instructor write the non-clinical framing of a simulation scenario.

The clinical case is fixed and reviewed separately. You must not state, add or hint at any
clinical fact: no findings, no test results, no diagnosis or differential, no vital signs,
no medication, no anatomy. Write only about the setting, how the people behave, and what
the session trains.

Case, as the student sees it: {case['learner_brief']}
Patient: {case['patient']['name']}, {case['patient']['age']}. {case['patient']['personality']}
Setting chosen: {req.environment}. Crowdedness: {req.crowdedness}. Difficulty: {req.difficulty}.
Equipment in the room: {', '.join(req.tools) or 'none'}.
Bystander: {req.bystander} ({t['bystander']['name']}, {t['bystander']['role_label']}).
Instructor's focus: {req.focus or 'not stated'}

Write:
- description: two or three sentences for the scenario card, spoiler-free.
- patient_personality: one sentence on the patient's manner only.
- bystander_lines: up to four short things the bystander says, worry or small talk only; an empty list if the bystander is 'none'.
- learning_objectives: ids chosen from this list only:
{objectives}"""


def draft(req: AssistRequest, cases: dict[str, dict]) -> AssistResult:
    t = studio.template(req.template_id)
    case = cases.get(t["case_id"]) if t else None
    if t is None or case is None:
        raise studio.StudioError(404, f"'{req.template_id}' is not a supported clinical case template.")
    fallback = template_draft(req, t)

    def from_template(note: str) -> AssistResult:
        return AssistResult(**fallback.model_dump(), source="template", notes=[note], requires_review=False)

    if not os.environ.get("ANTHROPIC_API_KEY"):
        return from_template("No ANTHROPIC_API_KEY: built from the template.")
    try:
        import anthropic
    except ImportError:
        return from_template("The 'anthropic' package is not installed: built from the template.")
    try:
        response = anthropic.Anthropic(timeout=40).messages.parse(
            model=MODEL, max_tokens=2000, output_config={"effort": "low"},
            messages=[{"role": "user", "content": _prompt(req, t, case)}], output_format=AssistDraft)
    except anthropic.APIError as e:
        return from_template(f"The model call failed ({type(e).__name__}): built from the template.")
    out = response.parsed_output
    if response.stop_reason == "refusal" or out is None:
        return from_template("The model returned no usable draft: built from the template.")

    notes = ["Drafted by an AI model. Narrative only; read it before using it."]
    for text in [out.description, out.patient_personality, *out.bystander_lines]:
        term = studio.clinical_claim(text, case, t)
        if term:
            return from_template(f"The AI draft was rejected because it mentioned '{term.rstrip('*')}', "
                                 f"which could state or hint at clinical facts: built from the template.")
    known = {o["id"] for o in t["learning_objectives"]}
    dropped = [o for o in out.learning_objectives if o not in known]
    if dropped:
        notes.append(f"Dropped objectives that are not in the template: {', '.join(dropped)}.")
    objectives = [o for o in out.learning_objectives if o in known] or fallback.learning_objectives
    lines = [line[:160] for line in out.bystander_lines] if req.bystander != "none" else []
    return AssistResult(description=out.description, patient_personality=out.patient_personality,
                        bystander_lines=lines, learning_objectives=objectives, source="llm", model=MODEL, notes=notes)
