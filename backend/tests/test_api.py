import json
from pathlib import Path

import pytest

FIXTURES = Path(__file__).parent / "fixtures"


def say(client, sid, text, role="learner"):
    return client.post(f"/sessions/{sid}/interactions", json={"role": role, "text": text})


def examine(client, sid, zone):
    return client.post(f"/sessions/{sid}/examine", json={"body_part": zone})


def crit(fb, cid):
    return next(c for cat in fb["categories"] for c in cat["criteria"] if c["id"] == cid)


def test_health_and_session_creation(client):
    assert client.get("/health").json() == {"status": "ok", "version": "0.1.0", "cases": 1}
    r = client.post("/sessions", json={"case_id": "wrist_trauma_001"})
    assert r.status_code == 201
    body = r.json()
    assert body["session_id"] and body["started_at"].endswith("Z")
    assert body["case"]["case_id"] == "wrist_trauma_001"
    assert len(body["case"]["zones"]) == 3
    assert client.post("/sessions", json={"case_id": "nope"}).status_code == 404
    assert client.post("/sessions", json={}).status_code == 422


@pytest.mark.parametrize("zone,finding,pain,reaction,anim", [
    ("right_anatomical_snuffbox", "marked_tenderness", 8, "strong_pain", "arm_withdrawal"),
    ("right_distal_forearm", "no_focal_tenderness", 1, "no_pain", "none"),
    ("left_wrist", "normal", 0, "no_pain", "none"),
])
def test_examination_findings(client, sid, zone, finding, pain, reaction, anim):
    r = examine(client, sid, zone)
    assert r.status_code == 200
    j = r.json()
    assert (j["finding"], j["pain_level"], j["reaction"], j["animation"]) == (finding, pain, reaction, anim)
    assert j["action"] == "palpation" and j["repeat_count"] == 1
    assert j["voice_context"].startswith("[")


def test_unknown_zone_and_session(client, sid):
    assert examine(client, sid, "left_knee").status_code == 404
    assert examine(client, "missing", "left_wrist").status_code == 404
    assert say(client, "missing", "hi").status_code == 404
    assert client.get("/sessions/missing/feedback").status_code == 404
    assert client.post("/sessions/missing/reset").status_code == 404
    assert client.post("/sessions/missing/diagnose", json={"diagnosis": "x"}).status_code == 404


def test_duplicate_examination_repeat_count(client, sid):
    a, b = examine(client, sid, "left_wrist").json(), examine(client, sid, "left_wrist").json()
    assert (a["repeat_count"], b["repeat_count"]) == (1, 2)
    assert {k: v for k, v in a.items() if k != "repeat_count"} == {k: v for k, v in b.items() if k != "repeat_count"}
    fb = client.get(f"/sessions/{sid}/feedback").json()
    assert fb["relevant_findings"] == ["Left wrist: normal (pain 0/10)"]  # neutral label before a diagnosis


def test_reset_clears_state(client, sid):
    examine(client, sid, "right_anatomical_snuffbox")
    say(client, sid, "hello")
    client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": "scaphoid"})
    r = client.post(f"/sessions/{sid}/reset")
    assert r.status_code == 200 and r.json()["session_id"] == sid
    assert examine(client, sid, "right_anatomical_snuffbox").json()["repeat_count"] == 1
    fb = client.get(f"/sessions/{sid}/feedback").json()
    assert fb["diagnosis_submitted"] is None and fb["transcript_available"] is False
    assert say(client, sid, "x").json() == {"count": 1}


@pytest.mark.parametrize("diagnosis,verdict,score", [
    ("Suspected scaphoid fracture", "correct", 6),
    ("Distal radius FRACTURE", "partial", 3),
    ("Sprain", "incorrect", 0),
])
def test_diagnosis_verdicts(client, sid, diagnosis, verdict, score):
    fb = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": diagnosis}).json()
    assert fb["diagnostic_assessment"]["verdict"] == verdict
    assert fb["diagnostic_assessment"]["expected"] == "Suspected scaphoid fracture"
    assert fb["next_steps"]
    assert crit(fb, "scaphoid_considered")["points"] == score
    assert crit(fb, "scaphoid_considered")["met"] == (verdict == "correct")


def test_resubmit_replaces_diagnosis(client, sid):
    client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": "Sprain"})
    fb = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": "Scaphoid"}).json()
    assert fb["diagnostic_assessment"]["verdict"] == "correct"


