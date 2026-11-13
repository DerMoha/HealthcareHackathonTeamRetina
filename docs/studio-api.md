# MedSim Studio API

Additions to [api-contract.md](api-contract.md). Same server, JSON, snake_case. Errors are
`{ "detail": "<text>" }`, except a rejected scenario configuration:
`422 { "detail": { "message": "...", "issues": [Issue] } }`.

A **scenario** configures one clinical case (the *template*): setting, difficulty, equipment,
companions. It never holds clinical facts; those stay in `scenarios/<case_id>.json`.

## Types

```jsonc
// ScenarioConfig: what the instructor chooses. Every id must come from the catalogue.
{ "template_id": "wrist_trauma_001", "title": "3-80 chars",
  "environment": "outpatient_clinic", "difficulty": "standard", "crowdedness": "quiet",
  "tools": ["measuring_tape", "wrist_support_medium", "imaging_xray"],
  "bystander": "none", "teammate": "none",
  "learning_objectives": ["focused_history"],            // at least one
  "narrative": { "description": "", "patient_personality": "", "bystander_lines": [],
                 "source": "template" },                 // template | instructor | llm; all optional
  "seed": 7 }                                            // optional; chosen at random when null

// Issue
{ "field": "tools", "severity": "error" | "warning", "message": "..." }

// ScenarioDefinition: generated and validated; this is what the library stores per version.
{ "schema_version": 1, "scenario_id": "scn_1a2b3c4d", "version": 1, "code": "K7Q2MX",
  "title": "...", "created_at": "2026-11-13T10:00:00Z",
  "source_template": { "template_id": "...", "case_id": "...", "case_schema_version": 3 },
  "seed": 7,
  "review": { "state": "draft" | "experimental" | "clinician_reviewed",
              "reviewer_name": null, "reviewer_role": null, "reviewed_at": null, "notes": null },
  "published": false,
  "config": ScenarioConfig,
  "environment": { "id", "label", "brief", "setting_context", "ambient_level": 0.35,
                   "crowd": { "id", "label", "figures": [{ "angle_deg": 118, "distance_m": 2.8 }] } },
  "resources": [{ "id", "label", "kind": "measurement_tool" | "orthosis_size" | "investigation",
                  "available": true, "deliverable": false, "unsupported_reason": null }],
  "companions": { "bystander": null | { "name", "role_label", "mood": "calm" | "anxious",
                                        "lines": { "calm": [..], "anxious": [..] }, "interject_every_s": 25 },
                  "teammate": { "name", "role_label", "present": false } },
  "difficulty": { "id", "label", "hint_policy": "auto" | "on_request" | "off", "description",
                  "hints": [{ "id", "text" }] },
  "clinical_rules": { "case_id", "immutable_facts": [..], "findings_sha256": "...", "statement": "...",
                      "constraints": ["<criterion> (4 pts): <why it cannot be earned>"] },
  "assessment": { "dimensions": [{ "id": "core" | "management" | "fitting", "title", "max_score",
                                   "achievable_max", "not_assessable": [{ "id", "label", "points", "reason" }] }],
                  "learning_objectives": [{ "id", "label" }], "note": "..." },
  "narrative": { "description", "patient_personality", "source", "ai_generated": false },
  "origin": null | { "duplicated_from" | "imported_from": "...", "version", "claimed_review_state" } }
```

## Authoring

| | |
|---|---|
| `GET /studio/catalog` | `[Template]`: `template_id, case_id, label, summary, clinical_review, environments[{id,label,brief,unsupported_equipment[]}], unsupported_environments[{id,label,reason}], equipment[{id,label,kind}], difficulties[{id,label,hint_policy,description}], crowdedness[{id,label,noise,figures}], bystander_behaviors[{id,label}], teammate_behaviors[{id,label}], learning_objectives[{id,label,needs_kind?}], hints[text], dimensions[...]` |
| `POST /studio/validate` | body `ScenarioConfig` → `{ "valid": bool, "issues": [Issue] }`. A body that breaks the schema itself (title under 3 characters, wrong types) is a standard FastAPI `422` with a list in `detail`. |
| `POST /studio/preview` | body `ScenarioConfig` → the `ScenarioDefinition` it would produce (id `scn_preview`, nothing saved). 422 with issues if invalid. |
| `POST /studio/assist` | body `{ template_id, environment, difficulty, crowdedness, tools[], bystander, focus }` → `{ source: "llm" | "template", model, description, patient_personality, bystander_lines[], learning_objectives[], notes[], requires_review }`. Uses the LLM only when `ANTHROPIC_API_KEY` is set; otherwise deterministic. |

