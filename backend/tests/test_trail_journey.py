"""Forest-trail variant of the road trauma journey: trail -> ambulance -> emergency department.
Same patient, findings, team and scoring as road_trauma_journey_001; only the mechanism and the first place differ."""
import json
import re

import pytest

from app import director, main, studio

TRAIL = "trail_trauma_journey_001"
ROAD = "road_trauma_journey_001"
DIAGNOSIS = "Open fracture of the right distal radius and ulna"
NOTES = {"history": "34-year-old mountain biker, over the handlebars onto the right arm on a forest trail. Helmet, "
                    "no head injury, no neck pain. Penicillin allergy.",
         "examination": "Bleeding wound over a deformity of the right distal forearm. Hand pink, sensation intact after splint.",
         "interpretation": "Displaced fractures of the radius and ulna with soft tissue gas.",
         "management": "IV antibiotics and tetanus given. Urgent orthopaedic referral for debridement and fixation in theatre.",
         "follow_up": "Admit, nil by mouth."}
PLACE_WORDS = ("forest", "trail", "woods")  # the app picks the 3D place from a stage's `setting`


@pytest.fixture(autouse=True)
def library(tmp_path, monkeypatch):
    monkeypatch.setenv("MEDSIM_STUDIO_DB", str(tmp_path / "library.json"))
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    for var in ("AWS_ACCESS_KEY_ID", "AWS_PROFILE"):
        monkeypatch.delenv(var, raising=False)
    studio.LIVE.clear()
    director.HUB.clear()


def create(client, **body):
    r = client.post("/sessions", json={"case_id": TRAIL} | body)
    assert r.status_code == 201, r.text
    return r.json()


@pytest.fixture
def tid(client):
    return create(client)["session_id"]


def say(client, sid, text):
    assert client.post(f"/sessions/{sid}/interactions", json={"role": "learner", "text": text}).status_code == 200


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


def perfect_run(client, sid, handover):
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
    say(client, sid, handover)
    for a in ("iv_antibiotics", "tetanus", "orthopaedic_referral"):
        done(client, sid, a)
    assert order(client, sid, "rt_xray_forearm").status_code == 200
    return client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": DIAGNOSIS, "notes": NOTES}).json()


# ---------------------------------------------------------------- the case file

def _strip_text(node):
    """The case without its wording: ids, numbers, check types, stages and requirements only."""
    if isinstance(node, dict):
        return {k: _strip_text(v) for k, v in node.items()
                if k not in {"title", "label", "met_text", "missed_text", "name", "keywords", "_doc"}}
    if isinstance(node, list):
        return [_strip_text(v) for v in node]
    return node


def test_trail_case_is_a_variant_with_the_road_case_findings_and_scoring():
    trail, road = main.SCENARIOS[TRAIL], main.SCENARIOS[ROAD]
    assert ROAD in trail["_doc"] and "not separately clinician-reviewed" in trail["_doc"].lower()
    for key in ("schema_version", "persona", "examination_zones", "investigations", "orthotics"):
        assert trail[key] == road[key], key
    assert trail["patient"]["name"] == road["patient"]["name"] and trail["patient"]["age"] == road["patient"]["age"]
    assert {k: v for k, v in trail["catalog"].items() if k not in {"summary", "icon", "setting"}} == \
        {k: v for k, v in road["catalog"].items() if k not in {"summary", "icon", "setting"}}
    assert [d["id"] for d in trail["scripted_dialogue"]] == [d["id"] for d in road["scripted_dialogue"]]
    # same rubric and management: ids, points, check types, stages, zones, actions
    assert _strip_text(trail["hidden"]["rubric"]) == _strip_text(road["hidden"]["rubric"])
    assert _strip_text(trail["hidden"]["management"]) == _strip_text(road["hidden"]["management"])
    td, rd = trail["hidden"]["diagnosis"], road["hidden"]["diagnosis"]
    assert {k: v for k, v in td.items() if k != "name"} == {k: v for k, v in rd.items() if k != "name"}
    # same team and actions; results and prerequisites unchanged except the scene check on the trail
    tj, rj = trail["journey"], road["journey"]
    assert tj["team"] == rj["team"]
    for ts, rs in zip(tj["stages"], rj["stages"], strict=True):
        assert (ts["id"], ts["team"], ts["investigations"]) == (rs["id"], rs["team"], rs["investigations"])
        assert [a["id"] for a in ts["actions"]] == [a["id"] for a in rs["actions"]]
        for ta, ra in zip(ts["actions"], rs["actions"]):
            if ta["id"] != "scene_safety":
                assert ({k: v for k, v in ta.items() if k != "response"} == {k: v for k, v in ra.items() if k != "response"}), ta["id"]
    assert tj["stages"][1]["setting"] == rj["stages"][1]["setting"] and tj["stages"][2] == rj["stages"][2]


