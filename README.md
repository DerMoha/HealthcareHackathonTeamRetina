<img src="assets/icon.svg" width="64" height="64" alt="">

# MedSim XR

**MedSim XR is Team Retina’s Apple Vision Pro prototype from Healthcare Hackathon Bayern 2026 in Erlangen, Germany.** We wanted to see whether mixed reality could give learners a repeatable way to practise a whole clinical encounter, from the first conversation through examination, assessment, and feedback.

![A virtual patient in the mixed-reality fracture clinic](docs/screenshots/pitch/wrist-01-in-your-room.jpg)

## The healthcare hackathon

Medical Valley EMN brought participants, healthcare experts, and mentors together in Erlangen on **12–14 November 2026**. Teams spent about 48 hours developing prototypes for practical healthcare challenges and presented their work to a jury on the final day. [Medical Valley EMN’s event recap](https://www.medical-valley-emn.de/en/recap-healthcare-hackathon-bayern-erlangen-2026/)

Our starting point was **Meet Your AI Patient**, the challenge from **OTH Amberg-Weiden**. The brief called for an AI-powered patient on Apple Vision Pro so medical students could practise taking a patient history in a realistic setting. It also called for feedback after each consultation, so learners could see which questions they asked, which details they missed, and how they structured the interview. [Official challenge brief](https://hackathon.medical-valley-emn.de/meet-your-ai-patient/)

## What we built at the hackathon

The Vision Pro app puts a virtual patient in the room. Learners interview and examine the patient, use tools such as an ultrasound probe or wrist support, and record their reasoning before getting a scored debrief. The web-based MedSim Studio gives instructors a way to configure the setting and equipment, introduce distractions during a session, and review how the learner did.

We used AI for the patient conversation and authored cases for the clinical findings and scoring. That lets a learner repeat a case with the same findings while the conversation can take a different course. [Project architecture](docs/architecture.md)

This archive preserves the prototype, demo materials, and the team's test evidence. The pitch also explored future ideas such as adjusting distractions in response to a learner's heart rate. That concept used staged readings. The cases use fictional patient histories and are intended for education and simulation only.

## What you can try

- **Wrist injury** · Examine a patient who fell from a bicycle, review imaging, and measure and fit a wrist support in the orthotics lab.
- **Obstetric ultrasound** · Apply gel, position the probe, and identify and measure views in a simulated mid-trimester scan.
- **Trauma journey** · Coordinate with simulated teammates as one patient moves from the roadside or forest trail through an ambulance to the emergency department.
- **MedSim Studio** · Configure a case, publish it with a launch code, trigger events with the Live Director, and review the debrief. Try `LKGLZX` (guided clinic), `5344E7` (busy walk-in), or `7B46EL` (forest trail) on a fresh Studio library.

The [demo script](docs/demo-script.md) walks through the wrist case. The [pitch deck](docs/pitch/MedSimXR-pitch.pptx) and [screenshot gallery](docs/screenshots/pitch/README.md) cover the rest of the prototype.

## Run locally

### Clinical backend and Studio

The [backend setup](backend/README.md) covers Python 3.12+, macOS, Linux, and Windows. For a browser-only demo, build [MedSim Studio](studio/README.md) first and start the backend afterward. The backend serves the built Studio at <http://localhost:8000/app/> and its API docs at <http://localhost:8000/docs>.

### Vision Pro app

Use a Mac with Xcode 26 or later and the visionOS SDK. The app targets visionOS 26 or later. Open the checked-in [Xcode project](visionos/MedSimXR.xcodeproj), choose a simulator or a Vision Pro, and run. The [app setup](visionos/README.md) covers project generation and configuration. Follow the [device guide](docs/vision-pro-setup.md) for pairing, signing, and connecting over your local network.

The app bundles case logic and scripted audio for offline sessions. For live conversation, follow the [ElevenLabs setup](elevenlabs/setup.md). Backend credentials go in a local `.env` based on [the example](.env.example).

## Repository guide

- [visionos/](visionos/) has the SwiftUI and RealityKit app, local case engine, and simulator scripts.
- [backend/](backend/) has the FastAPI case engine, scoring, Studio API, and test fixtures.
- [studio/](studio/) has the React instructor interface.
- [scenarios/](scenarios/) has the JSON case definitions shared by the backend and the offline app.
- [docs/](docs/) has the [architecture](docs/architecture.md), [clinical API](docs/api-contract.md), [Studio API](docs/studio-api.md), and [troubleshooting](docs/troubleshooting.md).

## Verification and limits

The [simulator report](docs/simulator-test-report.md) records scripted checks for examinations, patient movement, scoring, replay, and offline fallback. The [interaction record](docs/interaction-verification.md) tracks physical headset, manual gestures, and live voice as unverified in that test pass. Scoring uses case-specific checklists and keyword matching. The cases and fitting workflows are educational prototypes.

Run `python -m pytest` from `backend/` after installing its requirements. On macOS, run `bash visionos/scripts/check_offline_engine.sh` and `bash visionos/scripts/check_patient_behavior.sh` from the repository root. The [Studio docs](studio/README.md) include the TypeScript build check.

## Asset credits

See the credits for [patient avatars](assets/patient/README.md), [radiology images](assets/radiology/README.md), [ultrasound images](assets/ultrasound/README.md), and [pitch assets](assets/pitch/). This snapshot has no repository-wide license file. Individual assets carry the terms in their credit notes.
