"""MedSim Studio: authoring, library, runtime adapter, live director, debrief."""
import copy
import json

import pytest

from app import assist, director, main, studio

ALL_TOOLS = ["measuring_tape", "wrist_support_small", "wrist_support_medium", "wrist_support_large",
             "imaging_xray", "imaging_mri", "imaging_ct"]
SNUFFBOX = "right_anatomical_snuffbox"


@pytest.fixture(autouse=True)
def library(tmp_path, monkeypatch):
    monkeypatch.setenv("MEDSIM_STUDIO_DB", str(tmp_path / "library.json"))
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    for var in ("AWS_ACCESS_KEY_ID", "AWS_PROFILE"):  # keep Bedrock out of the deterministic tests
        monkeypatch.delenv(var, raising=False)
    studio.LIVE.clear()
    director.HUB.clear()


def config(**over):
    base = dict(template_id="wrist_trauma_001", title="Test scenario", environment="outpatient_clinic",
                difficulty="standard", crowdedness="quiet", tools=list(ALL_TOOLS), bystander="none",
                teammate="none", learning_objectives=["focused_history"], seed=7)
    return base | over


def code(client, title):
    return next(s["code"] for s in client.get("/scenarios/published").json() if title in s["title"])


def launch(client, title):
    r = client.post("/sessions", json={"case_id": "wrist_trauma_001", "scenario_code": code(client, title)})
    assert r.status_code == 201, r.text
    return r.json()


def event(client, sid, kind, event_id=None, **params):
    body = {"kind": kind, "params": params} | ({"event_id": event_id} if event_id else {})
    return client.post(f"/sessions/{sid}/director/events", json=body)


# P0 authoring

def test_catalog_lists_only_supported_options(client):
    t = next(t for t in client.get("/studio/catalog").json() if t["template_id"] == "wrist_trauma_001")
    assert t["kind"] == "single" and t["stages"] == []
    assert [e["id"] for e in t["environments"]] == ["outpatient_clinic", "emergency_department", "community_clinic"]
    assert {e["id"] for e in t["unsupported_environments"]} == {"sports_sideline", "ambulance"}
    assert all(e["reason"] for e in t["unsupported_environments"])
    assert "hidden" not in json.dumps(t) and "scaphoid" not in json.dumps(t).lower()


@pytest.mark.parametrize("over,field,text", [
    (dict(environment="sports_sideline"), "environment", "different mechanism"),
    (dict(environment="moon_base"), "environment", "not a supported environment"),
    (dict(environment="community_clinic"), "tools", "X-ray (radiographs) is not available"),
    (dict(tools=["defibrillator"]), "tools", "not a supported equipment identifier"),
    (dict(bystander="aggressive_stranger"), "bystander", "not a supported bystander behaviour"),
    (dict(difficulty="nightmare"), "difficulty", "not a supported difficulty"),
    (dict(template_id="chest_pain_001"), "template_id", "not a supported clinical case template"),
    (dict(learning_objectives=[]), "learning_objectives", "at least one"),
    (dict(title="Scaphoid fracture drill"), "title", "must not state or hint"),
    (dict(narrative={"description": "The X-ray shows nothing."}), "narrative.description", "must not state"),
])
def test_unsupported_combinations_are_errors_with_a_reason(client, over, field, text):
    r = client.post("/studio/validate", json=config(**over)).json()
    assert not r["valid"]
    assert any(i["field"] == field and i["severity"] == "error" and text in i["message"] for i in r["issues"]), r
    assert client.post("/studio/scenarios", json=config(**over)).status_code == 422  # never saved


