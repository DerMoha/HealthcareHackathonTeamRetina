import SwiftUI

/// A notebook-sized glass page (also the radiology viewer's page).
struct NotebookPage: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(24).frame(width: 720, height: 700, alignment: .top).glassBackgroundEffect()
    }
}

/// The notebook's colours, shared by its pages and the debrief: teal is the learner, orange the
/// patient, blue the team, indigo the replay; green, orange and red grade a score.
enum NoteTone {
    static let learner = Color.teal
    static let patient = Color.orange
    static let team = Color.blue
    static let replay = Color.indigo
    static func score(_ fraction: Double) -> Color { fraction >= 0.75 ? .green : fraction >= 0.5 ? .orange : .red }
    /// A score's bar or ring: a good score runs from the learner's teal into green.
    static func scoreRamp(_ fraction: Double) -> [Color] { fraction >= 0.75 ? [learner, .green] : [score(fraction).opacity(0.6), score(fraction)] }
}

/// A rounded card on the notebook glass: a slightly lighter layer with a hairline edge.
struct NoteCard: ViewModifier {
    var padding: CGFloat = 18
    var tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(.white.opacity(0.07))
                if let tint { shape.fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)) }
            }
            .overlay { shape.strokeBorder(.white.opacity(0.10), lineWidth: 1) }
    }
}

extension View {
    func noteCard(padding: CGFloat = 18, tint: Color? = nil) -> some View { modifier(NoteCard(padding: padding, tint: tint)) }
}

/// A round badge with someone's initials.
struct NoteAvatar: View {
    let name: String
    var color: Color
    var size: CGFloat = 44

