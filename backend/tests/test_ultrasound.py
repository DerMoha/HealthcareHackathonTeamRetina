"""Obstetric ultrasound case: catalog, gel and scans, evaluation from the scan record, no leaks."""
import json
import os
from pathlib import Path

import pytest

US = "obstetric_ultrasound_001"
WRIST = "wrist_trauma_001"
ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).parent / "fixtures"
MANIFEST = ROOT / "visionos" / "MedSimXR" / "Resources" / "Ultrasound" / "ultrasound_manifest.json"
REGIONS = ["abdomen_fundus", "abdomen_upper", "abdomen_center", "abdomen_lower", "abdomen_left", "abdomen_right"]

PERFECT_LEARNER = [
    "Hello, I'm a medical student. Are you Sarah? Could you confirm your full name and date of birth?",
    "I'd like to do your scan today. Is that all right with you?",
    "I'll put some gel on your tummy and move a probe over it to look at the baby. It may be a bit cold.",
]
AFTER_SCAN = [
    "I can see the heartbeat and the measurements look in keeping with twenty weeks.",
    "Would you like to know the sex if it can be seen? I can only tell you what the pictures show today.",
]
NOTES = {"examination": "BPD 4.61 cm, HC 16.73 cm. AC 13.82 cm, EFW 289 g. FL 3.17 cm. Posterior placenta. "
                        "Liquor normal. Four-chamber heart view seen. Spine seen.",
         "assessment": "Everything measured is in keeping with 20 weeks."}
IMPRESSION = "Normal singleton intrauterine pregnancy, about 20 weeks, posterior placenta, normal liquor"
# one region per view of the standard set (each region's first scan with gel), plus the second views needed
STANDARD = [("abdomen_lower", "head_bpd"), ("abdomen_upper", "heart_4ch"), ("abdomen_left", "spine"),
            ("abdomen_upper", "abdomen_ac"), ("abdomen_right", "femur"), ("abdomen_fundus", "placenta"),
            ("abdomen_fundus", "amniotic_fluid")]


def create(client, **config):
    body = {"case_id": US}
    if config:
        body["config"] = config
    return client.post("/sessions", json=body)


@pytest.fixture
def usid(client):
    return create(client).json()["session_id"]


def say(client, sid, text, role="learner"):
    assert client.post(f"/sessions/{sid}/interactions", json={"role": role, "text": text}).status_code == 200


def gel(client, sid):
    r = client.post(f"/sessions/{sid}/gel")
    assert r.status_code == 200, r.text
    return r.json()


def scan(client, sid, region, **extra):
    return client.post(f"/sessions/{sid}/scans", json={"region_id": region, **extra})


def perfect_run(client, sid, notes=NOTES, impression=IMPRESSION):
    for t in PERFECT_LEARNER:
        say(client, sid, t)
    gel(client, sid)
    for region, view in STANDARD:
        assert scan(client, sid, region).json()["region_id"] == region
    for t in AFTER_SCAN:
        say(client, sid, t)
    return client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": impression, "notes": notes}).json()


def category(fb, cid):
    return next(c for c in fb["categories"] if c["id"] == cid)


def crit(fb, cid):
    return next(c for cat in fb["categories"] for c in cat["criteria"] if c["id"] == cid)


# ---------------------------------------------------------------- catalog and config

def test_both_cases_are_listed_with_the_ultrasound_catalog(client):
    cases = {c["case_id"]: c for c in client.get("/cases").json()}
    assert set(cases) >= {WRIST, US}
    us = cases[US]
    cat = us["catalog"]
    assert cat["allowed_avatars"] == ["female"] and cat["default_avatar"] == "female"
    assert cat["avatar_model"] == "Patient_pregnant"
    assert cat["allowed_moods"] == ["calm", "nervous", "angry"]
    assert cat["icon"] and cat["setting"] and cat["summary"]
    assert cat["skills"] == ["Consent & communication", "Ultrasound probe handling", "Fetal biometry", "Documentation"]
    assert us["zones"] == [] and us["investigations"] == []
    assert us["orthotics"] == {"measurements": [], "sizes": [], "tightness": []}
    assert cases[WRIST]["ultrasound"] is None


