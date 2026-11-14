import SwiftUI

/// The clinical notebook that floats next to the patient. Closed it is a single button;
/// open it holds the learner's notes, the conversation, the diagnosis and, after
/// submission, the feedback. While it is open the patient's microphone is muted.
struct NotebookView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.session == nil {
            EmptyView()
        } else if model.notebookOpen {
            page
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

    @ViewBuilder
    private var page: some View {
        if let result = model.viewing, model.phase == .running {
            RadiologyViewer(result: result).modifier(Page())
        } else {
            notebook.modifier(Page())
        }
    }

    private struct Page: ViewModifier {
        func body(content: Content) -> some View {
            content.padding(24).frame(width: 720, height: 700, alignment: .top).glassBackgroundEffect()
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
                    ForEach(NotebookTab.tabs(ultrasound: model.isUltrasound)) { Text($0.title(ultrasound: model.isUltrasound)).tag($0) }
                }
                .pickerStyle(.segmented)
                if model.voice.status == .connected {
                    Label("Note-taking mode: the patient cannot hear you while the notebook is open.", systemImage: "mic.slash.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                ConsultationBar()
                switch model.notebookTab {
                case .history:
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
            ForEach(model.session?.case.investigations ?? []) { item in
                Button { Task { await model.orderInvestigation(item.id) } } label: {
                    Label(item.label, systemImage: "plus.circle").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered).disabled(model.phase != .running)
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
                DictateButton(id: id)
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
            if model.lastTidy?.field == id { TidyStatus() }
        }
        .frame(maxHeight: .infinity)
    }

    /// One-line field (diagnosis) with a compact Dictate button.
    private func field(_ text: Binding<String>, _ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(prompt, text: text).textFieldStyle(.roundedBorder)
                DictateButton(id: "diagnosis", compact: true)
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

    /// The full conversation, for reference. Not selectable, so it cannot be copied into the notes;
    /// the debrief compares the notes with it.
    private var conversation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label("For reference only. Your notes are what you chose to write down; the debrief compares them with this conversation.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
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
            .textSelection(.disabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// End the conversation for good, or resume one that was paused to save credits.
private struct ConsultationBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.phase == .running, !model.consultationEnded {
            if let pause = model.voicePause {
                HStack(spacing: 8) {
                    Label(pause == .notebook
                          ? "Conversation paused to save credits. It continues when you close the notebook."
                          : "Conversation paused after a quiet spell, to save credits.",
                          systemImage: "pause.circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if pause == .idle { Button("Resume") { Task { await model.resumeVoice() } } }
                }
            } else if model.voice.status == .connected {
                HStack {
                    Spacer()
                    Button { Task { await model.endConsultation() } } label: {
                        Label("End consultation", systemImage: "phone.down.fill")
                    }
                    .buttonStyle(.bordered)
                    .help("Ends the conversation with the patient. Notes, examination and diagnosis still work.")
                }
            }
        }
    }
}

/// What the AI tidy did to the last dictation into this note, with Undo.
private struct TidyStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.lastTidy?.status {
        case .pending:
            Label("Tidying your words…", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
        case .tidied:
            HStack(spacing: 8) {
                Label("Tidied by AI. Check it still says what you meant.", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.teal)
                Button("Undo") { model.undoTidy() }.font(.caption)
            }
        case .kept(let note):
            Label(note, systemImage: "text.quote").font(.caption).foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }
}

/// Mic button for one note: tap to start, tap again to stop and write the words into the note.
private struct DictateButton: View {
    @Environment(AppModel.self) private var model
    let id: String
    var compact = false

    var body: some View {
        let dictation = model.dictation
        let recording = dictation.state == .recording && dictation.target == id
        let transcribing = dictation.state == .transcribing && dictation.target == id
        Button {
            Task {
                await dictation.toggle(id) { words in
                    Task { await model.dictated(words, into: id) }
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
            VStack(alignment: .leading, spacing: 6) {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    let seconds = max(0, Int(context.date.timeIntervalSince(start)))
                    Label("Listening \(seconds / 60):\(String(format: "%02d", seconds % 60)). Tap Stop when you are done. The patient cannot hear you.",
                          systemImage: "waveform")
                        .symbolEffect(.variableColor.iterative)
                        .font(.caption).foregroundStyle(.red)
                }
                if dictation.engine == .live {
                    Text(dictation.partial.isEmpty ? "Speak now…" : dictation.partial)
                        .font(.callout)
                        .foregroundStyle(dictation.partial.isEmpty ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .animation(.default, value: dictation.partial)
                }
            }
        } else if dictation.state == .transcribing {
            Label("Writing your words into the note…", systemImage: "text.badge.plus")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