def test_perfect_run_scores_100(client, sid):
    for t in ["Hello, I'm a medical student. What happened to you? When did it start?",
              "Where does it hurt, and how bad is it on a scale of ten?",
              "Any numbness or tingling?",
              "May I examine your wrist?"]:
        say(client, sid, t)
    for z in ["right_anatomical_snuffbox", "right_distal_forearm", "left_wrist"]:
        examine(client, sid, z)
    say(client, sid, "Sorry, I'll be gentle.")
    fb = client.post(f"/sessions/{sid}/diagnose",
                     json={"diagnosis": "Scaphoid fracture, needs X-ray"}).json()
    assert fb["total_score"] == fb["max_score"] == 100
    assert fb["missed"] == [] and len(fb["strengths"]) == 15
    assert [c["id"] for c in fb["categories"]] == ["history", "examination", "communication", "reasoning"]


def test_empty_run(client, sid):
    fb = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": "Sprain"}).json()
    assert fb["total_score"] == 0 and fb["max_score"] == 100
    assert fb["transcript_available"] is False
    assert "could not be assessed" in fb["summary"]
    assert fb["strengths"] == [] and len(fb["missed"]) == 15


def graded(client, sid):
    """Feedback with criteria (they are redacted until a diagnosis exists)."""
    return client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": "unsure"}).json()


def test_permission_must_precede_first_exam(client, sid):
    examine(client, sid, "left_wrist")
    say(client, sid, "May I examine your wrist?")
    fb = graded(client, sid)
    assert crit(fb, "permission")["met"] is False and crit(fb, "permission")["evidence"] is None
    # fresh session: permission asked first
    sid2 = client.post("/sessions", json={"case_id": "wrist_trauma_001"}).json()["session_id"]
    say(client, sid2, "May I examine your wrist?")
    examine(client, sid2, "left_wrist")
    c = crit(graded(client, sid2), "permission")
    assert c["met"] and c["evidence"] == "May I examine your wrist?" and c["method"] == "keyword"


def test_response_must_follow_painful_exam(client, sid):
    say(client, sid, "Sorry about earlier")  # before any exam
    examine(client, sid, "left_wrist")  # pain 0, not painful
    say(client, sid, "I'm sorry")
    assert crit(graded(client, sid), "responded_to_pain")["met"] is False
    examine(client, sid, "right_anatomical_snuffbox")  # pain 8
    say(client, sid, "I'll be gentle")
    c = crit(graded(client, sid), "responded_to_pain")
    assert c["met"] and c["evidence"] == "I'll be gentle"


def test_learner_avoided_and_diagnosis_rules(client, sid):
    say(client, sid, "Stop whining")
    fb = graded(client, sid)
    assert crit(fb, "respectful")["met"] is False
    # significance needs the snuffbox examined even if diagnosis mentions it
    fb = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": "scaphoid"}).json()
    assert crit(fb, "significance")["met"] is False
    examine(client, sid, "right_anatomical_snuffbox")
    fb = client.get(f"/sessions/{sid}/feedback").json()
    assert crit(fb, "significance")["evidence"] == "scaphoid"
    assert crit(fb, "examined_snuffbox")["evidence"] == "Right anatomical snuffbox"
    assert crit(fb, "examined_snuffbox")["method"] == "rule"


def test_feedback_before_diagnosis_leaks_nothing(client, sid):
    fb = client.get(f"/sessions/{sid}/feedback").json()
    assert fb["diagnostic_assessment"] == {"verdict": "not_submitted", "expected": None,
                                           "explanation": "No diagnosis submitted yet."}
    assert fb["next_steps"] == [] and fb["diagnosis_submitted"] is None
    assert "Suspected" not in json.dumps(fb["diagnostic_assessment"])
    # rubric wording names the diagnosis, so it is withheld until one is submitted
    assert all(c["criteria"] == [] for c in fb["categories"])
    assert fb["strengths"] == [] and fb["missed"] == []
    assert "scaphoid" not in json.dumps(fb).lower() and "snuffbox" not in json.dumps(fb).lower()


def test_patient_facing_responses_hide_diagnosis(client):
    cases = client.get("/cases")
    sess = client.post("/sessions", json={"case_id": "wrist_trauma_001"})
    sid = sess.json()["session_id"]
    reset = client.post(f"/sessions/{sid}/reset")
    for r in (cases, sess, reset):
        text = r.text.lower()
        assert "scaphoid" not in text
        assert '"result"' not in text and "marked_tenderness" not in text
        assert "hidden" not in text and "rubric" not in text


