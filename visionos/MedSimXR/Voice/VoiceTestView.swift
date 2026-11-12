import SwiftUI

/// Standalone test screen for the live voice integration. Not wired into the app.
/// Show it temporarily, e.g. `WindowGroup { VoiceTestView() }` or as a sheet from any view.
struct VoiceTestView: View {
    @State private var voice = ElevenLabsVoiceService()
    @State private var turns: [TranscriptTurn] = []

    private let sampleContext = """
    CASE FACTS: You are Alex, 28. Yesterday you fell off your bicycle and landed on your outstretched right hand. \
    Your right wrist hurts, mostly on the thumb side. No numbness. You do not know what is wrong.
    """
    private let sampleEvent = """
    [The student presses on the thumb side of your right wrist. It hurts sharply and you pull your arm back. \
    React out loud right now in one short sentence.]
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voice test").font(.title2)
            HStack(spacing: 12) {
                Button("Start") { Task { await voice.start(caseContext: sampleContext) } }
                Button("Stop") { Task { await voice.stop() } }
                Button("Send exam event") { Task { await voice.sendExaminationEvent(sampleEvent) } }
            }
            Text("Status: \(voice.status.label)")
            Text("Mic: \(voice.micStatus.rawValue)")
            Text("Agent speaking: \(voice.isAgentSpeaking ? "yes" : "no")")
            Divider()
            List(turns) { turn in
                VStack(alignment: .leading) {
                    Text(turn.role == .learner ? "Learner" : "Patient").font(.caption).foregroundStyle(.secondary)
                    Text(turn.text)
                }
            }
        }
        .padding(24)
        .onAppear { voice.onTranscript = { turns.append($0) } }
    }
}
