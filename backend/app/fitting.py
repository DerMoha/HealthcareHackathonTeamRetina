"""Measurement and orthosis fitting: predefined outcomes from the scenario, plus the rubric.

Educational simulation. Nothing here is a validated sizing rule; every dimension, outcome
and response comes from `orthotics` / `hidden.fitting` in the scenario JSON. Mirrored by the
Swift offline engine (same precedence, same templates).

OUTCOME of a fit (first match wins):
  wrong_position     offset_cm outside reference.offset_cm [min, max]
  wrong_orientation  orientation != reference.orientation
  too_small/too_large  size before/after reference.size in orthotics.sizes order
  too_tight/too_loose  tightness after/before reference.tightness in orthotics.tightness order
  appropriate
No support on the arm -> "none".

CHECKS (comfort, neurovascular) answer for the CURRENT fit; phase is "after" while a support
is on the arm, else "before".

RUBRIC check types:
  measured                 one of `measurements` was taken before the first fit (or no fit at all)
  checked_before_fit       `check` recorded before the first fit (or no fit at all)
  final_fit                a support is on the arm and every listed field matches the reference
  checked_after_final_fit  `check` recorded after the last fit change, while a support is on;
                           with `keywords`, a learner turn after that point also counts
"""
from .models import CriterionResult, FittingAssessment
from .sessions import Session

COMFORT_CONTEXT = ('[The student asks how the wrist support feels. Answer out loud right now in one short '
                   'sentence with this meaning: "{}"]')
NV_CONTEXT = ('[The student checks the colour, feeling and movement of your fingers. Answer out loud right '
              'now in one short sentence with this meaning: "{}"]')
FIT_NOTE = ('[Context only, do not speak now. A wrist support was just put on or adjusted on your right wrist. '
            'If the student asks how it feels, answer with this meaning: "{}"]')
UNPROMPTED_CONTEXT = ('[The wrist support on your right wrist was just adjusted and it does not feel right. Say so out '
                      'loud right now, unprompted, in one short sentence with this meaning: "{}"]')
REMOVED_NOTE = "[Context only, do not speak now. The wrist support was taken off again.]"


def measure(scenario: dict, s: Session, measurement_id: str, value_cm: float | None) -> dict | None:
    """Record a measurement. Returns None for an unknown id, {} when no value is available."""
    spec = next((m for m in scenario["orthotics"]["measurements"] if m["id"] == measurement_id), None)
    if spec is None:
        return None
    predefined = scenario["hidden"]["fitting"]["measurements"].get(measurement_id)
    value = predefined if predefined is not None else value_cm
    if value is None:
        return {}
    value = round(value, 1)
    s.measurements.append({"seq": s.next_seq(), "measurement_id": measurement_id, "value_cm": value})
    return {"measurement_id": measurement_id, "label": spec["label"], "kind": spec["kind"], "value_cm": value,
            "source": "case" if predefined is not None else "avatar"}


def outcome(scenario: dict, fit: dict | None) -> str:
    if fit is None:
        return "none"
    ref = scenario["hidden"]["fitting"]["reference"]
    sizes = [x["id"] for x in scenario["orthotics"]["sizes"]]
    levels = scenario["orthotics"]["tightness"]
    lo, hi = ref["offset_cm"]
    if not lo <= fit["offset_cm"] <= hi:
        return "wrong_position"
    if fit["orientation"] != ref["orientation"]:
        return "wrong_orientation"
    if fit["size"] != ref["size"]:
        return "too_small" if sizes.index(fit["size"]) < sizes.index(ref["size"]) else "too_large"
    if fit["tightness"] != ref["tightness"]:
        return "too_tight" if levels.index(fit["tightness"]) > levels.index(ref["tightness"]) else "too_loose"
    return "appropriate"


def valid(scenario: dict, fit: dict | None) -> bool:
    o = scenario["orthotics"]
    return fit is None or (fit["size"] in [x["id"] for x in o["sizes"]] and fit["tightness"] in o["tightness"])


def current(s: Session) -> dict | None:
    return s.fittings[-1]["fit"] if s.fittings else None


def record_fit(scenario: dict, s: Session, fit: dict | None) -> dict:
    s.fittings.append({"seq": s.next_seq(), "fit": fit})
    spec = scenario["hidden"]["fitting"]["outcomes"][outcome(scenario, fit)]
    note = FIT_NOTE.format(spec["patient_response"]) if fit else REMOVED_NOTE
    return {"attempt": sum(1 for f in s.fittings if f["fit"]), "voice_note": note,
            "comfortable": spec["comfortable"], "patient_response": spec["patient_response"],
            "voice_context": UNPROMPTED_CONTEXT.format(spec["patient_response"]), "animation": spec["animation"]}


def check(scenario: dict, s: Session, kind: str) -> dict:
    fit = current(s)
    spec = scenario["hidden"]["fitting"]["outcomes"][outcome(scenario, fit)]
    s.checks.append({"seq": s.next_seq(), "check": kind})
    nv = kind == "neurovascular"
    response = spec["neurovascular_response"] if nv else spec["patient_response"]
    return {"check": kind, "phase": "after" if fit else "before",
            "finding": spec["neurovascular"] if nv else None, "patient_response": response,
            "voice_context": (NV_CONTEXT if nv else COMFORT_CONTEXT).format(response),
            "comfortable": spec["comfortable"], "animation": "none" if nv else spec["animation"]}


def assess(scenario: dict, s: Session, redact: bool, hit) -> FittingAssessment:
    spec = scenario["hidden"]["fitting"]
    ref = spec["reference"]
    fit = current(s)
    first_fit = next((f["seq"] for f in s.fittings if f["fit"]), float("inf"))
    last_change = s.fittings[-1]["seq"] if s.fittings else None

    def met(check: dict) -> bool:
        kind = check["type"]
        if kind == "measured":
            return any(m["measurement_id"] in check["measurements"] and m["seq"] < first_fit for m in s.measurements)
        if kind == "checked_before_fit":
            return any(c["check"] == check["check"] and c["seq"] < first_fit for c in s.checks)
        if kind == "final_fit":
            if fit is None:
                return False
            lo, hi = ref["offset_cm"]
            return all(lo <= fit[f] <= hi if f == "offset_cm" else fit[f] == ref[f] for f in check["fields"])
        if kind == "checked_after_final_fit":
            if fit is None:
                return False
            if any(c["check"] == check["check"] and c["seq"] > last_change for c in s.checks):
                return True
            return any(t["role"] == "learner" and t["seq"] > last_change and hit(t["text"], check.get("keywords", []))
                       for t in s.interactions)
        raise ValueError(f"unknown fitting check type {kind!r}")

    results = []
    for c in spec["rubric"]["criteria"]:
        ok = met(c["check"])
        results.append(CriterionResult(
            id=c["id"], label=c["label"], met=ok, points=c["points"] if ok else 0, max_points=c["points"],
            method="rule", evidence=None, comment=c["met_text"] if ok else c["missed_text"], area=c["area"]))
    return FittingAssessment(
        title=spec["rubric"]["title"], score=sum(r.points for r in results), max_score=spec["rubric"]["max_score"],
        criteria=[] if redact else results, final_fit=fit, reference=None if redact else ref,
        explanation=None if redact else spec["outcomes"][outcome(scenario, fit)]["explanation"])
