"""Zone lookup -> clinical finding."""
from .models import ExamineResult
from .sessions import Session, now_iso


def examine(scenario: dict, session: Session, body_part: str, action: str) -> ExamineResult | None:
    """Record the examination and return its result, or None for an unknown zone."""
    zone = next((z for z in scenario["examination_zones"] if z["id"] == body_part), None)
    if zone is None:
        return None
    r = zone["result"]
    session.examinations.append({"seq": session.next_seq(), "zone_id": body_part,
                                 "action": action, "pain_level": r["pain_level"]})
    repeat = sum(e["zone_id"] == body_part for e in session.examinations)
    return ExamineResult(body_part=body_part, action=action, repeat_count=repeat, **r)


def investigate(scenario: dict, s: Session, investigation_id: str) -> dict | None:
    """Record an ordered investigation and return the scenario's predefined result."""
    inv = next((i for i in scenario.get("investigations", []) if i["id"] == investigation_id), None)
    if inv is None:
        return None
    ordered_at = now_iso()
    s.investigations.append({"seq": s.next_seq(), "investigation_id": investigation_id, "ordered_at": ordered_at})
    return {"investigation_id": inv["id"], "label": inv["label"], "modality": inv["modality"], **inv["result"],
            "ordered_at": ordered_at,
            "repeat_count": sum(1 for o in s.investigations if o["investigation_id"] == investigation_id)}
