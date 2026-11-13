# ElevenLabs agent setup

The app talks to an ElevenLabs Agent. Everything below is dashboard configuration; no code change is needed to change model, voice or prompt.

## 1. Create the agent
1. elevenlabs.io > Agents > Create agent > Blank agent. Name it `MedSim Patient Alex`.
2. System prompt: paste the full contents of `elevenlabs/patient_system_prompt.md`.
3. First message: `Hello, doctor.` The patient is standing when the session starts and greets the student.
4. Language: English (default). Optional German: add German as an additional language and say in the prompt "Reply in the language the student uses"; case facts are English, so the patient answers in German from them.

## 2. Dynamic variable
Agent > Variables (or just the prompt using `{{case_context}}`): define `case_context` with a placeholder default, e.g.
`CASE FACTS: You are Alex, 28. You fell off your bicycle yesterday onto your outstretched right hand. Your right wrist hurts near the base of the thumb. No numbness. You do not know what is wrong.`
so dashboard "Test AI agent" works. The app overrides it at start with the scenario's `voice_context`.

## 3. LLM
- Preferred: **GPT-6 Luna** (shown in ElevenLabs' LLM list as "GPT-6 Luna", the slug `gpt-6-luna` is my guess, pick it from the dropdown).
- Verified from the ElevenLabs LLM docs page (fetched during development): the list includes GPT-6 family (6.1 Sol, 6.1 Terra, 6 Astra, 6 Sol, 6 Luna), GPT-5.x, GPT-4.1, GPT-4o, Gemini 3.x Flash variants, Claude Sonnet 5.5 / Haiku 4.5 and others. NOT verified: actual latency/quality of Luna, whether your account/plan can select it, and any per-model pricing.
- Fallback: **Gemini 3.5 Flash** or **GPT-4.1 Mini** (low latency, widely available). If a model is deprecated or unavailable, simply pick another in Agent > LLM.

## 4. Voice
Agent > Voice: pick a natural, warm, young-adult English voice from the library (try "Charlie"-style or similar relaxed male voices; any empathetic conversational voice works). Model: a Flash/Turbo v2.5 model for latency. Note the Voice ID if you want `generate_clips.py` to use the same voice (`ELEVENLABS_VOICE_ID`).

## 5. Conversation behaviour
- Turn-taking: Eagerness "Normal" (or "Eager" for snappier replies); turn timeout about 7 s.
- Interruptions: **enabled** (Advanced > "Interruptions"/"Allow interruption"). The SDK handles barge-in.
- Client events (Advanced > Client events): enable at least `user_transcript`, `agent_response`, `agent_response_correction`, `interruption`, `audio` is not needed. Without `user_transcript` and `agent_response` the in-app transcript stays empty.
- Disable any "end call" system tool; the session is ended by the app.
- Security > Overrides: none needed. Dynamic variables are sent by the app automatically.

## 5b. Client tool: patient movements
Agent > Tools > Add tool > **Client tool**. The app (`ElevenLabsVoiceService.handleTool`) answers it.
- Name: `perform_patient_action` (exact).
- Description: `Moves the patient's body. Call it when the student asks the patient to sit down, hold out or relax the arms, or show which wrist hurts.`
- **Wait for response: ON** (the app returns `success: …`, `invalid_state: …` or `failure: …`; without this the agent cannot know whether it moved).
- Parameter `action`: type string, required, enum `sit_down`, `extend_both_arms`, `relax_arms`, `indicate_right_wrist`. Description: `The movement to perform.`
- No other parameters. The app rejects any other value, so the model cannot invent animations, joint angles or coordinates.

Tool calls are not transcript turns and are not examinations: they never reach the scoring. NOT verified against a live agent (no credentials during development): that the dashboard forwards the tool to SDK 3.4.0 as `client_tool_call` with these field names. The app-side handler is exercised only through the scripted mock voice.

## 6. Public vs private agent
- **Public** (simplest for a hackathon): Security > "Enable authentication" OFF. Copy the Agent ID (`agent_...`). Put it either in `visionos/Config/Local.xcconfig` as `ELEVENLABS_AGENT_ID = agent_...` (rebuild) or in the in-app Settings field.
- **Private**: enable authentication. In the backend `.env` set `ELEVENLABS_API_KEY` and `ELEVENLABS_AGENT_ID`. Leave the app's agent ID EMPTY. The app then calls `GET /elevenlabs/conversation-token` on the backend and connects with that token. The API key never ships in the app.
- If neither works the app shows a voice error and falls back to local scripted speech.

## 7. Optional: offline clips
`ELEVENLABS_API_KEY=... ELEVENLABS_VOICE_ID=... python3 elevenlabs/generate_clips.py` writes mp3 fallbacks into `visionos/MedSimXR/Resources/Audio/`.

## Troubleshooting
- Patient says "of course" but does not move: the client tool is missing, misnamed, or "Wait for response" is off (step 5b); or the prompt's Body movements section was not pasted. The Debug card has buttons for every movement.
- Status "Microphone access denied": enable Microphone for MedSim XR in Settings > Privacy (on visionOS: Settings > Apps > MedSim XR), then restart the session. The app requests permission at session start (Info.plist must contain `NSMicrophoneUsageDescription`).
- Connected but no audio from the patient: check device volume and that the voice is set on the agent; check the agent works in the dashboard test; on a simulator audio output can be unreliable, test on device.
- Patient speaks but transcript empty: client events not enabled (step 5).
- Patient reads brackets aloud or ignores touches: prompt was not pasted in full, or the model is too weak; try the fallback LLM.
- "Voice connection timed out": network blocked (LiveKit/WebRTC needs outbound UDP/TCP 443 and, on a local network, the Local Network permission) or wrong agent ID. Private agent: check the backend returns a token (503 means env vars missing).
- Patient does not know the case: the `case_context` variable is not defined/used in the prompt (must appear exactly as `{{case_context}}`).
