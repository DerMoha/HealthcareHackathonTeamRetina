import SwiftUI

/// Session controls only. Notes, conversation, diagnosis and feedback live in the notebook
/// next to the patient (NotebookView); everything diagnostic is behind the Debug toggle.
struct ControlPanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @AppStorage(AppConfig.backendHostKey) private var backendHost = ""
    @AppStorage(AppConfig.agentIdKey) private var agentId = ""
    @AppStorage("fingertipExam") private var fingertip = false

    @State private var immersed = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "cross.case.fill").foregroundStyle(.teal).font(.title2)
                    Text("MedSim XR").font(.title2.bold())
                    Spacer()
                    if model.isBusy { ProgressView() }
                }
                Text(model.session?.case.learnerBrief
                     ?? "Start a session to meet your patient. Talk to them, examine them, and write your findings in the notebook beside them.")
                    .font(.callout).foregroundStyle(.secondary)
                sessionButtons
                statusCard
                if let err = model.lastError, !model.notebookOpen {
                    Label(err, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
                }
                Toggle("Debug", isOn: $model.debugMode)
                if model.debugMode { debugCard }
                settingsCard
            }
            .padding(20)
        }
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
            await model.examine(zoneId: zone, source: .script)
            let r = model.examinations.last
            SmokeLog.mark("examined \(zone) finding=\(r?.finding ?? "?") pain=\(r?.painLevel ?? -1) "
                + "animation=\(model.reaction?.animation ?? "?") speakLocally=\(model.reaction?.speakLocally ?? false) \(state())")
        }

        /// A spoken request: through the scripted voice when it is connected, else the same
        /// action hook directly (what the debug buttons do).
        func say(_ text: String, _ action: String) async {
            if let mock = model.voice as? MockVoiceService, mock.status == .connected {
                await mock.hear(text)
            } else {
                model.performPatientAction(action)
            }
        }

        func order(_ text: String, _ id: String) async {
            if let mock = model.voice as? MockVoiceService, mock.status == .connected {
                await mock.hear(text)
            } else {
                await model.orderInvestigation(id)
            }
        }

        await pause(3)
        SmokeLog.mark("STEP 01-launch")
        await pause(3)

        if case .opened = await openImmersiveSpace(id: "patient") { immersed = true }
        SmokeLog.mark("immersive opened=\(immersed)")
        await model.startSession()
        await pause(3.5)
        SmokeLog.mark("session id=\(model.session?.sessionId ?? "none") zones=\(model.zones.map(\.id)) \(state())")
        SmokeLog.mark("STEP 02-session")
        await pause(3)

        // Standing: the wrist cannot be examined yet, and a spoken request is never an examination.
        await model.examine(zoneId: "right_anatomical_snuffbox")
        SmokeLog.mark("standing examine state=\(model.behavior.state.rawValue) \(state())")
        SmokeLog.mark("STEP 03-sitting") // the script takes a burst of screenshots here
        await say("Please have a seat.", "sit_down")
        await say("Please sit down.", "sit_down") // repeated command
        await pause(3)
        SmokeLog.mark("STEP 03-seated")
        await pause(2)

        for line in model.scriptedDialogue.prefix(2) {
            model.askScripted(line)
            SmokeLog.mark("asked \(line.id) \(state())")
            await pause(4.5)
        }
        SmokeLog.mark("STEP 03-conversation")
        await pause(2)

        // Interrupted: relax in the middle of extending, then extend again.
        await say("Could you stretch out both arms?", "extend_both_arms")
        await pause(0.3)
        await say("Actually, relax your arms.", "relax_arms")
        await pause(0.2)
        await say("Please hold both arms out for me.", "extend_both_arms")
        await pause(2)
        SmokeLog.mark("STEP 04-arms-extended")
        await pause(2)
        await say("Which wrist hurts?", "indicate_right_wrist")
        await pause(0.6)
        SmokeLog.mark("STEP 04-indicating")
        await pause(3.5)

        await examine("left_wrist")
        await pause(3.5)
        SmokeLog.mark("STEP 04-pain")
        await examine("right_anatomical_snuffbox")
        await pause(3)
        SmokeLog.mark("after recoil state=\(model.behavior.state.rawValue) \(state())")
        await pause(2)

        SmokeLog.mark("STEP 05-killwindow") // the script may kill the backend here
        await pause(8)
        await examine("right_distal_forearm")
        await pause(3)

        // Orthotics lab: the same drop/snap path a drag uses, driven by commands.
        func drop(_ item: String, _ axialCm: Double, _ radialCm: Double) async {
            model.selectedTool = item
            await pause(0.8)
            model.labCommand = LabCommand(item: item, axialCm: axialCm, radialCm: radialCm)
            await pause(1.5)
        }
        await model.fittingCheck("neurovascular") // before immobilising
        await pause(2.5)
        SmokeLog.mark("STEP 05-lab-0-tray")
        await pause(2)
        await drop(OrthoticsLab.tapeName, 1, 3)
        SmokeLog.mark("STEP 05-lab-1-measure-wrist")
        await pause(2.5)
        await drop(OrthoticsLab.tapeName, 14, 3)
        SmokeLog.mark("STEP 05-lab-2-measure-forearm")
        await pause(2.5)
        await drop(OrthoticsLab.orthosisPrefix + "large", 3, 30) // dragged, let go too far from the arm
        SmokeLog.mark("missed drop fit=\(model.fit == nil ? "none" : "SET")")
        model.selectedTool = OrthoticsLab.orthosisPrefix + "large"
        await pause(1.5)
        SmokeLog.mark("STEP 05-lab-2-selected")
        await pause(2)
        // select-then-pinch path: same placement call the forearm pinch makes
        model.labCommand = LabCommand(item: OrthoticsLab.orthosisPrefix + "large", axialCm: 3, radialCm: 0, via: "pinch")
        model.selectedTool = nil
        await pause(3.5) // nobody asks: the patient speaks up about the loose fit
        await model.stepTightness(1) // same complaint again: must stay quiet
        await pause(2.5)
        await model.fittingCheck("comfort")
        await pause(1.5)
        SmokeLog.mark("STEP 05-lab-3-too-large")
        await pause(2.5)
        await drop(OrthoticsLab.orthosisPrefix + "medium", 3, 2)
        await model.stepTightness(1) // continuous adjustment: one remark at the end, not three
        await pause(0.3)
        await model.stepTightness(1)
        await pause(3.5)
        SmokeLog.mark("STEP 05-lab-4-too-tight")
        await pause(2.5)
        await model.stepTightness(-1)
        await model.fittingCheck("neurovascular")
        await pause(2.5)
        await model.fittingCheck("comfort")
        await pause(1.5)
        SmokeLog.mark("fitted \(model.fit.map { "\($0.size) \($0.tightness) \($0.orientation) \($0.offsetCm)cm" } ?? "none") "
            + "state=\(model.behavior.state.rawValue) \(state())")
        SmokeLog.mark("STEP 05-lab-5-fitted")
        await pause(2.5)

        model.recenter()
        await pause(2)
        SmokeLog.mark("recentered token=\(model.recenterToken)")

        await model.loadFeedback()
        SmokeLog.mark("pre-diagnosis feedback verdict=\(model.feedback?.diagnosticAssessment.verdict ?? "?") "
            + "criteria=\(model.feedback?.categories.map(\.criteria.count) ?? [])")
        // Investigation: ordered by voice (or the same hook), result opens in the viewer.
        await order("I would like to order an X-ray of his right wrist.", "right_wrist_xray")
        await pause(2)
        SmokeLog.mark("viewer open=\(model.viewing?.investigationId ?? "none") notebook=\(model.notebookOpen) \(state())")
        SmokeLog.mark("STEP 05-xray-viewer")
        await pause(3)
        model.viewerZoom = 2.5
        await pause(1.5)
        SmokeLog.mark("STEP 05-xray-zoom")
        await pause(3)
        model.closeViewer()
        await pause(1.5)
        SmokeLog.mark("viewer closed=\(model.viewing == nil) tab=\(model.notebookTab.rawValue) \(state())")
        SmokeLog.mark("STEP 05-investigations")
        await pause(3)
        model.notebookTab = .history

        // The learner documents the case and formulates the diagnosis in the notebook.
        model.setNotebookOpen(true)
        model.notes.history = "Fell off bicycle yesterday, landed on outstretched right hand. Pain worse on gripping."
        await pause(2)
        SmokeLog.mark("notebook open=\(model.notebookOpen) \(state())")
        SmokeLog.mark("STEP 06-notebook-history")
        await pause(3)
        model.notebookTab = .examination
        // "Sensation normal" was never asked: the feedback must flag it as unsupported.
        model.notes.examination = "Tender at the base of the right thumb. Right forearm and left wrist not tender. Sensation normal."
        await pause(1.5)
        SmokeLog.mark("STEP 07-notebook-examination")
        await pause(3)
        model.notebookTab = .assessment
        model.diagnosis = "Suspected scaphoid fracture"
        model.notes.interpretation = "X-ray shows no fracture, but an occult scaphoid fracture cannot be excluded."
        model.notes.management = "Thumb spica splint and analgesia."
        model.notes.followUp = "MRI of the wrist, or review in the fracture clinic in 10 days."
        await pause(1.5)
        SmokeLog.mark("STEP 08-notebook-assessment")
        await pause(3)
        await model.submitDiagnosis()
        let f = model.feedback
        SmokeLog.mark("diagnosed score=\(f?.totalScore ?? -1)/\(f?.maxScore ?? -1) verdict=\(f?.diagnosticAssessment.verdict ?? "?") "
            + "categories=\(f?.categories.map { "\($0.id):\($0.score)" } ?? []) "
            + "management=\(f?.management.score ?? -1)/\(f?.management.maxScore ?? -1) "
            + "fitting=\(f?.fitting.score ?? -1)/\(f?.fitting.maxScore ?? -1) "
            + "\(f?.management.criteria.map { "\($0.id):\($0.met)" } ?? []) "
            + "notes=\(f?.documentation.map { "\($0.criterionId):\($0.status)" } ?? []) \(state())")
        await pause(1.5)
        SmokeLog.mark("STEP 09-feedback")
        await pause(4)
        model.startReplay()
        await pause(2)
        SmokeLog.mark("STEP 09-replay-1")
        await pause(2.5)
        model.replayStep = 1 // the painful snuffbox palpation
        await pause(1.5)
        SmokeLog.mark("STEP 09-replay-2-snuffbox")
        await pause(2.5)
        model.showAnatomy = false
        model.replayStep = model.replayStepCount - 1
        await pause(1.5)
        SmokeLog.mark("STEP 09-replay-support")
        await pause(2.5)
        model.showAnatomy = true
        await pause(1.5)
        SmokeLog.mark("STEP 09-teaching-anatomy")
        await pause(2.5)
        model.exitReplay()
        SmokeLog.mark("replay exited teaching=\(model.teachingMode) notebook=\(model.notebookOpen)")
        await pause(1)

        await model.reset()
        await pause(2)
        SmokeLog.mark("reset feedback=\(model.feedback == nil ? "cleared" : "STILL SET") notes=\(model.notes == ClinicalNotes() ? "blank" : "KEPT") \(state())")
        SmokeLog.mark("STEP 10-reset")
        await pause(3)
        // New encounter: a report-only study, requested from the notebook button path.
        await model.orderInvestigation("right_wrist_mri")
        await pause(2)
        SmokeLog.mark("STEP 10-mri-report")
        await pause(3)

        await model.stopSession()
        if immersed { await dismissImmersiveSpace(); immersed = false }
        SmokeLog.mark("STEP 11-stopped")
        SmokeLog.mark("DONE")
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
