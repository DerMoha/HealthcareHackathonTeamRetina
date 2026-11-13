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
        WindowGroup {
            ControlPanelView()
                .environment(model)
                .environment(studio)
        }
        .defaultSize(width: ControlPanelView.idleSize.width, height: ControlPanelView.idleSize.height)
        // The dashboard is large; a running session shrinks the panel to a small palette
        // (the content decides the size).
        .windowResizability(.contentSize)
        // Low, like a tool palette: the patient keeps the centre of the view.
        .defaultWindowPlacement { _, _ in WindowPlacement(.utilityPanel) }

        // MedSim Studio in the headset: library, marketplace, launch and debrief. Authoring and
        // the Live Director stay in the web Studio (the instructor's screen).
        WindowGroup(id: StudioView.windowId) {
            StudioView()
                .environment(model)
                .environment(studio)
        }
        .defaultSize(width: 1000, height: 600)

        ImmersiveSpace(id: "patient") {
            ImmersivePatientView()
                .environment(model)
                .onAppear { model.immersiveOpen = true }
                .onDisappear { model.immersiveOpen = false }
        }
        // Progressive: the Digital Crown blends the case's room (EnvironmentSet) with the real one.
        .immersionStyle(selection: .constant(.progressive(0.2...1, initialAmount: 1)), in: .progressive(0.2...1, initialAmount: 1))
    }
}
