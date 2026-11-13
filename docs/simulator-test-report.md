# Simulator test report

Date: 2026-11-12 · Branch: `poc` · Mac: Apple M4 Pro (arm64), macOS 27.2.1 · Xcode 27.2 (27B52)
· Runtime: visionOS 27.2 (24N120) simulator, installed with `xcodebuild -downloadPlatform visionOS`
· Device: "MedSimXR Vision Pro" (Apple Vision Pro 4K device type), created by the smoke script.

**The app launches and runs in the visionOS simulator.** No crash in any run. Evidence:
screenshots in [screenshots/](screenshots/) and the app's own runtime log
([screenshots/demo/smoke.log](screenshots/demo/smoke.log)).

## How it was tested

The simulator was driven from the command line. This session had no permission to synthesize
mouse or keyboard input (macOS Accessibility not granted), so **nobody clicked anything**: the
app ran its built-in scripted demo (launch argument `-autoDemo`), which calls the same
`AppModel` functions the buttons and the pinch gesture call, and logs what actually happened.

```bash
visionos/scripts/simulator_smoke_test.sh                     # backend up
visionos/scripts/simulator_smoke_test.sh --kill-backend      # backend killed mid-session
visionos/scripts/simulator_smoke_test.sh --no-backend        # never any backend
visionos/scripts/simulator_smoke_test.sh --mock-voice --patient-offset 0.75,0,-1.0
```

All four variants end with `SMOKE TEST PASSED`. Regression after the last change:
backend `26 passed`; Swift offline check `all assertions passed`, `parity: 0 field difference(s)`;
device-SDK build exit 0.

## Results

| Feature | Status | Evidence / caveat |
|---|---|---|
| App launch, control window | **Tested in simulator** | `demo/01-launch.jpg` |
| Mixed immersive space opens | **Tested in simulator** | log `immersive opened=true`; room stays visible |
| Seated patient rendered | **Tested in simulator** | `demo/02-session.jpg`, `full-body/02-session.jpg` |
| Patient scale / proportions | **Tested in simulator** (by eye, against simulated furniture) | true scale needs the headset |
| Session creation via backend | **Tested in simulator** | log `engine=Backend`, 3 zones from the backend |
| Examination zones attached to wrists/forearm | **Tested in simulator** | faint spheres visible in `full-body/05-killwindow.jpg` |
| Examination → correct finding (all 3 zones) | **Tested in simulator** | log `examined …` lines |
| Pain animation (flinch + right-arm withdrawal) | **Tested in simulator** | `full-body/04-pain-1.jpg` vs `05-killwindow.jpg` |
| Red/green zone flash on examination | **Tested in simulator** | `full-body/04-pain-1.jpg` |
| Local audio clips | **Tested in simulator — started, not listened to** | `AVAudioPlayer.play()` returned true for every clip, none missing. Nobody heard the output. |
| Debug examination + scripted-question buttons | **Tested in simulator at function level** | the demo calls the same functions; the buttons themselves were not pressed |
| Recenter Patient | **Tested in simulator — partially** | placement re-ran; the simulator gave no tracked head pose, so the fixed fallback position was used both times |
| Feedback locked before diagnosis | **Tested in simulator** | `demo/06-feedback-locked.jpg`, log `criteria=[0, 0, 0, 0]` |
| Diagnosis submission + feedback screen | **Tested in simulator** | `demo/08-feedback.jpg`, 68/100, verdict correct |
| Reset scenario | **Tested in simulator** | log `reset feedback=cleared … exams=0 turns=0` |
| Backend killed mid-session → offline, progress kept | **Tested in simulator** | `--kill-backend`: `engine=Offline … exams=3`, same 68/100 |
| No backend at all | **Tested in simulator** | `--no-backend` run passes on the offline engine |
| Voice status / mic indicators | **Tested in simulator** with the scripted mock voice | `full-body/02-session.jpg` shows Connected / Live |
| Examination event handed to the voice layer, instant "Ow!" clip | **Tested in simulator** with the scripted mock voice | log `speakLocally=false`, `audio clip=ouch started=true` |
| Rubric scoring, privacy, API | **Automated tests only** | 26 pytest tests |
| Swift offline engine = backend | **Automated tests only** | golden-fixture parity, 0 differences |
| Gaze + pinch on a zone (mouse click in the simulator) | **Compiled, not runtime-tested** | needs a person; see below |
| Typing a diagnosis, scrolling feedback, Settings fields | **Compiled, not runtime-tested** | needs a person |
| Optional `Patient.usdz` | **Compiled, not runtime-tested** | no asset |
| ElevenLabs live conversation, transcripts, spoken exam reaction, reconnect | **Blocked by credentials** | no agent ID or API key on this machine |
| Conversation-token endpoint, clip generator against the real API | **Blocked by credentials** | 503 path tested only |
| Head-relative placement, passthrough, real audio in/out, mic permission prompt | **Requires physical Vision Pro** | |
| Fingertip (hand-tracking) examination | **Requires physical Vision Pro** | experimental, off by default |