def test_definition_is_complete_and_reproducible(client):
    cfg = config(environment="community_clinic", crowdedness="busy", bystander="anxious_relative",
                 tools=["measuring_tape", "wrist_support_small"])
    a = client.post("/studio/preview", json=cfg).json()
    b = client.post("/studio/preview", json=cfg).json()
    a.pop("created_at"), b.pop("created_at")
    assert a == b  # same configuration and seed -> same scenario
    assert a["seed"] == 7 and a["version"] == 1 and len(a["code"]) == 6
    assert a["source_template"] == {"template_id": "wrist_trauma_001", "case_id": "wrist_trauma_001", "case_schema_version": 3}
    assert a["clinical_rules"]["findings_sha256"] == studio.findings_hash(main.SCENARIOS["wrist_trauma_001"])
    assert a["environment"]["ambient_level"] == 0.6 and len(a["environment"]["crowd"]["figures"]) == 4
    inventory = {r["id"]: r for r in a["resources"]}
    assert inventory["wrist_support_small"]["available"] and not inventory["wrist_support_medium"]["available"]
    assert inventory["wrist_support_medium"]["deliverable"] and not inventory["imaging_mri"]["deliverable"]
    dims = {d["id"]: d for d in a["assessment"]["dimensions"]}
    assert dims["core"]["achievable_max"] == 100
    assert dims["management"]["achievable_max"] == 11  # imaging_requested 4 + result_interpreted 5 not assessable
    assert {b["id"] for b in dims["fitting"]["not_assessable"]} == {"size"}
    other = client.post("/studio/preview", json=cfg | {"seed": 8}).json()
    assert other["environment"]["crowd"]["figures"] != a["environment"]["crowd"]["figures"]
    assert "hidden" not in a and "marked_tenderness" not in json.dumps(a)


@pytest.mark.parametrize("tid", ["wrist_trauma_001", "road_trauma_journey_001", "trail_trauma_journey_001"])
def test_template_text_passes_its_own_clinical_rule(tid):
    t, case = studio.template(tid), main.SCENARIOS[tid]
    texts = [h["text"] for h in t["hints"]] + [l for v in t["bystander"]["lines"].values() for l in v] \
        + list(t["personalities"].values()) + [t["summary"], t["teammate"]["arrival_line"]]
    assert [x for x in texts if studio.clinical_claim(x, case, t)] == []


# P2 library

def test_library_versions_review_states_and_sharing(client):
    seeded = client.get("/studio/scenarios").json()
    assert {s["scenario_id"] for s in seeded} == {"scn_demo_clinic", "scn_demo_walkin", "scn_demo_trail"}
    assert all(s["review_state"] == "experimental" and s["published_version"] == 1 for s in seeded)

    d = client.post("/studio/scenarios", json=config()).json()
    sid = d["scenario_id"]
    assert d["review"]["state"] == "draft" and not d["published"]
    assert client.get(f"/scenarios/launch/{d['code']}").status_code == 404  # drafts are not launchable

    # the label needs an actual review
    assert client.post(f"/studio/scenarios/{sid}/state", json={"state": "clinician_reviewed"}).status_code == 409
    assert client.post(f"/studio/scenarios/{sid}/review", json={
        "reviewer_name": "Dr A", "reviewer_role": "Consultant", "attestation": False}).status_code == 422
    p = client.post(f"/studio/scenarios/{sid}/publish").json()
    assert p["published"] and p["review"]["state"] == "experimental"  # publishing never marks it reviewed
    assert client.get(f"/scenarios/launch/{d['code'].lower()}").json()["title"] == "Test scenario"
    r = client.post(f"/studio/scenarios/{sid}/review", json={
        "reviewer_name": "Dr A", "reviewer_role": "Consultant", "attestation": True}).json()
    assert r["review"]["state"] == "clinician_reviewed" and r["review"]["reviewer_name"] == "Dr A"

    # an edit is a new draft version; the reviewed version stays the published one
    v2 = client.put(f"/studio/scenarios/{sid}", json=config(title="Edited", difficulty="guided", seed=None)).json()
    assert v2["version"] == 2 and v2["review"]["state"] == "draft" and not v2["published"] and v2["seed"] == 7
    assert v2["code"] == d["code"] and v2["scenario_id"] == sid
    live = client.get(f"/scenarios/launch/{d['code']}").json()
    assert live["version"] == 1 and live["review_state"] == "clinician_reviewed" and live["title"] == "Test scenario"
    assert [v["review_state"] for v in client.get(f"/studio/scenarios/{sid}/versions").json()] == ["clinician_reviewed", "draft"]
    assert client.get(f"/studio/scenarios/{sid}?version=1").json()["title"] == "Test scenario"

    copy_ = client.post(f"/studio/scenarios/{sid}/duplicate").json()
    assert copy_["scenario_id"] != sid and copy_["title"] == "Copy of Edited" and copy_["review"]["state"] == "draft"

    # sharing: export is the document itself; an import never keeps a claimed review
    exported = client.get(f"/studio/scenarios/{sid}?version=1").json()
    imported = client.post("/studio/import", json=exported).json()
    assert imported["scenario_id"] != sid and imported["review"]["state"] == "draft" and not imported["published"]
    assert imported["origin"]["claimed_review_state"] == "clinician_reviewed"
    # marketplace: a download is a draft copy of the PUBLISHED version (v1), not of the newer draft
    got = client.post(f"/studio/marketplace/{d['code']}/download").json()
    assert got["title"] == "Test scenario" and got["review"]["state"] == "draft" and got["scenario_id"] != sid
    assert got["origin"] | {"version": 1} == got["origin"] and got["origin"]["downloaded_from"] == sid
    assert next(r for r in client.get("/studio/scenarios").json() if r["scenario_id"] == got["scenario_id"])["origin"]["code"] == d["code"]
    assert client.post("/studio/marketplace/NOPE00/download").status_code == 404
    tampered = copy.deepcopy(exported)
    tampered["config"]["tools"].append("defibrillator")
    assert client.post("/studio/import", json=tampered).status_code == 422
    assert client.post("/studio/import", json={"nope": 1}).status_code == 422
    assert client.get("/studio/scenarios/scn_nope").status_code == 404


