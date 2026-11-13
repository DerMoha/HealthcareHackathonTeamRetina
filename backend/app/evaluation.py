"""Rubric engine and feedback builder: pure functions over a scenario and a Session.

Conventions (shared with the Swift offline engine):
- Keyword match = case-insensitive whole word/phrase (no letter or digit directly
  before or after). A trailing "*" makes the keyword a stem: "numb*" also matches
  "numbness". Typographic apostrophes are treated as "'". See _hit().
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

LABELS: zones have a neutral `label` (shown during the session) and a `clinical_label`
(anatomical name). Feedback uses the clinical label only after a diagnosis.

NOTES: the notebook never earns examination or history points. Its assessment section is
read together with the diagnosis for diagnosis_or_learner_said (a written plan counts as
reasoning). After a diagnosis, each criterion with `note_keywords` is compared with the
notes (all sections joined by newlines):
  noted and met      -> documented   (DOC_OK)
  noted, not met     -> unsupported  (DOC_UNSUPPORTED_EXAM for category "examination", else _ASK)
  met, not noted     -> undocumented (DOC_MISSING)
  neither            -> no entry
No notes, or no diagnosis yet -> documentation == [].
If any entry is unsupported, the summary ends with UNSUPPORTED_SUMMARY.

INVESTIGATIONS AND MANAGEMENT: `hidden.management` is a separate 20-point dimension reported
as Feedback.management. It is NOT added to total_score/max_score (still the 100-point rubric).
Its checks read the ordered investigations and the written texts
  diagnosis, assessment, interpretation, management, follow_up
and never the conversation, so nothing the LLM says can earn or lose these points:
  ordered_any    first ordered investigation (by seq) in `investigations`; evidence = its label
  notes_said     first of `fields` (in list order) whose text hits `keywords`; evidence = that
                 text; `requires_ordered` = at least one of these must have been ordered;
                 `ignore_negated` = each text is lower-cased and NEGATED phrases ("no follow-up",
                 "without splint") are blanked first, and evidence is that processed text
  notes_avoided  met when at least one of `fields` is non-blank and none hits `keywords`
  any_of         result of the first met sub-check, else unmet with the last sub-check's method
Criteria are redacted (criteria == []) before a diagnosis, like the categories.
Feedback.investigations = "<label>: <impression>" per distinct ordered investigation, in order.
The plan text used by diagnosis_or_learner_said is the diagnosis followed by every non-blank
note among assessment, interpretation, management, follow_up (joined by newlines).

REPLAY: Feedback.replay has one entry per examination zone (scenario order) with its clinical
label, whether it was examined, the finding if so, and the zone's `teaching` text
(`contribution` if examined, else `missed`). Empty before a diagnosis.

MEASUREMENT AND FITTING: a third separate dimension (Feedback.fitting, 20 points, not in
total_score). Rules and outcome precedence are documented in fitting.py.

ULTRASOUND CASES (`scenario["ultrasound"]`, see ultrasound.py) reuse the same rubric with more check types.
The record is `Session.gels` and `Session.scans` (events with a shared `seq`); a view is OBTAINED only
when a good scan returned it, so points follow what was actually scanned, never what was written:
  learner_said_before_scan  learner turn before the first scan event (any quality); no scan = any turn
  learner_said_before_gel   before the first gel event; without gel before the first scan; else any turn
  learner_said_after_scan   learner turn after the first GOOD scan (no good scan = unmet)
  gel_before_scan           gel applied, and before the first scan (a case with no scan yet is still met)
  viewed_any                one of `views` obtained; evidence = that view's title
  documented_in_notes       one of `requires_viewed` obtained AND one of `fields` (notes sections, or
                            "diagnosis") hits `keywords`; evidence = that text. Notes alone earn nothing.
A category with `note_kind: "examination"` flags notes about a view that was never obtained as
"unsupported" with the examination wording. `hidden.management` and `hidden.fitting` are optional: absent,
Feedback.management and Feedback.fitting are empty (score 0 of 0, no criteria). Feedback.scan_review lists
`hidden.scan_review` items (views obtained versus expected) after a diagnosis; [] before and for other cases.

SUMMARY TEMPLATE after a diagnosis (deterministic; sentences joined by one space):
  S1  only if transcript_available is false: NO_TRANSCRIPT
  S2  strengths[0], if any
  S3  if any missed: "However, " + missed[0] with its first letter lower-cased
  S4  the diagnostic explanation text for the verdict
  strengths[0] / missed[0] are the first in rubric order.
"""
import re
from functools import lru_cache

