import Foundation
import Observation

/// What the patient avatar should do right now. Views observe `AppModel.reaction`
/// and react on `id` change: play `animation`, a pain sound if `painLevel >= 5`,
/// and speak `text` locally when `speakLocally` is true.
struct ReactionEvent: Identifiable, Equatable {
    let id = UUID()
    /// arm_withdrawal | flinch | none
    var animation: String
    var painLevel: Int
    var text: String
    /// Optional bundled clip name (Resources/Audio/<clip>.*), e.g. a zone id or scripted line id.
    var clip: String?
    /// False when the live voice agent will say the line itself.
    var speakLocally: Bool
}

enum NotebookTab: String, CaseIterable, Identifiable {
    case history = "History", examination = "Examination", investigations = "Investigations",
         assessment = "Assessment", conversation = "Transcript"
    var id: String { rawValue }
}

enum SessionPhase: Equatable {
    case idle, running, feedback
}

enum SummaryState: Equatable {
    case idle, waiting
    case ready(String)
    case failed(String)
}

/// The only object views talk to. Orchestrates engine + voice + avatar reactions.
@MainActor
@Observable
final class AppModel {
    let engine: any ClinicalEngine
    let voice: any VoiceService
    /// The patient's body: standing, sitting, arm poses, recoil.
    let behavior = PatientBehaviorController()

    private(set) var phase: SessionPhase = .idle
    private(set) var session: SessionInfo?
    private(set) var transcript: [TranscriptTurn] = []
    private(set) var examinations: [ExaminationResult] = []
    private(set) var reaction: ReactionEvent?
    private(set) var feedback: Feedback?
    private(set) var lastError: String?
    /// Incremented by `recenter()`; the immersive view re-places the patient on change.
    private(set) var recenterToken = 0
    private(set) var isBusy = false
    var debugMode = false

    /// The learner's notebook: free-text notes plus the diagnosis they formulate themselves.
    var notes = ClinicalNotes()
    var diagnosis = ""
    var notebookTab = NotebookTab.history
    private(set) var notebookOpen = false

    /// Results the learner has received, latest order of each investigation.
    private(set) var investigationResults: [InvestigationResult] = []
    /// Result shown in the radiology viewer (takes the notebook's place while set).
    private(set) var viewing: InvestigationResult?
    var viewerZoom = 1.0

    /// Orthotics lab. `fit` is the support as the engine last recorded it; the scene renders it.
    private(set) var measurements: [MeasurementResult] = []
    private(set) var fit: OrthosisFit?
    private(set) var lastCheck: FittingCheckResult?
    var selectedTool: String?
    /// One-shot instruction for the 3D lab (scripted demo, panel fallback buttons).
    var labCommand: LabCommand?
    /// Spatial Clinical Replay; only available once feedback is showing.
    private(set) var teachingMode = false
    var replayStep = 0
    var showAnatomy = true
    /// Every examination that reached the engine, with how and where it happened.
    private(set) var examEvents: [ExamEvent] = []
    private var sessionStart = Date()
    @ObservationIgnored private var fitReactionTask: Task<Void, Never>?
    /// The complaint the patient last voiced about the fit, so it is not repeated.
    private var lastFitComplaint: String?
    /// Quiet time after the last adjustment before the patient speaks up unprompted.
    static let fitReactionDelay: TimeInterval = 1.3

    /// The ElevenLabs post-call summary of the consultation. Only a draft: it reaches the
    /// notes when the learner inserts it, so the documentation feedback stays theirs.
    private(set) var summaryState = SummaryState.idle
    @ObservationIgnored private var summaryTask: Task<Void, Never>?
    /// How long to wait for ElevenLabs to finish its analysis, and how often to ask.
    static let summaryTimeout: TimeInterval = 90
    static let summaryPollInterval: TimeInterval = 3

    /// Replay steps: one per examination, then the support placement.
    var replayStepCount: Int { examEvents.count + 1 }
    var replayEvent: ExamEvent? { teachingMode && examEvents.indices.contains(replayStep) ? examEvents[replayStep] : nil }

    /// Seconds between accepted examination events (gaze+pinch or fingertip).
    static let examineCooldown: TimeInterval = 1.5
    private var lastExamineAt = Date.distantPast

    var zones: [ZoneInfo] { session?.case.zones ?? [] }
    var scriptedDialogue: [ScriptedLine] { session?.case.scriptedDialogue ?? [] }
    var engineModeLabel: String { engine.modeLabel }