# P1 runtime

def test_two_variants_of_one_case_behave_differently(client):
    a, b = launch(client, "Quiet clinic"), launch(client, "Busy walk-in")
    assert a["case"]["case_id"] == b["case"]["case_id"] == "wrist_trauma_001"
    assert [i["id"] for i in a["case"]["investigations"]] == ["right_wrist_xray", "right_wrist_mri", "right_wrist_ct"]
    assert b["case"]["investigations"] == []
    assert [s["id"] for s in a["case"]["orthotics"]["sizes"]] == ["small", "medium", "large"]
    assert [s["id"] for s in b["case"]["orthotics"]["sizes"]] == ["small", "large"]
    assert (a["scenario"]["hint_policy"], b["scenario"]["hint_policy"]) == ("auto", "off")
    assert (a["scenario"]["noise_level"], b["scenario"]["noise_level"]) == (0.0, 0.6)
    assert a["scenario"]["bystander"] is None and b["scenario"]["bystander"]["mood"] == "anxious"
    assert len(b["scenario"]["crowd_figures"]) == 4 and a["scenario"]["crowd_figures"] == []
    assert "no imaging on site" in b["case"]["learner_brief"] and "Sam is getting anxious" in b["case"]["voice_context"]
    assert a["case"]["voice_context"].startswith(main.SCENARIOS["wrist_trauma_001"]["voice_context"])

    sa, sb = a["session_id"], b["session_id"]
    # unavailable equipment is refused by the engine, not just hidden
    assert client.post(f"/sessions/{sb}/investigations", json={"investigation_id": "right_wrist_xray"}).status_code == 409
    assert client.post(f"/sessions/{sa}/investigations", json={"investigation_id": "right_wrist_xray"}).status_code == 200
    fit = {"size": "medium", "orientation": "thumb_radial", "offset_cm": 3, "tightness": "snug"}
    assert client.post(f"/sessions/{sb}/fitting", json={"fit": fit}).status_code == 409
    assert client.post(f"/sessions/{sa}/fitting", json={"fit": fit}).status_code == 200
    # the clinical facts are the same in both
    ea = client.post(f"/sessions/{sa}/examine", json={"body_part": SNUFFBOX}).json()
    eb = client.post(f"/sessions/{sb}/examine", json={"body_part": SNUFFBOX}).json()
    assert ea == eb and ea["pain_level"] == 8
    # hints depend on difficulty
    assert client.get(f"/sessions/{sa}/hint").json()["hint"]["id"] == "introduce"
    assert client.get(f"/sessions/{sb}/hint").json() == {"policy": "off", "hint": None}


def test_default_session_is_unchanged_and_unknown_code_is_an_error(client, sid):
    full = client.post("/sessions", json={"case_id": "wrist_trauma_001"}).json()
    assert full["scenario"] is None and len(full["case"]["investigations"]) == 3
    assert full["case"]["learner_brief"] == main.SCENARIOS["wrist_trauma_001"]["learner_brief"]
    assert client.post("/sessions", json={"case_id": "wrist_trauma_001", "scenario_code": "NOPE00"}).status_code == 404
    assert client.get(f"/sessions/{sid}/director").status_code == 409
    assert client.get(f"/sessions/{sid}/hint").status_code == 409
    d = client.get(f"/sessions/{sid}/debrief").json()
    assert d["scenario"] is None and d["interventions"] == [] and "Fixed default case" in d["interpretation"][0]