def test_public_regions_name_anchors_but_not_views(client):
    regions = {c["case_id"]: c for c in client.get("/cases").json()}[US]["ultrasound"]["regions"]
    assert [r["id"] for r in regions] == REGIONS
    for r in regions:
        assert set(r) == {"id", "label", "attach_to", "radius"}
        assert r["attach_to"] == r["id"] and 0.03 <= r["radius"] <= 0.08 and r["label"]


def test_nothing_hidden_leaks_into_public_responses(client):
    sess = create(client)
    sid = sess.json()["session_id"]
    reset = client.post(f"/sessions/{sid}/reset")
    pre = client.get(f"/sessions/{sid}/feedback")
    assert pre.json()["scan_review"] == []
    for r in (client.get("/cases"), sess, reset, pre):
        text = r.text.lower()
        for word in ['"hidden"', "rubric", '"persona"', "patient_by_mood", "clinical_label", '"views"',
                     "posterior", "cephalic", "bpd", "4.61", "singleton", "heart_4ch", "head_bpd", "us_head"]:
            assert word not in text, (word, r.request.url)
    case = sess.json()["case"]
    assert "normal" not in json.dumps([case["title"], case["learner_brief"], case["catalog"]]).lower()
    ctx = case["voice_context"].lower()
    for word in ["posterior", "cephalic", "bpd", "4.61", "singleton", "anomaly", "placenta is"]:
        assert word not in ctx


def test_config_allows_only_the_female_patient_and_the_three_moods(client):
    assert create(client).json()["config"] == {"mood": "calm", "avatar": "female"}
    for mood in ("calm", "nervous", "angry"):
        assert create(client, mood=mood, avatar="female").json()["config"] == {"mood": mood, "avatar": "female"}
    assert create(client, avatar="male").status_code == 422
    assert create(client, mood="furious").status_code == 422


def test_mood_changes_voice_context_and_lines_but_not_facts(client):
    ctx, lines = {}, {}
    for mood in ("calm", "nervous", "angry"):
        case = create(client, mood=mood).json()["case"]
        ctx[mood] = case["voice_context"]
        lines[mood] = {d["id"]: d["patient"] for d in case["scripted_dialogue"]}
    base = {c["case_id"]: c for c in client.get("/cases").json()}[US]["voice_context"]
    assert all(c.startswith(base) for c in ctx.values()) and len(set(ctx.values())) == 3
    assert "first-time mother" in ctx["nervous"] and "waiting" in ctx["angry"] and "she/her" in ctx["calm"]
    assert "Sarah" in ctx["calm"] and "20 weeks pregnant" in base and "gravida 1" in base
    assert len({l["us_greeting"] for l in lines.values()}) == 3
    assert lines["calm"].keys() == lines["angry"].keys()
    ids = list(lines["calm"])
    assert {"us_greeting", "us_consent", "us_symptoms", "us_movements", "us_worries", "us_sex_question"} <= set(ids)


def test_scripted_line_ids_do_not_collide_with_the_wrist_case(client):
    cases = {c["case_id"]: c for c in client.get("/cases").json()}
    assert not {d["id"] for d in cases[US]["scripted_dialogue"]} & {d["id"] for d in cases[WRIST]["scripted_dialogue"]}


# ---------------------------------------------------------------- gel and scans

def test_every_region_yields_its_views_in_order_and_cycles(client, usid):
    gel(client, usid)
    expected = {
        "abdomen_fundus": ["placenta", "amniotic_fluid"],
        "abdomen_upper": ["heart_4ch", "abdomen_ac"],
        "abdomen_center": ["overview", "spine", "umbilical_cord"],
        "abdomen_lower": ["head_bpd", "head_hc", "head_cerebellum", "profile"],
        "abdomen_left": ["spine", "femur"],
        "abdomen_right": ["femur", "amniotic_fluid"],
    }
    for region, views in expected.items():
        got = [scan(client, usid, region).json()["view_id"] for _ in range(len(views) + 1)]
        assert got == views + [views[0]], region  # the next scan starts the cycle again


