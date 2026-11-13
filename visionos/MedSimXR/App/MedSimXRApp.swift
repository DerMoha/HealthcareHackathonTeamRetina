import SwiftUI

@main
struct MedSimXRApp: App {
    // Single construction point. Launch arguments: `-useMocks` (mock engine and voice),
    // `-mockVoice` (real engines, deterministic scripted voice instead of ElevenLabs).
    @State private var model: AppModel = {
        let args = ProcessInfo.processInfo.arguments
        if !args.contains("-useMocks"),
           let offline = try? OfflineClinicalEngine(caseId: AppConfig.defaultCaseId) {
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
        .defaultSize(width: 400, height: 460)
        // Small and low, like a tool palette: the patient keeps the centre of the view.
        .defaultWindowPlacement { _, _ in WindowPlacement(.utilityPanel) }

        ImmersiveSpace(id: "patient") {
            ImmersivePatientView()
                .environment(model)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