def test_interactions_store_turns_offline(client, sid, monkeypatch):
    import httpx

    def boom(*a, **k):
        raise AssertionError("network call")
    monkeypatch.setattr(httpx, "get", boom)  # the only outbound call the app makes
    assert say(client, sid, "hi").json() == {"count": 1}
    r = client.post(f"/sessions/{sid}/interactions",
                    json={"role": "patient", "text": "hello", "timestamp": "2026-11-12T10:00:05Z"})
    assert r.json() == {"count": 2}
    assert client.post(f"/sessions/{sid}/interactions", json={"role": "bot", "text": "x"}).status_code == 422
    assert client.get(f"/sessions/{sid}/feedback").json()["transcript_available"] is True


def test_patient_turns_alone_are_not_a_transcript(client, sid):
    say(client, sid, "hello", role="patient")
    assert client.get(f"/sessions/{sid}/feedback").json()["transcript_available"] is False


def test_token_unconfigured_503(client, monkeypatch):
    monkeypatch.delenv("ELEVENLABS_API_KEY", raising=False)
    monkeypatch.delenv("ELEVENLABS_AGENT_ID", raising=False)
    r = client.get("/elevenlabs/conversation-token")
    assert r.status_code == 503 and "not configured" in r.json()["detail"]


def test_token_upstream_rejection_502_hides_key(client, monkeypatch):
    import httpx
    monkeypatch.setenv("ELEVENLABS_API_KEY", "sk-secret")
    monkeypatch.setenv("ELEVENLABS_AGENT_ID", "agent_x")
    monkeypatch.setattr(httpx, "get", lambda *a, **k: httpx.Response(401, json={"detail": "sk-secret"}))
    r = client.get("/elevenlabs/conversation-token")
    assert r.status_code == 502 and "sk-secret" not in r.text


def test_token_success(client, monkeypatch):
    import httpx
    monkeypatch.setenv("ELEVENLABS_API_KEY", "k")
    monkeypatch.setenv("ELEVENLABS_AGENT_ID", "a")
    monkeypatch.setattr(httpx, "get", lambda *a, **k: httpx.Response(200, json={"token": "t", "conversation_id": "c"}))
    assert client.get("/elevenlabs/conversation-token").json() == {"token": "t"}


def run_parity(client):
    spec = json.loads((FIXTURES / "parity_input.json").read_text(encoding="utf-8"))
    sid = client.post("/sessions", json={"case_id": spec["case_id"]}).json()["session_id"]
    out = None
    for s in spec["steps"]:
        if s["op"] == "interaction":
            say(client, sid, s["text"], s["role"])
        elif s["op"] == "examine":
            client.post(f"/sessions/{sid}/examine", json={"body_part": s["body_part"], "action": s["action"]})
        elif s["op"] in ("measure", "fit", "check"):
            path = {"measure": "measurements", "fit": "fitting", "check": "checks"}[s["op"]]
            client.post(f"/sessions/{sid}/{path}", json=s["body"])
        elif s["op"] == "investigate":
            client.post(f"/sessions/{sid}/investigations", json={"investigation_id": s["investigation_id"]})
        else:
            out = client.post(f"/sessions/{sid}/diagnose",
                              json={"diagnosis": s["diagnosis"], "notes": s.get("notes")}).json()
    out["session_id"] = "SESSION"
    return out


def test_parity_golden(client):
    expected = json.loads((FIXTURES / "parity_expected.json").read_text(encoding="utf-8"))
    assert run_parity(client) == expected


def test_keywords_match_whole_words_not_substrings(client, sid):
    # Each line used to earn a criterion through a substring hit.
    for t in ["I once toured Scotland by a waterfall.",       # land / fall -> mechanism
              "That is an accurate broadcast.",               # rate -> severity, cast -> imaging
              "What a scandal, I'm a bit worried.",           # scan -> imaging, "i'm a " -> introduction
              "Where is the doctor? Let me scan it quickly.", # doctor -> introduction, "can i" -> permission
              "Can I ask you something?"]:                    # generic "can i" -> permission
        say(client, sid, t)
    fb = graded(client, sid)
    for cid in ["mechanism", "severity", "introduction", "permission"]:
        assert crit(fb, cid)["met"] is False, cid
    assert crit(fb, "location")["met"]  # "Where ..." is still a real location question


