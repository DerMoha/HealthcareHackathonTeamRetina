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

## Voice-driven movement (added with the behaviour state machine)

Needs a live ElevenLabs agent with the `perform_patient_action` client tool (elevenlabs/setup.md, step 5b). None of this was run against a live agent.

- [ ] Session start: Alex stands in front of the stool and says hello.
- [ ] "Please have a seat" (and two other phrasings): Alex acknowledges and sits. Feet stay planted.
- [ ] "Could you stretch out your arms?": both arms come forward. "You can relax": they go back.
- [ ] "Which wrist hurts?": he lifts the right wrist and answers in words.
- [ ] Ask for arms while he is standing: he says he needs to sit first and does not claim to have moved.
- [ ] Gaze + pinch on the wrist zones with arms extended: the highlight sits on the wrist, not on the thigh where it used to be.
- [ ] Painful palpation with arms extended: recoil, then arms return to the extended pose; conversation continues without reconnecting.
- [ ] Zones cannot be pinched while he stands.
- [ ] Standing distance: his head is about 1 m from you when standing (he steps back onto the stool when sitting). Adjust `Placement.distance` if too close.
- [ ] No voice: the control panel shows "Ask Alex to sit down"; Debug has all four movements.

## Investigations and management

- [ ] Add the `order_investigation` client tool (elevenlabs/setup.md 5c) and re-paste the system prompt.
- [ ] "I'd like an X-ray of his right wrist": viewer opens; Alex only acknowledges and never states a result.
- [ ] Ask Alex "what did the X-ray show?": he must not know.
- [ ] Viewer readable at the notebook's distance; pinch zoom and the magnifier buttons work; image pans when zoomed.
- [ ] Back to notebook → Assessment: type or dictate the three plan fields; submit.
- [ ] Feedback shows "Investigation and management · n/20" under the categories.

## Orthotics lab

- [ ] Tray and its panel are reachable to the left of the patient; labels readable.
- [ ] Pinch + drag the tape to the wrist and to the forearm: value appears beside the arm and in the panel.
- [ ] Pinch + drag a support onto the right forearm: snaps when released near the arm, returns to the tray when released elsewhere.
- [ ] Drag the fitted support along the arm; drag it away to take it off.
- [ ] The support stays on the arm through "relax your arms", "hold them out" and a pain recoil.
- [ ] Ask by voice "how does that feel?" after a too-large and a too-tight fit: Alex's answer matches the panel's quoted answer.
- [ ] Tray position: adjust `tray.position` in `Reality/OrthoticsLab.swift` if it is in the way.
- [ ] After feedback: anatomy toggle shows bones and the green intended position on the arm.

## Pinch placement, replay (do these first)

- [ ] Pinch a support on the tray: lifts, base lights, forearm glows, panel says "selected".
- [ ] Pinch the forearm: support goes on where you pinched. Pinch near the elbow instead: it goes on there (wrong position) and Alex complains.
- [ ] With an item selected, a pinch on the wrist places the item and does **not** count as an examination.
- [ ] Cancel works; pinching the selected item again deselects.
- [ ] Drag and drop still works.
- [ ] Alex complains once, unprompted, about a bad fit; not on every Tighten press.
- [ ] Replay: opens only from the feedback; steps, Anatomy toggle and Exit work; bones sit on the forearm in the arm's current pose; labels do not cover the wrist.
- [ ] Replay step text says "gaze and pinch on the patient" for examinations you did by pinch.
- [ ] Record the results in `docs/interaction-verification.md`.