    var body: some View {
        let letters = name.split(separator: " ").filter { $0.first?.isLetter ?? false }.prefix(2).compactMap(\.first)
        Text(String(letters))
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .top, endPoint: .bottom)))
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
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
            notebook // pitch: larger, so the debrief's mark scheme fits on one page
                .frame(width: SmokeLog.pitch ? (inFeedback ? 1240 : 960) : 880, height: SmokeLog.pitch ? (inFeedback ? 1100 : 900) : 760, alignment: .top)
                .glassBackgroundEffect()
        } else if SmokeLog.pitch {
            EmptyView() // pitch shots: no closed-notebook button in the picture
        } else {
            Button { model.setNotebookOpen(true) } label: {
                VStack(spacing: 8) {
                    Image(systemName: "book.closed.fill").font(.system(size: 46)).foregroundStyle(NoteTone.learner)
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

    private var inFeedback: Bool { model.phase == .feedback && model.feedback != nil }

    private var notebook: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 30).padding(.top, 26).padding(.bottom, 20)
            Divider().opacity(0.6)
            if inFeedback {
                FeedbackView().padding(.horizontal, 30).padding(.top, 20)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    rail
                    Divider().opacity(0.6)
                    page.padding(.horizontal, 28).padding(.vertical, 22)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        // Leaving a page ends its recording; what was said is still written into the note.
        .onChange(of: model.notebookTab) { Task { await model.dictation.stop() } }
        .onDisappear { Task { await model.dictation.stop() } }
    }

    // MARK: Header and tabs

    private var header: some View {
        let c = model.session?.case, patient = c?.patient
        // The setting, or the case title when it does not just repeat the patient's name.
        let place = c?.catalog?.setting ?? c.flatMap { $0.title.contains($0.patient.name) ? nil : $0.title }
        return HStack(spacing: 16) {
            NoteAvatar(name: patient?.name ?? "Patient", color: NoteTone.patient, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(inFeedback ? "Debrief" : "Clinical notebook").font(.title2.weight(.bold))
                Text([patient.map { "\($0.name), \($0.age)" }, place].compactMap { $0 }.joined(separator: "  ·  "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            if model.isBusy { ProgressView() }
            if model.voice.status == .connected, !inFeedback {
                Label("Patient can't hear you", systemImage: "mic.slash.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(NoteTone.patient)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(NoteTone.patient.opacity(0.16), in: Capsule())
                    .help("Note-taking mode: the patient cannot hear you while the notebook is open.")
            }
            Button { model.setNotebookOpen(false) } label: { Image(systemName: "xmark") }
                .buttonBorderShape(.circle)
                .accessibilityLabel("Close notebook")
        }
    }

    private var tabs: [NotebookTab] { NotebookTab.tabs(ultrasound: model.isUltrasound, journey: model.journey != nil) }

    private func icon(_ tab: NotebookTab) -> String {
        switch tab {
        case .team: "person.3.fill"
        case .history: "text.bubble.fill"
        case .examination: model.isUltrasound ? "waveform.path.ecg.rectangle.fill" : "stethoscope"
        case .investigations: "doc.text.image.fill"
        case .assessment: "list.bullet.clipboard.fill"
        case .conversation: "quote.bubble.fill"
        }
    }

    /// A small count beside a tab: what has piled up there.
    private func badge(_ tab: NotebookTab) -> Int {
        switch tab {
        case .team: model.teamLog.count
        case .investigations: model.investigationResults.count
        case .conversation: model.transcript.count
        default: 0
        }
    }

    private var rail: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 6) {
            Text("SECTIONS").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(.tertiary)
                .padding(.horizontal, 14).padding(.bottom, 4)
            ForEach(tabs) { tab in
                let selected = model.notebookTab == tab
                Button { model.notebookTab = tab } label: {
                    HStack(spacing: 12) {
                        Image(systemName: icon(tab)).font(.body.weight(.semibold))
                            .foregroundStyle(selected ? NoteTone.learner : .secondary).frame(width: 26)
                        Text(tab.title(ultrasound: model.isUltrasound)).font(.body.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? .primary : .secondary).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        if badge(tab) > 0 {
                            Text("\(badge(tab))").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NoteTone.learner.opacity(0.22))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .hoverEffect()
            }
            Spacer(minLength: 0)
            if SmokeLog.pitch { pitchOwnership }
            if model.phase == .running, model.voice.status == .paused {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Patient paused to save credits.", systemImage: "pause.circle").font(.caption).foregroundStyle(.secondary)
                    Button("Talk to patient") { Task { await model.talkToPatient() } }.buttonStyle(.bordered)
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 22)
        .frame(width: 250)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Pages

    private func pageTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.bold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var page: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 16) {
            switch model.notebookTab {
            case .team:
                TeamPage()
            case .history:
                pageTitle("History", "What the patient told you, in your own words.")
                summaryDraft
                editor($model.notes.history, "History notes", icon: "text.bubble", id: "history")
            case .examination:
                if model.isUltrasound {
                    pageTitle("Scan findings", "The views you obtained and what the images and measurements show.")
                    if SmokeLog.pitch { pitchScanViews } else { recordedScans }
                    editor($model.notes.examination, "Findings", icon: "waveform.path.ecg", id: "examination")
                } else {
                    pageTitle("Examination", "What you examined, and what you found.")
                    recorded
                    editor($model.notes.examination, "Examination notes", icon: "stethoscope", id: "examination")
                }
            case .investigations:
                investigations
            case .assessment where model.isUltrasound:
                pageTitle("Impression", "Your overall impression and what you told the patient.")
                field($model.diagnosis, "Overall impression")
                editor($model.notes.assessment, "Summary and explanation to the patient", icon: "person.wave.2", id: "assessment")
                submit("Submit impression")
            case .assessment:
                pageTitle("Assessment and plan", "Commit to a diagnosis, then plan what happens next.")
                field($model.diagnosis, "Suspected diagnosis")
                editor($model.notes.interpretation, "Interpretation of investigations", icon: "doc.text.magnifyingglass", id: "interpretation")
                if SmokeLog.pitch { pitchTidy } else {
                    editor($model.notes.management, "Immediate management", icon: "cross.case", id: "management")
                }
                editor($model.notes.followUp, "Further imaging or follow-up plan", icon: "calendar.badge.clock", id: "followUp")
                submit("Submit diagnosis and plan")
            case .conversation:
                pageTitle("Transcript", "Everything said in this encounter.")
                conversation
            }
            if let message = model.dictation.message {
                Label(message, systemImage: "mic.badge.xmark").font(.footnote).foregroundStyle(.orange)
            }
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func submit(_ title: String) -> some View {
        Button { Task { await model.submitDiagnosis() } } label: {
            Label(title, systemImage: "checkmark.seal.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent).tint(NoteTone.learner).controlSize(.large)
        .disabled(model.diagnosis.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
    }

    /// Every investigation the case offers, in a fixed order and without advice, then the
    /// results received so far. Also the fallback when the voice tool is unavailable.
    private var investigations: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageTitle("Investigations", "Request what you need. Results arrive here.")
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Request an investigation")
                ForEach(model.availableInvestigations) { item in
                    Button { Task { await model.orderInvestigation(item.id) } } label: {
                        Label(item.label, systemImage: "plus.circle.fill").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered).disabled(model.phase != .running)
                }
                if let stage = model.currentStage, model.availableInvestigations.isEmpty {
                    Text("No investigations can be requested \(stage.label.lowercased()).").foregroundStyle(.tertiary)
                }
            }
            .noteCard()
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Results")
                if model.investigationResults.isEmpty {
                    Text("Nothing requested yet.").foregroundStyle(.tertiary)
                }
                ForEach(model.investigationResults) { result in
                    HStack(spacing: 14) {
                        Image(systemName: "doc.text.image.fill").font(.title3).foregroundStyle(NoteTone.learner)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.label).font(.body.weight(.semibold))
                            Text("Requested \(result.orderedAt)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("View result") { model.show(result) }
                    }
                }
            }
            .noteCard()
            Spacer(minLength: 0)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
    }

    /// Free-text note with a Dictate button beside its title. Dictated text is appended to
    /// the note; the system keyboard's dictation key also still works.
    private func editor(_ text: Binding<String>, _ title: String, icon: String, id: String) -> some View {
        let live = SmokeLog.pitch && id == "followUp" // pitch: this note is being dictated
        let active = model.dictation.isActive(id) || live
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(NoteTone.learner)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if live {
                    Label("Stop dictating", systemImage: "stop.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(.red.opacity(0.85), in: Capsule())
                } else {
                    DictateButton(id: id, text: text)
                }
            }
            if SmokeLog.pitch, !text.wrappedValue.isEmpty { // pitch: static text, a squeezed TextEditor clips its line
                Text(text.wrappedValue + (live ? " |" : "")).font(.body).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 9)
            } else {
                TextEditor(text: text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .overlay(alignment: .topLeading) {
                        if text.wrappedValue.isEmpty && !active {
                            Text("Tap Dictate and speak, or tap here to type")
                                .foregroundStyle(.tertiary).padding(.horizontal, 9).padding(.vertical, 8).allowsHitTesting(false)
                        }
                    }
            }
            if live {
                Label("Listening 0:07  ·  your words go into this note. The patient cannot hear you.", systemImage: "waveform")
                    .symbolEffect(.variableColor.iterative).font(.caption.weight(.medium)).foregroundStyle(.red)
            } else if active { DictationStatus() }
            else if SmokeLog.pitch, !text.wrappedValue.isEmpty { pitchByYou(id == "interpretation" ? "Dictated by you  ·  10:41" : model.isUltrasound && id == "examination" ? "Dictated by you while scanning  ·  14:22" : "Written by you") }
        }
        .noteCard(padding: 14)
        .overlay {
            if active {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.red.opacity(0.8), lineWidth: 2)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// ElevenLabs' post-call summary of the conversation. Shown as a draft; only the learner
    /// puts it into the notes, so the documentation feedback still reflects their own notes.
    @ViewBuilder
    private var summaryDraft: some View {
        switch model.summaryState {
        case .idle:
            if model.phase == .running, model.voice.status == .connected || model.voice.status == .paused {
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
                        .buttonStyle(.borderedProminent).tint(NoteTone.learner)
                    Button("Discard") { model.discardSummary() }
                }
            }
            .noteCard(padding: 14, tint: .orange)
        case .failed(let reason):
            HStack(spacing: 8) {
                Label(reason, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                Spacer()
                Button("Try again") { model.endConsultation() }
                Button("Dismiss") { model.discardSummary() }
            }
        }
    }

    /// One-line field (diagnosis) with a compact Dictate button, set large: it is the answer.
    private func field(_ text: Binding<String>, _ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(prompt)
            HStack(spacing: 12) {
                TextField(prompt, text: text)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                DictateButton(id: "diagnosis", text: text, compact: true)
            }
            if SmokeLog.pitch { pitchByYou("Your diagnosis  ·  typed 10:40") }
            if model.dictation.isActive("diagnosis") { DictationStatus() }
        }
        .noteCard(padding: 16, tint: NoteTone.learner)
    }

    /// What was actually examined, in neutral words: the area and what the patient said.
    @ViewBuilder
    private var recorded: some View {
        if !model.examinations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Recorded examinations")
                ForEach(Array(model.examinations.enumerated()), id: \.offset) { _, exam in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "hand.point.up.left.fill").foregroundStyle(NoteTone.learner)
                        Text(model.zones.first { $0.id == exam.bodyPart }?.label ?? exam.bodyPart).fontWeight(.semibold)
                        Text("\u{201C}\(exam.patientResponse)\u{201D}").foregroundStyle(NoteTone.patient.opacity(0.9))
                    }
                    .font(.callout)
                }
            }
            .noteCard(padding: 14)
        }
    }

    /// What was actually scanned, in neutral words: no view names, so nothing is filled in for the learner.
    @ViewBuilder
    private var recordedScans: some View {
        if model.gelApplied || !model.scanLog.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Recorded")
                HStack {
                    Image(systemName: "drop.fill").foregroundStyle(model.gelApplied ? NoteTone.learner : .orange)
                    Text(model.gelApplied ? "Gel applied" : "No gel applied yet").fontWeight(.medium)
                }
                .font(.callout)
                ForEach(Array(model.scanLog.enumerated()), id: \.offset) { _, scan in
                    HStack(alignment: .top) {
                        Image(systemName: scan.quality == "good" ? "waveform.path.ecg" : "exclamationmark.triangle.fill")
                            .foregroundStyle(scan.quality == "good" ? NoteTone.learner : .orange)
                        Text(model.ultrasound?.regions.first { $0.id == scan.regionId }?.label ?? scan.regionId).fontWeight(.medium)
                        Text(scan.quality == "good" ? "image obtained" : "no usable image").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
            .noteCard(padding: 14)
        }
    }

    // MARK: Pitch (uinotebook): whose words these are, and the AI tidy the learner approves

    /// The anomaly-scan views the learner froze, with their measurements; one view still to get.
    private var pitchScanViews: some View {
        let views: [(String, String, String?)] = [
            ("Head: transthalamic plane", "BPD 4.61 cm  ·  HC 16.73 cm", "14:06"),
            ("Head: transcerebellar plane", "cerebellum and cisterna magna seen", "14:07"),
            ("Abdomen: stomach and umbilical vein", "AC 13.82 cm  ·  EFW 289 g", "14:11"),
            ("Femur", "FL 3.17 cm", "14:12"),
            ("Heart: four-chamber view", "heart rate 148 bpm", "14:09"),
            ("Spine: sagittal", "vertebrae aligned", "14:14"),
            ("Placenta and liquor", "posterior  ·  deepest pool 5.1 cm", "14:16"),
            ("Heart: outflow tracts", "not yet obtained, fetus lying spine up", nil),
        ]
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                sectionLabel("Views you froze  ·  anomaly scan checklist")
                Spacer()
                Text("7 of 8").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(NoteTone.learner)
            }
            ForEach(views, id: \.0) { name, value, time in
                HStack(spacing: 10) {
                    Image(systemName: time == nil ? "circle.dashed" : "checkmark.circle.fill")
                        .foregroundStyle(time == nil ? .orange : NoteTone.learner).frame(width: 22)
                    Text(name).font(.callout.weight(.semibold))
                    Text(value).font(.callout).foregroundStyle(time == nil ? .orange : .secondary).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(time.map { "frozen \($0)" } ?? "to do").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
        }
        .noteCard(padding: 14)
    }

    private func pitchByYou(_ text: String) -> some View {
        Label(text, systemImage: "person.crop.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(NoteTone.learner)
    }

    private var pitchOwnership: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Your notebook", systemImage: "person.crop.circle.badge.checkmark").font(.subheadline.weight(.semibold))
                .foregroundStyle(NoteTone.learner)
            Text("Only you write here. Dictate or type; AI tidies your words when you ask, and nothing goes in until you accept.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(NoteTone.learner.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// A dictated note with the AI's tidy version beside it, waiting for the learner to accept it.
    private var pitchTidy: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "cross.case").font(.subheadline.weight(.semibold)).foregroundStyle(NoteTone.learner)
                Text("Immediate management").font(.subheadline.weight(.semibold))
                Spacer()
                Label("AI tidy suggestion", systemImage: "sparkles").font(.caption.weight(.bold)).foregroundStyle(.purple)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(.purple.opacity(0.18), in: Capsule())
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("YOU SAID").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(NoteTone.learner).frame(width: 66, alignment: .leading)
                Text("\u{201C}so thumb spica splint and um painkillers, paracetamol and ibuprofen, and come back if it goes numb or gets worse\u{201D}")
                    .font(.callout).foregroundStyle(.secondary).strikethrough(color: .secondary.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("TIDIED").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.purple).frame(width: 66, alignment: .leading)
                Text("Thumb spica splint. Analgesia: paracetamol and ibuprofen. Safety-net: return if numbness or worsening pain.")
                    .font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Text("Your words only, reordered. Nothing added.").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Keep mine") {}.buttonStyle(.bordered).controlSize(.small)
                Button {} label: { Label("Accept", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent).tint(NoteTone.learner).controlSize(.small)
            }
        }
        .noteCard(padding: 14, tint: .purple)
    }

    /// The conversation as chat bubbles: the learner on the right in teal, the patient on the left in orange.
    private var conversation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if model.transcript.isEmpty {
                    Text("Nothing said yet.").foregroundStyle(.secondary)
                }
                ForEach(model.transcript) { turn in
                    let learner = turn.role == .learner
                    let tone = learner ? NoteTone.learner : NoteTone.patient
                    VStack(alignment: learner ? .trailing : .leading, spacing: 4) {
                        Text(learner ? "You" : model.session?.case.patient.name ?? "Patient")
                            .font(.caption.weight(.semibold)).foregroundStyle(tone)
                        Text(turn.text).font(.callout)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(tone.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .frame(maxWidth: .infinity, alignment: learner ? .trailing : .leading)
                    .padding(learner ? .leading : .trailing, 80)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The notebook's Team page in a journey case: where the encounter is, who is there, what the
/// team can be asked to do, the move on, and the team log. Every button calls the same model
/// method as JourneyPanel (and the voice agent's `request_team_action` tool).
private struct TeamPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if SmokeLog.pitch, let journey = model.journey {
            VStack(alignment: .leading, spacing: 16) {
                stepper(journey.stages)
                PitchTeamLog()
            }
        } else if let journey = model.journey, let stage = model.currentStage {
            VStack(alignment: .leading, spacing: 16) {
                stepper(journey.stages)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "location.fill").foregroundStyle(NoteTone.learner)
                        Text(stage.label).font(.title3.weight(.bold))
                        Spacer()
                        HStack(spacing: -8) {
                            ForEach(model.teamPresent) { NoteAvatar(name: $0.name, color: NoteTone.team, size: 34) }
                        }
                    }
                    Text(stage.brief).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(model.teamPresent.map { "\($0.name), \($0.role)" }.joined(separator: "   ·   "))
                        .font(.caption.weight(.medium)).foregroundStyle(NoteTone.team)
                }
                .noteCard(padding: 16)

                Text("ASK THE TEAM").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(stage.actions) { action in actionTile(action, journey) }
                }
                moveButton
                log
            }
        }
    }

    /// The places of the journey, done ones ticked, the current one in teal.
    private func stepper(_ stages: [JourneyStage]) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(stages.enumerated()), id: \.offset) { i, s in
                let done = i < model.stageIndex, current = i == model.stageIndex
                if i > 0 {
                    Capsule().fill(done || current ? NoteTone.learner.opacity(0.8) : .white.opacity(0.15)).frame(height: 3)
                }
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(current ? NoteTone.learner : done ? NoteTone.learner.opacity(0.35) : .white.opacity(0.12))
                        if done { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                        else { Text("\(i + 1)").font(.caption.weight(.bold)) }
                    }
                    .frame(width: 26, height: 26)
                    Text(s.label).font(.footnote.weight(current ? .semibold : .regular))
                        .foregroundStyle(current ? .primary : .secondary).lineLimit(1).fixedSize()
                }
            }
        }
    }

    private func actionTile(_ action: JourneyAction, _ journey: JourneyInfo) -> some View {
        let name = journey.member(action.member)?.name ?? action.member
        let done = model.teamLog.contains { $0.actionId == action.id && $0.done }
        return Button { Task { await model.requestTeamAction(action.id) } } label: {
            HStack(spacing: 12) {
                NoteAvatar(name: name, color: NoteTone.team, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.label).font(.callout.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    Text(name).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: done ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3).foregroundStyle(done ? .green : .secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .disabled(model.phase != .running || model.isBusy || model.journeyBusy)
    }

    @ViewBuilder
    private var moveButton: some View {
        if let next = model.nextStage {
            Button { Task { await model.advanceStage() } } label: {
                Label("Move on: \(next.label)", systemImage: "arrow.right.circle.fill").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(NoteTone.learner).controlSize(.large)
            .disabled(model.phase != .running || model.isBusy || model.journeyBusy)
        } else {
            Label("Last stop. Write your assessment and plan.", systemImage: "flag.checkered")
                .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    /// What the team did, newest first: observations, treatments, and requests they could not do yet.
    private var log: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TEAM LOG").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.teamLog.count) entries").font(.caption).foregroundStyle(.tertiary)
            }
            if model.teamLog.isEmpty {
                Text("Nothing asked yet.").foregroundStyle(.tertiary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.teamLog.reversed()) { logRow($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .noteCard(padding: 16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func logRow(_ r: TeamActionResult) -> some View {
        let place = model.journey?.stages.first { $0.id == r.stageId }?.label ?? r.stageId
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: r.done ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3).foregroundStyle(r.done ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(r.label).font(.callout.weight(.semibold))
                    Text(r.member.name).font(.caption).foregroundStyle(NoteTone.team)
                    Spacer()
                    Text(place).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                Text(r.result ?? r.response).font(.callout).foregroundStyle(.secondary)
            }
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
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(recording ? .red : NoteTone.learner)
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

/// Pitch (uinotebook): the journey's log, everyone in it: the crew, the bystanders who interrupt, and you.
private struct PitchTeamLog: View {
    enum Kind { case crew, bystander, you }
    struct Entry: Identifiable {
        let id = UUID()
        let time, who, role: String
        let kind: Kind
        let stage, title, text: String
        var interrupts = false
    }

    static let bystander = Color.pink
    static let entries: [Entry] = [
        Entry(time: "17:38", who: "Sam", role: "Paramedic", kind: .crew, stage: "Roadside", title: "Scene safety",
              text: "Lane closed by the police, engine off, no fuel leak."),
        Entry(time: "17:39", who: "Driver", role: "Bystander", kind: .bystander, stage: "Roadside", title: "Interrupts",
              text: "\u{201C}I didn't see him, he came out of nowhere! Is he going to be OK?\u{201D}", interrupts: true),
        Entry(time: "17:39", who: "You", role: "to the driver", kind: .you, stage: "Roadside", title: "Kept focus",
              text: "\u{201C}I'll talk to you in a moment, I need to help Jordan first.\u{201D}"),
        Entry(time: "17:40", who: "Sam", role: "Paramedic", kind: .crew, stage: "Roadside", title: "Bleeding controlled",
              text: "Direct pressure and a saline-soaked dressing."),
        Entry(time: "17:41", who: "Lena", role: "Technician", kind: .crew, stage: "Roadside", title: "Observations",
              text: "HR 112  ·  BP 124/78  ·  RR 22  ·  SpO2 97 %  ·  GCS 15"),
        Entry(time: "17:42", who: "Passer-by", role: "Bystander", kind: .bystander, stage: "Roadside", title: "Interrupts",
              text: "\u{201C}Shouldn't you take his helmet off? He's struggling in that.\u{201D}", interrupts: true),
        Entry(time: "17:43", who: "You", role: "notebook", kind: .you, stage: "Roadside", title: "Examination note",
              text: "\u{201C}Bleeding wound over a deformed right distal forearm.\u{201D}"),
        Entry(time: "17:47", who: "Sam", role: "Paramedic", kind: .crew, stage: "Roadside", title: "Splint and pain relief",
              text: "Vacuum splint, hand to above the elbow. Penthrox inhaled."),
        Entry(time: "17:55", who: "Lena", role: "Technician", kind: .crew, stage: "Ambulance", title: "Repeat observations",
              text: "HR 104  ·  BP 120/76  ·  RR 18  ·  SpO2 98 %"),
        Entry(time: "17:58", who: "Lena", role: "Technician", kind: .crew, stage: "Ambulance", title: "IV access and analgesia",
              text: "18 G cannula, bloods taken. Morphine 5 mg IV with an antiemetic."),
        Entry(time: "18:10", who: "You", role: "to Dr Omar", kind: .you, stage: "Resus", title: "ATMIST handover",
              text: "\u{201C}Jordan, 34, cyclist knocked off by a car forty minutes ago\u{2026}\u{201D}"),
        Entry(time: "18:11", who: "Dr Omar", role: "Registrar", kind: .crew, stage: "Resus", title: "Interrupts",
              text: "\u{201C}Quickly please, a second trauma call is two minutes out.\u{201D}", interrupts: true),
        Entry(time: "18:22", who: "Priya", role: "Nurse", kind: .crew, stage: "Resus", title: "IV antibiotics",
              text: "Penicillin allergy checked; protocol alternative given. Tetanus booster."),
        Entry(time: "18:30", who: "Dr Omar", role: "Registrar", kind: .crew, stage: "Resus", title: "Orthopaedic referral",
              text: "Review within the hour for debridement; nil by mouth."),
    ]

    private func color(_ k: Kind) -> Color { k == .crew ? NoteTone.team : k == .bystander ? Self.bystander : NoteTone.learner }

    var body: some View {
        let e = Self.entries
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("ENCOUNTER LOG").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                chip("All \(e.count)", .white, on: true)
                chip("Crew \(e.filter { $0.kind == .crew }.count)", NoteTone.team)
                chip("Bystanders \(e.filter { $0.kind == .bystander }.count)", Self.bystander)
                chip("You \(e.filter { $0.kind == .you }.count)", NoteTone.learner)
                chip("Interruptions \(e.filter(\.interrupts).count)", .orange, icon: "bolt.fill")
            }
            VStack(alignment: .leading, spacing: 11) {
                ForEach(e) { row($0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .noteCard(padding: 16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func chip(_ text: String, _ c: Color, on: Bool = false, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.caption.weight(.semibold)).foregroundStyle(on ? .primary : c)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(c.opacity(on ? 0.18 : 0.14), in: Capsule())
    }

    private func row(_ r: Entry) -> some View {
        let c = color(r.kind)
        return HStack(alignment: .top, spacing: 12) {
            Text(r.time).font(.caption.monospacedDigit().weight(.medium)).foregroundStyle(.secondary).frame(width: 42, alignment: .leading)
                .padding(.top, 6)
            NoteAvatar(name: r.kind == .you ? "Y" : r.who, color: c, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(r.who).font(.callout.weight(.bold)).foregroundStyle(c)
                    Text(r.role).font(.caption).foregroundStyle(.secondary)
                    Text(r.title).font(.callout.weight(.semibold))
                    if r.interrupts {
                        Label("INTERRUPTION", systemImage: "bolt.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(.orange.opacity(0.18), in: Capsule())
                    }
                    Spacer(minLength: 4)
                    Text(r.stage).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.08), in: Capsule())
                }
                Text(r.text).font(.callout).foregroundStyle(r.kind == .crew ? .secondary : .primary).lineLimit(1)
            }
        }
    }
}