def test_scan_result_carries_image_title_measurements_and_credit(client, usid):
    gel(client, usid)
    r = scan(client, usid, "abdomen_lower").json()
    assert r["quality"] == "good" and r["gel_applied"] is True and r["view_id"] == "head_bpd"
    assert r["image"] == "us_head_bpd" and "Transthalamic" in r["title"] and r["caption"]
    assert r["measurements"] == [{"label": "BPD", "value": 4.61, "unit": "cm"}]
    assert "CC BY 4.0" in r["image_credit"] and r["depth_cm"] > 0 and r["gain"] > 0 and r["repeat_count"] == 1
    heart = scan(client, usid, "abdomen_upper").json()
    assert heart["view_id"] == "heart_4ch" and heart["measurements"] == []
    assert "heart" in heart["patient_response"].lower() and "baby" in heart["patient_response"].lower()
    assert heart["voice_context"].startswith("[") and heart["patient_response"] in heart["voice_context"]
    assert scan(client, usid, "abdomen_upper").json()["measurements"][0] == {"label": "AC", "value": 13.82, "unit": "cm"}


def test_scanning_before_gel_gives_no_image_and_a_reminder(client, usid):
    r = scan(client, usid, "abdomen_upper").json()
    assert r["quality"] == "poor" and r["view_id"] is None and r["image"] is None and r["gel_applied"] is False
    assert r["measurements"] == [] and "gel" in r["caption"].lower() and "gel" in r["patient_response"].lower()
    assert r["repeat_count"] == 1 and scan(client, usid, "abdomen_upper").json()["repeat_count"] == 2
    g = gel(client, usid)
    assert g["applied"] and g["repeat_count"] == 1 and "cold" in g["patient_response"]
    # the poor attempts did not use up the region's views
    assert scan(client, usid, "abdomen_upper").json()["view_id"] == "heart_4ch"
    again = gel(client, usid)
    assert again["repeat_count"] == 2 and again["patient_response"] != g["patient_response"]


def test_gel_hint_can_only_make_a_scan_worse(client, usid):
    assert scan(client, usid, "abdomen_lower", gel_applied=True).json()["quality"] == "poor"  # no gel recorded
    gel(client, usid)
    assert scan(client, usid, "abdomen_lower", gel_applied=False).json()["quality"] == "poor"
    assert scan(client, usid, "abdomen_lower", gel_applied=True).json()["quality"] == "good"
    assert scan(client, usid, "abdomen_lower").json()["quality"] == "good"


def test_unknown_region_and_wrong_case_are_404(client, usid):
    assert scan(client, usid, "abdomen_nowhere").status_code == 404
    assert client.post(f"/sessions/{usid}/scans", json={}).status_code == 422
    assert client.post("/sessions/nope/gel").status_code == 404
    wrist = client.post("/sessions", json={"case_id": WRIST}).json()["session_id"]
    assert client.post(f"/sessions/{wrist}/gel").status_code == 404
    assert scan(client, wrist, "abdomen_upper").status_code == 404


def test_reset_clears_gel_and_scans(client, usid):
    gel(client, usid)
    scan(client, usid, "abdomen_upper")
    client.post(f"/sessions/{usid}/reset")
    assert scan(client, usid, "abdomen_upper").json()["quality"] == "poor"  # gel is gone
    assert gel(client, usid)["repeat_count"] == 1
    fb = client.get(f"/sessions/{usid}/feedback").json()
    assert fb["relevant_findings"] == ["Upper abdomen, midline: no usable image (no gel)"]


