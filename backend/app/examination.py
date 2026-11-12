"""Zone lookup -> clinical finding."""
from .models import ExamineResult
from .sessions import Session


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
