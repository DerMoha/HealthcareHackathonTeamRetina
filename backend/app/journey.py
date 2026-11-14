"""Continuous journey cases (`scenario["journey"]`): places the encounter moves through and the
AI medical team that helps there. Mirrors OfflineClinicalEngine's journey section in Swift.

Rules:
- The session starts in stages[0]. `advance` moves to the NEXT stage only (no skipping, no going back).
- A team action is looked up in the CURRENT stage; the same id may exist in several stages with
  different results. It is done only when every id in `requires` was done before (in any stage);
  otherwise the member answers with `blocked_response` and the request is recorded with done=False.
- An investigation listed in any stage can only be requested while in one of those stages.
- Nothing here is ever produced by the voice model: the engine supplies every line and result.
"""
from .models import StageResult, TeamActionResult
from .sessions import Session


class JourneyError(Exception):
    def __init__(self, status: int, detail: str):
        self.status, self.detail = status, detail


def current(scenario: dict, s: Session) -> dict:
    stages = scenario["journey"]["stages"]
    sid = s.stages[-1]["stage_id"] if s.stages else stages[0]["id"]
    return next(st for st in stages if st["id"] == sid)


def stage_at(scenario: dict, s: Session, seq: int) -> str:
    """Stage the session was in when the event with `seq` happened."""
    before = [e for e in s.stages if e["seq"] < seq]
    return before[-1]["stage_id"] if before else scenario["journey"]["stages"][0]["id"]


def _member(scenario: dict, member_id: str) -> dict:
    """Unknown ids fall back to the id as name (same as the Swift engine)."""
    return next((m for m in scenario["journey"]["team"] if m["id"] == member_id),
                {"id": member_id, "name": member_id, "role": ""})


def context_note(member: dict, text: str) -> str:
    """What the voice agent learns about a team line it must not answer."""
    return f"[Context only, do not speak now. {member['name']} ({member['role']}) just said: \"{text}\"]"


def advance(scenario: dict, s: Session, stage_id: str) -> StageResult:
    j = scenario.get("journey")
    if j is None:
        raise JourneyError(404, "This case has no journey")
    stages = j["stages"]
    if not any(st["id"] == stage_id for st in stages):
        raise JourneyError(404, f"Unknown stage '{stage_id}'")
    here = stages.index(current(scenario, s))
    if here + 1 >= len(stages):
        raise JourneyError(409, f"The journey already ended at '{stages[here]['label']}'.")
    nxt = stages[here + 1]
    if nxt["id"] != stage_id:
        raise JourneyError(409, f"You can only move on to the next place: '{nxt['label']}'.")
    s.stages.append({"seq": s.next_seq(), "stage_id": stage_id})
    arrival = [{"member": line["member"], "speaker": _member(scenario, line["member"])["name"], "text": line["text"]}
               for line in nxt.get("arrival", [])]
    return StageResult(stage_id=stage_id, label=nxt["label"], index=here + 1, count=len(stages),
                       arrival=arrival, voice_context=nxt.get("voice_context", ""))


def team_action(scenario: dict, s: Session, action_id: str) -> TeamActionResult:
    if scenario.get("journey") is None:
        raise JourneyError(404, "This case has no medical team")
    stage = current(scenario, s)
    action = next((a for a in stage["actions"] if a["id"] == action_id), None)
    if action is None:
        allowed = ", ".join(a["id"] for a in stage["actions"])
        anywhere = any(a["id"] == action_id for st in scenario["journey"]["stages"] for a in st["actions"])
        if anywhere:
            raise JourneyError(409, f"'{action_id}' is not available {stage['label'].lower()}. Available here: {allowed}.")
        raise JourneyError(404, f"Unknown team action '{action_id}'. Available here: {allowed}.")
    done_before = {e["action_id"] for e in s.team_actions if e["done"]}
    done = all(r in done_before for r in action.get("requires", []))
    s.team_actions.append({"seq": s.next_seq(), "stage_id": stage["id"], "action_id": action_id, "done": done})
    member = _member(scenario, action["member"])
    response = action["response"] if done else action.get("blocked_response", "")
    patient = action.get("patient_response", "") if done else ""
    voice = (f"[{member['name']} ({member['role']}) is helping you. Say out loud right now, in one short sentence, "
             f"something with this meaning: \"{patient}\"]") if patient else context_note(member, response)
    repeat = sum(1 for e in s.team_actions if e["action_id"] == action_id and e["stage_id"] == stage["id"] and e["done"])
    return TeamActionResult(
        stage_id=stage["id"], action_id=action_id, label=action["label"],
        member={k: member[k] for k in ("id", "name", "role")}, done=done, response=response,
        result=action.get("result") if done else None, patient_response=patient, voice_context=voice,
        repeat_count=repeat)


def investigation_error(scenario: dict, s: Session, investigation_id: str) -> str | None:
    """Why the investigation cannot be requested here, or None when it can (or the case has no journey)."""
    j = scenario.get("journey")
    if j is None:
        return None
    where = [st for st in j["stages"] if investigation_id in st.get("investigations", [])]
    if not where or current(scenario, s) in where:
        return None
    return f"That investigation is not available {current(scenario, s)['label'].lower()}. " \
           f"It can be requested {' or '.join(st['label'].lower() for st in where)}."


def action_label(scenario: dict, stage_id: str, action_id: str) -> str:
    stage = next(st for st in scenario["journey"]["stages"] if st["id"] == stage_id)
    action = next(a for a in stage["actions"] if a["id"] == action_id)
    return f"{stage['label']}: {action['label']}"
