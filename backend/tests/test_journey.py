"""Road trauma journey case: roadside -> ambulance -> emergency department with an AI medical team."""
import json
import os
from pathlib import Path

import pytest

RT = "road_trauma_journey_001"
WRIST = "wrist_trauma_001"
FIXTURES = Path(__file__).parent / "fixtures"
DIAGNOSIS = "Open fracture of the right distal radius and ulna"
NOTES = {"history": "34-year-old cyclist knocked off by a car. Helmet, no head injury, no neck pain. Penicillin allergy.",
         "examination": "Bleeding wound over a deformity of the right distal forearm. Hand pink, sensation intact after splint.",
         "interpretation": "Displaced fractures of the radius and ulna with soft tissue gas.",
         "management": "IV antibiotics and tetanus given. Urgent orthopaedic referral for debridement and fixation in theatre.",
         "follow_up": "Admit, nil by mouth."}


def create(client, case_id=RT, **config):
    body = {"case_id": case_id}
    if config:
        body["config"] = config
    r = client.post("/sessions", json=body)
    assert r.status_code == 201, r.text
    return r.json()


@pytest.fixture
def jid(client):
    return create(client)["session_id"]


def say(client, sid, text, role="learner"):
    assert client.post(f"/sessions/{sid}/interactions", json={"role": role, "text": text}).status_code == 200


def team(client, sid, action):
    return client.post(f"/sessions/{sid}/team-actions", json={"action_id": action})


def done(client, sid, action):
    r = team(client, sid, action)
    assert r.status_code == 200, r.text
    return r.json()


def stage(client, sid, stage_id):
    return client.post(f"/sessions/{sid}/stage", json={"stage_id": stage_id})


def examine(client, sid, zone):
    assert client.post(f"/sessions/{sid}/examine", json={"body_part": zone, "action": "palpation"}).status_code == 200


def order(client, sid, inv):
    return client.post(f"/sessions/{sid}/investigations", json={"investigation_id": inv})


def crit(fb, cid):
    return next(c for cat in fb["categories"] for c in cat["criteria"] if c["id"] == cid)


def category(fb, cid):
    return next(c for c in fb["categories"] if c["id"] == cid)


def perfect_run(client, sid):
    say(client, sid, "Hello, I'm a medical student working with the ambulance crew. Can you tell me your name?")
    done(client, sid, "scene_safety")
    say(client, sid, "Did you hit your head or black out? Does your neck hurt?")
    for a in ("haemorrhage_control", "observations", "photograph_wound"):
        done(client, sid, a)
    examine(client, sid, "rt_forearm_wound")
    done(client, sid, "splint_arm")
    examine(client, sid, "rt_right_hand")
    done(client, sid, "analgesia")
    say(client, sid, "Do you have any allergies, take any medicines or have any medical problems?")
    assert stage(client, sid, "ambulance").status_code == 200
    for a in ("observations", "iv_access", "iv_analgesia", "pre_alert"):
        done(client, sid, a)
    assert stage(client, sid, "hospital").status_code == 200
    say(client, sid, "Handover: Jordan, 34-year-old cyclist knocked off by a car. Bleeding forearm wound, splinted, "
                     "heart rate down to 104, we've given Penthrox and morphine.")
    for a in ("iv_antibiotics", "tetanus", "orthopaedic_referral"):
        done(client, sid, a)
    assert order(client, sid, "rt_xray_forearm").status_code == 200
    return client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": DIAGNOSIS, "notes": NOTES}).json()


# ---------------------------------------------------------------- catalog and public data

def test_case_is_listed_spoiler_free_with_a_public_journey(client):
    cases = {c["case_id"]: c for c in client.get("/cases").json()}
    case = cases[RT]
    assert case["catalog"]["allowed_avatars"] == ["male", "female"] and case["catalog"]["allowed_moods"] == ["calm", "nervous"]
    assert cases[WRIST]["journey"] is None and cases["obstetric_ultrasound_001"]["journey"] is None
    shown = json.dumps([case["title"], case["learner_brief"], case["catalog"], case["voice_context"],
                        [z["label"] for z in case["zones"]], case["journey"]]).lower()
    for word in ["fracture", "compound", "radius", "ulna", "broken", "gustilo"]:
        assert word not in shown, word
    j = case["journey"]
    assert [m["id"] for m in j["team"]] == ["sam", "lena", "priya", "omar"]
    assert [s["id"] for s in j["stages"]] == ["scene", "ambulance", "hospital"]
    assert j["stages"][2]["investigations"] == ["rt_xray_forearm", "rt_ct_head", "rt_bloods"]
    for s in j["stages"]:
        assert set(s) == {"id", "label", "setting", "brief", "team", "noise", "arrival", "actions", "investigations"}
        assert all(set(a) == {"id", "label", "member"} and a["member"] in s["team"] for a in s["actions"])
        assert all(set(l) == {"member", "speaker", "text"} and l["member"] in s["team"] for l in s["arrival"])
    assert j["stages"][0]["arrival"][0]["speaker"] == "Sam"