def test_keyword_stems_and_typographic_apostrophe(client, sid):
    say(client, sid, "Hi, I’m a medical student. Any numbness or tingling?")
    say(client, sid, "Is it okay if I examine your wrist?")
    examine(client, sid, "right_anatomical_snuffbox")
    say(client, sid, "I apologise, I’ll be gentle.")
    fb = client.post(f"/sessions/{sid}/diagnose",
                     json={"diagnosis": "Scaphoidfraktur, X-rays and a CT needed"}).json()
    for cid in ["introduction", "associated_symptoms", "permission", "responded_to_pain",
                "scaphoid_considered", "further_assessment"]:
        assert crit(fb, cid)["met"], cid


def doc(fb, cid):
    return next((d for d in fb["documentation"] if d["criterion_id"] == cid), None)


def test_notes_never_earn_examination_points(client, sid):
    # The learner writes up an examination that never happened.
    notes = {"history": "Fell off bike yesterday.",
             "examination": "Marked snuffbox tenderness on the right, left wrist normal.",
             "assessment": ""}
    fb = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": "scaphoid fracture", "notes": notes}).json()
    exam = next(c for c in fb["categories"] if c["id"] == "examination")
    assert exam["score"] == 0
    assert crit(fb, "examined_snuffbox")["met"] is False and crit(fb, "significance")["met"] is False
    assert doc(fb, "examined_snuffbox")["status"] == "unsupported"
    assert "no matching examination" in doc(fb, "examined_snuffbox")["comment"]
    assert doc(fb, "mechanism")["status"] == "unsupported"  # written down, never asked
    assert "not supported" in fb["summary"]


def test_notes_documented_undocumented_and_written_plan(client, sid):
    say(client, sid, "What happened?")
    examine(client, sid, "right_anatomical_snuffbox")
    examine(client, sid, "left_wrist")
    notes = {"history": "", "examination": "Tender at the base of the thumb.",
             "assessment": "Plan: X-ray, splint."}
    fb = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": "wrist injury", "notes": notes}).json()
    assert doc(fb, "examined_snuffbox")["status"] == "documented"
    assert doc(fb, "comparison")["status"] == "undocumented"   # examined, not written down
    assert doc(fb, "mechanism")["status"] == "undocumented"    # asked, not written down
    assert doc(fb, "severity") is None                          # neither asked nor noted
    assert crit(fb, "further_assessment")["met"]                # the written plan counts as reasoning
    assert crit(fb, "scaphoid_considered")["points"] == 0       # but the diagnosis itself must be in the diagnosis


def test_no_notes_means_no_documentation_and_nothing_before_diagnosis(client, sid):
    examine(client, sid, "right_anatomical_snuffbox")
    pre = client.get(f"/sessions/{sid}/feedback").json()
    assert pre["documentation"] == []
    assert pre["relevant_findings"] == ["Right wrist, thumb side: marked tenderness (pain 8/10)"]
    post = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": "sprain"}).json()
    assert post["documentation"] == []
    assert post["relevant_findings"] == ["Right anatomical snuffbox: marked tenderness (pain 8/10)"]


def test_public_case_text_is_spoiler_free(client):
    case = client.get("/cases").json()[0]
    # zone ids are internal contract ids and never displayed; labels are
    shown = json.dumps([case["title"], case["learner_brief"], case["patient"],
                        [z["label"] for z in case["zones"]]]).lower()
    for word in ["bicycle", "bike", "fall", "fell", "scaphoid", "snuffbox", "fracture", "tender"]:
        assert word not in shown, word


def test_diagnosis_synonyms(client):
    def verdict(text):
        sid = client.post("/sessions", json={"case_id": "wrist_trauma_001"}).json()["session_id"]
        return client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": text}).json()["diagnostic_assessment"]["verdict"]
    for text in ["Scaphoid fracture", "suspected scaphoid #", "Kahnbeinfraktur", "fractured carpal navicular",
                 "Skaphoidfraktur", "scafoid fracture"]:
        assert verdict(text) == "correct", text
    for text in ["distal radius fracture", "broken wrist", "Handgelenk gebrochen"]:
        assert verdict(text) == "partial", text
    for text in ["sprain", "tendinitis", "arthritis"]:
        assert verdict(text) == "incorrect", text


