"""Live Scenario Director: predefined instructor events, coaching hints, and the debrief.

EVENTS are a closed set (EVENTS below). Each one changes only the per-session scenario state
in studio.Live: noise level, the bystander's mood, whether the helper is there, which
equipment is available, whether coaching is offered. No event has a path to the case data,
so findings, results and the rubric cannot change, and nothing that was already examined or
ordered is invalidated. There is deliberately no event that removes equipment or adds a
clinical complication. An event that cannot apply (no bystander, noise already at its
maximum, equipment the environment does not have) is rejected with a reason and not recorded.

PROTOCOL  /ws/sessions/{session_id}?role=runtime|director   (JSON text frames)
  director -> server  {"type":"event","event_id":"<uuid chosen by the sender>","kind":"...","params":{...}}
  server   -> runtime {"type":"event","seq","event_id","kind","label","line":{"speaker","text"}|null,
                       "voice_context":str|null,"scenario":ScenarioRuntime,"case":CasePublic}
  runtime  -> server  {"type":"ack","event_id","applied":bool,"detail":str}
  server   -> director {"type":"state", ...state()}   after every change, and on connect
  server   -> director {"type":"rejected","event_id","reason"}
DEDUPLICATION: an event_id is recorded once. Sending it again changes nothing and re-sends
the event to the runtime only if it has not been acknowledged. RECONNECTION: when a runtime
connects, every unacknowledged event is sent again in order; the runtime ignores event ids
it has already applied and acknowledges them again.
"""
from fastapi import WebSocket

from . import evaluation, fitting, studio
from .sessions import Session, now_iso, public_case

NOISE_STEP, NOISE_MAX = 0.25, 1.0
HINT_STEP = {"off": "on_request", "on_request": "auto"}

EVENTS = [
    {"kind": "bystander_anxious", "label": "Bystander becomes anxious"},
    {"kind": "helper_arrives", "label": "A helper arrives"},
    {"kind": "crowd_noise_up", "label": "Crowd noise increases"},
    {"kind": "deliver_equipment", "label": "Deliver an equipment item", "param": "item"},
    {"kind": "enable_coaching", "label": "Make coaching available"},
]

# session id -> role -> sockets
HUB: dict[str, dict[str, set[WebSocket]]] = {}


def _sockets(session_id: str, role: str) -> set[WebSocket]:
    return HUB.setdefault(session_id, {"runtime": set(), "director": set()})[role]


def _deliverable(live: studio.Live) -> list[dict]:
    return [{"id": r.id, "label": r.label} for r in live.definition.resources
            if r.id not in live.available and r.unsupported_reason is None]


def _blocked(live: studio.Live, kind: str, params: dict) -> str | None:
    """Why the event cannot apply right now, or None."""
    if kind == "bystander_anxious":
        if live.mood is None:
            return "There is no bystander in this scenario."
        return "The bystander is already anxious." if live.mood == "anxious" else None
    if kind == "helper_arrives":
        return "The helper is already there." if live.teammate_present else None
    if kind == "crowd_noise_up":
        return "The noise is already at its maximum." if live.noise >= NOISE_MAX else None
    if kind == "enable_coaching":
        return "Coaching hints already appear automatically." if live.hint_policy == "auto" else None
    if kind == "deliver_equipment":
        item = params.get("item")
        r = next((r for r in live.definition.resources if r.id == item), None)
        if r is None:
            return f"'{item}' is not an equipment item of this case."
        if r.unsupported_reason:
            return f"{r.label} cannot be delivered. {r.unsupported_reason}"
        return f"{r.label} is already available." if r.id in live.available else None
    return f"'{kind}' is not a director event."


