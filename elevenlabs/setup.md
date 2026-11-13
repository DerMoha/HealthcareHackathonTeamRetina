# ElevenLabs agent setup

The app talks to an ElevenLabs Agent. Everything below is dashboard configuration; no code change is needed to change model, voice or prompt.

**Shortcut:** `python3 elevenlabs/sync_agent.py` does sections 1-6 (private agent) through the config API, which costs no credits. It needs only `ELEVENLABS_API_KEY` in `.env`. Without `ELEVENLABS_AGENT_ID` it creates the agent and writes the id into `.env`; otherwise it updates that agent. It then reads the agent back and prints ok/BAD per setting. Re-run it after editing the prompt, and restart the backend after a new id. Not set by the script: voice (agent default) and interruptions/eagerness (ElevenLabs defaults).

**Credits:** ElevenLabs bills connection time, so the app pauses the call itself (`VoicePausePolicy` in `ElevenLabsVoiceService.swift`): after 45 s without a finished spoken turn, after the notebook has been open 15 s, and at 590 s per connection (if the student talked in the last 45 s it reconnects straight away instead, with a short audio gap). The control window then shows "Paused · patient waiting" and **Talk to …**; closing the notebook resumes a pause the notebook caused. Examinations while paused use the local voice and are not sent to the agent. A resumed call is a new ElevenLabs conversation: `case_context` carries the newest ~8000 characters of the transcript plus recent context updates, and the first message is overridden to empty (needs the first-message override, set by the script). Very long consultations forget early details. The agent's `max_duration_seconds` (600) is only a safety net. Settings > **Check credits** shows the account's remaining credits (`GET /elevenlabs/usage`, all account usage, not only this agent). The end-of-consultation summary covers only what was said during connected calls.

## 1. Create the agent
1. elevenlabs.io > Agents > Create agent > Blank agent. Name it `MedSim Patient Alex`.
2. System prompt: paste the full contents of `elevenlabs/patient_system_prompt.md`.
3. First message: `Hello, doctor.` The patient is standing when the session starts and greets the student.
4. Language: English (default). Optional German: add German as an additional language and say in the prompt "Reply in the language the student uses"; case facts are English, so the patient answers in German from them.

## 2. Dynamic variable
Agent > Variables (or just the prompt using `{{case_context}}`): define `case_context` with a placeholder default, e.g.
`CASE FACTS: You are Alex, 28. You fell off your bicycle yesterday onto your outstretched right hand. Your right wrist hurts near the base of the thumb. No numbness. You do not know what is wrong.`
so dashboard "Test AI agent" works. The app overrides it at start with the scenario's `voice_context`.

Mood and appearance need no prompt change. The app folds them into `case_context`: after the case facts it appends a "HOW YOU COME ACROSS" block (for example "Mood: nervous ..." and the pronoun line for the chosen appearance). The prompt's "Personality" section is the default manner; the block takes precedence for tone, never for facts.

Optional, one voice per appearance: Agent > Security > Overrides > enable **Voice**. Then paste a voice ID for the male and the female patient into the app's Settings (control panel > Settings). The app sends it as the TTS `voice_id` override at conversation start (ElevenLabs Swift SDK 3.4.0 `TTSOverrides`). Without an override the agent's own voice is used for both. NOT verified against a live agent.

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
- Security > Overrides: enable **First message** (resumed calls start without a greeting) and, optionally, **Voice** (step 2). Dynamic variables are sent by the app automatically.

## 5b. Client tool: patient movements
Agent > Tools > Add tool > **Client tool**. The app (`ElevenLabsVoiceService.handleTool`) answers it.
- Name: `perform_patient_action` (exact).
- Description: `Moves the patient's body. Call it when the student asks the patient to sit down, hold out or relax the arms, or show which wrist hurts.`
- **Wait for response: ON** (the app returns `success: …`, `invalid_state: …` or `failure: …`; without this the agent cannot know whether it moved).
- Parameter `action`: type string, required, enum `sit_down`, `extend_both_arms`, `relax_arms`, `indicate_right_wrist`. Description: `The movement to perform.`
- No other parameters. The app rejects any other value, so the model cannot invent animations, joint angles or coordinates.

