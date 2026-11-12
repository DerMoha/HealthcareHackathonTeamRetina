#!/usr/bin/env python3
"""Generate offline fallback voice clips with the ElevenLabs text-to-speech REST API.

Env: ELEVENLABS_API_KEY (required), ELEVENLABS_VOICE_ID (required),
     ELEVENLABS_MODEL_ID (optional, default eleven_multilingual_v2).
Output: visionos/MedSimXR/Resources/Audio/<id>.mp3 (ouch, zone ids, scripted dialogue ids).
"""
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCENARIO = ROOT / "scenarios" / "wrist_trauma_001.json"
OUT = ROOT / "visionos" / "MedSimXR" / "Resources" / "Audio"


def clips(scenario):
    yield "ouch", "Ow!"
    for zone in scenario.get("examination_zones", []):
        yield zone["id"], zone["result"]["patient_response"]
    for line in scenario.get("scripted_dialogue", []):
        yield line["id"], line["patient"]


def synthesize(key, voice, model, text):
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice}?output_format=mp3_44100_128"
    body = json.dumps({"text": text, "model_id": model}).encode()
    req = urllib.request.Request(
        url, data=body, method="POST",
        headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def main():
    key = os.environ.get("ELEVENLABS_API_KEY")
    voice = os.environ.get("ELEVENLABS_VOICE_ID")
    model = os.environ.get("ELEVENLABS_MODEL_ID", "eleven_multilingual_v2")
    if not key or not voice:
        sys.exit("error: set ELEVENLABS_API_KEY and ELEVENLABS_VOICE_ID in the environment")
    scenario = json.loads(SCENARIO.read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    for name, text in clips(scenario):
        try:
            audio = synthesize(key, voice, model, text)
        except urllib.error.HTTPError as e:
            sys.exit(f"error: ElevenLabs returned HTTP {e.code} for '{name}': {e.read().decode(errors='replace')[:300]}")
        except (urllib.error.URLError, TimeoutError) as e:
            sys.exit(f"error: could not reach ElevenLabs for '{name}': {e}")
        # Remove same-named placeholders with other extensions.
        for old in OUT.glob(f"{name}.*"):
            if old.suffix != ".mp3":
                old.unlink()
        (OUT / f"{name}.mp3").write_bytes(audio)
        print(f"wrote {name}.mp3  <- {text!r}")


if __name__ == "__main__":
    main()