from .models import (CategoryResult, CriterionResult, DiagnosticAssessment, DocumentationItem,
                     Feedback, FittingAssessment, ManagementAssessment, ReplayZone, ScanReviewItem)
from . import fitting, ultrasound
from .sessions import Session

DISCLAIMER = ("Educational simulation only. Not a clinical diagnostic tool. "
              "Transcript-based criteria use simple keyword heuristics.")
NO_TRANSCRIPT = ("No conversation transcript was recorded, so history-taking and "
                 "communication could not be assessed.")
PENDING_SUMMARY = "Submit a diagnosis to unlock detailed feedback."
DOC_OK = "Documented, and supported by the session record."
DOC_UNSUPPORTED_EXAM = ("Your notes mention this, but no matching examination was recorded. "
                        "Notes alone earn no points.")
DOC_UNSUPPORTED_ASK = ("Your notes mention this, but no matching question was recorded. "
                       "Notes alone earn no points.")
DOC_MISSING = "You did this, but did not write it down."
UNSUPPORTED_SUMMARY = "Some of your notes are not supported by what was actually asked or examined."


@lru_cache(maxsize=None)
def _pattern(keyword: str) -> re.Pattern:
    stem = keyword.endswith("*")
    body = re.escape(keyword.rstrip("*").strip().lower())
    return re.compile(r"(?<!\w)" + body + ("" if stem else r"(?!\w)"))


def _hit(text: str, keywords: list[str]) -> bool:
    low = text.lower().replace("\u2019", "'")
    return any(_pattern(k).search(low) for k in keywords)


# "no|not|without|kein*|ohne" plus the next one or two words (same sentence part).
NEGATED = re.compile(r"(?<!\w)(?:no|not|without|kein\w*|ohne)\s+[\w-]+(?:\s+[\w-]+)?")
PLAN_FIELDS = ("assessment", "interpretation", "management", "follow_up")


def _management_check(check: dict, ordered: list[str], texts: dict[str, str], labels: dict[str, str]):
    """Return (met, evidence, method) for one investigation/management check."""
    kind = check["type"]
    if kind == "ordered_any":
        hit = next((o for o in ordered if o in check["investigations"]), None)
        return hit is not None, labels.get(hit), "rule"
    if kind == "any_of":
        result = (False, None, "rule")
        for sub in check["checks"]:
            result = _management_check(sub, ordered, texts, labels)
            if result[0]:
                break
        return result
    written = [texts.get(f, "") for f in check["fields"]]
    if kind == "notes_avoided":
        met = any(t.strip() for t in written) and not any(_hit(t, check["keywords"]) for t in written)
        return met, None, "keyword"
    if kind == "notes_said":
        need = check.get("requires_ordered")
        if check.get("ignore_negated"):  # "no follow-up" must not count as arranging follow-up
            written = [NEGATED.sub(" ", t.lower()) for t in written]
        quote = next((t for t in written if _hit(t, check["keywords"])), None)
        if need and not any(o in need for o in ordered):
            quote = None
        return quote is not None, quote, "keyword"
    raise ValueError(f"unknown management check type {kind!r}")


def _management(scenario: dict, s: Session, redact: bool):
    spec = scenario["hidden"].get("management")
    if spec is None:  # cases without investigations or management scoring
        return ManagementAssessment(title="", score=0, max_score=0, criteria=[]), []
    invs = {i["id"]: i for i in scenario.get("investigations", [])}
    ordered = list(dict.fromkeys(o["investigation_id"] for o in sorted(s.investigations, key=lambda o: o["seq"])))
    texts = {"diagnosis": s.diagnosis or "", **(s.notes or {})}
    results = []
    for c in spec["criteria"]:
        met, ev, method = _management_check(c["check"], ordered, texts, {k: v["label"] for k, v in invs.items()})
        results.append(CriterionResult(
            id=c["id"], label=c["label"], met=met, points=c["points"] if met else 0, max_points=c["points"],
            method=method, evidence=ev if met else None, comment=c["met_text"] if met else c["missed_text"],
            area=c["area"]))
    assessment = ManagementAssessment(title=spec["title"], score=sum(r.points for r in results),
                                      max_score=spec["max_score"], criteria=[] if redact else results)
    return assessment, [f"{invs[o]['label']}: {invs[o]['result']['impression']}" for o in ordered]


