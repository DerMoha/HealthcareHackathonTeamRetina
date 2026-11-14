import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.sessions import SESSIONS

CASE = "wrist_trauma_001"


@pytest.fixture
def client():
    SESSIONS.clear()
    return TestClient(app)


@pytest.fixture
def sid(client):
    return client.post("/sessions", json={"case_id": CASE}).json()["session_id"]


@pytest.fixture(autouse=True)
def _no_bedrock(monkeypatch):
    """No test may reach Amazon Bedrock; tests that need the model patch notes_ai._ask."""
    monkeypatch.setenv("MEDSIM_NOTES_AI", "off")
