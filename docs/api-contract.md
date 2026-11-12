# MedSim XR — Shared Contracts (v1)

Single source of truth for all three workstreams. **Do not change a field name
or semantics without updating this file, the backend models, and
`visionos/MedSimXR/Models/Contracts.swift` in the same commit.**

## 0. Conventions

- Base URL: `http://<backend-host>:8000` (no path prefix). Headset config key: `MEDSIM_BACKEND_HOST` (`host:port`).
- JSON, `snake_case` keys, UTF-8. Swift decodes with `.convertFromSnakeCase`.
- Timestamps: ISO-8601 UTC strings. Server-assigned unless noted.
- Errors: FastAPI default `{"detail": "<human readable message>"}`.
  - `404` unknown session / case / examination zone
  - `422` request validation failure
  - `503` ElevenLabs token endpoint not configured
- The backend (or the offline engine implementing the same rules) is the **only** source of clinical findings. The headset sends *which zone* was touched, never a finding.
- Anything under `hidden` in a scenario file never leaves the engine, except through the feedback response **after** a diagnosis was submitted.

## 1. Scenario file (`scenarios/<case_id>.json`)

See `scenarios/wrist_trauma_001.json`. Top-level keys:

| Key | Visible to learner/app | Purpose |
|---|---|---|
| `case_id`, `title`, `learner_brief`, `patient` | yes | metadata |
| `voice_context` | app only (sent to voice agent) | facts the *patient* knows; contains no diagnosis |
| `examination_zones[]` → `id,label,attach_to,offset,radius` | yes | spatial zone definition |
| `examination_zones[].result` | only via `/examine` | finding for that zone |
| `scripted_dialogue[]` → `id,learner,patient` | yes | offline fallback dialogue |
| `hidden.diagnosis`, `hidden.next_steps`, `hidden.rubric` | **no** | scoring |

Zone placement: `attach_to` is the name of an avatar entity (`right_wrist`,
`right_forearm`, `left_wrist`, …); `offset` is `[x,y,z]` metres in that
entity's local space; `radius` is the collision sphere radius in metres.

### Rubric check types (`hidden.rubric.categories[].criteria[].check`)

Keyword matching = case-insensitive **whole word or phrase**: no letter or digit may directly precede or follow the match (`land` does not match "Scotland", `ct` does not match "doctor"). A trailing `*` makes the keyword a stem (`numb*` matches "numbness"). Typographic apostrophes (’) count as `'`. "Learner turns" =
interactions with `role == "learner"`. Ordering uses the session event
sequence (interactions and examinations share one monotonically increasing `seq`).

| `type` | Met when | `method` in feedback |
|---|---|---|
| `learner_said` | any learner turn contains any keyword | `keyword` |
| `learner_said_before_exam` | a learner turn containing a keyword has `seq` lower than the first examination (or there is no examination yet) | `keyword` |
| `learner_said_after_pain` | a learner turn containing a keyword comes after an examination with `pain_level >= 5` | `keyword` |
| `learner_avoided` | at least one learner turn exists and none contains a keyword | `keyword` |
| `examined_any` | any zone in `zones` was examined | `rule` |
| `diagnosis_or_learner_said` | submitted diagnosis or any learner turn contains a keyword; if `requires_examined` is set, at least one of those zones must also have been examined | `keyword` |
| `diagnosis_matches` | diagnosis contains an `accepted_keywords` entry → full points; else a `partial_keywords` entry → half points (rounded down), `met=false`; else 0 | `rule` |

Keyword criteria are a documented heuristic, not a real assessment of empathy
or reasoning; the feedback must label them with `method: "keyword"`.

## 2. Session lifecycle

### `GET /health`
```json
{ "status": "ok", "version": "0.1.0", "cases": 1 }
```

### `GET /cases` → `CasePublic[]`
```json
[{
  "case_id": "wrist_trauma_001",
  "title": "Wrist pain after a bicycle fall",
  "learner_brief": "Alex, 28, presents with ...",
  "patient": { "name": "Alex", "age": 28, "appearance": "...", "personality": "..." },
  "voice_context": "CASE FACTS ...",
  "zones": [
    { "id": "right_anatomical_snuffbox", "label": "Right anatomical snuffbox",
      "attach_to": "right_wrist", "offset": [0.0, 0.0, 0.0], "radius": 0.05 }
  ],
  "scripted_dialogue": [ { "id": "greeting", "learner": "...", "patient": "..." } ]
}]
```
Never contains `result` or anything from `hidden`.

### `POST /sessions`
Request `{ "case_id": "wrist_trauma_001" }` → `201`
```json
{ "session_id": "b1f6…", "started_at": "2026-11-12T10:00:00Z", "case": { …CasePublic… } }
```

### `POST /sessions/{session_id}/reset`
Clears examinations, interactions, diagnosis. Keeps `session_id`. Returns the same shape as `POST /sessions` (`200`, new `started_at`).

## 3. Examination

### `POST /sessions/{session_id}/examine`
Request (examination event):
```json
{ "body_part": "right_anatomical_snuffbox", "action": "palpation" }
```
`action` is optional, default `"palpation"`. `body_part` must be a zone `id` of the case, else `404`.