def test_scenario_images_and_credits_match_the_bundled_manifest():
    scenario = json.loads((ROOT / "scenarios" / f"{US}.json").read_text(encoding="utf-8"))
    manifest = {m["id"]: m for m in json.loads(MANIFEST.read_text(encoding="utf-8"))}
    us = scenario["ultrasound"]
    views = {v["id"]: v for v in us["views"]}
    for v in views.values():
        entry = manifest[v["image"]]
        assert (MANIFEST.parent / entry["file"]).is_file()
        assert entry["license"] in v["image_credit"], v["id"]
    for r in us["regions"]:
        assert r["views"] and all(v in views for v in r["views"])
    review_views = {v for item in scenario["hidden"]["scan_review"] for v in item["views"]}
    assert review_views <= set(views)
    assert {v["image"] for item in scenario["hidden"]["scan_review"] for v in [item]} <= set(manifest)
    anchors = json.loads((ROOT / "visionos/MedSimXR/Resources/Patient_pregnant.json").read_text())["anchors"]
    assert {r["attach_to"] for r in us["regions"]} <= set(anchors)


# ---------------------------------------------------------------- evaluation

def test_perfect_run_scores_100(client, usid):
    fb = perfect_run(client, usid)
    assert (fb["total_score"], fb["max_score"]) == (100, 100), [(c["id"], c["met"]) for cat in fb["categories"] for c in cat["criteria"] if not c["met"]]
    assert fb["diagnostic_assessment"]["verdict"] == "correct" and "20 weeks" in fb["diagnostic_assessment"]["expected"]
    assert [c["id"] for c in fb["categories"]] == ["communication", "scanning", "documentation"]
    assert fb["missed"] == [] and len(fb["strengths"]) == 22
    assert fb["replay"] == [] and fb["investigations"] == [] and fb["next_steps"]
    assert fb["management"] == {"title": "", "score": 0, "max_score": 0, "criteria": []}
    assert fb["fitting"]["max_score"] == 0 and fb["fitting"]["criteria"] == [] and fb["fitting"]["explanation"] is None
    assert [d["status"] for d in fb["documentation"]] == ["documented"] * 7
    assert crit(fb, "view_head")["evidence"] == "Transthalamic view of the fetal head (BPD)"
    assert all(i["obtained"] for i in fb["scan_review"] if i["expected"])
    assert len(fb["relevant_findings"]) == 7 and fb["relevant_findings"][0].endswith("BPD 4.61 cm")


def test_empty_run_is_redacted_and_scores_nothing(client, usid):
    fb = client.get(f"/sessions/{usid}/feedback").json()
    assert fb["diagnostic_assessment"]["verdict"] == "not_submitted" and fb["total_score"] == 0
    assert all(c["criteria"] == [] for c in fb["categories"]) and fb["scan_review"] == [] and fb["next_steps"] == []
    assert fb["strengths"] == [] and fb["missed"] == [] and fb["max_score"] == 100


def test_only_views_actually_obtained_earn_points(client, usid):
    for t in PERFECT_LEARNER:
        say(client, usid, t)
    gel(client, usid)
    scan(client, usid, "abdomen_lower")   # head_bpd
    scan(client, usid, "abdomen_upper")   # heart_4ch
    fb = client.post(f"/sessions/{usid}/diagnose", json={"diagnosis": IMPRESSION, "notes": NOTES}).json()
    met = {c["id"] for cat in fb["categories"] for c in cat["criteria"] if c["met"]}
    assert {"view_head", "view_heart", "gel_applied"} <= met
    assert not met & {"view_spine", "view_abdomen", "view_femur", "view_placenta", "view_liquor"}
    assert category(fb, "scanning")["score"] == 15
    # values were written down for views that were never obtained: no points, flagged as unsupported
    assert not met & {"doc_abdomen", "doc_femur", "doc_placenta", "doc_liquor"} and "doc_head" in met
    docs = {d["criterion_id"]: d for d in fb["documentation"]}
    for cid in ("view_abdomen", "view_femur", "view_placenta", "view_liquor", "view_spine"):
        assert docs[cid]["status"] == "unsupported", cid
        assert "no matching examination was recorded" in docs[cid]["comment"]
    assert docs["view_head"]["status"] == "documented" and docs["view_heart"]["status"] == "documented"
    assert "not supported" in fb["summary"]
    obtained = {i["id"] for i in fb["scan_review"] if i["obtained"]}
    assert obtained == {"head", "heart"}


