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
    case history = "History", examination = "Examination", assessment = "Assessment", conversation = "Conversation"
    var id: String { rawValue }
}

enum SessionPhase: Equatable {
    case idle, running, feedback
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

    // MARK: Examination

    /// Entry point for gaze+pinch, fingertip contact and debug buttons.
    func examine(zoneId: String) async {
        guard phase == .running, behavior.canExamine else { return }
        let now = Date()
        guard now.timeIntervalSince(lastExamineAt) >= Self.examineCooldown else { return }
        lastExamineAt = now
        do {
            let result = try await engine.examine(zoneId: zoneId, action: "palpation")
            examinations.append(result)
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
