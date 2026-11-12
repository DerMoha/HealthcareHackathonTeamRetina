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
    assert fb["relevant_findings"] == ["Left wrist (comparison): normal (pain 0/10)"]


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
        else:
            out = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": s["diagnosis"]}).json()
    out["session_id"] = "SESSION"
    return out


def test_parity_golden(client):
    expected = json.loads((FIXTURES / "parity_expected.json").read_text(encoding="utf-8"))
    assert run_parity(client) == expected