def test_trail_mechanism_replaces_the_road_one_everywhere():
    trail = {k: v for k, v in main.SCENARIOS[TRAIL].items() if k != "_doc"}
    text = json.dumps(trail, ensure_ascii=False).lower()
    for word in ("a car", "the car", "car's", "hit by a car", "police", "driver", "roadside", "side road",
                 "knocked off", "low wall", "traffic", "cyclist"):
        assert not re.search(rf"\b{re.escape(word)}\b", text), word
    for word in ("handlebars", "root", "hikers", "fire road", "mountain bike"):
        assert word in text, word
    scene = trail["journey"]["stages"][0]
    assert scene["label"] == "On the trail" and scene["setting"].startswith("Forest trail")
    for later in trail["journey"]["stages"][1:]:  # must still be shown as the ambulance and the hospital
        assert not any(w in later["setting"].lower() for w in PLACE_WORDS), later["id"]
    assert trail["hidden"]["rubric"]["categories"][0]["title"] == "On the trail"
    handover = next(c for cat in trail["hidden"]["rubric"]["categories"] for c in cat["criteria"] if c["id"] == "handover")
    assert {"over the handlebars", "came off", "mountain bike"} <= set(handover["check"]["keywords"])


# ---------------------------------------------------------------- catalog and public data

def test_trail_case_is_listed_spoiler_free_with_a_public_journey(client):
    cases = {c["case_id"]: c for c in client.get("/cases").json()}
    case = cases[TRAIL]
    assert ROAD in cases  # the road case is still there
    assert case["catalog"]["icon"] == "bicycle" and case["catalog"]["setting"].startswith("Forest trail")
    shown = json.dumps([case["title"], case["learner_brief"], case["catalog"], case["voice_context"],
                        [z["label"] for z in case["zones"]], case["journey"]]).lower()
    for word in ["fracture", "compound", "radius", "ulna", "broken", "gustilo"]:
        assert word not in shown, word
    j = case["journey"]
    assert [m["id"] for m in j["team"]] == ["sam", "lena", "priya", "omar"]
    assert [(s["id"], s["label"]) for s in j["stages"]] == [
        ("scene", "On the trail"), ("ambulance", "In the ambulance"), ("hospital", "In the emergency department")]
    assert j["stages"][0]["setting"] == "Forest trail, a mountain bike off the path, hikers around"
    assert j["stages"][2]["investigations"] == ["rt_xray_forearm", "rt_ct_head", "rt_bloods"]
    for s in j["stages"]:
        assert set(s) == {"id", "label", "setting", "brief", "team", "noise", "arrival", "actions", "investigations"}
    assert j["stages"][0]["arrival"][0]["speaker"] == "Sam" and "fire road" in j["stages"][0]["arrival"][0]["text"]


def test_trail_nothing_hidden_leaks_into_public_responses(client):
    sid = create(client)["session_id"]
    for r in (client.get("/cases"), client.post(f"/sessions/{sid}/reset"), client.get(f"/sessions/{sid}/feedback")):
        text = r.text.lower()
        for word in ['"hidden"', "rubric", '"persona"', "patient_by_mood", "clinical_label", "blocked_response",
                     '"requires"', "heart rate 112", "vacuum splint", "bone visible", "soft-tissue gas", '"_doc"']:
            assert word not in text, (word, r.request.url)


# ---------------------------------------------------------------- stages and the team

def test_trail_stages_move_forward_one_at_a_time(client, tid):
    assert stage(client, tid, "hospital").status_code == 409
    assert stage(client, tid, "scene").status_code == 409
    r = stage(client, tid, "ambulance").json()
    assert (r["stage_id"], r["index"], r["count"], r["label"]) == ("ambulance", 1, 3, "In the ambulance")
    assert r["arrival"][0]["speaker"] == "Lena" and "along the trail" in r["arrival"][0]["text"]
    assert r["voice_context"].startswith("[Context only, do not speak now. You are now")
    h = stage(client, tid, "hospital").json()
    assert h["index"] == 2 and h["arrival"][0]["speaker"] == "Dr Omar"
    assert "already ended" in stage(client, tid, "hospital").json()["detail"]
    client.post(f"/sessions/{tid}/reset")
    assert stage(client, tid, "ambulance").status_code == 200  # reset is back on the trail