def test_nothing_hidden_leaks_into_public_responses(client):
    sess = create(client)
    sid = sess["session_id"]
    for r in (client.get("/cases"), client.post(f"/sessions/{sid}/reset"), client.get(f"/sessions/{sid}/feedback")):
        text = r.text.lower()
        for word in ['"hidden"', "rubric", '"persona"', "patient_by_mood", "clinical_label", "blocked_response",
                     '"requires"', "heart rate 112", "vacuum splint", "bone visible", "soft-tissue gas"]:
            assert word not in text, (word, r.request.url)


# ---------------------------------------------------------------- stages

def test_stages_move_forward_one_at_a_time(client, jid):
    assert stage(client, jid, "hospital").status_code == 409
    assert stage(client, jid, "scene").status_code == 409
    assert stage(client, jid, "moon").status_code == 404
    r = stage(client, jid, "ambulance").json()
    assert (r["stage_id"], r["index"], r["count"], r["label"]) == ("ambulance", 1, 3, "In the ambulance")
    assert [(l["member"], l["speaker"]) for l in r["arrival"]] == [("lena", "Lena")]
    assert r["voice_context"].startswith("[Context only, do not speak now. You are now")
    h = stage(client, jid, "hospital").json()
    assert h["index"] == 2 and h["arrival"][0]["speaker"] == "Dr Omar"
    assert "already ended" in stage(client, jid, "hospital").json()["detail"]
    client.post(f"/sessions/{jid}/reset")
    assert stage(client, jid, "ambulance").status_code == 200  # reset is back at the roadside


def test_cases_without_a_journey_refuse_stages_and_team_actions(client, sid):
    assert stage(client, sid, "ambulance").status_code == 404
    assert team(client, sid, "observations").status_code == 404


# ---------------------------------------------------------------- team actions

def test_team_actions_belong_to_the_current_place(client, jid):
    assert team(client, jid, "teleport").status_code == 404
    r = team(client, jid, "iv_antibiotics")
    assert r.status_code == 409 and "not available at the roadside" in r.json()["detail"]
    obs = done(client, jid, "observations")
    assert obs["member"] == {"id": "lena", "name": "Lena", "role": "Emergency medical technician"}
    assert obs["done"] and "112" in obs["result"] and obs["patient_response"] == ""
    assert obs["voice_context"].startswith("[Context only, do not speak now. Lena (Emergency medical technician) just said:")
    assert done(client, jid, "observations")["repeat_count"] == 2
    bleed = done(client, jid, "haemorrhage_control")
    assert bleed["patient_response"] and bleed["voice_context"].startswith("[Sam (Paramedic) is helping you. Say out loud")
    stage(client, jid, "ambulance")
    again = done(client, jid, "observations")
    assert "104" in again["result"] and again["repeat_count"] == 1 and again["stage_id"] == "ambulance"


def test_a_missing_prerequisite_blocks_the_action(client, jid):
    stage(client, jid, "ambulance")
    blocked = done(client, jid, "iv_analgesia")
    assert not blocked["done"] and blocked["result"] is None and "IV access first" in blocked["response"]
    assert blocked["patient_response"] == "" and blocked["repeat_count"] == 0
    done(client, jid, "iv_access")
    ok = done(client, jid, "iv_analgesia")
    assert ok["done"] and "morphine" in ok["result"].lower() and ok["repeat_count"] == 1
    stage(client, jid, "hospital")
    assert done(client, jid, "iv_antibiotics")["done"]  # the ambulance cannula still counts


def test_investigations_only_at_the_hospital(client, jid):
    r = order(client, jid, "rt_xray_forearm")
    assert r.status_code == 409 and "in the emergency department" in r.json()["detail"]
    stage(client, jid, "ambulance")
    assert order(client, jid, "rt_ct_head").status_code == 409
    stage(client, jid, "hospital")
    x = order(client, jid, "rt_xray_forearm").json()
    assert "radius and ulna" in x["report"] and x["image"] is None
    assert order(client, jid, "rt_bloods").json()["modality"] == "Laboratory"


def test_wrist_investigations_are_not_restricted(client, sid):
    assert order(client, sid, "right_wrist_xray").status_code == 200


# ---------------------------------------------------------------- scoring

def test_perfect_journey_scores_100_and_full_management(client, jid):
    fb = perfect_run(client, jid)
    assert (fb["total_score"], fb["max_score"]) == (100, 100), [c for c in fb["missed"]]
    assert [(c["id"], c["score"]) for c in fb["categories"]] == [("scene", 35), ("transfer", 30), ("hospital", 35)]
    assert fb["management"]["score"] == fb["management"]["max_score"] == 20
    assert fb["diagnostic_assessment"]["verdict"] == "correct"
    assert crit(fb, "scene_safety")["evidence"] == "At the roadside: Check the scene is safe"
    assert crit(fb, "neurovascular_after_splint")["evidence"] == "Right hand: circulation, sensation and movement"
    assert crit(fb, "handover")["evidence"].startswith("Handover:")
    assert fb["investigations"][0].startswith("Right forearm radiographs")
    assert fb["fitting"]["max_score"] == 0 and fb["scan_review"] == []
    assert [r["zone_id"] for r in fb["replay"]] == ["rt_forearm_wound", "rt_right_hand", "rt_left_wrist"]
    assert {d["criterion_id"]: d["status"] for d in fb["documentation"]} == {"head_and_neck": "documented",
                                                                             "allergies": "documented"}


