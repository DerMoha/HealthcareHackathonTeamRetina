import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.sessions import SESSIONS

CASE = "wrist_trauma_001"


@pytest.fixture(autouse=True)
def trace_dir(tmp_path, monkeypatch):
    # off by default: TestClient runs each websocket on its own loop thread, and file writes shift its timing
    monkeypatch.setenv("MEDSIM_TRACE", "0")
    monkeypatch.setenv("MEDSIM_LOG_DIR", str(tmp_path / "logs"))
    return tmp_path / "logs"


@pytest.fixture
def client():
    SESSIONS.clear()
    return TestClient(app)


@pytest.fixture
def sid(client):
    return client.post("/sessions", json={"case_id": CASE}).json()["session_id"]