def test_trail_team_actions_belong_to_the_current_place(client, tid):
    r = team(client, tid, "iv_antibiotics")
    assert r.status_code == 409 and "not available on the trail" in r.json()["detail"]
    safe = done(client, tid, "scene_safety")
    assert safe["member"]["id"] == "sam" and "hikers" in safe["result"] and "police" not in safe["response"].lower()
    assert "112" in done(client, tid, "observations")["result"]
    stage(client, tid, "ambulance")
    blocked = done(client, tid, "iv_analgesia")
    assert not blocked["done"] and "IV access first" in blocked["response"]
    done(client, tid, "iv_access")
    assert done(client, tid, "iv_analgesia")["done"]
    assert "mountain biker" in done(client, tid, "pre_alert")["response"]
    assert order(client, tid, "rt_xray_forearm").status_code == 409
    stage(client, tid, "hospital")
    assert "radius and ulna" in order(client, tid, "rt_xray_forearm").json()["report"]


# ---------------------------------------------------------------- scoring

def test_trail_perfect_journey_scores_100_and_full_management(client, tid):
    fb = perfect_run(client, tid, "Handover: Jordan, 34-year-old mountain biker who went over the handlebars on a "
                                  "forest trail. Bleeding forearm wound, splinted, heart rate down to 104, we've given "
                                  "Penthrox and morphine.")
    assert (fb["total_score"], fb["max_score"]) == (100, 100), fb["missed"]
    assert [(c["id"], c["title"], c["score"]) for c in fb["categories"]] == [
        ("scene", "On the trail", 35), ("transfer", "In the ambulance", 30), ("hospital", "In the emergency department", 35)]
    assert fb["management"]["score"] == fb["management"]["max_score"] == 20
    assert fb["diagnostic_assessment"]["verdict"] == "correct"
    assert crit(fb, "scene_safety")["evidence"] == "On the trail: Check the scene is safe"
    assert {d["criterion_id"]: d["status"] for d in fb["documentation"]} == {"head_and_neck": "documented",
                                                                             "allergies": "documented"}


def test_trail_scores_like_the_road_case_for_the_same_run(client):
    """Same actions, same handover structure: same points per criterion in both cases."""
    def run(case_id, handover):
        sid = client.post("/sessions", json={"case_id": case_id}).json()["session_id"]
        return perfect_run(client, sid, handover)
    road = run(ROAD, "Handover: Jordan, 34, knocked off by a car.")
    trail = run(TRAIL, "Handover: Jordan, 34, over the handlebars on a trail.")
    points = lambda fb: [(c["id"], c["points"], c["met"]) for cat in fb["categories"] for c in cat["criteria"]]  # noqa: E731
    assert points(road) == points(trail)
    assert road["management"]["score"] == trail["management"]["score"]


def test_trail_mechanism_counts_as_a_handover_only_at_the_hospital(client, tid):
    stage(client, tid, "ambulance")
    say(client, tid, "He came off his mountain bike, over the handlebars onto his right arm.")  # in the ambulance
    stage(client, tid, "hospital")
    fb = client.post(f"/sessions/{tid}/diagnose", json={"diagnosis": "broken arm"}).json()
    assert not crit(fb, "handover")["met"] and fb["diagnostic_assessment"]["verdict"] == "partial"

    sid = create(client)["session_id"]
    stage(client, sid, "ambulance")
    stage(client, sid, "hospital")
    say(client, sid, "He came off his mountain bike, over the handlebars onto his right arm.")
    fb = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": DIAGNOSIS}).json()
    assert crit(fb, "handover")["met"] and fb["diagnostic_assessment"]["verdict"] == "correct"


@pytest.mark.parametrize("text,verdict", [
    ("Open fracture right distal radius and ulna", "correct"), ("compound fracture of the forearm", "correct"),
    ("fractured forearm", "partial"), ("wrist sprain", "incorrect")])
def test_trail_diagnosis_wording(client, text, verdict):
    sid = create(client)["session_id"]
    fb = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": text}).json()
    assert fb["diagnostic_assessment"]["verdict"] == verdict


# ---------------------------------------------------------------- Studio template

def trail_config(**over):
    base = dict(template_id=TRAIL, title="Wet autumn trail", environment="wet_autumn", difficulty="standard",
                crowdedness="busy", bystander="anxious_relative", tools=["xray_forearm", "bloods"],
                learning_objectives=["handover", "communication_under_pressure"], seed=5)
    return base | over


