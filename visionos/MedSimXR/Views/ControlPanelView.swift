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
        .task { await autoDemo() }
    }

    /// Scripted run of the whole demo, driven by launch argument `-autoDemo`.
    /// Used by visionos/scripts/simulator_smoke_test.sh; "STEP" lines are screenshot cues.
    private func autoDemo() async {
        guard SmokeLog.enabled else { return }
        func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        func state() -> String {
            "engine=\(model.engineModeLabel) voice=\(model.voice.status.label) mic=\(model.voice.micStatus.rawValue) "
                + "exams=\(model.examinations.count) turns=\(model.transcript.count) error=\(model.lastError ?? "none")"
        }
        func examine(_ zone: String) async {
            await model.examine(zoneId: zone)
            let r = model.examinations.last
            SmokeLog.mark("examined \(zone) finding=\(r?.finding ?? "?") pain=\(r?.painLevel ?? -1) "
                + "animation=\(model.reaction?.animation ?? "?") speakLocally=\(model.reaction?.speakLocally ?? false) \(state())")
        }

        await pause(3)
        SmokeLog.mark("STEP 01-launch")
        await pause(3)

        if case .opened = await openImmersiveSpace(id: "patient") { immersed = true }
        SmokeLog.mark("immersive opened=\(immersed)")
        await model.startSession()
        await pause(3)
        SmokeLog.mark("session id=\(model.session?.sessionId ?? "none") zones=\(model.zones.map(\.id)) \(state())")
        SmokeLog.mark("STEP 02-session")
        await pause(3)

        model.debugMode = true
        for line in model.scriptedDialogue.prefix(2) {
            model.askScripted(line)
            SmokeLog.mark("asked \(line.id) \(state())")
            await pause(4.5)
        }
        SmokeLog.mark("STEP 03-conversation")
        await pause(3)

        await examine("left_wrist")
        await pause(3.5)
        SmokeLog.mark("STEP 04-pain")
        await examine("right_anatomical_snuffbox")
        await pause(5)

        SmokeLog.mark("STEP 05-killwindow") // the script may kill the backend here
        await pause(8)
        await examine("right_distal_forearm")
        await pause(3)

        model.recenter()
        await pause(2)
        SmokeLog.mark("recentered token=\(model.recenterToken)")

        await model.loadFeedback()
        SmokeLog.mark("pre-diagnosis feedback verdict=\(model.feedback?.diagnosticAssessment.verdict ?? "?") "
            + "criteria=\(model.feedback?.categories.map(\.criteria.count) ?? [])")
        await pause(1.5)
        SmokeLog.mark("STEP 06-feedback-locked")
        await pause(3)
        hideFeedback = true

        diagnosis = "Suspected scaphoid fracture"
        await pause(1.5)
        SmokeLog.mark("STEP 07-diagnosis-entered")
        await pause(3)
        await model.submitDiagnosis(diagnosis)
        let f = model.feedback
        SmokeLog.mark("diagnosed score=\(f?.totalScore ?? -1)/\(f?.maxScore ?? -1) verdict=\(f?.diagnosticAssessment.verdict ?? "?") "
            + "categories=\(f?.categories.map { "\($0.id):\($0.score)" } ?? []) \(state())")
        await pause(1.5)
        SmokeLog.mark("STEP 08-feedback")
        await pause(4)

        await model.reset()
        await pause(2)
        SmokeLog.mark("reset feedback=\(model.feedback == nil ? "cleared" : "STILL SET") \(state())")
        SmokeLog.mark("STEP 09-reset")
        await pause(3)

        await model.stopSession()
        if immersed { await dismissImmersiveSpace(); immersed = false }
        SmokeLog.mark("STEP 10-stopped")
        SmokeLog.mark("DONE")
    }

    private func panel(model: AppModel) -> some View {
        @Bindable var model = model
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusCard
                sessionButtons

                if model.phase == .running {
                    if !model.examinations.isEmpty { lastExamCard }
                    diagnosisCard
                }

                if model.feedback != nil || model.phase == .running {
                    HStack {
                        Button("Show Feedback") {
                            hideFeedback = false
                            Task { await model.loadFeedback() }
                        }
                        Button("Reset Scenario") { Task { await model.reset() } }
                    }
                    .buttonStyle(.bordered)
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
            statusRow("brain.head.profile", "AI connection", voiceLabel, color: statusColor)
            if case .failed(let reason) = model.voice.status {
                Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
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
