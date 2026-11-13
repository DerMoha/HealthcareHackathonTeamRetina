#!/usr/bin/env python3
"""Create or update the MedSim patient agent from this repo, via the ElevenLabs config API.

Config calls cost no credits; only live conversations do.
Reads ELEVENLABS_API_KEY (and ELEVENLABS_AGENT_ID, if set) from the repo .env.
No agent id yet: creates the agent and writes its id into .env. Otherwise: updates it.
Re-run after editing patient_system_prompt.md. The steps match setup.md sections 1-6 (private agent).
"""
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENV = ROOT / ".env"
API = "https://api.elevenlabs.io/v1/convai"
LLM = "gpt-6-luna"
# Safety net only: the app pauses or rolls over at 590 s (VoicePausePolicy.limitSeconds) and on idle.
MAX_SECONDS = 600


def string_param(description, enum=None):
    p = {"type": "string", "description": description}
    if enum:
        p["enum"] = enum
    return p


def client_tool(name, description, param, schema):
    return {"type": "client", "name": name, "description": description, "expects_response": True,
            "response_timeout_secs": 10,
            "parameters": {"type": "object", "properties": {param: schema}, "required": [param]}}


# Investigation and team ids are not enumerated: Studio cases add new ones, the app validates every id.
TOOLS = [
    client_tool("perform_patient_action",
                "Moves the patient's body. Call it when the student asks the patient to sit down, hold out or "
                "relax the arms, or show which wrist hurts.",
                "action", string_param("The movement to perform.",
                                       ["sit_down", "extend_both_arms", "relax_arms", "indicate_right_wrist"])),
    client_tool("order_investigation",
                "Places an order for an imaging investigation when the student asks for one. The result is shown "
                "to the student by the app; it is not returned to you.",
                "investigation", string_param("The investigation id the student asked for (listed in the case "
                                              "information).")),
    client_tool("request_team_action",
                "Asks a member of the medical team (paramedic, technician, nurse, doctor) to do something the "
                "student requested. The app makes the team member answer out loud; you never speak for them.",
                "action", string_param("The action id for the place the patient is in now (listed under TEAM "
                                       "ACTION IDS in the case information).")),
]

# Phrases the speech recognition should favour (the movement requests and common clinical words).
ASR_KEYWORDS = ["sit down", "have a seat", "take a seat", "hold out your arms", "stretch out", "relax your arms",
                "which wrist", "show me", "X-ray", "MRI", "CT scan", "snuffbox", "scaphoid", "wrist"]

PLACEHOLDER_CONTEXT = ("CASE FACTS: You are Alex, 28. You fell off your bicycle yesterday onto your outstretched "
                       "right hand. Your right wrist hurts near the base of the thumb. No numbness. You do not "
                       "know what is wrong.")


def read_env():
    env = {}
    for line in ENV.read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip("\"'")
    return env


def call(key, method, path, body=None):
    req = urllib.request.Request(API + path, method=method, headers={"xi-api-key": key,
                                                                     "Content-Type": "application/json"},
                                 data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path} failed: HTTP {e.code} {e.read().decode()[:500]}")


def sync_tools(key):
    existing = {t["tool_config"]["name"]: t["id"] for t in call(key, "GET", "/tools").get("tools", [])}
    ids = []
    for tool in TOOLS:
        if tool["name"] in existing:
            call(key, "PATCH", f"/tools/{existing[tool['name']]}", {"tool_config": tool})
            ids.append(existing[tool["name"]])
        else:
            ids.append(call(key, "POST", "/tools", {"tool_config": tool})["id"])
    return ids


def agent_body(tool_ids):
    return {
        "name": "MedSim Patient Alex",
        "conversation_config": {
            "agent": {
                "first_message": "Hello, doctor.",
                "language": "en",
                "prompt": {"prompt": (ROOT / "elevenlabs" / "patient_system_prompt.md").read_text(),
                           "llm": LLM, "tool_ids": tool_ids},
                "dynamic_variables": {"dynamic_variable_placeholders": {"case_context": PLACEHOLDER_CONTEXT}},
            },
            # turn_timeout -1: no "Are you still there?" nagging, which also kept idle calls alive.
            # retranscribe: a turn cut by the timeout is transcribed again instead of arriving as "...".
            "turn": {"turn_timeout": -1, "retranscribe_on_turn_timeout": True},
            "asr": {"keywords": ASR_KEYWORDS},
            "conversation": {"max_duration_seconds": MAX_SECONDS,
                             "client_events": ["audio", "interruption", "user_transcript", "agent_response",
                                               "agent_response_correction"]},
        },
        "platform_settings": {
            # Private agent: the app gets a conversation token from the backend, the key never ships.
            "auth": {"enable_auth": True},
            # voice_id: per-avatar voice. first_message: a resumed conversation must not greet again.
            "overrides": {"conversation_config_override": {"tts": {"voice_id": True},
                                                           "agent": {"first_message": True}}},
        },
    }


def main():
    env = read_env()
    key, agent_id = env.get("ELEVENLABS_API_KEY"), env.get("ELEVENLABS_AGENT_ID")
    if not key:
        sys.exit("ELEVENLABS_API_KEY missing in .env")
    body = agent_body(sync_tools(key))
    if agent_id:
        call(key, "PATCH", f"/agents/{agent_id}", body)
        print(f"updated agent {agent_id}")
    else:
        agent_id = call(key, "POST", "/agents/create", body)["agent_id"]
        text = ENV.read_text()
        text, n = re.subn(r"(?m)^ELEVENLABS_AGENT_ID=.*$", f"ELEVENLABS_AGENT_ID={agent_id}", text)
        ENV.write_text(text if n else text.rstrip("\n") + f"\nELEVENLABS_AGENT_ID={agent_id}\n")
        print(f"created agent {agent_id} (written to .env)")

    # Read back what ElevenLabs stored, so a silently dropped field shows up here.
    got = call(key, "GET", f"/agents/{agent_id}")
    conf, sent = got["conversation_config"], body["conversation_config"]
    checks = {
        "prompt": conf["agent"]["prompt"]["prompt"].strip() == sent["agent"]["prompt"]["prompt"].strip(),
        "llm": conf["agent"]["prompt"].get("llm") == LLM,
        "tools": sorted(conf["agent"]["prompt"].get("tool_ids") or []) == sorted(sent["agent"]["prompt"]["tool_ids"]),
        "client_events": set(sent["conversation"]["client_events"]) <= set(conf["conversation"].get("client_events") or []),
        "max_duration": conf["conversation"].get("max_duration_seconds") == MAX_SECONDS,
        "turn": conf["turn"].get("turn_timeout") == -1 and conf["turn"].get("retranscribe_on_turn_timeout") is True,
        "asr_keywords": conf.get("asr", {}).get("keywords") == ASR_KEYWORDS,
        "auth": got["platform_settings"].get("auth", {}).get("enable_auth") is True,
        "voice_override": got["platform_settings"]["overrides"]["conversation_config_override"]["tts"].get("voice_id") is True,
        "first_message_override": got["platform_settings"]["overrides"]["conversation_config_override"]["agent"].get("first_message") is True,
    }
    for name, ok in checks.items():
        print(f"  {'ok ' if ok else 'BAD'} {name}")
    sys.exit(0 if all(checks.values()) else 1)


if __name__ == "__main__":
    main()
