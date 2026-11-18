<img src="assets/icon.svg" width="64" height="64" alt="">

# MedSim XR

Alex fell off his bike and hurt his wrist. On Apple Vision Pro, you can sit down with him, ask what happened, examine his wrist, and decide what you’d do next. At the end, you can see what you picked up and what you missed.

That’s **MedSim XR**, the prototype we built as **Team Retina** at Healthcare Hackathon Bayern.

![A virtual patient in the mixed-reality fracture clinic](docs/screenshots/pitch/wrist-01-in-your-room.jpg)

## The healthcare hackathon

We built MedSim XR in Erlangen, Germany, on **12–14 November 2026**. Medical Valley EMN brought teams and healthcare mentors together, and we had about 48 hours to turn a challenge into something we could show the jury. [Event recap](https://www.medical-valley-emn.de/en/recap-healthcare-hackathon-bayern-erlangen-2026/)

We picked **Meet Your AI Patient**, a challenge from **OTH Amberg-Weiden**. The idea was to give medical students a place to practise taking a patient history. Could you walk into a room, talk to a virtual patient, then get feedback on how you handled the conversation? [Challenge brief](https://hackathon.medical-valley-emn.de/meet-your-ai-patient/)

## What we built at the hackathon

If a patient asks, “Can you look at my wrist?”, we wanted you to be able to do just that. You can check where it hurts, look at an X-ray, fit a wrist support, and write down what you think is going on. The conversation can go differently each time, but the case findings stay the same so you can try a different approach and compare how you did.

We also built **MedSim Studio** so an instructor could run the same case in a quiet clinic or a busy walk-in and see how the learner handled it. For the pitch, we mocked up a scene that gets louder or quieter as the learner’s heart rate changes. The readings in that demo were staged.

The cases are fictional and built for practice.

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