Unsupported choices are errors with a reason, for example choosing `sports_sideline`, or X-ray
in `community_clinic`. Free text (`title`, `narrative.*`) is rejected when it names a finding,
a result or the diagnosis. Equipment that makes a criterion unearnable is a warning.

## Library

| | |
|---|---|
| `GET /studio/scenarios` | `[{ scenario_id, code, title, version, versions, review_state, published_version, template_id, environment, difficulty, crowdedness, created_at, ai_generated }]`, newest first |
| `POST /studio/scenarios` | body `ScenarioConfig` → `201 ScenarioDefinition` (version 1, draft) |
| `GET /studio/scenarios/{id}[?version=N]` | `ScenarioDefinition` (latest by default). This document is also the export format. |
| `GET /studio/scenarios/{id}/versions` | `[{ version, created_at, review_state, published }]` |
| `PUT /studio/scenarios/{id}` | body `ScenarioConfig` → new version, draft. `seed: null` keeps the seed. The published version stays live until published again. |
| `POST /studio/scenarios/{id}/duplicate` | `201` new scenario, draft, "Copy of …" |
| `POST /studio/scenarios/{id}/state` | `{ "state": "draft" | "experimental" }`. `clinician_reviewed` → 409. Setting `draft` unpublishes. |
| `POST /studio/scenarios/{id}/review` | `{ reviewer_name, reviewer_role, attestation: true, notes }` → latest version becomes `clinician_reviewed`. The only way to get that state. `attestation: false` → 422. |
| `POST /studio/scenarios/{id}/publish` · `/unpublish` | Publishes the latest version under the scenario's `code`. A draft becomes `experimental`; nothing ever becomes `clinician_reviewed` by publishing. |
| `POST /studio/import` | body: an exported `ScenarioDefinition` → `201` new scenario. Only `config` is used; it is validated and regenerated, and it starts as draft with the claimed state kept in `origin`. |

Storage: `backend/data/studio_library.json` (override `MEDSIM_STUDIO_DB`). On first use it is
seeded with two published, experimental variants of `wrist_trauma_001`:
`LKGLZX` "Quiet clinic, full kit (guided)" and `5344E7` "Busy walk-in, limited kit (challenging)".

## Launch

| | |
|---|---|
| `GET /scenarios/published` | `[{ code, scenario_id, version, title, description, review_state, environment, difficulty, crowdedness, case_id }]` |
| `GET /scenarios/launch/{code}` | one of those, or 404. Case-insensitive. |
| `POST /sessions` | `{ "case_id": "...", "scenario_code": "K7Q2MX" }` → `SessionInfo` with `scenario` set. Unknown code → 404. Without `scenario_code` everything is as before and `scenario` is `null`. |

With a scenario, `SessionInfo.case` is the same case shaped by the scenario: `investigations`,
`orthotics.sizes` and `orthotics.measurements` contain only what is available, `learner_brief`
names the setting, and `voice_context` ends with an `ENCOUNTER SETTING` block (setting,
companions, manner). The engine refuses unavailable equipment with `409`.

```jsonc
// SessionInfo.scenario (ScenarioRuntime)
{ "scenario_id", "version", "code", "title", "review_state", "seed",
  "environment_id", "environment_label", "difficulty", "hint_policy": "auto" | "on_request" | "off",
  "noise_level": 0.6, "crowd_figures": [{ "angle_deg", "distance_m" }],
  "bystander": null | { "name", "role_label", "mood", "lines": { "calm": [], "anxious": [] }, "interject_every_s" },
  "teammate": { "name", "role_label", "present": false },
  "equipment": [{ "id", "label", "kind", "available" }] }
```

