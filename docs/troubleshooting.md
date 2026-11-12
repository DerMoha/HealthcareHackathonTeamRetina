# Troubleshooting

## Backend

| Symptom | Fix |
|---|---|
| App shows **Engine: Offline** | Backend not reachable. Check it was started with `--host 0.0.0.0`, both devices are on the same Wi-Fi, the host in Settings is `IP:8000` without `http://`, and the firewall allows port 8000 (Windows: allow Python on private networks). Test from another device: `http://<ip>:8000/health`. Press Reset Scenario or Start Session to retry the backend. |
| `pip install` fails building wheels | Use Python 3.12 or 3.13, not a pre-release interpreter. |
| `GET /elevenlabs/conversation-token` → 503 | `ELEVENLABS_API_KEY` / `ELEVENLABS_AGENT_ID` missing. Start with `--env-file ../.env`. |
| → 502 | ElevenLabs rejected the request: wrong key, wrong agent ID, or the key lacks agent access. |
| Session errors after restarting the backend | Sessions are in memory. The app falls back to offline automatically; Reset Scenario starts a fresh backend session. |

## Voice

| Symptom | Fix |
|---|---|
| **AI: Error: Microphone access denied** | Headset Settings → Apps → MedSim XR → Microphone. |
| **No agent ID set and backend unreachable…** | Enter a public agent ID in Settings, or fix the backend connection for private agents. |
| **Voice connection timed out** | Headset has no internet (hotspot/captive portal), or the agent ID is wrong. |
| Connected, but the patient does not react aloud to an examination | In the ElevenLabs dashboard the agent must accept text input, and the prompt must contain the bracketed-events section from `patient_system_prompt.md`. |
| Patient reads the brackets aloud or reveals the diagnosis | The dashboard prompt differs from `patient_system_prompt.md`; paste it again. |
| Patient does not know the case facts | Dynamic variable `case_context` is not defined on the agent, or `{{case_context}}` is missing from the prompt. |
| Echo / patient interrupts itself | Lower headset volume; check turn-taking settings in `elevenlabs/setup.md`. |

## visionOS build and app

| Symptom | Fix |
|---|---|
| `module 'ElevenLabs' has a minimum deployment target of visionOS 26.0` | Deployment target must stay ≥ 26.0 in `project.yml`. |
| Undefined symbols for `x86_64` on simulator | Keep `EXCLUDED_ARCHS[sdk=xrsimulator*] = x86_64` (LiveKit WebRTC has no x86_64 simulator slice); Apple-silicon Mac required for the simulator. |
| Package resolution fails ("network connection was lost") | Retry; the WebRTC binary is large. File → Packages → Reset Package Caches. |
| New Swift file "not in scope" | Run `xcodegen` in `visionos/` again. |
| Signing error | Set `DEVELOPMENT_TEAM` in `Config/Local.xcconfig`, run `xcodegen`. Bundle id `dev.medsimxr.app` may need changing if it is taken for your team. |
| Patient appears inside furniture or behind you | Face free floor space and press Recenter Patient. |
| Pinch on the wrist does nothing | Session must be running (Start Session). Zones show a faint highlight when looked at. Use Debug mode buttons as fallback. |
| Run without backend and voice for UI work | Add launch argument `-useMocks` to the scheme. |
