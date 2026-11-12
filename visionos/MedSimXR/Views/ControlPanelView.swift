import SwiftUI

struct ControlPanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @AppStorage(AppConfig.backendHostKey) private var backendHost = ""
    @AppStorage(AppConfig.agentIdKey) private var agentId = ""
    @AppStorage("fingertipExam") private var fingertip = false

    @State private var diagnosis = ""
    @State private var immersed = false
    @State private var hideFeedback = false

    var body: some View {
        @Bindable var model = model
        Group {
            if model.feedback != nil && !hideFeedback {
                FeedbackView(onBack: { hideFeedback = true })
            } else {
                panel(model: model)
            }
        }
        .onChange(of: model.feedback) { hideFeedback = false }
    }

    private func panel(model: AppModel) -> some View {
        @Bindable var model = model
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusCard
                sessionButtons

                if model.phase == .running {
                    diagnosisCard
                }

                if model.feedback != nil || model.phase == .running {
                    HStack {
                        Button("Show Feedback") {
                            hideFeedback = false
                            Task { await model.loadFeedback() }
                        }
                        Button("Reset Scenario", role: .destructive) { Task { await model.reset() } }
                    }
                    .disabled(model.isBusy)
                }

                if let err = model.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.red)
                }

                if !model.transcript.isEmpty { transcriptCard }

                Toggle("Debug mode", isOn: $model.debugMode)
                if model.debugMode { debugCard }

                settingsCard
            }
            .padding(24)
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "cross.case.fill").foregroundStyle(.teal).font(.title2)
                Text("MedSim XR").font(.title.bold())
                Spacer()
                if model.isBusy { ProgressView() }
            }
            if let c = model.session?.case {
                Text(c.title).font(.headline)
                Text(c.learnerBrief).font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Start a session to meet your virtual patient. Talk to them, then examine the wrist.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow("brain.head.profile", "AI connection", model.voice.status.label, color: statusColor)
            statusRow(model.voice.micStatus == .live ? "mic.fill" : "mic.slash", "Microphone", model.voice.micStatus.rawValue,
                      color: model.voice.micStatus == .live ? .green : .secondary)
            statusRow("server.rack", "Engine", model.engineModeLabel, color: .secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusColor: Color {
        switch model.voice.status {
        case .connected: .green
        case .connecting: .orange
        case .failed: .red
        case .disconnected: .secondary
        }
    }

    private func statusRow(_ icon: String, _ title: String, _ value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 24).foregroundStyle(color)
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).foregroundStyle(color).lineLimit(2).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private var sessionButtons: some View {
        HStack {
            if model.phase == .idle {
                Button {
                    Task {
                        if !immersed {
                            if case .opened = await openImmersiveSpace(id: "patient") { immersed = true }
                        }
                        await model.startSession()
                    }
                } label: { Label("Start Session", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.teal)
            } else {
                Button {
                    Task {
                        await model.stopSession()
                        if immersed { await dismissImmersiveSpace(); immersed = false }
                    }
                } label: { Label("Stop Session", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.red)
                Button { model.recenter() } label: { Label("Recenter Patient", systemImage: "scope") }
            }
        }
        .disabled(model.isBusy)
    }

    private var diagnosisCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your diagnosis").font(.headline)
            TextField("Suspected diagnosis", text: $diagnosis)
            HStack {
                Button("Suspected scaphoid fracture") { diagnosis = "Suspected scaphoid fracture" }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Submit Diagnosis") { Task { await model.submitDiagnosis(diagnosis) } }
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(diagnosis.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Conversation").font(.headline)
            ForEach(model.transcript.suffix(4)) { turn in
                HStack(alignment: .top, spacing: 6) {
                    Text(turn.role == .learner ? "You" : "Patient")
                        .font(.caption.bold())
                        .foregroundStyle(turn.role == .learner ? .teal : .orange)
                        .frame(width: 52, alignment: .leading)
                    Text(turn.text).font(.callout)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var debugCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Examine").font(.subheadline.bold())
            ForEach(model.zones) { z in
                Button(z.label) { Task { await model.examine(zoneId: z.id) } }
                    .buttonStyle(.bordered).disabled(model.phase != .running)
            }
            Text("Ask").font(.subheadline.bold())
            ForEach(model.scriptedDialogue) { line in
                Button(line.learner) { model.askScripted(line) }
                    .buttonStyle(.bordered).disabled(model.phase != .running)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var settingsCard: some View {
        DisclosureGroup("Settings") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Backend host (host:port)", text: $backendHost)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("ElevenLabs agent ID", text: $agentId)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("Fingertip examination (experimental)", isOn: $fingertip)
                Text("Backend and agent changes apply on the next Start.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }
}