# ---- investigations and management (separate 20-point dimension)

XRAY, MRI, CT = "right_wrist_xray", "right_wrist_mri", "right_wrist_ct"


def order(client, sid, inv):
    return client.post(f"/sessions/{sid}/investigations", json={"investigation_id": inv})


def mgmt(client, sid, diagnosis="Suspected scaphoid fracture", **notes):
    f = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": diagnosis, "notes": notes}).json()
    return f, {c["id"]: c for c in f["management"]["criteria"]}


def test_investigation_results_come_from_the_scenario(client, sid):
    case = client.get("/cases").json()[0]
    assert [i["id"] for i in case["investigations"]] == [XRAY, MRI, CT]
    assert all(set(i) == {"id", "label"} for i in case["investigations"])  # no results in the public case
    x = order(client, sid, XRAY).json()
    assert x["impression"] == "No definite fracture visible." and x["image"] == "wrist_xray_pa"
    assert x["repeat_count"] == 1 and x["ordered_at"].endswith("Z")
    assert "scaphoid fracture" not in (x["label"] + x["title"]).lower()  # viewer header stays neutral
    m = order(client, sid, MRI).json()
    assert "scaphoid" in m["impression"] and m["image"] is None and "Simulated report only" in m["image_credit"]
    assert "scaphoid" in order(client, sid, CT).json()["impression"]
    assert order(client, sid, XRAY).json()["repeat_count"] == 2
    assert order(client, sid, "biopsy").status_code == 404
    assert order(client, "nope", XRAY).status_code == 404


def test_xray_does_not_reveal_mri_and_feedback_lists_only_ordered(client, sid):
    x = order(client, sid, XRAY).json()
    assert "MRI" not in json.dumps(x) and "scaphoid fracture" not in json.dumps(x).lower()
    f = client.get(f"/sessions/{sid}/feedback").json()
    assert f["investigations"] == ["Right wrist radiographs: No definite fracture visible."]
    assert f["management"]["criteria"] == []  # redacted before a diagnosis
    client.post(f"/sessions/{sid}/reset")
    assert client.get(f"/sessions/{sid}/feedback").json()["investigations"] == []


def test_management_is_separate_from_the_100_point_total(client, sid):
    before = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": "scaphoid fracture"}).json()
    order(client, sid, XRAY)
    after, c = mgmt(client, sid, "scaphoid fracture",
                    interpretation="Normal X-ray does not exclude an occult scaphoid fracture.",
                    management="Thumb spica splint, analgesia.", follow_up="MRI or fracture clinic review in 10 days.")
    assert after["max_score"] == before["max_score"] == 100
    assert after["management"]["score"] == after["management"]["max_score"] == 20
    assert [x["area"] for x in after["management"]["criteria"]] == [
        "investigation", "interpretation", "management", "management", "safety"]
    assert all(x["area"] is None for cat in after["categories"] for x in cat["criteria"])
    # the written plan also satisfies the existing reasoning criterion; nothing else moves
    assert after["total_score"] - before["total_score"] == 4


def test_occult_fracture_recognised_despite_negative_xray(client, sid):
    order(client, sid, XRAY)
    f, c = mgmt(client, sid, interpretation="X-ray negative but I still suspect a fracture clinically.")
    assert c["result_interpreted"]["met"] and c["imaging_requested"]["evidence"] == "Right wrist radiographs"
    assert not c["immobilisation"]["met"] and not c["further_assessment_plan"]["met"]
    assert c["no_false_reassurance"]["met"] and f["management"]["score"] == 11


def test_interpretation_needs_a_result(client, sid):
    _, c = mgmt(client, sid, interpretation="Occult fracture cannot be excluded.")
    assert not c["result_interpreted"]["met"] and not c["imaging_requested"]["met"]


def test_unsafe_reassurance_after_negative_xray(client, sid):
    order(client, sid, XRAY)
    f, c = mgmt(client, sid, "Wrist sprain", interpretation="X-ray normal, fracture ruled out.",
                management="Just a sprain. Reassure and discharge, no follow-up.")
    assert not c["no_false_reassurance"]["met"] and not c["result_interpreted"]["met"]
    assert f["management"]["score"] == 4  # only the imaging request