def test_hints_follow_what_the_student_has_done(client):
    sid = launch(client, "Quiet clinic")["session_id"]
    hint = lambda: (client.get(f"/sessions/{sid}/hint").json()["hint"] or {}).get("id")  # noqa: E731
    client.post(f"/sessions/{sid}/interactions", json={"role": "learner", "text": "Hello, what happened?"})
    assert hint() == "permission"            # "introduce" no longer applies
    client.post(f"/sessions/{sid}/examine", json={"body_part": SNUFFBOX})
    assert hint() == "compare"
    assert hint() == "acknowledge_pain"      # never the same hint twice
    assert [h["id"] for h in client.get(f"/sessions/{sid}/debrief").json()["hints"]] == ["permission", "compare", "acknowledge_pain"]


# P3 director

def test_director_events_apply_dedupe_and_keep_clinical_facts(client):
    s = launch(client, "Busy walk-in")
    sid = s["session_id"]
    case_before = copy.deepcopy(main.SCENARIOS["wrist_trauma_001"])
    exam_before = client.post(f"/sessions/{sid}/examine", json={"body_part": SNUFFBOX}).json()

    assert event(client, sid, "bystander_anxious").status_code == 409            # already anxious
    assert event(client, sid, "deliver_equipment", item="imaging_mri").status_code == 409  # not in this environment
    assert event(client, sid, "deliver_equipment", item="defibrillator").status_code == 409
    assert event(client, sid, "patient_deteriorates").status_code == 409         # not a predefined event
    assert event(client, sid, "remove_equipment", item="measuring_tape").status_code == 409

    first = event(client, sid, "deliver_equipment", "evt-1", item="wrist_support_medium").json()
    again = event(client, sid, "deliver_equipment", "evt-1", item="wrist_support_medium").json()
    assert not first["duplicate"] and again["duplicate"] and again["intervention"]["seq"] == first["intervention"]["seq"]
    assert event(client, sid, "deliver_equipment", "evt-2", item="wrist_support_medium").status_code == 409  # already there
    assert event(client, sid, "helper_arrives").json()["intervention"]["line"]["speaker"] == "Kim"
    assert event(client, sid, "crowd_noise_up").status_code == 200
    assert event(client, sid, "crowd_noise_up").status_code == 200
    assert event(client, sid, "crowd_noise_up").status_code == 409               # capped at 1.0
    assert event(client, sid, "enable_coaching").status_code == 200

    state = client.get(f"/sessions/{sid}/director").json()
    assert [i["kind"] for i in state["interventions"]] == ["deliver_equipment", "helper_arrives", "crowd_noise_up",
                                                         "crowd_noise_up", "enable_coaching"]
    assert state["scenario"]["noise_level"] == 1.0 and state["scenario"]["hint_policy"] == "on_request"
    assert state["scenario"]["teammate"]["present"]
    assert {e["kind"]: e["enabled"] for e in state["events"]}["crowd_noise_up"] is False
    fit = {"size": "medium", "orientation": "thumb_radial", "offset_cm": 3, "tightness": "snug"}
    assert client.post(f"/sessions/{sid}/fitting", json={"fit": fit}).status_code == 200  # delivered item works
    assert client.get(f"/sessions/{sid}/hint").json()["policy"] == "on_request"

    # nothing clinical moved
    assert main.SCENARIOS["wrist_trauma_001"] == case_before
    exam_after = client.post(f"/sessions/{sid}/examine", json={"body_part": SNUFFBOX}).json()
    assert {**exam_after, "repeat_count": 1} == exam_before
    assert client.post(f"/sessions/{sid}/investigations", json={"investigation_id": "right_wrist_mri"}).status_code == 409

    client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": "scaphoid fracture"})
    assert event(client, sid, "crowd_noise_up").status_code == 409  # not after submission
    # a new encounter of the scenario starts from its configuration again
    fresh = client.post(f"/sessions/{sid}/reset").json()
    assert fresh["scenario"]["noise_level"] == 0.6 and [x["id"] for x in fresh["case"]["orthotics"]["sizes"]] == ["small", "large"]
    assert client.get(f"/sessions/{sid}/director").json()["interventions"] == []


