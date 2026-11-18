# MedSim XR clinical backend

FastAPI service for case logic, examination findings, educational scoring, and MedSim Studio. The clinical engine reads the shared JSON case definitions. Active sessions live in memory, and Studio stores its library in a local JSON file. See the [clinical API](../docs/api-contract.md) and [Studio API](../docs/studio-api.md).

## Setup and run

Use Python 3.12 or later. From the repository root on macOS or Linux:

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --port 8000
```

Windows PowerShell:

```powershell
cd backend
py -3.12 -m venv .venv
.venv\Scripts\Activate.ps1      # if blocked: Set-ExecutionPolicy -Scope Process Bypass
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --port 8000
```

Check <http://localhost:8000/health> and open the [interactive API docs](http://localhost:8000/docs). Run the tests with `python -m pytest` from `backend/` in the activated environment.

## Configuration

The default local setup works without credentials. For optional integrations, copy the root [.env.example](../.env.example) to `.env` in the repository root. Environment variables take precedence.

- `ELEVENLABS_API_KEY` and `ELEVENLABS_AGENT_ID` enable private-agent tokens and the consultation summary. The API key alone enables ElevenLabs Scribe for notebook dictation. See the [voice setup](../elevenlabs/setup.md).
- `MEDSIM_SCENARIOS_DIR`: override the scenarios folder (default `../scenarios`).
- `MEDSIM_STUDIO_DB`: override the library file (default `backend/data/studio_library.json`).
- `MEDSIM_TRACE=0`: disable tracing. By default the backend records API exchanges and director WebSocket frames in `logs/events.jsonl`, and writes session snapshots to `logs/sessions/`. These are inspection records. Active sessions reset on restart. Set `MEDSIM_LOG_DIR` to change the log directory.

## Reaching the backend from the Vision Pro

Append `--host 0.0.0.0` to the Uvicorn command to listen on your trusted local network. Set `MEDSIM_BACKEND_HOST` to the backend machine's LAN address and port, for example `192.168.1.50:8000`. Connect both devices to the same Wi-Fi network.

- macOS: `ipconfig getifaddr en0` (Wi-Fi; try `en1` if empty)
- Linux: `hostname -I`
- Windows: `ipconfig`, use the IPv4 Address of the Wi-Fi adapter

Windows firewall: the first time uvicorn listens, allow Python on **Private** networks in the
prompt. Otherwise (admin PowerShell):
`New-NetFirewallRule -DisplayName "MedSim backend" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow -Profile Private`

Quick check from another device: `http://<LAN-IP>:8000/health`.

## Layout

- `app/main.py` routes; `app/models.py` schemas; `app/sessions.py` scenario loading and session store
- `app/examination.py` zone lookup; `app/evaluation.py` rubric engine and feedback (summary template documented in its docstring)
- `tests/fixtures/parity_*.json` golden input/output shared with the Swift offline engine
