# Architecture

```
 Vision Pro app (Swift)                                  Laptop
┌──────────────────────────────────────────┐          ┌───────────────────────────┐
│ Views/        control panel, feedback    │          │ backend/ (FastAPI)        │
│ Reality/      avatar, placement, audio   │   HTTP   │  sessions  examination    │
│ Interaction/  exam zones, fingertip      │◄────────►│  evaluation (rubric)      │
│        │  ▲                              │          │  /elevenlabs/token        │
│        ▼  │ reaction                     │          └────────────┬──────────────┘
│ App/AppModel  ── the only orchestrator   │                       │ reads
│   │ ClinicalEngine        │ VoiceService │          ┌────────────▼──────────────┐
│   ▼                       ▼              │          │ scenarios/*.json          │
│ Networking/            Voice/            │  bundled │  zones, findings, rubric  │
│  Fallback ─ Backend     ElevenLabs SDK ──┼──WebRTC──►  ElevenLabs agent (LLM+TTS)
│      └──── Offline ◄── same JSON ────────┼──────────┘
└──────────────────────────────────────────┘
```

## Rules that keep it honest

- **Findings come from the engine, never from the UI or the LLM.** The app sends a zone id;
  the engine returns finding, pain level, animation, the patient's line, and a stage
  direction for the voice agent.
- **The diagnosis stays hidden.** Everything under `hidden` in the scenario is only used for
  scoring. The voice agent receives `voice_context` (what the patient knows), which does not
  contain the diagnosis. Feedback requested before a diagnosis withholds rubric wording.
- **The pain reaction never waits for the network.** Animation and "Ow!" are local; the
  agent's spoken reply follows when it arrives.

## Examination flow

1. Gaze + pinch (or fingertip, or Debug button) on a zone → `AppModel.examine(zoneId:)`, 1.5 s cooldown.
2. `ClinicalEngine.examine` → `ExaminationResult`.
3. `AppModel.reaction` changes → avatar animation + local audio.
4. Voice connected: `result.voiceContext` is sent as a bracketed text message; the agent speaks
   the reaction and its reply lands in the transcript. Voice not connected: the app plays the
   bundled clip (or system TTS) for `patientResponse`.

## Fallbacks

| Failure | What happens |
|---|---|
| Backend unreachable at start or mid-session | `FallbackClinicalEngine` switches to `OfflineClinicalEngine`, which shadowed every event; status shows "Offline" |
| ElevenLabs unavailable / no agent ID / mic denied | Status shows the reason; local clips speak the patient lines; Debug mode offers scripted questions that feed the transcript |
| Hand tracking unavailable | Gaze + pinch (default) |
| Gaze + pinch unreliable | Debug mode buttons per zone |
| No `Patient.usdz` | Procedural primitive avatar (default) |

## Adding a case

Add `scenarios/<case_id>.json` (same schema, see [api-contract.md](api-contract.md)). The backend
loads every file in the folder; the app bundles the folder and lists every bundled case on the
dashboard (`OfflineClinicalEngine(bundle:)`; the backend's `GET /cases` is merged in when reachable).
Add a `catalog` (card text, allowed moods and avatars, optional `avatar_model`) and a `persona`
(copy it from an existing case) so the dashboard and the voice agent can use it. Zone `attach_to` names must exist on the avatar
(`right_wrist`, `right_forearm`, `left_wrist`, …). The agent prompt needs no change — case
facts arrive through `{{case_context}}`.

## Workstream ownership

| Area | Owner |
|---|---|
| `visionos/MedSimXR/{App,Views,Reality,Interaction,Resources}` | Dev 1 (visionOS) |
| `visionos/MedSimXR/Voice`, `elevenlabs/` | Dev 2 (voice) |
| `backend/`, `scenarios/` | Dev 3 (Windows) |
| `visionos/MedSimXR/Models/Contracts.swift`, `docs/api-contract.md` | shared — change together |

If the rubric logic changes in `backend/app/evaluation.py`, mirror it in
`Networking/OfflineClinicalEngine.swift`, regenerate `backend/tests/fixtures/parity_expected.json`,
and run `visionos/scripts/check_offline_engine.sh`.
