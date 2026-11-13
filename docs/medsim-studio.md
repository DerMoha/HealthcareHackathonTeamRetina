# MedSim Studio and Live Director

Instructors configure, publish and launch scenarios, steer a running session, and get a
debrief that says what the score was earned under. API: [studio-api.md](studio-api.md).

```
 studio/ (React, Vite)                backend/ (FastAPI)                     Vision Pro app
┌────────────────────────┐   HTTP   ┌─────────────────────────────┐  HTTP  ┌──────────────────────────┐
│ Overview  Library      │◄────────►│ studio.py   validate,        │◄──────►│ ScenarioCard  pick / code │
│ Marketplace Generator  │          │             generate, library│        │ AppModel      scenario    │
│                        │    WS    │ director.py events, hints,   │   WS   │ DirectorLink  ack, replay │
│ Director  Debrief (WS) │◄────────►│             debrief          │◄──────►│ ScenarioStage room        │
└────────────────────────┘          │ assist.py   optional LLM     │        └──────────────────────────┘
                                    │ studio_templates/*.json      │
                                    │ scenarios/*.json  (clinical) │
                                    └─────────────────────────────┘
```

## What a scenario is, and is not

A scenario is a configuration of one clinical case: environment, difficulty, crowdedness,
equipment, bystander, helper, learning objectives, and optional narrative text. The case
file `scenarios/<case_id>.json` stays the only source of history, findings, results,
diagnosis and rubric, and is read at runtime. A scenario cannot hold or override any of it;
`clinical_rules.findings_sha256` records which case content it was generated against.

Everything selectable is listed in `backend/studio_templates/<template_id>.json`. A choice
that is not there, or a combination the template rules out, is a validation error with the
reason (for example a pitch-side setting for a case whose history is a bicycle fall seen the
next day, or an X-ray in a clinic without imaging). Nothing is substituted silently.

One clinical case exists today (`wrist_trauma_001`), so there is one template. Adding a
template for another case means writing its `studio_templates` file; no code changes.

## What a scenario changes at runtime

| Setting | Effect in the running session |
|---|---|
| Equipment | Tray shows only the available supports and the tape; the notebook offers only available investigations; the engine refuses the rest with `409` |
| Environment | Sign in the room, base noise level, a line in the patient's voice context, which equipment can exist there |
| Crowdedness | Background figures (positions from the seed), added noise |
| Bystander | A figure beside the patient who speaks up unprompted at an interval; mood shown; a line in the voice context |
| Helper | A figure by the tray; announces deliveries |
| Difficulty | Coaching hints: automatic (guided), on request (standard), none (challenging); the patient's manner in the voice context |
| Seed | Order of the bystander's lines, crowd positions, interjection interval |

Two published variants of the same case are seeded into a new library:

| Code | Title | Differences |
|---|---|---|
| `LKGLZX` | Quiet clinic, full kit (guided) | all equipment, no companions, no noise, automatic hints |
| `5344E7` | Busy walk-in, limited kit (challenging) | no imaging, no medium support, anxious partner, four background figures, 60% noise, no hints |

## Review states

`draft` → `experimental` → `clinician_reviewed`. Publishing a draft makes it experimental.
`clinician_reviewed` is set only by `POST /studio/scenarios/{id}/review` with a named
reviewer and an explicit attestation; nothing else in the backend or the interface can
produce it. Editing creates a new draft version (the published version stays live until
published again). Imports start as draft whatever the file claims. There is no login in
this build, so the reviewer's name is taken on trust: the label means "someone recorded a
review", not "identity verified". The app and the debrief show the state.

Both seeded scenarios are experimental. The underlying case is not clinician-reviewed either.

## Live Director

Five predefined events: bystander becomes anxious, a helper arrives, crowd noise increases,
an equipment item is delivered, coaching becomes available. Each changes only the session's
scenario state; none can reach the case data. There is no event that removes equipment,
alters a finding or adds a complication, and events that cannot apply are rejected with the
reason (no bystander to make anxious, MRI in a clinic without imaging, noise already at
maximum, anything after the diagnosis was submitted).

The app acknowledges every event with what the scene shows after applying it. Each event has
an id chosen by the sender: the backend records an id once, the app applies an id once.
When the app's connection drops it reconnects on its own and the backend re-sends whatever
was not acknowledged.

## Debrief

`GET /sessions/{id}/debrief`: the unchanged feedback plus the configuration used, resources
(available at the start, delivered, used), instructor interventions with acknowledgements,
hints given, and the student's decisions in order. Scores are never rescaled. Where the
scenario's resources make a criterion impossible, the debrief says so and gives the
achievable maximum (walk-in variant: management is out of 11 achievable, not 20, because
both imaging criteria need imaging).

## AI assistance

`POST /studio/assist` drafts a description, the patient's manner, bystander lines and a
choice of objectives. With `ANTHROPIC_API_KEY` set (and `pip install anthropic`) it asks
Claude through structured output; otherwise it builds the draft from the template, the same
every time. Either way the text goes through the same check as instructor text: anything
naming a finding, a result or the diagnosis is rejected, and objectives outside the
template's list are dropped. AI text is marked as such on the scenario.

