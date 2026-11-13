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
                    ForEach(NotebookTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if model.voice.status == .connected {
                    Label("Note-taking mode: the patient cannot hear you while the notebook is open.", systemImage: "mic.slash.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                switch model.notebookTab {
                case .history:
                    editor($model.notes.history, "What did the patient tell you?")
                case .examination:
                    recorded
                    editor($model.notes.examination, "What did you examine, and what did you find?")
                case .investigations:
                    investigations
                case .assessment:
                    TextField("Suspected diagnosis", text: $model.diagnosis)
                        .textFieldStyle(.roundedBorder)
                    editor($model.notes.interpretation, "Interpretation of investigations")
                    editor($model.notes.management, "Immediate management")
                    editor($model.notes.followUp, "Further imaging or follow-up plan")
                    Button { Task { await model.submitDiagnosis() } } label: {
                        Label("Submit diagnosis and plan", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(model.diagnosis.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
                case .conversation:
                    conversation
                }
            }
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
            }
        }
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

    /// Free-text note. The system keyboard's dictation key gives speech-to-text.
    private func editor(_ text: Binding<String>, _ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prompt).font(.subheadline).foregroundStyle(.secondary)
            TextEditor(text: text)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text("Tap to type or dictate").foregroundStyle(.tertiary).padding(16).allowsHitTesting(false)
                    }
                }
        }
        .frame(maxHeight: .infinity)
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
