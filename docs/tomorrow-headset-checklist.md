# Headset checklist

Order matters: each block depends on the one before. Stop and fix before moving on.
Budget: 45–60 minutes. Requires visionOS 26+ on the headset.

## 0. Before putting the headset on (10 min)

- [ ] `cd backend && source .venv/bin/activate && uvicorn app.main:app --host 0.0.0.0 --port 8000 --env-file ../.env`
- [ ] From a phone on the same Wi-Fi: `http://<laptop-ip>:8000/health` answers. If not: firewall / hotspot isolation.
- [ ] `visionos/Config/Local.xcconfig`: `DEVELOPMENT_TEAM`, `MEDSIM_BACKEND_HOST = <laptop-ip>:8000`, `ELEVENLABS_AGENT_ID`.
- [ ] `cd visionos && xcodegen`, build and run on the device. Signing errors → change the bundle id in `project.yml`.
- [ ] ElevenLabs agent created per `elevenlabs/setup.md`; test it once in the dashboard.

## 1. Does it run at all (5 min)

- [ ] App launches, control window readable.
- [ ] **Start Session** → room stays visible (mixed immersion), patient appears.
- [ ] Status card: Engine **Backend**. If Offline → backend host wrong (Settings in the panel).

## 2. Placement and scale — first thing never tested (10 min)

- [ ] Patient is on the floor, about 1.5 m away, slightly to the right of the window, facing you.
- [ ] Looks like a seated adult on the stool (head top around 1.37 m). Feet on the floor, not floating, not sunk.
- [ ] Skin, hair and shirt render cleanly up close (hair is alpha cut-out; look for holes or shimmer).
- [ ] Turn 90°, **Recenter Patient** → patient moves in front of the new direction. This uses the head pose and has never run.
- [ ] If the patient is off: tune `distance` / `lateral` in `Reality/Placement.swift`.

## 3. Gaze + pinch — second thing never tested (10 min)

- [ ] Look at the patient's right wrist (your left): a highlight appears.
- [ ] Pinch → red flash, arm pulls back, "Ow!". Panel shows "Right anatomical snuffbox · marked tenderness · pain 8/10".
- [ ] Forearm above the wrist → green flash, "That part doesn't really hurt."
- [ ] Other wrist → green flash, "No, that side feels completely fine."
- [ ] The wrist and forearm zones can be hit separately. If not: shrink `radius` in `scenarios/wrist_trauma_001.json`.
- [ ] If pinch is unreliable: Debug mode buttons give the same result. Decide now which one the demo uses.

## 4. Live voice — third thing never tested (15 min)

- [ ] Microphone prompt appears on first Start; accept. Status: **Connected**, Microphone **Live**.
- [ ] "What happened to you?" → Alex answers with the bicycle story, in a natural voice, within ~2 s.
- [ ] Your words and Alex's appear under Conversation.
- [ ] Pinch the painful wrist → instant "Ow!" clip, then Alex **says** a pain reaction. Listen: Alex must not read out square brackets or stage directions.
- [ ] Ask "What is my diagnosis?" → Alex does not know.
- [ ] Interrupt Alex mid-sentence → Alex stops.
- [ ] No echo / Alex answering themself. If so: lower volume, check turn-taking in the dashboard.
- [ ] Turn Wi-Fi off for 10 s → status shows the problem, app keeps working with local voice.

If voice cannot be fixed in time: demo with Debug mode scripted questions; everything else is unaffected.

## 5. Full run and fallbacks (10 min)

- [ ] Pinch the **Notebook** beside the patient → it opens; Microphone shows **Muted**. Close → **Live** again.
- [ ] Type a note with the virtual keyboard, then use the keyboard's dictation key. Check Alex does **not** answer while you dictate.
- [ ] Notebook is readable and reachable where it floats; if not, tune its position in `Views/ImmersivePatientView.swift`.
- [ ] Assessment → enter your own diagnosis → **Submit diagnosis** → feedback appears inside the notebook.
- [ ] Complete `docs/demo-script.md` once, timed.
- [ ] Feedback screen: readable at arm's length, scrolls, **Try Again** resets.
- [ ] Kill the backend mid-session → Engine switches to **Offline**, session continues, feedback still appears.
- [ ] Optional: `ELEVENLABS_API_KEY=… ELEVENLABS_VOICE_ID=… python3 elevenlabs/generate_clips.py`, rebuild → offline lines use the agent's voice instead of the macOS placeholder.
- [ ] Optional, only if everything above is solid: Settings → Fingertip examination.
