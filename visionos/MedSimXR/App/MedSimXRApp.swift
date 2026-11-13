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

    var body: some Scene {
        WindowGroup {
            ControlPanelView()
                .environment(model)
        }
        .defaultSize(width: ControlPanelView.idleSize.width, height: ControlPanelView.idleSize.height)
        // The dashboard is large; a running session shrinks the panel to a small palette
        // (the content decides the size).
        .windowResizability(.contentSize)
        // Low, like a tool palette: the patient keeps the centre of the view.
        .defaultWindowPlacement { _, _ in WindowPlacement(.utilityPanel) }

        ImmersiveSpace(id: "patient") {
            ImmersivePatientView()
                .environment(model)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