def test_notes_alone_never_earn_scanning_or_documentation_points(client, usid):
    fb = client.post(f"/sessions/{usid}/diagnose", json={"diagnosis": IMPRESSION, "notes": NOTES}).json()
    assert category(fb, "scanning")["score"] == 0
    assert category(fb, "documentation")["score"] == 5  # only the impression, which is the learner's own statement
    assert all(d["status"] == "unsupported" for d in fb["documentation"]) and len(fb["documentation"]) == 7


def test_scan_without_gel_costs_the_gel_criteria(client, usid):
    say(client, usid, "Hello, I'm a medical student. Could you confirm your full name?")
    say(client, usid, "Is it okay if we start?")
    scan(client, usid, "abdomen_lower")     # dry probe
    say(client, usid, PERFECT_LEARNER[2])   # warning comes too late
    gel(client, usid)
    scan(client, usid, "abdomen_lower")
    fb = client.post(f"/sessions/{usid}/diagnose", json={"diagnosis": IMPRESSION}).json()
    assert not crit(fb, "gel_applied")["met"] and "without gel" in crit(fb, "gel_applied")["comment"].lower()
    assert crit(fb, "gel_warning")["met"]                 # still said before the gel went on
    assert not crit(fb, "procedure_explained")["met"]     # but not before the first (dry) scan
    assert crit(fb, "view_head")["met"]  # the later scan with gel still counts
    assert fb["relevant_findings"][0].startswith("Transthalamic")


def test_gel_before_the_first_scan_and_a_warning_before_the_gel_are_credited(client, usid):
    gel(client, usid)  # gel first, but no warning given
    scan(client, usid, "abdomen_lower")
    fb = client.get(f"/sessions/{usid}/feedback").json()
    assert fb["total_score"] == 5 + 5  # gel_applied, view_head; nothing else is credited without a diagnosis
    after = client.post(f"/sessions/{usid}/diagnose", json={"diagnosis": "x"}).json()
    assert crit(after, "gel_applied")["met"] and not crit(after, "gel_warning")["met"]


def test_communication_checks_follow_the_order_of_events(client, usid):
    say(client, usid, "Let's start.")
    gel(client, usid)
    scan(client, usid, "abdomen_lower")
    say(client, usid, "Hello, I'm a medical student. Could you confirm your full name?")
    say(client, usid, "Is it okay if I scan you? It may be a bit cold.")
    say(client, usid, "Everything looks fine, I can see the heartbeat.")
    fb = client.post(f"/sessions/{usid}/diagnose", json={"diagnosis": IMPRESSION}).json()
    assert crit(fb, "introduction")["met"] and crit(fb, "identity_check")["met"]
    assert not crit(fb, "consent")["met"]              # asked after scanning had started
    assert not crit(fb, "procedure_explained")["met"]  # explained after the first scan
    assert not crit(fb, "gel_warning")["met"]          # warned after the gel
    assert crit(fb, "findings_explained")["met"]       # said after the first good scan
    assert not crit(fb, "sex_handled")["met"] and crit(fb, "respectful")["met"]


def test_findings_are_only_explained_after_a_good_scan(client, usid):
    say(client, usid, "Everything looks fine, I can see the heartbeat.")
    scan(client, usid, "abdomen_upper")  # dry probe: poor image
    fb = client.post(f"/sessions/{usid}/diagnose", json={"diagnosis": IMPRESSION}).json()
    assert not crit(fb, "findings_explained")["met"]