## Two-minute manual check still worth doing in the simulator

```bash
open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app
cd backend && .venv/bin/python -m uvicorn app.main:app --port 8000
```
Run the MedSimXR scheme on "MedSimXR Vision Pro" from Xcode, press **Start Session**, hold
right-drag / use the camera controls to look down at the patient's hands, then **click the wrist
on the left side of the picture** (the patient's right). Expected: red flash, arm pulls back,
"Ow!". Click the other wrist: green flash, "No, that side feels completely fine."

## Problems found by launching, and fixed

| Found | Fix |
|---|---|
| ElevenLabs package forces deployment target ≥ 26.0 (found at integration) | target raised |
| Patient sat directly behind the control window | placed 0.55 m to the wearer's right, turned to face them |
| Voice error rendered as two lines of red text, unreadable | short orange status "Unavailable · local voice", reason underneath |
| "Reset Scenario" was red text on a red button | plain bordered button |
| No visible confirmation that an examination registered | zone flashes red (painful) or green; last finding shown on the panel |
| Reaction animation could drift if retriggered mid-animation | animates back to fixed rest poses |
| Keyword scoring matched substrings ("Scotland" → mechanism, "I'm a bit worried" → introduction, any "can I …" → permission) | whole-word matching with explicit stems and explicit permission/introduction phrases, same rule in both engines, tested |

Simulator log during the runs showed only simulator noise (proxy lookups, CoreAudio hardware
notices); no RealityKit errors, no missing resources, no permission failures.

## ElevenLabs readiness (code review, SDK 3.4.0)

| Item | Finding |
|---|---|
| Agent ID / token | public agent ID from Settings or xcconfig; otherwise token from `GET /elevenlabs/conversation-token`. No key in the app. |
| Microphone permission | `NSMicrophoneUsageDescription` in Info.plist; `AVAudioApplication.requestRecordPermission()` before connecting; denial shown in the status card |
| Start / stop | `ElevenLabs.startConversation(agentId:|conversationToken:config:)`, `endConversation()`; 10 s connect timeout; stale callbacks ignored by generation counter |
| Status visibility | connection, microphone (Live/Muted/Denied) and "speaking" shown in the status card |
| Audio in/out | configured by the SDK (LiveKit); the app adds nothing. Mixing with the local "Ow!" clip is untested |
| Transcripts | `onUserTranscript` / `onAgentResponse` (finalized events only), de-duplicated by event id |
| Examination events | `Conversation.sendMessage(_:)` with the engine's bracketed stage direction — a text user message, which triggers a reply (a contextual update does not) |
| Brackets spoken aloud | prevented by prompt only (`patient_system_prompt.md`); transcripts drop any line starting with `[`. **Must be listened for in the first live test.** |
| Errors | readable status, one automatic reconnect, then local-voice fallback; UI never blocks on the connection |

None of this has run against ElevenLabs. To run it: follow `elevenlabs/setup.md`, then put the
agent ID in the app's Settings (public agent) or `ELEVENLABS_API_KEY` + `ELEVENLABS_AGENT_ID` in
`.env` (private agent). Until then use `-mockVoice`: a deterministic stand-in that "connects",
shows a live microphone and answers each examination with the scenario's example line.

## UX and patient-realism pass (2026-11-13)

Same method: scripted demo in the simulator, nobody clicked or typed. Screenshots in
[screenshots/demo](screenshots/demo) (default placement, backend killed mid-session) and
[screenshots/full-body](screenshots/full-body) (patient pushed back to fit the fixed camera,
scripted mock voice).

Regression after the last change: backend `31 passed`; Swift offline check `all assertions
passed`, `parity: 0 field difference(s)`; smoke test passed in three variants
(`--kill-backend`, `--mock-voice`, `--procedural --no-backend`).

| Change | Status | Evidence / caveat |
|---|---|---|
| Spoiler-free introduction ("Alex, 28, is waiting to be seen…") | **Tested in simulator** + automated | `demo/01-launch.jpg`, `demo/02-session.jpg`; test asserts title, brief, patient text and zone labels contain no mechanism, anatomy or diagnosis words |
| No prefilled diagnosis | **Tested in simulator** | button removed; `demo/08-notebook-assessment.jpg` |
| Neutral zone labels during the session, anatomical names only in feedback | **Automated tests only** | pytest + Swift check |
| Rubric detail and expected diagnosis withheld until submission | **Tested in simulator** + automated | log `criteria=[0, 0, 0, 0]` before submission |
| Diagnosis synonyms (scaphoid / navicular / Kahnbein / misspellings; fracture → partial) | **Automated tests only** | `test_diagnosis_synonyms` |
| Realistic seated patient (`Patient.usdz`, 53 joints, 1.38 m) on a stool | **Tested in simulator** | `full-body/02-session.jpg`; log `avatar usdz joints=53 size=(0.53, 1.38, 0.78) minY=0.0` |
| Examination zones on the new model's wrists/forearm | **Tested in simulator** (positions are measured from the posed skeleton) | faint spheres in `full-body/05-killwindow.jpg`; whether they are easy to hit by gaze needs a person |
| Pain reaction on the new model (lean back, right arm pulled back, red flash) | **Tested in simulator** | `full-body/04-pain-*.jpg` vs `05-killwindow.jpg` |
| Primitive avatar still works as fallback | **Tested in simulator** | `--procedural` run passes |
| Notebook opens beside the patient, sections, notes shown | **Tested in simulator at function level** | `demo/06…08-notebook-*.jpg`; opened and filled by the script, not by pinch or keyboard |
| Notebook mutes the microphone (note-taking mode) | **Tested in simulator** with the scripted mock voice | log `notebook open=true … mic=Muted`, Live again after reset. Real ElevenLabs mute: blocked by credentials |
| Diagnosis submitted from the notebook, feedback shown in it | **Tested in simulator** | `demo/09-feedback.jpg`, 72/100 |
| Notes compared with the record; claimed-but-not-done flagged; no points from notes | **Tested in simulator** + automated | log `associated_symptoms:unsupported`; `test_notes_never_earn_examination_points` |
| Reset clears notes | **Tested in simulator** | log `notes=blank` |
| Offline fallback with notes | **Tested in simulator** | `--kill-backend`: feedback from the offline engine, same documentation result |
| Typing and dictating into the notebook, pinch to open | **Compiled, not runtime-tested** | needs a person in the simulator or the headset |
| Compact control window as a low "utility panel" | **Not effective in the simulator** | placement request is ignored there; window opens straight ahead, so the patient sits 0.3 m to its right. Check on the headset |

Known visual limits seen in the screenshots: fingers are slightly splayed, the face is neutral
and does not move, and the first session start shows the patient about a second late while the
model loads.