def _apply(live: studio.Live, kind: str, params: dict, seq: int) -> tuple[dict | None, str]:
    """Mutates `live`; returns (spoken line or None, context note for the patient's voice agent)."""
    t = live.template
    if kind == "bystander_anxious":
        live.mood = "anxious"
        b = live.definition.companions["bystander"]
        return ({"speaker": b["name"], "text": b["lines"]["anxious"][0]},
                f"[Context only, do not speak now. {t['bystander']['anxious_context']}]")
    if kind == "helper_arrives":
        live.teammate_present = True
        return ({"speaker": t["teammate"]["name"], "text": t["teammate"]["arrival_line"]},
                f"[Context only, do not speak now. {t['teammate']['context']}]")
    if kind == "crowd_noise_up":
        live.noise = round(min(NOISE_MAX, live.noise + NOISE_STEP), 2)
        return None, ("[Context only, do not speak now. It has become louder around you. If you cannot hear the "
                      "student well, you may ask them to speak up. The facts of your case do not change.]")
    if kind == "enable_coaching":
        live.hint_policy = HINT_STEP[live.hint_policy]
        return None, ""
    item = next(r for r in live.definition.resources if r.id == params["item"])
    live.available.add(item.id)
    live.delivered[item.id] = seq
    line = {"speaker": t["teammate"]["name"], "text": t["teammate"]["delivery_line"].format(item=item.label)} \
        if live.teammate_present else None
    return line, f"[Context only, do not speak now. Someone brought in more equipment: {item.label}.]"


def state(scenario: dict, s: Session) -> dict:
    """What the director panel shows: scenario state, what may be triggered, what happened."""
    live = studio.LIVE[s.id]
    events = []
    for e in EVENTS:
        if e.get("param"):
            options = _deliverable(live)
            events.append(e | {"options": options, "enabled": bool(options),
                               "reason": None if options else "Nothing left that can be delivered here."})
        else:
            reason = _blocked(live, e["kind"], {})
            events.append(e | {"enabled": reason is None, "reason": reason})
    return {"session_id": s.id, "started_at": s.started_at, "runtime_connected": bool(_sockets(s.id, "runtime")),
            "scenario": studio.runtime(live).model_dump(), "events": events, "interventions": live.interventions,
            "hints": live.hints,
            "activity": {"learner_turns": sum(t["role"] == "learner" for t in s.interactions),
                         "examinations": len(s.examinations), "investigations": len(s.investigations),
                         "measurements": len(s.measurements), "fit_changes": len(s.fittings),
                         "diagnosis_submitted": s.diagnosis is not None}}


def _message(scenario: dict, s: Session, live: studio.Live, iv: dict) -> dict:
    return {"type": "event", **{k: iv[k] for k in ("seq", "event_id", "kind", "label", "line", "voice_context")},
            "scenario": studio.runtime(live).model_dump(),
            "case": studio.shape_case(public_case(scenario), live).model_dump()}


async def _send(session_id: str, role: str, message: dict) -> None:
    for ws in list(_sockets(session_id, role)):
        try:
            await ws.send_json(message)
        except Exception:  # noqa: BLE001 - a dead socket must not block the others
            _sockets(session_id, role).discard(ws)


async def broadcast_state(scenario: dict, s: Session) -> None:
    if s.id in studio.LIVE:
        await _send(s.id, "director", {"type": "state", **state(scenario, s)})


async def submit(scenario: dict, s: Session, event_id: str, kind: str, params: dict) -> dict:
    """Validate, record once, apply and forward. Returns {"accepted", "duplicate", "reason", "intervention"}."""
    live = studio.LIVE[s.id]
    known = next((i for i in live.interventions if i["event_id"] == event_id), None)
    if known:
        if not known["acknowledged"]:
            await _send(s.id, "runtime", _message(scenario, s, live, known))
        return {"accepted": True, "duplicate": True, "reason": None, "intervention": known}
    if s.diagnosis is not None:
        return {"accepted": False, "duplicate": False, "reason": "The student has already submitted.", "intervention": None}
    reason = _blocked(live, kind, params)
    if reason:
        return {"accepted": False, "duplicate": False, "reason": reason, "intervention": None}
    seq = s.next_seq()
    line, voice_context = _apply(live, kind, params, seq)
    label = next(e["label"] for e in EVENTS if e["kind"] == kind)
    if kind == "deliver_equipment":
        label += f": {next(r.label for r in live.definition.resources if r.id == params['item'])}"
    iv = {"seq": seq, "event_id": event_id, "kind": kind, "label": label, "params": params, "at": now_iso(),
          "line": line, "voice_context": voice_context or None, "acknowledged": False, "ack_detail": None}
    live.interventions.append(iv)
    await _send(s.id, "runtime", _message(scenario, s, live, iv))
    await broadcast_state(scenario, s)
    return {"accepted": True, "duplicate": False, "reason": None, "intervention": iv}


