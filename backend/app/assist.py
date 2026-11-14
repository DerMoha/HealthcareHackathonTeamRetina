"""Optional AI drafting help for instructors: description, patient personality, bystander
lines and a choice of learning objectives. Narrative only.

The model is given the public case brief and the template's lists, and returns an
`AssistDraft` through structured output. Its text is then checked with the same rule as
instructor text (studio.clinical_claim): anything that names a finding, a result or the
diagnosis is rejected and the deterministic template draft is returned instead, with the
reason. Objectives outside the template's list are dropped. A draft is never clinical
ground truth and a scenario that uses one is marked `ai_generated`.

Live drafting is off unless MEDSIM_LIVE_AI=1. By default the draft is the template's
hand-written `demo_draft` text for the chosen options (source "demo"): a deterministic preview
of what the assistant produces, with no model call.

When on, the model is reached with ANTHROPIC_API_KEY (Anthropic API) or, failing that, with AWS
credentials (Amazon Bedrock: AWS_ACCESS_KEY_ID or AWS_PROFILE, region from AWS_REGION /
AWS_DEFAULT_REGION). With neither (or without the `anthropic` package) the draft is built
from the template alone and is the same every time.
"""
import os
from typing import Literal

from pydantic import BaseModel, Field

from . import studio

MODEL = "claude-opus-5-5"
BEDROCK_MODEL = os.environ.get("MEDSIM_BEDROCK_MODEL", "us.anthropic.claude-opus-5-5")


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
    source: Literal["llm", "demo", "template"]
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
    drop = {"safe_plan_without_imaging"} if studio._refs(t, available, "investigation") else set()
    if not mood and req.crowdedness == "quiet":
        drop.add("communication_under_pressure")
    objectives = [o for o in objectives if o not in drop]  # ids differ per template
    b, demo = t["bystander"], t.get("demo_draft", {})
    place = pick(t["environments"], req.environment, "brief").removeprefix("Setting: ")
    who = pick(t["bystander_behaviors"], req.bystander, "label")
    description = " ".join(filter(None, [
        demo.get("scenes", {}).get(req.environment) or f"{t['summary']} {place[:1].upper()}{place[1:]}",
        next((c.get("scene", "") for c in t["crowdedness"] if c["id"] == req.crowdedness), ""),
        "" if not mood else demo["bystander"][mood].format(name=b["name"]) if demo.get("bystander")
        else f"{b['name']} ({b['role_label']}) is there too: {who[:1].lower()}{who[1:]}.",
        demo.get("pressure", {}).get(req.difficulty) or pick(t["difficulties"], req.difficulty, "description")]))
    personality = demo.get("personalities", {}).get(req.difficulty) or t["personalities"].get(req.difficulty, "")
    if mood == "anxious":
        personality += f" Gets tenser each time {b['name']} interrupts."
    lines = (demo.get("lines") or b["lines"])[mood][:4] if mood else []
    return AssistDraft(description=description[:600], patient_personality=personality[:300],
                       bystander_lines=lines, learning_objectives=objectives)


