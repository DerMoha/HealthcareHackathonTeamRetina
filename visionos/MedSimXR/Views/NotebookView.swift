import SwiftUI

/// A notebook-sized glass page.
struct NotebookPage: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(24).frame(width: 720, height: 700, alignment: .top).glassBackgroundEffect()
    }
}

/// The clinical notebook that floats next to the patient. Closed it is a single button;
/// open it holds the learner's notes, the conversation, the diagnosis and, after
/// submission, the feedback. While it is open the patient's microphone is muted.
struct NotebookView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.session == nil {
            EmptyView()
        } else if model.notebookOpen {
            notebook.modifier(NotebookPage())
        } else {
            Button { model.setNotebookOpen(true) } label: {
                VStack(spacing: 8) {
                    Image(systemName: "book.closed.fill").font(.system(size: 46))
                    Text("Notebook").font(.headline)
                }
                .padding(22)
            }
            .buttonBorderShape(.roundedRectangle(radius: 24))
            .glassBackgroundEffect()
        }
    }

    /// The open result, in its own movable panel so the learner can read it while writing notes.
    struct ViewerPanel: View {
        @Environment(AppModel.self) private var model

        var body: some View {
            if let result = model.viewing, model.phase == .running {
                RadiologyViewer(result: result).modifier(NotebookPage())
            }
        }
    }

    private var notebook: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "book.fill").foregroundStyle(.teal)
                Text("Clinical notebook").font(.title3.bold())
                Spacer()
                if model.isBusy { ProgressView() }
                Button("Close") { model.setNotebookOpen(false) }
            }
            if model.phase == .feedback, model.feedback != nil {
                FeedbackView()
            } else {
                Picker("Section", selection: $model.notebookTab) {
                    ForEach(NotebookTab.tabs(ultrasound: model.isUltrasound, journey: model.journey != nil)) {
                        Text($0.title(ultrasound: model.isUltrasound)).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                if model.voice.status == .connected {
                    Label("Note-taking mode: the patient cannot hear you while the notebook is open.", systemImage: "mic.slash.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                switch model.notebookTab {
                case .team:
                    JourneyPanel()
                case .history:
                    summaryDraft
                    editor($model.notes.history, "What did the patient tell you?", id: "history")
                case .examination:
                    if model.isUltrasound {
                        recordedScans
                        editor($model.notes.examination, "Which views did you obtain, and what do the images and measurements show?", id: "examination")
                    } else {
                        recorded
                        editor($model.notes.examination, "What did you examine, and what did you find?", id: "examination")
                    }
                case .investigations:
                    investigations
                case .assessment where model.isUltrasound:
                    field($model.diagnosis, "Overall impression")
                    editor($model.notes.assessment, "Summary of the findings and what you told the patient", id: "assessment")
                    Button { Task { await model.submitDiagnosis() } } label: {
                        Label("Submit impression", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(model.diagnosis.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
                case .assessment:
                    field($model.diagnosis, "Suspected diagnosis")
                    editor($model.notes.interpretation, "Interpretation of investigations", id: "interpretation")
                    editor($model.notes.management, "Immediate management", id: "management")
                    editor($model.notes.followUp, "Further imaging or follow-up plan", id: "followUp")
                    Button { Task { await model.submitDiagnosis() } } label: {
                        Label("Submit diagnosis and plan", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(model.diagnosis.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
                case .conversation:
                    conversation
                }
            }
            if let message = model.dictation.message {
                Label(message, systemImage: "mic.badge.xmark").font(.footnote).foregroundStyle(.orange)
            }
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
            }
        }
        // Leaving a page ends its recording; what was said is still written into the note.
        .onChange(of: model.notebookTab) { Task { await model.dictation.stop() } }
        .onDisappear { Task { await model.dictation.stop() } }
    }

    /// Every investigation the case offers, in a fixed order and without advice, then the
    /// results received so far. Also the fallback when the voice tool is unavailable.
    private var investigations: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Request an investigation").font(.subheadline).foregroundStyle(.secondary)
            ForEach(model.availableInvestigations) { item in
                Button { Task { await model.orderInvestigation(item.id) } } label: {
                    Label(item.label, systemImage: "plus.circle").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered).disabled(model.phase != .running)
            }
            if let stage = model.currentStage, model.availableInvestigations.isEmpty {
                Text("No investigations can be requested \(stage.label.lowercased()).").foregroundStyle(.tertiary)
            }
            Text("Results").font(.subheadline).foregroundStyle(.secondary).padding(.top, 6)
            if model.investigationResults.isEmpty {
                Text("Nothing requested yet.").foregroundStyle(.tertiary)
            }
            ForEach(model.investigationResults) { result in
                HStack {
                    Image(systemName: "doc.text.image").foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.label).fontWeight(.medium)
                        Text("Requested \(result.orderedAt)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("View result") { model.show(result) }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Free-text note with a Dictate button beside its title. Dictated text is appended to
    /// the note; the system keyboard's dictation key also still works.
    private func editor(_ text: Binding<String>, _ prompt: String, id: String) -> some View {
        let active = model.dictation.isActive(id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(prompt).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                DictateButton(id: id, text: text)
            }
            TextEditor(text: text)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    if active {
                        RoundedRectangle(cornerRadius: 14).stroke(.red.opacity(0.8), lineWidth: 2)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty && !active {
                        Text("Tap Dictate and speak, or tap here to type")
                            .foregroundStyle(.tertiary).padding(16).allowsHitTesting(false)
                    }
                }
            if active { DictationStatus() }
        }
        .frame(maxHeight: .infinity)
    }

    /// ElevenLabs' post-call summary of the conversation. Shown as a draft; only the learner
    /// puts it into the notes, so the documentation feedback still reflects their own notes.
    @ViewBuilder
    private var summaryDraft: some View {
        switch model.summaryState {
        case .idle:
            if model.phase == .running, model.voice.status == .connected {
                VStack(alignment: .leading, spacing: 4) {
                    Button { model.endConsultation() } label: {
                        Label("End consultation and draft a summary", systemImage: "text.bubble")
                    }
                    .buttonStyle(.bordered)
                    Text("Ends the conversation with the patient. ElevenLabs then drafts a summary for you to review.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case .waiting:
            HStack(spacing: 8) {
                ProgressView()
                Text("ElevenLabs is summarising the conversation…").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.discardSummary() }
            }
        case .ready(let text):
            VStack(alignment: .leading, spacing: 8) {
                Label("AI-generated draft. Check it against what the patient said before you use it.",
                      systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.orange)
                ScrollView { Text(text).font(.callout).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 150)
                HStack {
                    Button("Insert into history notes") { model.insertSummary() }
                        .buttonStyle(.borderedProminent).tint(.teal)
                    Button("Discard") { model.discardSummary() }
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        case .failed(let reason):
            HStack(spacing: 8) {
                Label(reason, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                Spacer()
                Button("Try again") { model.endConsultation() }
                Button("Dismiss") { model.discardSummary() }
            }
        }
    }

    /// One-line field (diagnosis) with a compact Dictate button.
    private func field(_ text: Binding<String>, _ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(prompt, text: text).textFieldStyle(.roundedBorder)
                DictateButton(id: "diagnosis", text: text, compact: true)
            }
            if model.dictation.isActive("diagnosis") { DictationStatus() }
        }
    }

    /// What was actually examined, in neutral words: the area and what the patient said.
    @ViewBuilder
    private var recorded: some View {
        if !model.examinations.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recorded examinations").font(.subheadline).foregroundStyle(.secondary)
                ForEach(Array(model.examinations.enumerated()), id: \.offset) { _, exam in
                    HStack(alignment: .top) {
                        Image(systemName: "hand.point.up.left.fill").foregroundStyle(.teal)
                        Text(model.zones.first { $0.id == exam.bodyPart }?.label ?? exam.bodyPart).fontWeight(.medium)
                        Text("\u{201C}\(exam.patientResponse)\u{201D}").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    /// What was actually scanned, in neutral words: no view names, so nothing is filled in for the learner.
    @ViewBuilder
    private var recordedScans: some View {
        if model.gelApplied || !model.scanLog.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recorded").font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Image(systemName: "drop.fill").foregroundStyle(model.gelApplied ? .teal : .orange)
                    Text(model.gelApplied ? "Gel applied" : "No gel applied yet").fontWeight(.medium)
                }
                .font(.callout)
                ForEach(Array(model.scanLog.enumerated()), id: \.offset) { _, scan in
                    HStack(alignment: .top) {
                        Image(systemName: scan.quality == "good" ? "waveform.path.ecg" : "exclamationmark.triangle.fill")
                            .foregroundStyle(scan.quality == "good" ? .teal : .orange)
                        Text(model.ultrasound?.regions.first { $0.id == scan.regionId }?.label ?? scan.regionId).fontWeight(.medium)
                        Text(scan.quality == "good" ? "image obtained" : "no usable image").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var conversation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if model.transcript.isEmpty {
                    Text("Nothing said yet.").foregroundStyle(.secondary)
                }
                ForEach(model.transcript) { turn in
                    HStack(alignment: .top, spacing: 8) {
                        Text(turn.role == .learner ? "You" : "Patient")
                            .font(.caption.bold())
                            .foregroundStyle(turn.role == .learner ? .teal : .orange)
                            .frame(width: 56, alignment: .leading)
                        Text(turn.text).font(.callout)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Mic button for one note: tap to start, tap again to stop and write the words into the note.
private struct DictateButton: View {
    @Environment(AppModel.self) private var model
    let id: String
    @Binding var text: String
    var compact = false

    var body: some View {
        let dictation = model.dictation
        let recording = dictation.state == .recording && dictation.target == id
        let transcribing = dictation.state == .transcribing && dictation.target == id
        Button {
            Task {
                await dictation.toggle(id) { words in
                    let needsSpace = !(text.last?.isWhitespace ?? true)
                    text += (needsSpace ? " " : "") + words
                }
            }
        } label: {
            if transcribing {
                HStack(spacing: 6) { ProgressView().controlSize(.small); if !compact { Text("Writing…") } }
            } else if recording {
                Label(compact ? "Stop" : "Stop dictating", systemImage: "stop.circle.fill")
            } else if compact {
                Image(systemName: "mic.fill")
            } else {
                Label("Dictate", systemImage: "mic.fill")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(recording ? .red : .teal)
        .disabled(dictation.state == .transcribing || model.phase != .running)
        .help(recording ? "Stop and write it into the note" : "Dictate into this note")
        .accessibilityLabel(recording ? "Stop dictating" : "Dictate into \(id)")
    }
}

/// Shown under the note being dictated into: listening time, or that the words are on their way.
private struct DictationStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let dictation = model.dictation
        if dictation.state == .recording, let start = dictation.startedAt {
            TimelineView(.periodic(from: start, by: 1)) { context in
                let seconds = max(0, Int(context.date.timeIntervalSince(start)))
                Label("Listening \(seconds / 60):\(String(format: "%02d", seconds % 60)). Tap Stop when you are done. The patient cannot hear you.",
                      systemImage: "waveform")
                    .symbolEffect(.variableColor.iterative)
                    .font(.caption).foregroundStyle(.red)
            }
        } else if dictation.state == .transcribing {
            Label("Writing your words into the note…", systemImage: "text.badge.plus")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