Response (examination result):
```json
{
  "body_part": "right_anatomical_snuffbox",
  "action": "palpation",
  "finding": "marked_tenderness",
  "pain_level": 8,
  "reaction": "strong_pain",
  "patient_response": "Ow! Yes, that's exactly where it hurts!",
  "animation": "arm_withdrawal",
  "voice_context": "[The student presses on ... React out loud ...]",
  "repeat_count": 1
}
```
- `pain_level`: 0–10. `reaction`: `strong_pain | mild_pain | no_pain`. `animation`: `arm_withdrawal | flinch | none`.
- `repeat_count`: how many times this zone has been examined in this session including this one (duplicates are recorded and return the same finding).
- The headset applies its own ~1.5 s cooldown before sending; the backend does not rate-limit.

## 4. Voice context protocol

1. **Conversation start** — the app passes `case.voice_context` to the agent as dynamic variable `case_context` (the agent prompt contains `{{case_context}}`).
2. **Examination** — after `/examine` returns, the app forwards `result.voice_context` verbatim to the agent through `VoiceService.sendExaminationEvent(_:)`. The text is a bracketed stage direction `[...]`; the agent prompt explains that bracketed text is a physical event, not learner speech. The mechanism must make the agent **speak** a reaction (in the ElevenLabs SDK a plain contextual update does not trigger a reply; a text user message does).
3. Bracketed stage directions must **not** be recorded as learner transcript turns.
4. The immediate pain sound and animation are local and never wait for the agent.
5. If voice is not connected, the app speaks `result.patient_response` locally instead.

### `GET /elevenlabs/conversation-token`
Private agents only. Backend calls ElevenLabs with `ELEVENLABS_API_KEY` + `ELEVENLABS_AGENT_ID` and returns
```json
{ "token": "<short-lived conversation token>" }
```
`503` when the env vars are missing.

## 5. Transcript

### `POST /sessions/{session_id}/interactions`
```json
{ "role": "learner", "text": "What happened to you?", "timestamp": "2026-11-12T10:00:05Z" }
```
`role`: `learner | patient`. `timestamp` optional (server time if omitted). Response `{ "count": 3 }` (interactions stored). No LLM calls.

## 6. Diagnosis & feedback

### `POST /sessions/{session_id}/diagnose`
Request `{ "diagnosis": "Suspected scaphoid fracture" }` → `Feedback`. Re-submitting replaces the previous diagnosis.

### `GET /sessions/{session_id}/feedback` → `Feedback`
Works at any time. Before a diagnosis is submitted nothing hidden leaks: `diagnostic_assessment.verdict == "not_submitted"`, `expected == null`, `next_steps == []`, every category keeps its `score` but has `criteria == []`, `strengths == []`, `missed == []`, and `summary == "Submit a diagnosis to unlock detailed feedback."` (the rubric wording itself would reveal the diagnosis).

```json
{
  "session_id": "b1f6…",
  "case_id": "wrist_trauma_001",
  "diagnosis_submitted": "Suspected scaphoid fracture",
  "total_score": 78,
  "max_score": 100,
  "summary": "Good job identifying the painful region. However, you did not ask about numbness or altered sensation. You correctly considered a scaphoid injury. Further medical assessment and appropriate imaging would be indicated.",
  "transcript_available": true,
  "diagnostic_assessment": {
    "verdict": "correct",
    "explanation": "Correct. A fall on an outstretched hand with ...",
    "expected": "Suspected scaphoid fracture"
  },
  "categories": [
    {
      "id": "history", "title": "History-taking", "score": 24, "max_score": 30,
      "criteria": [
        { "id": "mechanism", "label": "Mechanism of injury", "met": true,
          "points": 6, "max_points": 6, "method": "keyword",
          "evidence": "What happened to you?", "comment": "You asked how the injury happened." }
      ]
    }
  ],
  "strengths": ["You palpated the anatomical snuffbox and elicited marked tenderness, the key finding."],
  "missed": ["You did not ask about numbness or altered sensation."],
  "relevant_findings": ["Right anatomical snuffbox: marked tenderness (pain 8/10)"],
  "next_steps": ["Request dedicated scaphoid-view radiographs; an initial X-ray can be normal."],
  "disclaimer": "Educational simulation only. Not a clinical diagnostic tool. Transcript-based criteria use simple keyword heuristics."
}
```
- `verdict`: `correct | partial | incorrect | not_submitted`.
- Category ids and order: `history` (30), `examination` (40), `communication` (20), `reasoning` (10).
- `criteria[].evidence`: first matching learner quote (preferred over the diagnosis text), or examined zone label; `null` whenever `met` is false. `comment`: the criterion's `met_text` or `missed_text`.
- `strengths` = `met_text` of met criteria; `missed` = `missed_text` of unmet criteria.
- `relevant_findings`: one line per distinct examined zone, `"<label>: <finding with spaces> (pain <n>/10)"`.
- `transcript_available`: false when no learner turns were recorded.
- `summary` (after a diagnosis), sentences joined by one space: (1) only if no transcript: "No conversation transcript was recorded, so history-taking and communication could not be assessed." (2) first strength, if any (3) if any missed: "However, " + first missed item, first letter lower-cased (4) `diagnostic_assessment.explanation`.

## 7. Swift-side interfaces

Defined in `visionos/MedSimXR/Models/Contracts.swift`:

- `ClinicalEngine` — implemented by `BackendClinicalEngine` (HTTP), `OfflineClinicalEngine` (bundled scenario JSON, same rules), `FallbackClinicalEngine` (backend first, offline on network failure).
- `VoiceService` — implemented by `ElevenLabsVoiceService` and `MockVoiceService`.
- `AppModel` (`App/AppModel.swift`) owns both and is the only object views talk to.
