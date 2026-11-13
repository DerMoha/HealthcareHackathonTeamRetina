# 90-second demo

## Before going on stage

1. Backend running on the laptop (`uvicorn app.main:app --host 0.0.0.0 --port 8000`), same Wi-Fi as the headset.
2. App installed; Settings in the control panel show the right backend host and agent ID.
3. Do one full dry run. The status card should read **AI connection: Connected**, **Microphone: Live**, **Engine: Backend**.
4. Stand where the patient should sit (clear floor ~1.5 m ahead), press **Reset Scenario**, then **Recenter Patient**.
5. Know where **Debug** is (one toggle on the control panel): examination and question buttons, your safety net. Leave it off unless needed; it shows findings.
6. While the notebook is open the patient's microphone is muted (note-taking mode). Close it to talk again.

## Script

| Time | Do | Say |
|---|---|---|
| 0–15 s | Press **Start Session**. Alex stands by the stool and greets you. Say **"Please have a seat"**: he sits. Later **"Could you stretch out both arms?"** before examining. | "This is Alex. Not a chatbot on a screen — a patient in the room who does what you ask." |
| 15–35 s | Ask the patient. | "Hello, I'm a medical student. What happened to you?" → Alex describes the bicycle fall. Follow up: "Where exactly does it hurt?" |
| 35–55 s | "May I examine your wrist?" Then look at the left wrist, pinch (no pain). Look at the right wrist near the thumb, pinch. | Alex pulls the arm back: "Ow! That's exactly where it hurts!" → "I'm sorry, I'll be gentle." |
| 55–70 s | "Any numbness or tingling?" Pinch the **Notebook** beside Alex. Jot one line under Examination, go to **Assessment**, type or dictate your diagnosis, **Submit diagnosis**. | "Nothing on screen told me what this is. I write down what I found and commit to my own diagnosis." |
| 70–90 s | Feedback in the notebook: score, what went well, missed questions, notes vs. what actually happened, next steps. | "Findings come from a case engine, not the language model. And I can't earn points by writing down an examination I never did. **Try Again** resets Alex." |

## If something fails live

| Problem | Do |
|---|---|
| Patient does not answer / AI status shows an error | Debug mode → tap the scripted question buttons (each shows the question it asks). Alex answers with local audio and the transcript still counts. |
| Alex does not sit or move when asked | Control panel → **Ask Alex to sit down** (shown when voice is not connected), or Debug mode → the four patient movement buttons. He cannot be examined while standing. |
| Pinch does not register on the wrist | Debug mode → zone buttons. Same reaction, same scoring. |
| Engine shows **Offline** | Nothing — keep going. Findings and feedback are identical. |
| Patient is in the wrong place | **Recenter Patient** while looking where Alex should sit. |
| No network at all | Start Session still works: patient, examination, pain reaction, diagnosis, feedback. Only the live conversation is missing. |

## Investigations and management (added)

After examining the wrist:

1. Say **"I would like to order an X-ray of his right wrist"** (or notebook → **Investigations** → Right wrist radiographs). The radiology viewer opens beside the patient.
2. Zoom with the magnifier buttons or a pinch. Read the short report: no definite fracture visible.
3. **Back to notebook** → **Assessment**. Fill in: suspected diagnosis, interpretation of investigations, immediate management, further imaging or follow-up.
4. **Submit diagnosis and plan**. Feedback shows the usual 100-point score plus a separate "Investigation and management" score out of 20.

Talking point: "The X-ray is normal. The teaching point is what the student does next: a normal first X-ray does not exclude a scaphoid fracture." Do not order the MRI in front of the audience unless you want to show the answer.

If voice ordering fails: the notebook buttons do the same thing, also offline.
