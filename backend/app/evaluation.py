"""Rubric engine and feedback builder: pure functions over a scenario and a Session.

Conventions (shared with the Swift offline engine):
- Keyword match = case-insensitive substring.
- Learner turns = interactions with role "learner", ordered by shared `seq`.
- evidence = full text of the FIRST qualifying learner turn (by seq); for
  diagnosis_or_learner_said a learner quote wins over the diagnosis text; for
  examined_any the label of the first-examined matching zone. evidence is
  null whenever met is false (so also for a partial diagnosis match) and for a
  met learner_avoided (there is no matching quote).
- comment = met_text if met else missed_text.
- learner_said_after_pain: learner turn seq > seq of the FIRST examination with pain_level >= 5.

BEFORE A DIAGNOSIS IS SUBMITTED the rubric wording would give the answer away,
so feedback is redacted: scores stay, but every category has criteria == [],
strengths == [] and missed == [], and summary == PENDING_SUMMARY.

SUMMARY TEMPLATE after a diagnosis (deterministic; sentences joined by one space):
  S1  only if transcript_available is false: NO_TRANSCRIPT
  S2  strengths[0], if any
  S3  if any missed: "However, " + missed[0] with its first letter lower-cased
  S4  the diagnostic explanation text for the verdict
  strengths[0] / missed[0] are the first in rubric order.
"""
from .models import (CategoryResult, CriterionResult, DiagnosticAssessment, Feedback)
from .sessions import Session

DISCLAIMER = ("Educational simulation only. Not a clinical diagnostic tool. "
              "Transcript-based criteria use simple keyword heuristics.")
NO_TRANSCRIPT = ("No conversation transcript was recorded, so history-taking and "
                 "communication could not be assessed.")
PENDING_SUMMARY = "Submit a diagnosis to unlock detailed feedback."


def _hit(text: str, keywords: list[str]) -> bool:
    low = text.lower()
    return any(k.lower() in low for k in keywords)


def _first_quote(turns: list[dict], keywords: list[str]) -> str | None:
    return next((t["text"] for t in turns if _hit(t["text"], keywords)), None)


def _run_check(check: dict, max_points: int, s: Session, labels: dict[str, str]):
    """Return (points, met, evidence, method) for one criterion."""
    kind = check["type"]
    kws = check.get("keywords", [])
    turns = sorted((t for t in s.interactions if t["role"] == "learner"), key=lambda t: t["seq"])
    exams = sorted(s.examinations, key=lambda e: e["seq"])
    quote, method = None, "keyword"

    if kind == "learner_said":
        quote = _first_quote(turns, kws)
        met = quote is not None
    elif kind == "learner_said_before_exam":
        first = exams[0]["seq"] if exams else float("inf")
        quote = _first_quote([t for t in turns if t["seq"] < first], kws)
        met = quote is not None
    elif kind == "learner_said_after_pain":
        pain = next((e["seq"] for e in exams if e["pain_level"] >= 5), None)
        quote = _first_quote([t for t in turns if pain is not None and t["seq"] > pain], kws)
        met = quote is not None
    elif kind == "learner_avoided":
        met = bool(turns) and _first_quote(turns, kws) is None
    elif kind == "examined_any":
        method = "rule"
        zone = next((e["zone_id"] for e in exams if e["zone_id"] in check["zones"]), None)
        met = zone is not None
        quote = labels[zone] if zone else None
    elif kind == "diagnosis_or_learner_said":
        quote = _first_quote(turns, kws)
        if quote is None and s.diagnosis and _hit(s.diagnosis, kws):
            quote = s.diagnosis
        need = check.get("requires_examined")
        if need and not any(e["zone_id"] in need for e in exams):
            quote = None
        met = quote is not None
    else:  # diagnosis_matches is handled in evaluate()
        raise ValueError(f"unknown check type {kind!r}")
    return (max_points if met else 0), met, (quote if met else None), method


def evaluate(scenario: dict, s: Session) -> Feedback:
    hidden = scenario["hidden"]
    diag = hidden["diagnosis"]
    labels = {z["id"]: z["label"] for z in scenario["examination_zones"]}
    findings = {z["id"]: z["result"] for z in scenario["examination_zones"]}

    # verdict
    if s.diagnosis is None:
        verdict, text = "not_submitted", diag["not_submitted_text"]
    elif _hit(s.diagnosis, diag["accepted_keywords"]):
        verdict, text = "correct", diag["correct_text"]
    elif _hit(s.diagnosis, diag["partial_keywords"]):
        verdict, text = "partial", diag["partial_text"]
    else:
        verdict, text = "incorrect", diag["incorrect_text"]

    categories, strengths, missed = [], [], []
    for cat in hidden["rubric"]["categories"]:
        results = []
        for c in cat["criteria"]:
            mx, check = c["points"], c["check"]
            if check["type"] == "diagnosis_matches":
                pts = {"correct": mx, "partial": mx // 2}.get(verdict, 0)
                met, ev, method = verdict == "correct", None, "rule"
                if met:
                    ev = s.diagnosis
            else:
                pts, met, ev, method = _run_check(check, mx, s, labels)
            (strengths if met else missed).append(c["met_text"] if met else c["missed_text"])
            results.append(CriterionResult(
                id=c["id"], label=c["label"], met=met, points=pts, max_points=mx,
                method=method, evidence=ev, comment=c["met_text"] if met else c["missed_text"]))
        categories.append(CategoryResult(
            id=cat["id"], title=cat["title"], score=sum(r.points for r in results),
            max_score=cat["max_score"], criteria=results))

    # relevant findings: distinct zones in order of first examination
    seen = list(dict.fromkeys(e["zone_id"] for e in sorted(s.examinations, key=lambda e: e["seq"])))
    relevant = [f"{labels[z]}: {findings[z]['finding'].replace('_', ' ')} (pain {findings[z]['pain_level']}/10)"
                for z in seen]

    has_transcript = any(t["role"] == "learner" for t in s.interactions)
    summary = _summary(strengths, missed, text, has_transcript)
    if verdict == "not_submitted":  # redact: rubric wording reveals the diagnosis
        categories = [c.model_copy(update={"criteria": []}) for c in categories]
        strengths, missed, summary = [], [], PENDING_SUMMARY
    next_steps = list(hidden["next_steps"]) if verdict != "not_submitted" else []
    return Feedback(
        session_id=s.id, case_id=s.case_id, diagnosis_submitted=s.diagnosis,
        total_score=sum(c.score for c in categories), max_score=sum(c.max_score for c in categories),
        summary=summary,
        transcript_available=has_transcript,
        diagnostic_assessment=DiagnosticAssessment(
            verdict=verdict, explanation=text,
            expected=diag["name"] if verdict != "not_submitted" else None),
        categories=categories, strengths=strengths, missed=missed,
        relevant_findings=relevant, next_steps=next_steps, disclaimer=DISCLAIMER)


def _summary(strengths, missed, explanation, has_transcript) -> str:
    parts = [] if has_transcript else [NO_TRANSCRIPT]
    if strengths:
        parts.append(strengths[0])
    if missed:
        parts.append("However, " + missed[0][:1].lower() + missed[0][1:])
    parts.append(explanation)
    return " ".join(parts)
