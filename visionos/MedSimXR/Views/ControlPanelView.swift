import SwiftUI

/// The Session page of the main window: scenario choice, start/stop, status, settings. Notes, conversation, diagnosis and feedback live in the notebook
/// next to the patient (NotebookView); everything diagnostic is behind the Debug toggle.
struct ControlPanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @AppStorage(AppConfig.backendHostKey) private var backendHost = ""
    @AppStorage(AppConfig.agentIdKey) private var agentId = ""
    @AppStorage("fingertipExam") private var fingertip = false

    /// Tracked by the model: the Studio window can open the patient's space too.
    private var immersed: Bool { model.immersiveOpen }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Session").font(.largeTitle.bold())
                    Spacer()
                    if model.isBusy { ProgressView() }
                }
                Text(model.session?.case.learnerBrief
                     ?? "Start a session to meet your patient. Talk to them, examine them, and write your findings in the notebook beside them.")
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        ScenarioCard()
                        sessionButtons
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 14) {
                        statusCard
                        if let err = model.lastError, !model.notebookOpen {
                            Label(err, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
                        }
                        Toggle("Debug", isOn: $model.debugMode)
                        if model.debugMode { debugCard }
                        settingsCard
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(32)
        }
    }

    // MARK: Sections

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow("brain.head.profile", "AI connection", voiceLabel, color: statusColor)
            if case .failed(let reason) = model.voice.status {
                Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            statusRow(model.voice.micStatus == .live ? "mic.fill" : "mic.slash", "Microphone", model.voice.micStatus.rawValue,
                      color: model.voice.micStatus == .live ? .green : .secondary)
            statusRow("server.rack", "Engine", model.engineModeLabel, color: .secondary)
            // One-tap fallback when nobody is listening: without it a standing patient cannot be examined.
            if model.phase == .running, model.behavior.state == .standingIdle, model.voice.status != .connected {
                Button("Ask Alex to sit down") { model.performPatientAction(PatientAction.sitDown.rawValue) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusColor: Color {
        switch model.voice.status {
        case .connected: .green
        case .connecting, .failed: .orange
        case .disconnected: .secondary
        }
    }

    /// A failed voice connection is not fatal: the patient keeps talking through local clips.
    private var voiceLabel: String {
        if case .failed = model.voice.status { return "Unavailable · local voice" }
        return model.voice.status.label + (model.voice.isAgentSpeaking ? " · speaking" : "")
    }

    private var lastExamCard: some View {
        let exam = model.examinations.last
        let painful = (exam?.painLevel ?? 0) >= 5
        return HStack(spacing: 10) {
            Image(systemName: painful ? "exclamationmark.triangle.fill" : "hand.point.up.left.fill")
                .foregroundStyle(painful ? .red : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.zones.first { $0.id == exam?.bodyPart }?.label ?? "").font(.subheadline.bold())
                Text("\((exam?.finding ?? "").replacingOccurrences(of: "_", with: " ")) · pain \(exam?.painLevel ?? 0)/10")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(model.examinations.count) examined").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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
                        if !immersed { _ = await openImmersiveSpace(id: "patient") }
                        await model.startSession()
                    }
                } label: { Label("Start Session", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.teal)
            } else {
                Button {
                    Task {
                        await model.stopSession()
                        if immersed { await dismissImmersiveSpace() }
                    }
                } label: { Label("Stop Session", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.red)
                Button { model.recenter() } label: { Label("Recenter Patient", systemImage: "scope") }
            }
        }
        .disabled(model.isBusy)
    }

    /// Demo safety net: trigger examinations and scripted questions without touching the avatar.
    private var debugCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.examinations.isEmpty { lastExamCard }
            Text("Examine").font(.subheadline.bold())
            ForEach(model.zones) { z in
                Button(z.label) { Task { await model.examine(zoneId: z.id) } }
                    .buttonStyle(.bordered).disabled(model.phase != .running)
            }
            Text("Patient: \(model.behavior.state.rawValue.replacingOccurrences(of: "_", with: " "))").font(.subheadline.bold())
            ForEach(PatientAction.allCases, id: \.self) { action in
                Button(action.rawValue.replacingOccurrences(of: "_", with: " ").capitalized) {
                    model.performPatientAction(action.rawValue)
                }
                .buttonStyle(.bordered).disabled(model.phase != .running)
            }
            if model.behavior.canExamine, let orthotics = model.session?.case.orthotics, !orthotics.sizes.isEmpty {
                // Fallback if neither pinch nor drag works: same placement call, fixed spot on the arm.
                Text("Equipment").font(.subheadline.bold())
                Button("Measure wrist") { model.labCommand = LabCommand(item: OrthoticsLab.tapeName, axialCm: 1, radialCm: 0, via: "debug") }
                Button("Measure forearm") { model.labCommand = LabCommand(item: OrthoticsLab.tapeName, axialCm: 14, radialCm: 0, via: "debug") }
                ForEach(orthotics.sizes) { size in
                    Button("Put \(size.label) support on the wrist") {
                        model.labCommand = LabCommand(item: OrthoticsLab.orthosisPrefix + size.id, axialCm: 3, radialCm: 0, via: "debug")
                    }
                }
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