## Demonstration path

```bash
# 1. backend (serves the built Studio at /app/)
cd studio && npm install && npm run build && cd ..
cd backend && .venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
# Studio: http://localhost:8000/app/      (development: cd studio && npm run dev)
```

The Studio is a dashboard with a side menu:

| Menu | Page |
|---|---|
| Home › Overview | Last session (open its director or debrief), last scenario worked on, counts, shortcuts |
| Scenarios › My scenarios | Scenarios created in the generator or duplicated here: versions, review, publish, export |
| Scenarios › Downloaded | Copies taken from the marketplace or imported from a file. Always drafts; the original's review state is shown but not carried over |
| Scenarios › Marketplace | Published scenarios on this server with their launch codes; search, filter to clinician-reviewed, *Download a copy* |
| Scenarios › Scenario generator | Six steps: basics and setting, people, equipment, learning objectives, narrative, review and save. Each step shows its error count; the generated definition and its consequences (noise, figures, coaching, earnable points) update as you go |
| Sessions › Live director, Debrief | As before |

1. **Scenario generator**: pick the template, change the conditions (for example community clinic, busy,
   anxious partner, remove the medium support). Issues appear as you go. Step 6 shows the generated definition.
2. *Save to my scenarios*, then **My scenarios**: *Publish*. Note the launch code (it also appears in the **Marketplace**).
3. Vision Pro app: enter the code under *Scenario* (or pick it from the list), *Start Session*.
4. **Director**: the session appears; trigger *A helper arrives* or *Deliver an equipment
   item*. The log shows the headset's acknowledgement.
5. The student submits a diagnosis. **Debrief** (and the feedback page in the app) shows the
   configuration, interventions and how to read the score.

Without a headset the same path runs in the simulator:
`visionos/scripts/scenario_smoke_test.sh --variant walkin` plays the instructor.

## What was verified, and how

| | Verified by | Result |
|---|---|---|
| Backend: authoring, library, review states, runtime shaping, director, dedup, reconnect replay, hints, debrief, assist fallback | `cd backend && python -m pytest` | 77 passed (55 existing, 22 new) |
| Existing scoring unchanged | same test run: feedback with and without a scenario is identical | passed |
| Swift offline engine parity, patient behaviour | `visionos/scripts/check_offline_engine.sh`, `check_patient_behavior.sh` | passed |
| Existing app flow incl. offline fallback | `simulator_smoke_test.sh --mock-voice --kill-backend` | passed |
| Scenario launch changes the running app; two variants differ | `scenario_smoke_test.sh --variant walkin` and `--variant clinic`, Vision Pro simulator | passed; logs and screenshots in `docs/screenshots/scenario-*` |
| Director events reach the app, are acknowledged, change the scene; repeated event id applied once; event sent while the link was down arrives after reconnect | walk-in run | passed |
| Unknown code is an error; unreachable backend runs the default case offline | `--variant unknown`, `--variant offline` | passed |
| The whole path through the Studio interface: author in the form (clinical title rejected, X-ray disabled in the community clinic, warnings shown), save, publish, launch that code in the simulator, click *Bystander becomes anxious* in the Director tab, app acknowledges, Debrief tab shows it | Studio served at `/app/`, driven by script in a browser tab; app log in `docs/screenshots/scenario-studio-ui/smoke.log` | passed, no console errors |

Not verified:

- **The dashboard with a live headset session.** The simulator run in the table above used the
  earlier tabbed layout. The dashboard (side menu, overview, marketplace, stepped generator)
  was then checked in headless Chromium against a backend without a session: every page renders
  in light, dark and narrow layouts, *Download a copy* lands in Downloaded as a draft, and a
  scenario built in the generator saves into My scenarios. Screenshots:
  `docs/screenshots/studio-dashboard/`. The Live director and Debrief pages are the same
  components as before but were not re-run against the simulator in the new layout.
- In the interface, Edit, Unpublish, Import/Export, the state buttons and the review form
  were not clicked (their endpoints are covered by the backend tests), nor was the panel's
  own socket reconnect.

- **On a real Vision Pro.** Everything above ran in the simulator. How loud the room noise
  and the bystander's system voice are on the device, and whether the live ElevenLabs agent
  hears them through the microphone and reacts, is untested. The noise is capped at half
  volume for that reason.
- **The live LLM call.** No Anthropic credentials were available here. The request was
  checked against the installed SDK's signature and the validation after it is tested with a
  stubbed response; a real response has not been seen.
- **The live voice agent with scenario context.** Simulator runs use the scripted mock voice,
  whose `sendContext` does nothing. The setting text is in the `voice_context` the agent
  would receive; its effect on the agent's behaviour is untested.
- The figures are plain capsules and the noise is synthesised. They show that the scenario
  reached the scene; they are not a realistic ward.