Tool calls are not transcript turns and are not examinations: they never reach the scoring. NOT verified against a live agent (no credentials during development): that the dashboard forwards the tool to SDK 3.4.0 as `client_tool_call` with these field names. The app-side handler is exercised only through the scripted mock voice.

## 5c. Client tool: ordering investigations
Agent > Tools > Add tool > **Client tool**.
- Name: `order_investigation` (exact).
- Description: `Places an order for an imaging investigation when the student asks for one. The result is shown to the student by the app; it is not returned to you.`
- **Wait for response: ON.**
- Parameter `investigation`: type string, required, enum `right_wrist_xray`, `right_wrist_mri`, `right_wrist_ct`. Description: `The investigation the student asked for.`

The app validates the id against the case, asks the clinical engine for the predefined result, opens the viewer, and returns only `success: … requested …` or `failure: …` to the agent. The result text never reaches the model. Fallback without voice: notebook > Investigations. NOT verified against a live agent.

For the road trauma journey case add its ids to the enum: `rt_xray_forearm`, `rt_ct_head`, `rt_bloods` (or remove the enum; the app rejects unknown ids and ids that are not available in the current place).

## 5d. Client tool: asking the medical team (journey cases)
Agent > Tools > Add tool > **Client tool**. Only used by cases whose case information has THE MEDICAL TEAM (today: `road_trauma_journey_001`).
- Name: `request_team_action` (exact).
- Description: `Asks a member of the medical team (paramedic, technician, nurse, doctor) to do something the student requested. The app makes the team member answer out loud; you never speak for them.`
- **Wait for response: ON** (the app returns `success: …`, `blocked: …` or `failure: …`).
- Parameter `action`: type string, required, enum `scene_safety`, `observations`, `haemorrhage_control`, `photograph_wound`, `splint_arm`, `analgesia`, `iv_access`, `iv_analgesia`, `pre_alert`, `iv_antibiotics`, `tetanus`, `orthopaedic_referral`. Description: `The action id for the place the patient is in now (listed under TEAM ACTION IDS in the case information).`
- Re-paste `patient_system_prompt.md` (section "Medical team and changing places").

The app checks the id against the current place, asks the clinical engine, speaks the member's line with the system voice above their figure, and logs it in the notebook's Team tab. Team lines are not transcript turns. The team buttons in the control window and the notebook are the fallback without voice. NOT verified against a live agent.

## 6. Public vs private agent
- **Public** (simplest for a hackathon): Security > "Enable authentication" OFF. Copy the Agent ID (`agent_...`). Put it either in `visionos/Config/Local.xcconfig` as `ELEVENLABS_AGENT_ID = agent_...` (rebuild) or in the in-app Settings field.
- **Private**: enable authentication. In the backend `.env` set `ELEVENLABS_API_KEY` and `ELEVENLABS_AGENT_ID`. Leave the app's agent ID EMPTY. The app then calls `GET /elevenlabs/conversation-token` on the backend and connects with that token. The API key never ships in the app.
- If neither works the app shows a voice error and falls back to local scripted speech.

## 6b. Consultation summary for the notebook
Notebook > History > **End consultation and draft a summary** ends the voice conversation, then the app polls the backend until ElevenLabs has generated its post-call summary (up to 90 s). The learner sees it as a draft and chooses **Insert into history notes** or **Discard**.
- The backend needs `ELEVENLABS_API_KEY` and `ELEVENLABS_AGENT_ID` in `.env` even for a **public** agent: reading a conversation needs the key, and the agent id limits the route to this agent's conversations.
- The agent must keep conversation transcripts (no zero-retention mode), or there is nothing to summarise.
- The text is ElevenLabs' generic call summary. NOT verified against a live agent: its wording (it may say "the user" and "the agent") and how long processing takes.

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