def _first_quote(turns: list[dict], keywords: list[str]) -> str | None:
    return next((t["text"] for t in turns if _hit(t["text"], keywords)), None)


def _run_check(check: dict, max_points: int, s: Session, labels: dict[str, str], plan: str | None):
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
    elif kind in ("learner_said_before_scan", "learner_said_before_gel", "learner_said_after_scan"):
        scans = sorted(s.scans, key=lambda e: e["seq"])
        gels = sorted(s.gels, key=lambda e: e["seq"])
        first_scan = scans[0]["seq"] if scans else float("inf")
        if kind == "learner_said_before_scan":
            quote = _first_quote([t for t in turns if t["seq"] < first_scan], kws)
        elif kind == "learner_said_before_gel":
            limit = gels[0]["seq"] if gels else first_scan
            quote = _first_quote([t for t in turns if t["seq"] < limit], kws)
        else:
            good = next((e["seq"] for e in scans if e["quality"] == "good"), None)
            quote = _first_quote([t for t in turns if good is not None and t["seq"] > good], kws)
        met = quote is not None
    elif kind == "gel_before_scan":
        method = "rule"
        first_scan = min((e["seq"] for e in s.scans), default=float("inf"))
        met = bool(s.gels) and min(e["seq"] for e in s.gels) < first_scan
    elif kind == "viewed_any":
        method = "rule"
        view = next((v for v in ultrasound.obtained_views(s) if v in check["views"]), None)
        met = view is not None
        quote = labels.get(view) if view else None
    elif kind == "documented_in_notes":
        obtained = ultrasound.obtained_views(s)
        texts = {"diagnosis": s.diagnosis or "", **(s.notes or {})}
        if any(v in obtained for v in check["requires_viewed"]):
            quote = next((texts[f] for f in check["fields"] if texts.get(f) and _hit(texts[f], kws)), None)
        met = quote is not None
    elif kind == "diagnosis_or_learner_said":
        quote = _first_quote(turns, kws)
        if quote is None and plan and _hit(plan, kws):
            quote = plan
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
    neutral = {z["id"]: z["label"] for z in scenario["examination_zones"]}
    labels = {z["id"]: z.get("clinical_label", z["label"]) for z in scenario["examination_zones"]}
    us = scenario.get("ultrasound")
    view_titles = {v["id"]: v["title"] for v in us["views"]} if us else {}
    notes = s.notes or {}
    note_text = "\n".join(notes.get(k, "") for k in ("history", "examination", "assessment"))
    plan = s.diagnosis  # diagnosis plus the written assessment and plan
    if plan:
        plan = "\n".join([plan] + [notes[k] for k in PLAN_FIELDS if notes.get(k, "").strip()])
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

    categories, strengths, missed, documentation = [], [], [], []
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
                pts, met, ev, method = _run_check(check, mx, s, {**labels, **view_titles}, plan)
            if note_text.strip() and c.get("note_keywords"):
                noted = _hit(note_text, c["note_keywords"])
                if noted or met:
                    status = "documented" if noted and met else "unsupported" if noted else "undocumented"
                    comment = {"documented": DOC_OK, "undocumented": DOC_MISSING,
                               "unsupported": DOC_UNSUPPORTED_EXAM if cat.get("note_kind", cat["id"]) == "examination"
                               else DOC_UNSUPPORTED_ASK}[status]
                    documentation.append(DocumentationItem(
                        criterion_id=c["id"], label=c["label"], status=status, comment=comment))
            (strengths if met else missed).append(c["met_text"] if met else c["missed_text"])
            results.append(CriterionResult(
                id=c["id"], label=c["label"], met=met, points=pts, max_points=mx,
                method=method, evidence=ev, comment=c["met_text"] if met else c["missed_text"]))
        categories.append(CategoryResult(
            id=cat["id"], title=cat["title"], score=sum(r.points for r in results),
            max_score=cat["max_score"], criteria=results))

    # relevant findings: distinct zones in order of first examination
    seen = list(dict.fromkeys(e["zone_id"] for e in sorted(s.examinations, key=lambda e: e["seq"])))
    shown = labels if verdict != "not_submitted" else neutral
    relevant = [f"{shown[z]}: {findings[z]['finding'].replace('_', ' ')} (pain {findings[z]['pain_level']}/10)"
                for z in seen]
    if us:
        relevant = _scan_findings(us, s, redact=verdict == "not_submitted")

    has_transcript = any(t["role"] == "learner" for t in s.interactions)
    summary = _summary(strengths, missed, text, has_transcript)
    if verdict == "not_submitted":  # redact: rubric wording reveals the diagnosis
        categories = [c.model_copy(update={"criteria": []}) for c in categories]
        strengths, missed, documentation, summary = [], [], [], PENDING_SUMMARY
    elif any(d.status == "unsupported" for d in documentation):
        summary += " " + UNSUPPORTED_SUMMARY
    next_steps = list(hidden["next_steps"]) if verdict != "not_submitted" else []
    replay = []
    if verdict != "not_submitted":  # zone teaching text names the diagnosis
        done = {e["zone_id"] for e in s.examinations}
        for z in scenario["examination_zones"]:
            t, hit = z["teaching"], z["id"] in done
            replay.append(ReplayZone(
                zone_id=z["id"], label=labels[z["id"]], important=t["important"], examined=hit,
                finding=z["result"]["finding"].replace("_", " ") if hit else None,
                pain_level=z["result"]["pain_level"] if hit else None,
                explanation=t["contribution"] if hit else t["missed"]))
    management, investigations = _management(scenario, s, redact=verdict == "not_submitted")
    return Feedback(
        session_id=s.id, case_id=s.case_id, diagnosis_submitted=s.diagnosis,
        total_score=sum(c.score for c in categories), max_score=sum(c.max_score for c in categories),
        summary=summary,
        transcript_available=has_transcript,
        diagnostic_assessment=DiagnosticAssessment(
            verdict=verdict, explanation=text,
            expected=diag["name"] if verdict != "not_submitted" else None),
        categories=categories, strengths=strengths, missed=missed,
        relevant_findings=relevant, next_steps=next_steps, documentation=documentation,
        management=management, investigations=investigations,
        fitting=(fitting.assess(scenario, s, verdict == "not_submitted", _hit) if "fitting" in hidden else
                 FittingAssessment(title="", score=0, max_score=0, criteria=[], final_fit=None, reference=None,
                                   explanation=None)),
        replay=replay, scan_review=_scan_review(scenario, s, redact=verdict == "not_submitted"),
        disclaimer=DISCLAIMER)


