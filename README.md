<img src="assets/icon.svg" width="64" height="64" alt="">

# MedSim XR — AI patient for Apple Vision Pro

A seated virtual patient in your real room. Talk to them (ElevenLabs Agents),
examine their wrist by gaze + pinch, watch them flinch, submit a diagnosis, get
structured feedback. One complete case: Alex, 28, wrist pain after a bicycle fall.

Educational simulation only. All patient data is fictional. Not a diagnostic tool.

```
visionos/    Vision Pro app (SwiftUI + RealityKit), XcodeGen project
backend/     FastAPI clinical scenario engine + tests (runs on Windows/macOS/Linux)
scenarios/   Case definitions (JSON) — single source of truth, bundled into the app
elevenlabs/  Agent prompt, dashboard setup, offline clip generator
docs/        Contracts, architecture, device setup, demo script, troubleshooting
```

## 1. Backend

macOS / Linux:
```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate   # Python 3.12+
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Windows PowerShell:
```powershell
cd backend
py -3.12 -m venv .venv; .venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Check: <http://localhost:8000/health>, interactive API: <http://localhost:8000/docs>.

Run the tests (from `backend/`, venv active):
```bash
python -m pytest
```

Swift offline engine check, including parity with the backend's golden fixture (macOS):
```bash
bash visionos/scripts/check_offline_engine.sh
```

## 2. ElevenLabs

Follow [elevenlabs/setup.md](elevenlabs/setup.md): create an agent, paste
[elevenlabs/patient_system_prompt.md](elevenlabs/patient_system_prompt.md), add
the dynamic variable `case_context`, pick the LLM and voice.

- **Public agent** (simplest): put the agent ID into `visionos/Config/Local.xcconfig`
  (`ELEVENLABS_AGENT_ID = agent_...`) or into the app's Settings panel.
- **Private agent**: `cp .env.example .env`, set `ELEVENLABS_API_KEY` and
  `ELEVENLABS_AGENT_ID`, start the backend with
  `uvicorn app.main:app --host 0.0.0.0 --port 8000 --env-file ../.env`, and leave
  the app's agent ID empty. The app fetches a short-lived token from the backend.
  No API key ever lives in the headset app.

Optional, nicer offline voice clips (replaces the macOS `say` placeholders):
```bash
ELEVENLABS_API_KEY=... ELEVENLABS_VOICE_ID=... python3 elevenlabs/generate_clips.py
```

## 3. Vision Pro app

```bash
brew install xcodegen                      # once
cd visionos
cp Config/Local.xcconfig.example Config/Local.xcconfig   # then edit, see below
xcodegen                                   # regenerate after adding/removing files
open MedSimXR.xcodeproj
```

`Config/Local.xcconfig` (gitignored):
```
MEDSIM_BACKEND_HOST = 192.168.1.50:8000    // LAN IP of the machine running the backend, no http://
ELEVENLABS_AGENT_ID = agent_xxxxxxxx       // empty for private agents
DEVELOPMENT_TEAM = ABCDE12345              // your Apple team ID
```

Both values can also be changed at runtime: control panel → Settings (applies on the next Start).
Find the backend machine's IP with `ipconfig getifaddr en0` (macOS) or `ipconfig` (Windows);
headset and backend must be on the same Wi-Fi.

Run on the headset: select the Vision Pro as destination in Xcode and press Run.
Full device steps (developer mode, pairing, permissions): [docs/vision-pro-setup.md](docs/vision-pro-setup.md).
Requires visionOS 26+.

Command-line compile check (no signing):
```bash
cd visionos && xcodebuild -quiet -project MedSimXR.xcodeproj -scheme MedSimXR \
  -destination 'generic/platform=visionOS' CODE_SIGNING_ALLOWED=NO build
```

## 4. Demo

[docs/demo-script.md](docs/demo-script.md) — 90 seconds. Everything except the live
conversation also works with no network at all (Debug mode has buttons for every
examination zone and scripted question).

## Status

Launched and exercised in the visionOS 27.2 simulator: app start, mixed immersive space, seated
patient, all three examinations with correct findings, flinch and arm withdrawal, zone flash,
local clips started, diagnosis, feedback, reset, and backend killed mid-session with the session
continuing offline. Details, evidence and the per-feature status table:
[docs/simulator-test-report.md](docs/simulator-test-report.md).

Re-run it:
```bash
visionos/scripts/simulator_smoke_test.sh --kill-backend   # needs: xcodebuild -downloadPlatform visionOS
```

**Not verified:**

- Gaze + pinch on the avatar, typing, scrolling: nobody has operated the app by hand yet.
- Audio was started, never listened to.
- Live ElevenLabs conversation: no credentials on the development machine. `-mockVoice` is a scripted stand-in.
- Anything that needs the headset: head-relative placement, passthrough, microphone, hand tracking.

First session with the headset: [docs/tomorrow-headset-checklist.md](docs/tomorrow-headset-checklist.md).

Known limits:

- Transcript scoring is whole-word keyword matching (labelled "heuristic" in the feedback). It
  cannot judge empathy or meaning, only whether certain phrases were said.
- Without live voice, history and communication points come only from the scripted Debug questions.
- Procedural primitive avatar; drop a `Patient.usdz` into `visionos/MedSimXR/Resources/` to replace the visuals.
- Offline speech uses macOS `say` placeholder clips until `generate_clips.py` is run.
- One case, English only, sessions in memory (a backend restart drops them; the app then continues offline).
