import SwiftUI

@main
struct MedSimXRApp: App {
    // Single construction point. Launch arguments: `-useMocks` (mock engine and voice),
    // `-mockVoice` (real engines, deterministic scripted voice instead of ElevenLabs).
    @State private var model: AppModel = {
        let args = ProcessInfo.processInfo.arguments
        if !args.contains("-useMocks"),
           let offline = try? OfflineClinicalEngine() {
            return AppModel(
                engine: FallbackClinicalEngine(primary: BackendClinicalEngine(), offline: offline),
                voice: args.contains("-mockVoice") ? MockVoiceService(scripted: true) : ElevenLabsVoiceService()
            )
        }
        return AppModel(engine: MockClinicalEngine(), voice: MockVoiceService())
    }()
    @State private var studio = StudioState()

    var body: some Scene {
        // One window: MedSim Studio, with the session controls on its Session page.
        WindowGroup {
            StudioView()
                .environment(model)
                .environment(studio)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)

        ImmersiveSpace(id: "patient") {
            ImmersivePatientView()
                .environment(model)
                .onAppear { model.immersiveOpen = true }
                .onDisappear { model.immersiveOpen = false }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