def _scan_findings(us: dict, s: Session, redact: bool) -> list[str]:
    """Ultrasound: what the scans produced. Before a diagnosis only the neutral region and whether an
    image appeared; after it, each obtained view with its measurements."""
    if redact:
        regions = {r["id"]: r["label"] for r in us["regions"]}
        out = []
        for rid in dict.fromkeys(e["region_id"] for e in sorted(s.scans, key=lambda e: e["seq"])):
            good = any(e["region_id"] == rid and e["quality"] == "good" for e in s.scans)
            out.append(f"{regions[rid]}: " + ("image obtained" if good else "no usable image (no gel)"))
        return out
    views = {v["id"]: v for v in us["views"]}
    out = []
    for vid in ultrasound.obtained_views(s):
        v = views[vid]
        detail = ", ".join(f"{m['label']} {m['value']:g} {m['unit']}" for m in v["measurements"]) or v["caption"]
        out.append(f"{v['title']}: {detail}")
    return out


def _scan_review(scenario: dict, s: Session, redact: bool) -> list[ScanReviewItem]:
    """Views obtained versus expected (`hidden.scan_review`); empty before a diagnosis."""
    items = scenario["hidden"].get("scan_review")
    if redact or not items:
        return []
    obtained = ultrasound.obtained_views(s)
    images = {v["id"]: v["image"] for v in scenario["ultrasound"]["views"]}
    out = []
    for item in items:
        hit = next((v for v in obtained if v in item["views"]), None)
        out.append(ScanReviewItem(id=item["id"], label=item["label"], expected=item["expected"], obtained=hit is not None,
                                  view_id=hit, image=images[hit] if hit else item["image"],
                                  explanation=item["met_text"] if hit else item["missed_text"]))
    return out


def _summary(strengths, missed, explanation, has_transcript) -> str:
    parts = [] if has_transcript else [NO_TRANSCRIPT]
    if strengths:
        parts.append(strengths[0])
    if missed:
        parts.append("However, " + missed[0][:1].lower() + missed[0][1:])
    parts.append(explanation)
    return " ".join(parts)