def test_websocket_ack_reconnect_and_deduplication(client):
    sid = launch(client, "Busy walk-in")["session_id"]
    url = f"/ws/sessions/{sid}"
    with client.websocket_connect(f"{url}?role=director") as boss:
        assert boss.receive_json()["runtime_connected"] is False
        with client.websocket_connect(f"{url}?role=runtime") as app:
            assert boss.receive_json()["runtime_connected"] is True
            boss.send_json({"type": "event", "event_id": "e1", "kind": "helper_arrives", "params": {}})
            got = app.receive_json()
            assert got["type"] == "event" and got["event_id"] == "e1" and got["scenario"]["teammate"]["present"]
            assert got["line"]["text"].startswith("Hi, I'm Kim") and "nurse" in got["voice_context"]
            assert boss.receive_json()["interventions"][0]["acknowledged"] is False
            app.send_json({"type": "ack", "event_id": "e1", "applied": True, "detail": "helper shown"})
            iv = boss.receive_json()["interventions"][0]
            assert iv["acknowledged"] and iv["ack_detail"] == "applied: helper shown"
            boss.send_json({"type": "event", "event_id": "e1", "kind": "helper_arrives", "params": {}})  # resent
            boss.send_json({"type": "event", "event_id": "e2", "kind": "bystander_anxious", "params": {}})
            assert boss.receive_json() == {"type": "rejected", "event_id": "e2", "reason": "The bystander is already anxious."}
        assert boss.receive_json()["runtime_connected"] is False
        # runtime is gone: the event is recorded and waits
        boss.send_json({"type": "event", "event_id": "e3", "kind": "deliver_equipment", "params": {"item": "wrist_support_medium"}})
        waiting = boss.receive_json()
        assert [i["event_id"] for i in waiting["interventions"]] == ["e1", "e3"] and not waiting["interventions"][1]["acknowledged"]
        with client.websocket_connect(f"{url}?role=runtime") as app:  # reconnect: only the missed event is replayed
            replay = app.receive_json()
            assert replay["event_id"] == "e3" and "medium" in [x["id"] for x in replay["case"]["orthotics"]["sizes"]]
            assert boss.receive_json()["runtime_connected"] is True
            boss.send_json({"type": "event", "event_id": "e3", "kind": "deliver_equipment", "params": {"item": "wrist_support_medium"}})
            assert app.receive_json()["event_id"] == "e3"  # still unacknowledged: sent again, not recorded again
            app.send_json({"type": "ack", "event_id": "e3", "applied": True, "detail": "tray rebuilt"})
            done = boss.receive_json()
            assert len(done["interventions"]) == 2 and all(i["acknowledged"] for i in done["interventions"])
    with pytest.raises(Exception):
        with client.websocket_connect("/ws/sessions/nope?role=runtime"):
            pass


# P5 debrief