    init(engine: any ClinicalEngine, voice: any VoiceService) {
        self.engine = engine
        self.voice = voice
        voice.onTranscript = { [weak self] turn in self?.record(turn) }
        voice.onAction = { [weak self] raw in self?.performPatientAction(raw) ?? "failure: unavailable" }
        voice.onOrder = { [weak self] raw in await self?.orderInvestigation(raw) ?? "failure: unavailable" }
    }

    // MARK: Session

    func startSession() async {
        await run {
            let info = try await self.engine.startSession(caseId: AppConfig.defaultCaseId)
            self.apply(info)
            Task { await self.voice.start(caseContext: info.case.voiceContext) }
        }
    }

    func stopSession() async {
        await voice.stop()
        phase = .idle
    }

    func reset() async {
        await voice.stop()
        await run {
            let info = try await self.engine.reset()
            self.apply(info)
            Task { await self.voice.start(caseContext: info.case.voiceContext) }
        }
    }

    func recenter() { recenterToken += 1 }

    /// Opening the notebook is note-taking mode: the patient's microphone is muted so that
    /// dictated notes are not heard as speech to the patient.
    func setNotebookOpen(_ open: Bool) {
        notebookOpen = open
        if !open { viewing = nil }
        Task { await voice.setMicMuted(open && phase == .running) }
    }

    /// Body movement requested by the voice agent's client tool or a debug button. Never an
    /// examination and never a transcript turn, so it cannot earn points.
    @discardableResult
    func performPatientAction(_ raw: String) -> String {
        guard phase == .running else { return "failure: no session is running" }
        let result = behavior.perform(raw).text
        SmokeLog.mark("action \(raw) -> \(result) exams=\(examinations.count) turns=\(transcript.count)")
        return result
    }

    // MARK: Investigations

    /// Requested from the notebook or by the voice agent's client tool. `raw` must be one of
    /// the case's investigation ids; the result comes from the clinical engine only. The
    /// returned text goes back to the voice agent and deliberately leaves the result out.
    @discardableResult
    func orderInvestigation(_ raw: String) async -> String {
        guard phase == .running, let offered = session?.case.investigations else { return "failure: no session is running" }
        guard let info = offered.first(where: { $0.id == raw }) else {
            return "failure: Unknown investigation. Allowed: \(offered.map(\.id).joined(separator: ", "))."
        }
        do {
            let result = try await engine.orderInvestigation(raw)
            investigationResults.removeAll { $0.investigationId == result.investigationId }
            investigationResults.append(result)
            show(result)
            lastError = nil
            SmokeLog.mark("investigation \(raw) impression=\"\(result.impression)\" image=\(result.image ?? "none") "
                + "imageFound=\(result.image.map { RadiologyImage.url($0) != nil } ?? false) engine=\(engineModeLabel) "
                + "results=\(investigationResults.count) exams=\(examinations.count) turns=\(transcript.count)")
            return "success: \(info.label) requested. The result is shown to the student on screen. "
                + "You do not know the result. Do not describe or guess it."
        } catch {
            lastError = error.localizedDescription
            return "failure: The request could not be sent."
        }
    }

    /// Opens the radiology viewer. It does not mute the microphone: only the notes pages do.
    func show(_ result: InvestigationResult) {
        viewerZoom = 1
        viewing = result
        notebookOpen = true
    }

    /// "Back to notebook": lands on the Investigations tab, in note-taking mode.
    func closeViewer() {
        viewing = nil
        notebookTab = .investigations
        setNotebookOpen(true)
    }

    // MARK: Measurement and orthosis fitting