def _prompt(req: AssistRequest, t: dict, case: dict) -> str:
    def find(options: list[dict], value: str) -> dict:
        return next((o for o in options if o["id"] == value), {"id": value, "label": value})

    env, crowd = find(t["environments"], req.environment), find(t["crowdedness"], req.crowdedness)
    level, behaviour = find(t["difficulties"], req.difficulty), find(t["bystander_behaviors"], req.bystander)
    b, mood = t["bystander"], behaviour.get("mood")
    tools = [e["label"] for e in t["equipment"] if e["id"] in req.tools]
    stages = studio.journey_stages(case)
    objectives = "\n".join(f"- {o['id']}: {o['label']}" for o in t["learning_objectives"])
    bystander = (f"{b['name']}, {b['role_label']}: {behaviour['label']}. Their voice so far: "
                 + " / ".join(f'"{line}"' for line in b["lines"][mood]) if mood else "none")
    journey = ("\nThe encounter moves through these places in order: "
               + "; ".join(f"{s['label']} ({s['setting']})" for s in stages) + "." if stages else "")
    return f"""You help a clinical instructor write the non-clinical framing of a simulation scenario
for medical students, played in mixed reality with a voiced virtual patient.

HARD RULES. The clinical case is fixed and reviewed separately. Do not state, add or hint at
any clinical fact: no findings, signs, test results, diagnosis or differential, vital signs,
medication or injury details beyond what the student brief already says. Do not invent
biography either (job, family, hobbies, plans, what happened before): the patient's history is
fixed and a made-up detail would contradict it. Write only about the place, the atmosphere,
how the people behave and speak, and what the session trains.

Student brief: {case['learner_brief']}
Patient: {case['patient']['name']}, {case['patient']['age']}. Baseline manner: {case['patient']['personality']}
Place: {env['label']}. {env.get('setting_context', '')}{journey}
Surroundings: {crowd['label']}.
Difficulty: {level['label']}. {level.get('description', '')}
Equipment at hand: {', '.join(tools) or 'none'}.
Bystander: {bystander}
Instructor's focus: {req.focus or 'not stated'}

STYLE. Concrete and specific to THIS combination of place, noise, bystander and difficulty; a
different choice of options should read clearly differently. Show the scene with one or two
sensory details (sounds, light, space, interruptions) and the pressure the student is under.
No clichés ("bustling", "a day like any other", "put your skills to the test"), no marketing
tone, no second-person instructions, no exclamation marks.

Write:
- description: two or three sentences for the scenario card. Set the scene and say what makes
  this version hard or interesting, without spoiling the case.
- patient_personality: one sentence the patient's voice actor plays from: manner, how they
  speak (pace, words, silences), and what makes them open up or close down. It must fit the
  baseline manner and the difficulty: harder means more guarded, not ruder.
- bystander_lines: up to four lines the bystander says, in their own voice, each under 160
  characters, fitting the place and their mood. Worry, impatience, small talk or practical
  remarks only, never a clinical claim. Do not repeat the lines above. Empty if the bystander is 'none'.
- learning_objectives: ids from this list only, the ones this setup actually exercises:
{objectives}"""


def draft(req: AssistRequest, cases: dict[str, dict]) -> AssistResult:
    t = studio.template(req.template_id)
    case = cases.get(t["case_id"]) if t else None
    if t is None or case is None:
        raise studio.StudioError(404, f"'{req.template_id}' is not a supported clinical case template.")
    fallback = template_draft(req, t)

    def from_template(note: str) -> AssistResult:
        return AssistResult(**fallback.model_dump(), source="template", notes=[note], requires_review=False)

    if os.environ.get("MEDSIM_LIVE_AI") != "1":  # hackathon: the live model is opt-in, the demo draft is the default
        return AssistResult(**fallback.model_dump(), source="demo", notes=[
            "Offline preview of the AI drafting assistant: hand-written text for these choices, no model was called.",
            "Live drafting (Claude via Anthropic API or Amazon Bedrock) turns on with MEDSIM_LIVE_AI=1."])
    use_bedrock = not os.environ.get("ANTHROPIC_API_KEY")
    if use_bedrock and not (os.environ.get("AWS_ACCESS_KEY_ID") or os.environ.get("AWS_PROFILE")):
        return from_template("No ANTHROPIC_API_KEY or AWS credentials: built from the template.")
    try:
        import anthropic
    except ImportError:
        return from_template("The 'anthropic' package is not installed: built from the template.")
    model = BEDROCK_MODEL if use_bedrock else MODEL
    errors: tuple[type[Exception], ...] = (anthropic.APIError,)
    if use_bedrock:
        import botocore.exceptions  # expired or missing AWS credentials surface as botocore errors
        errors += (botocore.exceptions.BotoCoreError, botocore.exceptions.ClientError)
    try:
        if use_bedrock:
            region = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION")
            client = anthropic.AnthropicBedrock(aws_region=region, timeout=60)
        else:
            client = anthropic.Anthropic(timeout=60)
        response = client.messages.parse(
            model=model, max_tokens=4000, output_config={"effort": "medium"},
            messages=[{"role": "user", "content": _prompt(req, t, case)}], output_format=AssistDraft)
    except errors as e:
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
    known = {o["id"] for o in t["learning_objectives"]
             if not o.get("needs_kind") or studio._refs(t, set(req.tools), o["needs_kind"])}
    dropped = [o for o in out.learning_objectives if o not in known]
    if dropped:
        notes.append(f"Dropped objectives that are not in the template or need missing equipment: {', '.join(dropped)}.")
    objectives = [o for o in out.learning_objectives if o in known] or fallback.learning_objectives
    lines = [line[:160] for line in out.bystander_lines] if req.bystander != "none" else []
    return AssistResult(description=out.description, patient_personality=out.patient_personality,
                        bystander_lines=lines, learning_objectives=objectives, source="llm", model=model, notes=notes)