def test_trail_template_is_in_the_catalog_with_its_places(client):
    t = next(t for t in client.get("/studio/catalog").json() if t["template_id"] == TRAIL)
    assert t["case_id"] == TRAIL and t["kind"] == "journey" and t["patient"] == {"name": "Jordan", "age": 34}
    assert [e["id"] for e in t["environments"]] == ["daytime", "wet_autumn", "dusk"]
    assert [(c["id"], c["figures"]) for c in t["crowdedness"]] == [("quiet", 0), ("moderate", 2), ("busy", 4)]
    assert {e["id"] for e in t["unsupported_environments"]} == {"city_street", "single_room", "next_day_clinic"}
    assert all(e["reason"] for e in t["unsupported_environments"])
    assert [(s["id"], s["label"]) for s in t["stages"]][0] == ("scene", "On the trail")
    assert t["stages"][0]["setting"].startswith("Forest trail")
    assert [d["id"] for d in t["dimensions"]] == ["core", "management"]
    assert "open fracture" not in json.dumps(t).lower() and "hidden" not in json.dumps(t)


@pytest.mark.parametrize("over,field,text", [
    (dict(environment="city_street"), "environment", "different mechanism"),
    (dict(environment="night_rain"), "environment", "not a supported environment"),
    (dict(tools=["imaging_mri"]), "tools", "not a supported equipment identifier"),
    (dict(title="Open fracture drill"), "title", "must not state or hint"),
])
def test_trail_unsupported_choices_are_errors(client, over, field, text):
    r = client.post("/studio/validate", json=trail_config(**over)).json()
    assert not r["valid"]
    assert any(i["field"] == field and i["severity"] == "error" and text in i["message"] for i in r["issues"]), r


def test_trail_scenario_is_generated_published_and_launched(client):
    assert client.post("/studio/validate", json=trail_config()).json()["valid"]
    d = client.post("/studio/scenarios", json=trail_config()).json()
    assert d["source_template"] == {"template_id": TRAIL, "case_id": TRAIL, "case_schema_version": 3}
    assert d["clinical_rules"]["findings_sha256"] == studio.findings_hash(main.SCENARIOS[TRAIL])
    noise = {s["id"]: s["noise"] for s in d["journey"]["stages"]}
    assert noise == {"scene": 0.6, "ambulance": 0.65, "hospital": 0.55}  # case + wet autumn 0.1 + group of hikers 0.2
    assert len(d["environment"]["crowd"]["figures"]) == 4
    assert d["companions"]["bystander"]["name"] == "Alex" and d["companions"]["bystander"]["mood"] == "anxious"
    listed = next(x for x in client.get("/studio/scenarios").json() if x["scenario_id"] == d["scenario_id"])
    assert listed["template_id"] == TRAIL
    assert client.post(f"/studio/scenarios/{d['scenario_id']}/publish").json()["published"]
    pub = next(x for x in client.get("/scenarios/published").json() if x["code"] == d["code"])
    assert pub["case_id"] == TRAIL and pub["kind"] == "journey" and pub["stages"][0] == "On the trail"
    s = create(client, scenario_code=d["code"])
    case = s["case"]
    assert [st["noise"] for st in case["journey"]["stages"]] == [0.6, 0.65, 0.55]
    assert {i["id"] for i in case["investigations"]} == {"rt_xray_forearm", "rt_bloods"}  # CT left out
    assert s["scenario"]["environment_label"] == "Wet autumn afternoon"
    assert "wet leaves" in case["voice_context"] and "Alex, one of the hikers" in case["voice_context"]
    assert case["voice_context"].startswith(main.SCENARIOS[TRAIL]["voice_context"])  # facts untouched
    sid = s["session_id"]
    stage(client, sid, "ambulance")
    stage(client, sid, "hospital")
    assert order(client, sid, "rt_ct_head").status_code == 409  # not in this scenario


def test_seeded_trail_scenario_launches_by_code(client):
    seeded = next(s for s in client.get("/studio/scenarios").json() if s["scenario_id"] == "scn_demo_trail")
    assert seeded["code"] == "7B46EL" and seeded["review_state"] == "experimental" and seeded["published_version"] == 1
    launch = client.get("/scenarios/launch/7b46el").json()
    assert launch["case_id"] == TRAIL and launch["kind"] == "journey"
    s = create(client, scenario_code="7B46EL")
    assert s["scenario"]["code"] == "7B46EL" and s["case"]["case_id"] == TRAIL
    assert s["scenario"]["bystander"]["mood"] == "calm" and len(s["scenario"]["crowd_figures"]) == 2
    assert {i["id"] for i in s["case"]["investigations"]} == {"rt_xray_forearm", "rt_ct_head", "rt_bloods"}