def test_debrief_reads_the_score_against_the_scenario(client):
    sid = launch(client, "Busy walk-in")["session_id"]
    plain = client.post("/sessions", json={"case_id": "wrist_trauma_001"}).json()["session_id"]
    for s in (sid, plain):
        client.post(f"/sessions/{s}/interactions", json={"role": "learner", "text": "Hello, I'm a medical student. What happened?"})
        client.post(f"/sessions/{s}/examine", json={"body_part": SNUFFBOX})
    event(client, sid, "deliver_equipment", item="wrist_support_medium")
    event(client, sid, "enable_coaching")
    client.get(f"/sessions/{sid}/hint")
    for s in (sid, plain):
        client.post(f"/sessions/{s}/measurements", json={"measurement_id": "right_wrist_circumference"})
        client.post(f"/sessions/{s}/fitting", json={"fit": {"size": "medium", "orientation": "thumb_radial", "offset_cm": 3, "tightness": "snug"}})
        fb = client.post(f"/sessions/{s}/diagnose", json={"diagnosis": "scaphoid fracture",
                                                         "notes": {"management": "Thumb spica splint, refer to fracture clinic."}}).json()
    d = client.get(f"/sessions/{sid}/debrief").json()
    # the existing scoring is identical with and without a scenario
    other = client.get(f"/sessions/{plain}/feedback").json()
    strip = lambda f: {k: v for k, v in f.items() if k != "session_id"}  # noqa: E731
    assert strip(d["feedback"]) == strip(fb) == strip(other)

    assert d["scenario"]["title"].startswith("Busy walk-in") and d["scenario"]["review_state"] == "experimental"
    res = {r["id"]: r for r in d["resources"]}
    assert not res["wrist_support_medium"]["available_at_start"] and res["wrist_support_medium"]["delivered_at_seq"]
    assert res["wrist_support_medium"]["used"] and res["measuring_tape"]["used"] and not res["wrist_support_small"]["used"]
    assert not res["imaging_xray"]["available_at_end"]
    assert [i["kind"] for i in d["interventions"]] == ["deliver_equipment", "enable_coaching"]
    assert d["scores"]["management"]["max_score"] == 20 and d["scores"]["management"]["achievable_max"] == 11
    assert d["scores"]["fitting"]["achievable_max"] == 20  # the medium support was delivered
    kinds = [t["type"] for t in d["timeline"]]
    assert kinds == ["question", "examination", "intervention", "intervention", "hint", "measurement", "fitting"]
    text = " ".join(d["interpretation"])
    assert "Challenging" in text and "of 11 achievable points" in text and "Instructor interventions: 2" in text
    assert "Coaching hints given: 1" in text and "not clinician-reviewed" in text


# P4 assistance

def test_assist_is_deterministic_without_credentials(client):
    body = {"template_id": "wrist_trauma_001", "environment": "community_clinic", "difficulty": "challenging",
            "crowdedness": "busy", "tools": ["measuring_tape"], "bystander": "anxious_relative"}
    a, b = client.post("/studio/assist", json=body).json(), client.post("/studio/assist", json=body).json()
    assert a == b and a["source"] == "demo" and a["model"] is None
    assert "safe_plan_without_imaging" in a["learning_objectives"] and "imaging_reasoning" not in a["learning_objectives"]
    assert len(a["bystander_lines"]) == 4
    # the draft is usable as it is
    cfg = config(environment="community_clinic", tools=["measuring_tape"], bystander="anxious_relative",
                 learning_objectives=a["learning_objectives"],
                 narrative={k: a[k] for k in ("description", "patient_personality", "bystander_lines")})
    assert client.post("/studio/validate", json=cfg).json()["valid"]
    assert client.post("/studio/assist", json=body | {"template_id": "nope"}).status_code == 404


def test_demo_drafts_are_clean_for_every_choice():
    import itertools
    for t in studio.templates():
        case = main.SCENARIOS[t["case_id"]]
        for env, diff, crowd, by in itertools.product(*(
                [o["id"] for o in t[k]] for k in ("environments", "difficulties", "crowdedness", "bystander_behaviors"))):
            d = assist.template_draft(assist.AssistRequest(template_id=t["template_id"], environment=env, difficulty=diff,
                                                           crowdedness=crowd, bystander=by), t)
            assert all(not studio.clinical_claim(x, case, t) for x in [d.description, d.patient_personality, *d.bystander_lines])
            assert len(d.description) < 600 and all(len(x) <= 160 for x in d.bystander_lines)


def test_ai_draft_with_clinical_claims_is_rejected(monkeypatch):
    """The model call is stubbed: this checks the validation after it, not the model."""
    import sys
    import types

    def fake(text):
        class Messages:
            def parse(self, **kw):
                return types.SimpleNamespace(stop_reason="end_turn", parsed_output=assist.AssistDraft(
                    description=text, patient_personality="Quiet.", bystander_lines=["Is it going to be okay?"],
                    learning_objectives=["focused_history", "imaging_reasoning", "invented_objective"]))
        mod = types.ModuleType("anthropic")
        mod.Anthropic = lambda **kw: types.SimpleNamespace(messages=Messages())
        mod.APIError = RuntimeError
        return mod

    req = assist.AssistRequest(template_id="wrist_trauma_001", environment="outpatient_clinic", difficulty="standard",
                               crowdedness="quiet", tools=ALL_TOOLS, bystander="calm_relative")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test")
    monkeypatch.setenv("MEDSIM_LIVE_AI", "1")
    monkeypatch.setitem(sys.modules, "anthropic", fake("A patient with a scaphoid fracture."))
    bad = assist.draft(req, main.SCENARIOS)
    assert bad.source == "template" and "rejected" in bad.notes[0] and "scaphoid" in bad.notes[0]
    monkeypatch.setitem(sys.modules, "anthropic", fake("A calm afternoon clinic with time to talk."))
    ok = assist.draft(req, main.SCENARIOS)
    assert ok.source == "llm" and ok.requires_review and ok.learning_objectives == ["focused_history", "imaging_reasoning"]
    assert "invented_objective" in ok.notes[1]
    no_kit = assist.draft(req.model_copy(update={"tools": ["measuring_tape"]}), main.SCENARIOS)
    assert no_kit.learning_objectives == ["focused_history"] and "imaging_reasoning" in no_kit.notes[1]


