# MedSim XR (visionOS)

Seated virtual patient in mixed reality. Talk to it, examine it by gaze+pinch, submit a diagnosis, get feedback.

## Layout

```
visionos/
  project.yml            XcodeGen spec (sources globbed from MedSimXR/)
  Config/                Default.xcconfig, Local.xcconfig (gitignored, see .example)
  MedSimXR/
    App/                 MedSimXRApp (the one place AppModel(engine:voice:) is built), AppModel
    Models/              Contracts, AppConfig, Mocks (shared; don't edit casually)
    Views/               ControlPanelView, FeedbackView, ImmersivePatientView
    Reality/             PatientAvatar (procedural), Placement (ARKit), ReactionPlayer (audio/TTS)
    Interaction/         ExamZones (from model.zones), FingertipExaminer (experimental)
    Resources/Audio/     <zone id | scripted line id | ouch>.m4a placeholder clips
```

Optional: drop a `Patient.usdz` into `MedSimXR/Resources/` to replace the procedural visuals. Zone anchors stay on the procedural skeleton.

## Regenerate / build

```
cd visionos && xcodegen
xcodebuild -quiet -project MedSimXR.xcodeproj -scheme MedSimXR \
  -destination 'generic/platform=visionOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Re-run `xcodegen` after adding or removing files.

## Configuration

Precedence: in-app Settings (UserDefaults) > Info.plist (from xcconfig) > default.

- `Config/Local.xcconfig`: `MEDSIM_BACKEND_HOST`, `ELEVENLABS_AGENT_ID`, `DEVELOPMENT_TEAM`.
- In-app: control panel > Settings (backend host, agent ID, fingertip toggle). Backend/agent changes apply on next Start.

## Audio clips

Names equal ids (`ouch`, zone ids, scripted dialogue ids). Placeholders are macOS `say`; replace with ElevenLabs renders using the same names. Lookup works with or without an `Audio` subdirectory in the bundle.