def test_points_follow_the_place_and_the_order(client, jid):
    examine(client, jid, "rt_right_hand")             # before the splint: no reassessment credit
    done(client, jid, "splint_arm")
    stage(client, jid, "ambulance")
    say(client, jid, "Handover: 34-year-old cyclist knocked off by a car.")  # said in the ambulance
    done(client, jid, "iv_analgesia")                 # refused: no cannula
    stage(client, jid, "hospital")
    done(client, jid, "observations")                 # only in hospital
    fb = client.post(f"/sessions/{jid}/diagnose", json={"diagnosis": "broken arm"}).json()
    for cid in ["neurovascular_after_splint", "handover", "pain_relief", "observations_scene", "repeat_observations",
                "scene_safety", "antibiotics"]:
        assert not crit(fb, cid)["met"], cid
    assert crit(fb, "splinted")["met"] and crit(fb, "splinted")["evidence"] == "At the roadside: Splint the arm"
    assert fb["diagnostic_assessment"]["verdict"] == "partial" and crit(fb, "diagnosis")["points"] == 5


def test_feedback_is_redacted_before_a_diagnosis(client, jid):
    done(client, jid, "scene_safety")
    pre = client.get(f"/sessions/{jid}/feedback").json()
    assert all(c["criteria"] == [] for c in pre["categories"]) and pre["management"]["criteria"] == []
    assert category(pre, "scene")["score"] == 5 and pre["replay"] == []


def test_unsafe_plan_and_missing_imaging(client, jid):
    stage(client, jid, "ambulance")
    stage(client, jid, "hospital")
    fb = client.post(f"/sessions/{jid}/diagnose", json={"diagnosis": "Open fracture", "notes": {
        "interpretation": "Displaced fractures.", "management": "Closed fracture, no antibiotics, discharge home."}}).json()
    m = {c["id"]: c for c in fb["management"]["criteria"]}
    assert not m["imaging_requested"]["met"] and not m["result_interpreted"]["met"]  # nothing was ordered
    assert not m["no_unsafe_discharge"]["met"] and not m["antibiotics_plan"]["met"]  # "no antibiotics" is negated


@pytest.mark.parametrize("text,verdict", [
    ("Open fracture right distal radius and ulna", "correct"), ("compound fracture of the forearm", "correct"),
    ("Gustilo II open forearm fracture", "correct"), ("offene Fraktur Unterarm", "correct"),
    ("fractured forearm", "partial"), ("distal radius fracture", "partial"), ("wrist sprain", "incorrect")])
def test_diagnosis_wording(client, text, verdict):
    sid = create(client)["session_id"]
    fb = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": text}).json()
    assert fb["diagnostic_assessment"]["verdict"] == verdict


# ---------------------------------------------------------------- parity with the Swift offline engine

def run_parity(client, case_id=RT):
    spec = json.loads((FIXTURES / "journey_parity_input.json").read_text(encoding="utf-8"))
    started = create(client, case_id, **spec["config"])
    sid = started["session_id"]
    results, feedback = [], None
    for s in spec["steps"]:
        op = s["op"]
        if op == "interaction":
            say(client, sid, s["text"], s["role"])
        elif op == "examine":
            examine(client, sid, s["body_part"])
        elif op in ("stage", "team", "investigate"):
            r = {"stage": lambda: stage(client, sid, s["stage_id"]), "team": lambda: team(client, sid, s["action_id"]),
                 "investigate": lambda: order(client, sid, s["investigation_id"])}[op]()
            body = r.json() if r.status_code == 200 else {"error": r.status_code}
            if op == "investigate" and r.status_code == 200:
                body["ordered_at"] = "TIME"
            results.append(body)
        else:
            feedback = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": s["diagnosis"], "notes": s["notes"]}).json()
    feedback["session_id"] = "SESSION"
    return {"case": started["case"], "config": started["config"], "results": results, "feedback": feedback}


def test_journey_parity_golden(client):
    """Golden for visionos/scripts/OfflineEngineCheck (Swift offline engine parity).
    Regenerate after editing the scenario: REGEN_FIXTURES=1 python -m pytest -k journey_parity."""
    got = run_parity(client)
    path = FIXTURES / "journey_parity_expected.json"
    if os.environ.get("REGEN_FIXTURES") or not path.exists():
        path.write_text(json.dumps(got, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    assert got == json.loads(path.read_text(encoding="utf-8"))
    errors = [r["error"] for r in got["results"] if "error" in r]
    assert errors == [409, 409, 409, 409]
    fb = got["feedback"]
    assert fb["diagnostic_assessment"]["verdict"] == "partial"
    assert not crit(fb, "neurovascular_after_splint")["met"] and not crit(fb, "handover")["met"]
