"""Notebook AI routes with the model replaced: tidy keeps the learner's facts, review stays grounded
in the transcript, everything degrades to the learner's own words, and usage never leaks the key."""
from app import notes_ai

TRANSCRIPT = [
    {"role": "learner", "text": "What happened to your wrist?"},
    {"role": "patient", "text": "I fell off my bike yesterday and landed on my right hand."},
    {"role": "learner", "text": "Any allergies?"},
    {"role": "patient", "text": "I'm allergic to penicillin."},
]


def fake_model(monkeypatch, answer):
    """Every model call returns `answer(schema)`; records the prompts."""
    prompts = []

    def ask(prompt, schema, effort, max_tokens):
        prompts.append(prompt)
        return answer(schema)
    monkeypatch.setattr(notes_ai, "_ask", ask)
    notes_ai._cache.clear()
    return prompts


def test_tidy_without_model_keeps_raw(client):
    r = client.post("/notes/tidy", json={"text": "  uh fell off the bike yesterday ", "field": "history"}).json()
    assert r["text"] == "uh fell off the bike yesterday" and r["source"] == "raw" and "unavailable" in r["note"]


def test_tidy_uses_model(client, monkeypatch):
    prompts = fake_model(monkeypatch, lambda s: s(text="- Fell off bike yesterday onto R hand."))
    r = client.post("/notes/tidy", json={"text": "uh so he fell off the bike yesterday onto the right hand",
                                         "field": "history"}).json()
    assert r == {"text": "- Fell off bike yesterday onto R hand.", "source": "ai", "note": ""}
    assert "Note section: history" in prompts[0] and "right hand" in prompts[0]


def test_tidy_rejects_invented_numbers(client, monkeypatch):
    fake_model(monkeypatch, lambda s: s(text="- Pain 8/10 since yesterday."))
    r = client.post("/notes/tidy", json={"text": "pain since yesterday"}).json()
    assert r["text"] == "pain since yesterday" and r["source"] == "raw" and "8" in r["note"]


def test_tidy_rejects_padding(client, monkeypatch):
    fake_model(monkeypatch, lambda s: s(text="- Pain. " + "Likely a scaphoid injury requiring imaging. " * 3))
    r = client.post("/notes/tidy", json={"text": "pain"}).json()
    assert r["source"] == "raw" and "longer" in r["note"]


def test_tidy_validates_input(client):
    assert client.post("/notes/tidy", json={"text": ""}).status_code == 422
    assert client.post("/notes/tidy", json={"text": "x" * 4001}).status_code == 422


def test_review_needs_conversation_and_notes(client, monkeypatch):
    fake_model(monkeypatch, lambda s: (_ for _ in ()).throw(AssertionError("no model call expected")))
    r = client.post("/notes/review", json={"notes": {"history": "fell"}, "transcript": TRANSCRIPT[1:2]}).json()
    assert r["source"] == "unavailable" and "No conversation" in r["note"]
    r = client.post("/notes/review", json={"notes": {}, "transcript": TRANSCRIPT}).json()
    assert r["source"] == "unavailable" and "empty" in r["note"]


def test_review_drops_ungrounded_quotes_and_caches(client, monkeypatch):
    def answer(schema):
        return schema(
            captured=[{"point": "Fall onto right hand", "quote": "landed on my right hand"}],
            missed=[{"point": "Penicillin allergy", "quote": "I'm allergic to penicillin."},
                    {"point": "Smoker", "quote": "I smoke ten a day"}],  # never said: dropped
            inaccurate=[])
    prompts = fake_model(monkeypatch, answer)
    body = {"notes": {"history": "Fell on right hand yesterday."}, "transcript": TRANSCRIPT}
    r = client.post("/notes/review", json=body).json()
    assert r["source"] == "ai" and [p["point"] for p in r["captured"]] == ["Fall onto right hand"]
    assert [p["point"] for p in r["missed"]] == ["Penicillin allergy"]
    assert "Patient: I'm allergic to penicillin." in prompts[0] and "history: Fell on right hand" in prompts[0]
    assert client.post("/notes/review", json=body).json() == r and len(prompts) == 1


def test_review_model_failure(client, monkeypatch):
    fake_model(monkeypatch, lambda s: None)
    r = client.post("/notes/review", json={"notes": {"history": "x"}, "transcript": TRANSCRIPT}).json()
    assert r["source"] == "unavailable" and r["missed"] == []


def test_adds_facts_rules():
    assert notes_ai._adds_facts("BPD 4.61 cm", "- BPD 4.61 cm") is None
    assert notes_ai._adds_facts("twenty weeks", "- 20 weeks") is not None


def test_usage_unconfigured_503(client, monkeypatch):
    monkeypatch.delenv("ELEVENLABS_API_KEY", raising=False)
    assert client.get("/elevenlabs/usage").status_code == 503


def test_usage_success_and_errors_hide_key(client, monkeypatch):
    import httpx
    monkeypatch.setenv("ELEVENLABS_API_KEY", "sk-secret")
    monkeypatch.setattr(httpx, "get", lambda *a, **k: httpx.Response(
        200, json={"tier": "free", "character_count": 850, "character_limit": 1000,
                   "next_character_count_reset_unix": 1767225600}))
    r = client.get("/elevenlabs/usage").json()
    assert r["tier"] == "free" and r["credits_remaining"] == 150 and r["resets_at"].startswith("2026-01-01")
    monkeypatch.setattr(httpx, "get", lambda *a, **k: httpx.Response(401, json={"detail": "sk-secret"}))
    r = client.get("/elevenlabs/usage")
    assert r.status_code == 502 and "sk-secret" not in r.text and "User: read" in r.text