`GET /sessions/{id}/hint` → `{ "policy": "...", "hint": { "id", "text" } | null }`: the next
coaching hint that fits what the student has done; never the same one twice; recorded for the
debrief. `409` for a session without a scenario.

## Live Director

| | |
|---|---|
| `GET /sessions/active` | `[{ session_id, started_at, title, code, runtime_connected, submitted }]`, sessions that run a scenario |
| `GET /sessions/{id}/director` | `DirectorState` (below) |
| `POST /sessions/{id}/director/events` | `{ "event_id": "<optional uuid>", "kind": "...", "params": {} }` → `{ accepted, duplicate, reason, intervention }`; `409 {detail: reason}` when it cannot apply |
| `WS /ws/sessions/{id}?role=director` or `role=runtime` | see below; closes with code 4404 for an unknown or default session |

Events (the whole list):

| kind | params | effect | rejected when |
|---|---|---|---|
| `bystander_anxious` | | bystander's mood → anxious, speaks a line | no bystander, or already anxious |
| `helper_arrives` | | the nurse appears, speaks a line | already there |
| `crowd_noise_up` | | noise +0.25, at most 1.0 | already 1.0 |
| `deliver_equipment` | `{ "item": "<equipment id>" }` | the item becomes available | unknown item, already there, or not possible in the environment |
| `enable_coaching` | | hint policy off → on_request → auto | already auto |

No event removes equipment, changes a finding or adds a complication, and none is accepted
after the diagnosis was submitted.

```jsonc
// DirectorState
{ "session_id", "started_at", "runtime_connected": true,
  "scenario": ScenarioRuntime,                       // current, after all events
  "events": [{ "kind", "label", "enabled": true, "reason": null,
               "param": "item", "options": [{ "id", "label" }] }],   // param/options only for deliver_equipment
  "interventions": [{ "seq", "event_id", "kind", "label", "params", "at",
                      "line": null | { "speaker", "text" }, "voice_context",
                      "acknowledged": false, "ack_detail": null | "applied: ..." }],
  "hints": [{ "seq", "id", "text", "at" }],
  "activity": { "learner_turns", "examinations", "investigations", "measurements", "fit_changes",
                "diagnosis_submitted" } }
```

WebSocket frames (JSON text):

```
director -> server   {"type":"event","event_id":"<uuid>","kind":"...","params":{}}
server   -> director {"type":"state", ...DirectorState}     on connect, after every change, and every 2 s
server   -> director {"type":"rejected","event_id":"...","reason":"..."}
server   -> runtime  {"type":"event","seq","event_id","kind","label","line","voice_context",
                      "scenario":ScenarioRuntime,"case":CasePublic}
runtime  -> server   {"type":"ack","event_id":"...","applied":true,"detail":"..."}
```

An `event_id` is recorded once: sending it again adds nothing, and re-sends the event to the
runtime only while it is unacknowledged. When a runtime (re)connects it receives every
unacknowledged event in order; it must ignore ids it has applied and acknowledge them again.

## Debrief

`GET /sessions/{id}/debrief` (any session):

```jsonc
{ "session_id", "case_id", "diagnosis_submitted": null | "...",
  "scenario": null | { "scenario_id", "version", "code", "title", "review_state", "template_id", "seed",
                       "environment", "crowdedness", "difficulty", "bystander", "teammate",
                       "learning_objectives": [{ "id", "label" }] },
  "resources": [{ "id", "label", "kind", "available_at_start", "delivered_at_seq", "available_at_end", "used" }],
  "interventions": [...], "hints": [...],
  "timeline": [{ "seq", "type": "question" | "examination" | "investigation" | "measurement" | "fitting"
                               | "check" | "intervention" | "hint", "label" }],
  "scores": { "core": { "score", "max_score" },
              "management": { "score", "max_score", "achievable_max", "not_assessable": [...] },
              "fitting": { ... } },                    // achievable_max only with a scenario
  "interpretation": ["Difficulty: ...", "..."],
  "feedback": Feedback }                               // the existing feedback, unchanged
```

Scores are the unchanged case rubric. `achievable_max` and `interpretation` say what the
scenario's resources allowed, so a score can be read against its constraints.
