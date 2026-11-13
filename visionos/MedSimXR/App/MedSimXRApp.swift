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
    @State private var immersion: any ImmersionStyle = Self.room
    private static let room = ProgressiveImmersionStyle.progressive(0.2...1, initialAmount: 1)

    var body: some Scene {
        // One window: MedSim Studio, with the session controls on its Session page.
        WindowGroup(id: "studio") {
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
                // pitch shots: without the case's room the patient sits in the wearer's own room
                .onChange(of: Pitch.shared.hideRoom) { _, hide in immersion = hide ? .mixed : Self.room }
        }
        // Progressive: the Digital Crown blends the case's room (EnvironmentSet) with the real one.
        .immersionStyle(selection: $immersion, in: .mixed, Self.room)
    }
}