def test_reasonable_alternative_pathways_get_credit(client, sid):
    order(client, sid, MRI)  # MRI first-line, no radiograph
    _, c = mgmt(client, sid, interpretation="MRI confirms a scaphoid waist fracture.",
                management="Below-elbow cast.", follow_up="")
    assert all(c[k]["met"] for k in ("imaging_requested", "result_interpreted", "immobilisation",
                                     "further_assessment_plan"))
    client.post(f"/sessions/{sid}/reset")
    order(client, sid, XRAY)
    _, c = mgmt(client, sid, management="Splint.", follow_up="Repeat radiographs and review in two weeks.")
    assert c["immobilisation"]["met"] and c["further_assessment_plan"]["met"]


def test_no_plan_written_earns_no_safety_credit(client, sid):
    f = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": " "})
    order(client, sid, XRAY)
    _, c = mgmt(client, sid, "x")
    assert c["no_false_reassurance"]["met"]  # the diagnosis text counts as written
    f = client.get(f"/sessions/{sid}/feedback").json()
    assert f["management"]["score"] == 6


def test_conversation_cannot_earn_management_points(client, sid):
    say(client, sid, "I will order an MRI, put you in a splint and the X-ray does not exclude a fracture.")
    _, c = mgmt(client, sid, "scaphoid fracture")
    assert [k for k, v in c.items() if v["met"]] == ["no_false_reassurance"]


# ---- measurement and orthosis fitting (third separate 20-point dimension)

GOOD = {"size": "medium", "orientation": "thumb_radial", "offset_cm": 3.0, "tightness": "snug"}


def post(client, sid, path, body):
    return client.post(f"/sessions/{sid}/{path}", json=body)


def fitted(client, sid, **change):
    return post(client, sid, "fitting", {"fit": {**GOOD, **change}})


def comfort(client, sid):
    return post(client, sid, "checks", {"check": "comfort"}).json()


def fitting_feedback(client, sid):
    f = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": "scaphoid fracture"}).json()
    return f, {c["id"]: c["met"] for c in f["fitting"]["criteria"]}


def test_measurements_circumference_is_predefined_length_comes_from_avatar(client, sid):
    case = client.get("/cases").json()[0]
    assert [x["id"] for x in case["orthotics"]["sizes"]] == ["small", "medium", "large"]
    assert "reference" not in json.dumps(case["orthotics"]) and "16.8" not in json.dumps(case)
    c = post(client, sid, "measurements", {"measurement_id": "right_wrist_circumference", "value_cm": 99}).json()
    assert c["value_cm"] == 16.8 and c["source"] == "case" and c["kind"] == "circumference"
    f = post(client, sid, "measurements", {"measurement_id": "right_forearm_length", "value_cm": 25.26}).json()
    assert f["value_cm"] == 25.3 and f["source"] == "avatar"
    assert post(client, sid, "measurements", {"measurement_id": "right_forearm_length"}).status_code == 422
    assert post(client, sid, "measurements", {"measurement_id": "skull"}).status_code == 404


@pytest.mark.parametrize("change,words,comfortable", [
    ({}, "snug and supported", True),
    ({"size": "large"}, "slides around", False),
    ({"size": "small"}, "squeezing", False),
    ({"orientation": "thumb_ulnar"}, "wrong side", False),
    ({"tightness": "tight"}, "too tight", False),
    ({"tightness": "loose"}, "loose", False),
    ({"offset_cm": 14.0}, "forearm", False),
])
def test_fitting_outcomes(client, sid, change, words, comfortable):
    ack = fitted(client, sid, **change).json()
    assert ack["attempt"] == 1 and "do not speak" in ack["voice_note"]
    assert ack["comfortable"] is comfortable and words in ack["patient_response"]  # unprompted reaction text
    assert not any(k in json.dumps(ack) for k in ("too_", "appropriate", "wrong_"))  # no outcome label leaves the engine
    c = comfort(client, sid)
    assert words in c["patient_response"] and c["comfortable"] is comfortable and c["phase"] == "after"
    assert c["patient_response"] in c["voice_context"]


def test_neurovascular_findings_follow_the_fit(client, sid):
    before = post(client, sid, "checks", {"check": "neurovascular"}).json()
    assert before["phase"] == "before" and "under 2 seconds" in before["finding"]
    fitted(client, sid, tightness="tight")
    tight = post(client, sid, "checks", {"check": "neurovascular"}).json()
    assert tight["phase"] == "after" and "about 3 seconds" in tight["finding"] and "tingly" in tight["patient_response"]
    fitted(client, sid)
    assert "under 2 seconds" in post(client, sid, "checks", {"check": "neurovascular"}).json()["finding"]
    assert post(client, sid, "fitting", {"fit": {**GOOD, "size": "xxl"}}).status_code == 404
    assert post(client, sid, "checks", {"check": "reflexes"}).status_code == 422