    func measure(_ id: String, valueCm: Double?) async {
        guard phase == .running, behavior.canExamine else { return }
        do {
            let result = try await engine.recordMeasurement(id, valueCm: valueCm)
            measurements.removeAll { $0.measurementId == id }
            measurements.append(result)
            lastError = nil
            SmokeLog.mark("measure \(id) value=\(result.valueCm) source=\(result.source) engine=\(engineModeLabel)")
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// A support was dropped on the forearm (`offsetCm` nil = taken off). A newly placed
    /// support starts in the tray orientation with its straps at the loosest setting.
    func placeOrthosis(size: String, offsetCm: Double?) async {
        guard let offsetCm else { return await setFit(nil) }
        var next = fit ?? OrthosisFit(size: size, orientation: "thumb_radial", offsetCm: offsetCm,
                                      tightness: session?.case.orthotics.tightness.first ?? "loose")
        if next.size != size { next.tightness = session?.case.orthotics.tightness.first ?? "loose" }
        next.size = size
        next.offsetCm = offsetCm
        await setFit(next)
    }

    func adjustFit(_ change: (inout OrthosisFit) -> Void) async {
        guard var next = fit else { return }
        change(&next)
        await setFit(next)
    }

    func stepTightness(_ step: Int) async {
        let levels = session?.case.orthotics.tightness ?? []
        guard let current = fit, let i = levels.firstIndex(of: current.tightness), levels.indices.contains(i + step) else { return }
        await adjustFit { $0.tightness = levels[i + step] }
    }

    /// Every change goes to the engine first; the scene shows only what was recorded.
    func setFit(_ next: OrthosisFit?) async {
        guard phase == .running, behavior.canExamine else { return }
        do {
            let ack = try await engine.recordFit(next)
            fit = next
            lastError = nil
            SmokeLog.mark("fit \(next.map { "size=\($0.size) offset=\($0.offsetCm) orientation=\($0.orientation) tightness=\($0.tightness)" } ?? "removed") "
                + "attempt=\(ack.attempt) engine=\(engineModeLabel) exams=\(examinations.count)")
            await voice.sendContext(ack.voiceNote)
            scheduleFitReaction(next == nil ? nil : ack)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Explicit, recorded check: "comfort" or "neurovascular". The engine supplies the
    /// finding and what the patient says; the voice agent only speaks it.
    func fittingCheck(_ kind: String) async {
        guard phase == .running, behavior.canExamine else { return }
        do {
            let result = try await engine.fittingCheck(kind)
            lastCheck = result
            if kind == "comfort" { // asked: the answer replaces any pending unprompted remark
                fitReactionTask?.cancel()
                lastFitComplaint = result.comfortable ? nil : result.patientResponse
            }
            await patientSays(result.patientResponse, voiceContext: result.voiceContext, animation: result.animation)
            lastError = nil
            SmokeLog.mark("check \(kind) phase=\(result.phase) comfortable=\(result.comfortable) "
                + "response=\"\(result.patientResponse)\" engine=\(engineModeLabel) turns=\(transcript.count)")
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The patient speaks a line the engine supplied: through the live agent when connected,
    /// otherwise locally. A flinch goes through the behaviour controller.
    private func patientSays(_ text: String, voiceContext: String, animation: String) async {
        let live = voice.status == .connected
        reaction = ReactionEvent(animation: animation, painLevel: 0, text: text, clip: nil, speakLocally: !live)
        if animation != "none" { behavior.pain(withdrawArm: false) }
        if live { await voice.sendExaminationEvent(voiceContext) }
        else { record(TranscriptTurn(role: .patient, text: text)) }
    }

    /// An uncomfortable fit makes the patient speak up without being asked: once, after the
    /// adjustments have stopped, and not again for the same complaint.
    private func scheduleFitReaction(_ ack: FitAck?) {
        fitReactionTask?.cancel()
        guard let ack, !ack.comfortable else { lastFitComplaint = nil; return }
        guard ack.patientResponse != lastFitComplaint else { return }
        fitReactionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.fitReactionDelay * 1_000_000_000))
            guard let self, !Task.isCancelled, self.phase == .running else { return }
            self.lastFitComplaint = ack.patientResponse
            SmokeLog.mark("fit reaction unprompted response=\"\(ack.patientResponse)\"")
            await self.patientSays(ack.patientResponse, voiceContext: ack.voiceContext, animation: ack.animation)
        }
    }

    // MARK: Spatial Clinical Replay

    /// Only after submission: the teaching content it shows would give the diagnosis away.
    func startReplay() {
        guard phase == .feedback, feedback?.replay.isEmpty == false else { return }
        replayStep = 0
        teachingMode = true
        setNotebookOpen(false)
        SmokeLog.mark("replay started steps=\(replayStepCount) events=\(examEvents.map { "\($0.zoneId):\($0.source)" })")
    }

    func exitReplay() {
        teachingMode = false
        setNotebookOpen(true)
    }

    // MARK: Examination

    /// Entry point for gaze+pinch, fingertip contact and debug buttons. Nothing else creates
    /// an examination: not speech, not tool calls, not notes. `contact` is the touched point
    /// in the zone's own space, when there was one.
    func examine(zoneId: String, contact: SIMD3<Float>? = nil, source: ExamSource = .button) async {
        guard phase == .running, behavior.canExamine else { return }
        let now = Date()
        guard now.timeIntervalSince(lastExamineAt) >= Self.examineCooldown else { return }
        lastExamineAt = now
        do {
            let result = try await engine.examine(zoneId: zoneId, action: "palpation")
            examinations.append(result)
            examEvents.append(ExamEvent(id: examEvents.count, zoneId: zoneId, action: result.action, finding: result.finding,
                                        painLevel: result.painLevel, time: Date().timeIntervalSince(sessionStart),
                                        pose: behavior.state.rawValue, contact: contact, source: source))
            if result.animation != "none" { behavior.pain(withdrawArm: result.animation == "arm_withdrawal") }
            let live = voice.status == .connected
            reaction = ReactionEvent(
                animation: result.animation,
                painLevel: result.painLevel,
                text: result.patientResponse,
                clip: result.bodyPart,
                speakLocally: !live
            )
            if live {
                await voice.sendExaminationEvent(result.voiceContext)
            } else {
                // Offline voice: the scripted reply still belongs in the transcript.
                record(TranscriptTurn(role: .patient, text: result.patientResponse))
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Scripted dialogue (fallback when live voice is unavailable)

    func askScripted(_ line: ScriptedLine) {
        guard phase == .running else { return }
        record(TranscriptTurn(role: .learner, text: line.learner))
        record(TranscriptTurn(role: .patient, text: line.patient))
        reaction = ReactionEvent(animation: "none", painLevel: 0, text: line.patient, clip: line.id, speakLocally: true)
    }

    // MARK: Consultation summary

    /// Ends the conversation with the patient and waits for ElevenLabs' post-call summary.
    /// The session keeps running: examinations and notes still work, the patient then
    /// speaks locally. Calling it again after a failure only retries the fetch.
    func endConsultation() {
        guard phase == .running, summaryState != .waiting else { return }
        summaryState = .waiting
        summaryTask?.cancel()
        summaryTask = Task { [weak self] in
            guard let self else { return }
            await self.voice.stop()
            let deadline = Date().addingTimeInterval(Self.summaryTimeout)
            while !Task.isCancelled {
                do {
                    if let text = try await self.voice.fetchSummary() {
                        guard !Task.isCancelled else { return }
                        self.summaryState = .ready(text)
                        SmokeLog.mark("summary ready chars=\(text.count)")
                        return
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.summaryState = .failed(error.localizedDescription)
                    return
                }
                if Date() >= deadline {
                    self.summaryState = .failed("ElevenLabs has not finished the summary yet. Try again in a minute.")
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(Self.summaryPollInterval * 1_000_000_000))
            }
        }
    }

    /// The learner accepts the draft: it is appended to their history notes, where they can edit it.
    func insertSummary() {
        guard case .ready(let text) = summaryState else { return }
        let existing = notes.history.trimmingCharacters(in: .whitespacesAndNewlines)
        notes.history = existing.isEmpty ? text : existing + "\n\n" + text
        summaryState = .idle
    }

    func discardSummary() {
        summaryTask?.cancel()
        summaryState = .idle
    }

    // MARK: Diagnosis / feedback

    func submitDiagnosis() async {
        let diagnosis = diagnosis.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !diagnosis.isEmpty, session != nil else { return }
        await run {
            self.feedback = try await self.engine.diagnose(diagnosis, notes: self.notes)
            self.phase = .feedback
            await self.voice.stop()
        }
    }

    func loadFeedback() async {
        guard session != nil else { return }
        await run { self.feedback = try await self.engine.feedback() }
    }

    // MARK: Private

    private func apply(_ info: SessionInfo) {
        session = info
        transcript = []
        examinations = []
        feedback = nil
        reaction = nil
        notes = ClinicalNotes()
        diagnosis = ""
        notebookTab = .history
        notebookOpen = false
        investigationResults = []
        viewing = nil
        measurements = []
        fit = nil
        lastCheck = nil
        selectedTool = nil
        teachingMode = false
        replayStep = 0
        examEvents = []
        sessionStart = Date()
        fitReactionTask?.cancel()
        lastFitComplaint = nil
        summaryTask?.cancel()
        summaryState = .idle
        lastExamineAt = .distantPast
        behavior.reset()
        phase = .running
    }

    private func record(_ turn: TranscriptTurn) {
        guard phase == .running else { return }
        transcript.append(turn)
        Task { await engine.recordInteraction(turn) }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await work()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