async def acknowledge(scenario: dict, s: Session, event_id: str, applied: bool, detail: str) -> None:
    live = studio.LIVE.get(s.id)
    iv = next((i for i in live.interventions if i["event_id"] == event_id), None) if live else None
    if iv and not iv["acknowledged"]:
        iv["acknowledged"], iv["ack_detail"] = True, f"{'applied' if applied else 'NOT applied'}: {detail}"
        await broadcast_state(scenario, s)


async def connect(scenario: dict, s: Session, role: str, ws: WebSocket) -> None:
    _sockets(s.id, role).add(ws)
    live = studio.LIVE[s.id]
    if role == "runtime":  # whatever was missed while disconnected
        for iv in live.interventions:
            if not iv["acknowledged"]:
                await ws.send_json(_message(scenario, s, live, iv))
    await broadcast_state(scenario, s)


async def disconnect(scenario: dict, s: Session, role: str, ws: WebSocket) -> None:
    _sockets(s.id, role).discard(ws)
    await broadcast_state(scenario, s)


# MARK: Coaching hints

def _hint_due(when: dict, s: Session) -> bool:
    kind = when["type"]
    learner = [t for t in s.interactions if t["role"] == "learner"]
    if kind == "always":
        return True
    if kind == "no_learner_turns":
        return not learner
    if kind == "no_examination":
        return not s.examinations
    if kind == "examined_fewer_than":
        return len({e["zone_id"] for e in s.examinations}) < when["count"]
    if kind == "pain_not_acknowledged":
        pain = next((e["seq"] for e in s.examinations if e["pain_level"] >= 5), None)
        return pain is not None and not any(t["seq"] > pain for t in learner)
    if kind == "not_ordered":
        return not s.investigations
    if kind == "not_measured":
        return not s.measurements
    if kind == "not_checked":
        return not any(c["check"] == when["check"] for c in s.checks)
    if kind == "fit_unchecked":
        return fitting.current(s) is not None and not any(c["seq"] > s.fittings[-1]["seq"] for c in s.checks)
    raise ValueError(f"unknown hint condition {kind!r}")


def next_hint(s: Session) -> dict:
    """The first hint of the template that applies to what the student has done so far and
    has not been given yet. Recorded for the debrief. {"policy", "hint": {"id","text"} | None}."""
    live = studio.LIVE[s.id]
    if live.hint_policy == "off":
        return {"policy": "off", "hint": None}
    given = {h["id"] for h in live.hints}
    hint = next((h for h in live.template["hints"]
                 if h["id"] not in given and studio._hint_fits(h, live.template, live.available)
                 and _hint_due(h["when"], s)), None)
    if hint is None:
        return {"policy": live.hint_policy, "hint": None}
    live.hints.append({"seq": s.next_seq(), "id": hint["id"], "text": hint["text"], "at": now_iso()})
    return {"policy": live.hint_policy, "hint": {"id": hint["id"], "text": hint["text"]}}


# MARK: Debrief