def test_perfect_fitting_scores_20_and_leaves_the_total_alone(client, sid):
    base = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": "scaphoid fracture"}).json()
    post(client, sid, "measurements", {"measurement_id": "right_wrist_circumference"})
    post(client, sid, "checks", {"check": "neurovascular"})
    fitted(client, sid, tightness="tight")
    comfort(client, sid)
    fitted(client, sid)  # adjusted after the patient complained
    post(client, sid, "checks", {"check": "neurovascular"})
    comfort(client, sid)
    f, met = fitting_feedback(client, sid)
    assert f["fitting"]["score"] == f["fitting"]["max_score"] == 20 and all(met.values())
    assert (f["total_score"], f["max_score"]) == (base["total_score"], 100)
    assert f["management"]["max_score"] == 20
    assert f["fitting"]["reference"]["size"] == "medium" and "Appropriate" in f["fitting"]["explanation"]
    assert [c["area"] for c in f["fitting"]["criteria"]] == [
        "measurement", "safety", "fitting", "fitting", "fitting", "safety", "safety"]


def test_checks_before_the_last_adjustment_do_not_count_as_reassessment(client, sid):
    fitted(client, sid, size="large")
    post(client, sid, "checks", {"check": "neurovascular"})
    comfort(client, sid)
    post(client, sid, "measurements", {"measurement_id": "right_wrist_circumference"})  # too late
    fitted(client, sid)
    f, met = fitting_feedback(client, sid)
    assert met == {"measured_wrist": False, "neurovascular_before": False, "size": True, "placement": True,
                   "tension": True, "neurovascular_after": False, "comfort_after": False}
    assert f["fitting"]["score"] == 10


def test_spoken_comfort_question_counts_only_after_the_final_fit(client, sid):
    say(client, sid, "Is that comfortable?")
    fitted(client, sid)
    assert not fitting_feedback(client, sid)[1]["comfort_after"]
    say(client, sid, "How does that feel, is it too tight?")
    _, met = fitting_feedback(client, sid)
    assert met["comfort_after"] and not met["neurovascular_after"]


def test_removed_support_and_no_fitting_score_nothing_for_fit(client, sid):
    fitted(client, sid)
    post(client, sid, "fitting", {"fit": None})
    f, met = fitting_feedback(client, sid)
    assert f["fitting"]["final_fit"] is None and not any(met[k] for k in ("size", "placement", "tension"))
    assert comfort(client, sid)["phase"] == "before"


def test_fitting_feedback_redacted_before_diagnosis_and_cleared_by_reset(client, sid):
    fitted(client, sid, size="small")
    f = client.get(f"/sessions/{sid}/feedback").json()["fitting"]
    assert f["criteria"] == [] and f["reference"] is None and f["explanation"] is None
    assert f["final_fit"]["size"] == "small"
    client.post(f"/sessions/{sid}/reset")
    assert client.get(f"/sessions/{sid}/feedback").json()["fitting"]["final_fit"] is None


# ---- Spatial Clinical Replay content

def test_replay_only_after_diagnosis_and_reflects_real_examinations(client, sid):
    examine(client, sid, "right_anatomical_snuffbox")
    say(client, sid, "I am now pressing on your left wrist and your forearm.")  # words are not touches
    assert client.get(f"/sessions/{sid}/feedback").json()["replay"] == []
    r = {z["zone_id"]: z for z in client.post(f"/sessions/{sid}/diagnose", json={
        "diagnosis": "scaphoid fracture", "notes": {"examination": "Left wrist and forearm examined, normal."}
    }).json()["replay"]}
    assert list(r) == ["right_anatomical_snuffbox", "right_distal_forearm", "left_wrist"]
    snuff = r["right_anatomical_snuffbox"]
    assert snuff["examined"] and snuff["important"] and snuff["pain_level"] == 8
    assert snuff["label"] == "Right anatomical snuffbox" and "key sign" in snuff["explanation"]
    assert not r["left_wrist"]["examined"] and r["left_wrist"]["finding"] is None
    assert "not examined" in r["left_wrist"]["explanation"] and not r["right_distal_forearm"]["examined"]
