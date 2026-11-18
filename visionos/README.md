# MedSim XR for visionOS

The SwiftUI and RealityKit app bundles the case definitions, avatars, and scripted audio for offline sessions.

## Build

Use Xcode 26 or later with the visionOS SDK. The app targets visionOS 26 or later. From this directory, open the checked-in project.

```bash
open MedSimXR.xcodeproj
```

After adding or removing app files, regenerate the project with [XcodeGen](https://github.com/yonaskolb/XcodeGen) by running `xcodegen` here. To compile without signing, use the following command.

```bash
xcodebuild -quiet -project MedSimXR.xcodeproj -scheme MedSimXR \
  -destination 'generic/platform=visionOS' CODE_SIGNING_ALLOWED=NO build
```

For pairing, signing, and a physical device run, see the [Vision Pro setup guide](../docs/vision-pro-setup.md).

## Configure

Copy [Config/Local.xcconfig.example](Config/Local.xcconfig.example) to `Config/Local.xcconfig` for local build settings.

- `MEDSIM_BACKEND_HOST` uses a host and port such as `192.168.1.50:8000`. The simulator default is `localhost:8000`.
- `DEVELOPMENT_TEAM` is your Apple team ID for signing a device build.
- `ELEVENLABS_AGENT_ID` selects a public agent. Leave it empty for a private agent and configure the backend using the [ElevenLabs guide](../elevenlabs/setup.md).

In-app settings override the backend host and agent ID from the build on the next session start. For offline testing, use the app's **Debug** controls or pass `-mockVoice` at launch for scripted voice.

## Source and assets

- [project.yml](project.yml) defines the Xcode project and bundles the [shared case definitions](../scenarios/).
- [MedSimXR/](MedSimXR/) contains app state, views, RealityKit scenes, networking, and voice.
- [scripts/](scripts/) contains Swift checks and simulator capture scripts. See the [simulator report](../docs/simulator-test-report.md) for an example run.
- The [avatar build notes](../assets/patient/README.md) and [voice setup](../elevenlabs/setup.md#7-optional-offline-clips) cover replacing the bundled models and clips.
