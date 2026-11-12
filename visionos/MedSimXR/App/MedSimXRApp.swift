import SwiftUI

@main
struct MedSimXRApp: App {
    // Single construction point. Launch argument `-useMocks` selects the dev mocks.
    @State private var model: AppModel = {
        if !ProcessInfo.processInfo.arguments.contains("-useMocks"),
           let offline = try? OfflineClinicalEngine(caseId: AppConfig.defaultCaseId) {
            return AppModel(
                engine: FallbackClinicalEngine(primary: BackendClinicalEngine(), offline: offline),
                voice: ElevenLabsVoiceService()
            )
        }
        return AppModel(engine: MockClinicalEngine(), voice: MockVoiceService())
    }()

    var body: some Scene {
        WindowGroup {
            ControlPanelView()
                .environment(model)
        }
        .defaultSize(width: 560, height: 780)

        ImmersiveSpace(id: "patient") {
            ImmersivePatientView()
                .environment(model)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