# Journey cases in the generator

def journey_config(**over):
    base = dict(template_id="road_trauma_journey_001", title="Night roadside", environment="night_rain",
                difficulty="standard", crowdedness="moderate", tools=["xray_forearm", "bloods"],
                learning_objectives=["handover"], seed=3)
    return base | over


def test_journey_template_is_in_the_catalog_with_its_places(client):
    t = next(t for t in client.get("/studio/catalog").json() if t["template_id"] == "road_trauma_journey_001")
    assert t["kind"] == "journey"
    assert [s["id"] for s in t["stages"]] == ["scene", "ambulance", "hospital"]
    assert all(s["team"] and s["actions"] for s in t["stages"])
    assert [d["id"] for d in t["dimensions"]] == ["core", "management"]  # no wrist support to score
    assert "open fracture" not in json.dumps(t).lower()


def test_journey_scenario_shapes_noise_and_investigations_per_place(client):
    d = client.post("/studio/scenarios", json=journey_config(advanced={"stage_noise": {"hospital": 0.9}})).json()
    noise = {s["id"]: s["noise"] for s in d["journey"]["stages"]}
    assert noise == {"scene": 0.75, "ambulance": 0.55, "hospital": 0.9}  # case + night rain 0.1 + onlookers 0.1
    listed = next(x for x in client.get("/studio/scenarios").json() if x["scenario_id"] == d["scenario_id"])
    assert listed["kind"] == "journey" and listed["stages"][0] == "At the roadside"
    client.post(f"/studio/scenarios/{d['scenario_id']}/publish")
    s = client.post("/sessions", json={"case_id": "road_trauma_journey_001", "scenario_code": d["code"]}).json()
    case = s["case"]
    assert [st["noise"] for st in case["journey"]["stages"]] == [0.75, 0.55, 0.9]
    assert {i["id"] for i in case["investigations"]} == {"rt_xray_forearm", "rt_bloods"}  # CT left out
    assert s["scenario"]["environment_label"] == "Night, heavy rain"


def test_advanced_overrides_are_validated_and_applied(client):
    bad = client.post("/studio/validate", json=journey_config(advanced={"stage_noise": {"moon": 0.2}})).json()
    assert any(i["field"] == "advanced.stage_noise" and i["severity"] == "error" for i in bad["issues"])
    wrist = client.post("/studio/validate", json=config(advanced={"stage_noise": {"scene": 0.2}})).json()
    assert "only applies to journey" in json.dumps(wrist)
    d = client.post("/studio/preview", json=config(
        bystander="anxious_relative", difficulty="guided",
        advanced={"hint_policy": "off", "interject_every_s": 45, "crowd_figures": 5})).json()
    assert d["difficulty"]["hint_policy"] == "off"
    assert d["companions"]["bystander"]["interject_every_s"] == 45
    assert len(d["environment"]["crowd"]["figures"]) == 5


def test_concurrent_first_loads_of_an_empty_library_do_not_fail(tmp_path, monkeypatch):
    from concurrent.futures import ThreadPoolExecutor
    from app import studio
    from app.sessions import load_scenarios
    monkeypatch.setenv("MEDSIM_STUDIO_DB", str(tmp_path / "library.json"))
    lib = studio.Library(load_scenarios())
    with ThreadPoolExecutor(8) as pool:  # each sees no file, seeds and saves at once
        list(pool.map(lambda _: lib._load(), range(16)))
    assert json.loads((tmp_path / "library.json").read_text()) and not list(tmp_path.glob("*.tmp"))
