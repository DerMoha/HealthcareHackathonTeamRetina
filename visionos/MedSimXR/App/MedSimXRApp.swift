import SwiftUI

@main
struct MedSimXRApp: App {
    // Single construction point: the orchestrator swaps in the real engine/voice here.
    @State private var model = AppModel(engine: MockClinicalEngine(), voice: MockVoiceService())

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
