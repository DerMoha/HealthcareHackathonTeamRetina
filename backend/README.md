# MedSim XR clinical backend

FastAPI service: single source of truth for examination findings and educational scoring.
In-memory sessions, no database, no LLM calls. Contract: `../docs/api-contract.md`.
Python 3.12+.

## Setup and run

macOS / Linux:

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
python -m pytest
```

Windows PowerShell:

```powershell
cd backend
py -3.12 -m venv .venv
.venv\Scripts\Activate.ps1      # if blocked: Set-ExecutionPolicy -Scope Process Bypass
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
python -m pytest
```

Interactive API docs: <http://localhost:8000/docs> (OpenAPI at `/openapi.json`).

## Configuration

Copy `../.env.example` to `../.env` (repo root). Real environment variables win over `.env`.

- `ELEVENLABS_API_KEY`, `ELEVENLABS_AGENT_ID`: needed only for `GET /elevenlabs/conversation-token`
  (503 if missing, 502 if ElevenLabs rejects the call). The key is never returned or logged.
- `MEDSIM_SCENARIOS_DIR`: override the scenarios folder (default `../scenarios`).

## Reaching the backend from the Vision Pro

The headset connects to `http://<this-machine-LAN-IP>:8000`; set that as `MEDSIM_BACKEND_HOST`.
Both devices must be on the same Wi-Fi network.

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
