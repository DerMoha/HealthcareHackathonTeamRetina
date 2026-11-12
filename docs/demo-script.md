# 90-second demo

## Before going on stage

1. Backend running on the laptop (`uvicorn app.main:app --host 0.0.0.0 --port 8000`), same Wi-Fi as the headset.
2. App installed; Settings in the control panel show the right backend host and agent ID.
3. Do one full dry run. The status card should read **AI connection: Connected**, **Microphone: Live**, **Engine: Backend**.
4. Stand where the patient should sit (clear floor ~1.5 m ahead), press **Reset Scenario**, then **Recenter Patient**.
5. Turn **Debug mode** on and leave it on — it is your safety net.

## Script

| Time | Do | Say |
|---|---|---|
| 0–15 s | Press **Start Session**. Patient appears seated in the room. | "This is Alex. Not a chatbot on a screen — a patient sitting in the room with you." |
| 15–35 s | Ask the patient. | "Hello, I'm a medical student. What happened to you?" → Alex describes the bicycle fall. Follow up: "Where exactly does it hurt?" |
| 35–55 s | "May I examine your wrist?" Then look at the left wrist, pinch (no pain). Look at the right wrist near the thumb, pinch. | Alex pulls the arm back: "Ow! That's exactly where it hurts!" → "I'm sorry, I'll be gentle." |
| 55–70 s | "Any numbness or tingling?" Then tap **Suspected scaphoid fracture** and **Submit Diagnosis**. | "The findings come from a clinical case engine, not from the language model — it cannot make up an examination result." |
| 70–90 s | Feedback screen: score, what went well, missed questions, findings, next steps. | "Every point is explainable. And one tap on **Try Again** resets Alex for the next student." |

## If something fails live

| Problem | Do |
|---|---|
| Patient does not answer / AI status shows an error | Debug mode → tap the scripted question buttons (each shows the question it asks). Alex answers with local audio and the transcript still counts. |
| Pinch does not register on the wrist | Debug mode → zone buttons. Same reaction, same scoring. |
| Engine shows **Offline** | Nothing — keep going. Findings and feedback are identical. |
| Patient is in the wrong place | **Recenter Patient** while looking where Alex should sit. |
| No network at all | Start Session still works: patient, examination, pain reaction, diagnosis, feedback. Only the live conversation is missing. |
