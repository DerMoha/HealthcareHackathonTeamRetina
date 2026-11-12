import SwiftUI

@main
struct MedSimXRApp: App {
    @State private var model = AppModel(engine: MockClinicalEngine(), voice: MockVoiceService())

    var body: some Scene {
        WindowGroup {
            Text("MedSim XR")
                .environment(model)
        }
    }
}