@pytest.mark.parametrize("text,ok", [
    ("Do you want to know the sex? I can only say what the pictures show.", True),
    ("I can't say from this picture, do you want to know if we can see it?", True),
    ("It's definitely a boy!", False),
    ("What a lovely picture.", False),
])
def test_sex_question_credit_needs_a_sensible_answer(client, usid, text, ok):
    gel(client, usid)
    scan(client, usid, "abdomen_lower")
    say(client, usid, text)
    fb = client.post(f"/sessions/{usid}/diagnose", json={"diagnosis": IMPRESSION}).json()
    assert crit(fb, "sex_handled")["met"] is ok


@pytest.mark.parametrize("impression,verdict", [
    ("Normal singleton pregnancy at 20 weeks", "correct"),
    ("Everything is unremarkable", "correct"),
    ("Singleton pregnancy, 20 weeks", "partial"),
    ("Fetal abnormality, anomaly seen", "incorrect"),
])
def test_impression_verdicts(client, usid, impression, verdict):
    fb = client.post(f"/sessions/{usid}/diagnose", json={"diagnosis": impression}).json()
    assert fb["diagnostic_assessment"]["verdict"] == verdict
    assert crit(fb, "impression")["points"] == {"correct": 5, "partial": 2, "incorrect": 0}[verdict]


def test_findings_and_scoring_do_not_depend_on_mood(client):
    def run(mood):
        sid = create(client, mood=mood).json()["session_id"]
        fb = perfect_run(client, sid)
        fb["session_id"] = "SESSION"
        return fb
    reference = run("calm")
    assert run("nervous") == reference and run("angry") == reference


def test_wrist_case_has_no_scan_review_and_keeps_its_scoring(client):
    sid = client.post("/sessions", json={"case_id": WRIST}).json()["session_id"]
    fb = client.post(f"/sessions/{sid}/diagnose", json={"diagnosis": "Suspected scaphoid fracture"}).json()
    assert fb["scan_review"] == [] and fb["max_score"] == 100 and fb["management"]["max_score"] == 20
    assert fb["fitting"]["max_score"] == 20


# ---------------------------------------------------------------- parity with the Swift offline engine

def run_ultrasound_parity(client):
    spec = json.loads((FIXTURES / "ultrasound_parity_input.json").read_text(encoding="utf-8"))
    created = client.post("/sessions", json={"case_id": spec["case_id"], "config": spec["config"]}).json()
    sid = created["session_id"]
    out = {"case": created["case"], "config": created["config"], "results": [], "feedback": None}
    for s in spec["steps"]:
        if s["op"] == "interaction":
            say(client, sid, s["text"], s["role"])
        elif s["op"] == "gel":
            out["results"].append(client.post(f"/sessions/{sid}/gel").json())
        elif s["op"] == "scan":
            body = {k: v for k, v in s.items() if k != "op"}
            out["results"].append(client.post(f"/sessions/{sid}/scans", json=body).json())
        else:
            out["feedback"] = client.post(f"/sessions/{sid}/diagnose",
                                          json={"diagnosis": s["diagnosis"], "notes": s.get("notes")}).json()
    out["feedback"]["session_id"] = "SESSION"
    return out


def test_ultrasound_parity_golden(client):
    """Swift's OfflineClinicalEngine must produce the same (checked by check_offline_engine.sh).
    Regenerate after editing the scenario: REGEN_FIXTURES=1 python -m pytest -k ultrasound_parity."""
    got = run_ultrasound_parity(client)
    path = FIXTURES / "ultrasound_parity_expected.json"
    if os.environ.get("REGEN_FIXTURES"):
        path.write_text(json.dumps(got, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    assert got == json.loads(path.read_text(encoding="utf-8"))
    fb = got["feedback"]
    assert [r["quality"] for r in got["results"] if "quality" in r] == ["poor", "good", "good", "good", "good", "poor", "good"]
    docs = {d["criterion_id"]: d["status"] for d in fb["documentation"]}
    assert docs["view_femur"] == "unsupported" and docs["view_head"] == "documented"