def debrief(scenario: dict, s: Session) -> dict:
    """Existing feedback, unchanged, plus what it was earned under: configuration, resources,
    instructor interventions, hints, and the student's decisions in order."""
    fb = evaluation.evaluate(scenario, s)
    live = studio.LIVE.get(s.id)
    labels = {z["id"]: z["label"] for z in scenario["examination_zones"]}  # neutral labels: no spoiler
    invs = {i["id"]: i["label"] for i in scenario.get("investigations", [])}

    timeline = [{"seq": t["seq"], "type": "question", "label": t["text"]} for t in s.interactions if t["role"] == "learner"]
    timeline += [{"seq": e["seq"], "type": "examination", "label": f"Examined {labels[e['zone_id']]}"} for e in s.examinations]
    timeline += [{"seq": o["seq"], "type": "investigation", "label": f"Requested {invs[o['investigation_id']]}"} for o in s.investigations]
    timeline += [{"seq": m["seq"], "type": "measurement", "label": f"Measured {m['measurement_id'].replace('_', ' ')}: {m['value_cm']} cm"}
                 for m in s.measurements]
    timeline += [{"seq": f["seq"], "type": "fitting",
                  "label": f"Support {f['fit']['size']}, {f['fit']['tightness']}" if f["fit"] else "Support removed"} for f in s.fittings]
    timeline += [{"seq": c["seq"], "type": "check", "label": f"Checked {c['check']}"} for c in s.checks]

    scores = {"core": {"score": fb.total_score, "max_score": fb.max_score},
              "management": {"score": fb.management.score, "max_score": fb.management.max_score},
              "fitting": {"score": fb.fitting.score, "max_score": fb.fitting.max_score}}
    out = {"session_id": s.id, "case_id": s.case_id, "scenario": None, "resources": [], "interventions": [],
           "hints": [], "interpretation": ["Fixed default case: every resource of the case was available, "
                                           "no instructor interventions, no coaching."]}
    if live:
        d = live.definition
        timeline += [{"seq": i["seq"], "type": "intervention", "label": f"Instructor: {i['label']}"} for i in live.interventions]
        timeline += [{"seq": h["seq"], "type": "hint", "label": f"Coaching hint: {h['text']}"} for h in live.hints]
        used = ({o["investigation_id"] for o in s.investigations} | {f["fit"]["size"] for f in s.fittings if f["fit"]}
                | ({"tape"} if s.measurements else set()))
        resources = [{"id": r.id, "label": r.label, "kind": r.kind, "available_at_start": r.available,
                      "delivered_at_seq": live.delivered.get(r.id), "available_at_end": r.id in live.available,
                      "used": (r.kind == "measurement_tool" and "tape" in used)
                              or next(e.get("ref") for e in live.template["equipment"] if e["id"] == r.id) in used}
                     for r in d.resources]
        dims = {x.id: x for x in studio.assessability(scenario, live.template, live.available)}
        notes = [f"Difficulty: {d.difficulty['label']}. {d.difficulty['description']}",
                 f"Setting: {d.environment['label']}, {d.environment['crowd']['label'].lower()}; "
                 f"noise level {round(live.noise * 100)}% at the end."]
        for key in ("management", "fitting"):
            dim = dims[key]
            scores[key] |= {"achievable_max": dim.achievable_max, "not_assessable": dim.not_assessable}
            if dim.not_assessable:
                notes.append(f"{dim.title}: {scores[key]['score']} of {dim.achievable_max} achievable points "
                             f"(the rubric maximum of {dim.max_score} includes "
                             f"{', '.join(repr(b['label']) for b in dim.not_assessable)}, which could not be earned here).")
        if live.delivered:
            notes.append("Delivered during the session: " + ", ".join(r["label"] for r in resources if r["delivered_at_seq"])
                         + ". Criteria that need them count as achievable from that point.")
        notes.append(f"Coaching hints given: {len(live.hints)}." if live.hints else "No coaching hints were given.")
        notes.append(f"Instructor interventions: {len(live.interventions)}"
                     + (" (" + "; ".join(i["label"] for i in live.interventions) + ")." if live.interventions else "."))
        if d.review.state != "clinician_reviewed":
            notes.append(f"This scenario is {d.review.state}, not clinician-reviewed.")
        out |= {"scenario": {"scenario_id": d.scenario_id, "version": d.version, "code": d.code, "title": d.title,
                             "review_state": d.review.state, "template_id": d.config.template_id, "seed": d.seed,
                             "environment": d.environment["label"], "crowdedness": d.environment["crowd"]["label"],
                             "difficulty": d.difficulty["label"], "bystander": d.config.bystander,
                             "teammate": d.config.teammate,
                             "learning_objectives": d.assessment["learning_objectives"]},
                "resources": resources, "interventions": live.interventions, "hints": live.hints,
                "interpretation": notes}
    return out | {"scores": scores, "timeline": sorted(timeline, key=lambda e: e["seq"]),
                  "diagnosis_submitted": s.diagnosis, "feedback": fb.model_dump()}
