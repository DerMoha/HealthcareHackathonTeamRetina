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
