import Foundation
import Observation

// Explicit, switchable development mocks, selected in MedSimXRApp by launch argument:
//   -useMocks   mock engine + voice that never connects
//   -mockVoice  real engines + deterministic scripted voice
// Never the default in a demo build.

@MainActor
final class MockClinicalEngine: ClinicalEngine {
    let modeLabel = "Mock"
    private var counts: [String: Int] = [:]

    private var current: SessionInfo?
    private let info = SessionInfo(
        sessionId: "mock",
        startedAt: ISO8601DateFormatter().string(from: Date()),
        case: CaseInfo(
            caseId: "wrist_trauma_001",
            title: "Wrist pain after a bicycle fall",
            learnerBrief: "Mock case.",
            patient: PatientInfo(name: "Alex", age: 28),
            voiceContext: "",
            zones: [
                ZoneInfo(id: "right_anatomical_snuffbox", label: "Right anatomical snuffbox", attachTo: "right_wrist", offset: [0, 0, 0], radius: 0.05),
                ZoneInfo(id: "right_distal_forearm", label: "Right distal forearm", attachTo: "right_forearm", offset: [0, 0, 0], radius: 0.06),
                ZoneInfo(id: "left_wrist", label: "Left wrist (comparison)", attachTo: "left_wrist", offset: [0, 0, 0], radius: 0.055),
            ],
            scriptedDialogue: [
                ScriptedLine(id: "greeting", learner: "What brings you here today?", patient: "I fell off my bike yesterday and my right wrist hurts."),
            ]
        )
    )

    var bundledCases: [CaseInfo] { [info.case] }
    func caseCatalog() async throws -> [CaseInfo] { [info.case] }
    func startSession(caseId: String, config: SessionConfig?) async throws -> SessionInfo {
        counts = [:]
        var started = info
        started.config = try (info.case.catalog ?? CaseCatalog()).resolve(config)
        started.sessionId = "mock"
        current = started
        return started
    }
    func reset() async throws -> SessionInfo { counts = [:]; return current ?? info }
    func recordInteraction(_ turn: TranscriptTurn) async {}

    func examine(zoneId: String, action: String) async throws -> ExaminationResult {
        counts[zoneId, default: 0] += 1
        let painful = zoneId == "right_anatomical_snuffbox"
        return ExaminationResult(
            bodyPart: zoneId, action: action,
            finding: painful ? "marked_tenderness" : "normal",
            painLevel: painful ? 8 : 0,
            reaction: painful ? "strong_pain" : "no_pain",
            patientResponse: painful ? "Ow! Yes, that's exactly where it hurts!" : "That doesn't really hurt.",
            animation: painful ? "arm_withdrawal" : "none",
            voiceContext: "[mock examination of \(zoneId)]",
            repeatCount: counts[zoneId] ?? 1
        )
    }

    func orderInvestigation(_ id: String) async throws -> InvestigationResult {
        InvestigationResult(investigationId: id, label: "Mock investigation", modality: "Mock", title: "Mock study",
                            report: "Mock report.", impression: "Mock impression.", image: nil,
                            imageCredit: "Simulated report only.", orderedAt: ISO8601DateFormatter().string(from: Date()),
                            repeatCount: 1)
    }

    func recordMeasurement(_ id: String, valueCm: Double?) async throws -> MeasurementResult {
        MeasurementResult(measurementId: id, label: "Mock measurement", kind: "length", valueCm: valueCm ?? 17, source: "case")
    }
    func recordFit(_ fit: OrthosisFit?) async throws -> FitAck { FitAck(attempt: 1, voiceNote: "", comfortable: true, patientResponse: "", voiceContext: "", animation: "none") }
    func fittingCheck(_ kind: String) async throws -> FittingCheckResult {
        FittingCheckResult(check: kind, phase: "before", finding: nil, patientResponse: "It feels fine.",
                           voiceContext: "[mock check]", comfortable: true, animation: "none")
    }

    func applyGel() async throws -> GelResult {
        GelResult(applied: true, patientResponse: "That's cold.", voiceContext: "[mock gel]", repeatCount: 1)
    }
    func scan(regionId: String, gelApplied: Bool?) async throws -> ScanResult {
        ScanResult(regionId: regionId, viewId: nil, image: nil, title: "Mock scan", caption: "Mock.", measurements: [],
                   imageCredit: "", depthCm: 10, gain: 50, quality: "poor", gelApplied: false, patientResponse: "",
                   voiceContext: "", repeatCount: 1)
    }

    func diagnose(_ diagnosis: String, notes: ClinicalNotes) async throws -> Feedback { makeFeedback(diagnosis) }
    func feedback() async throws -> Feedback { makeFeedback(nil) }

    private func makeFeedback(_ diagnosis: String?) -> Feedback {
        Feedback(
            sessionId: "mock", caseId: "wrist_trauma_001", diagnosisSubmitted: diagnosis,
            totalScore: 62, maxScore: 100,
            summary: "Mock feedback. Good job identifying the painful region. However, you did not ask about numbness.",
            transcriptAvailable: false,
            diagnosticAssessment: DiagnosticAssessment(verdict: diagnosis == nil ? "not_submitted" : "correct", explanation: "Mock assessment.", expected: diagnosis == nil ? nil : "Suspected scaphoid fracture"),
            categories: [
                CategoryResult(id: "history", title: "History-taking", score: 12, maxScore: 30, criteria: [
                    CriterionResult(id: "mechanism", label: "Mechanism of injury", met: true, points: 6, maxPoints: 6, method: "keyword", evidence: "What happened?", comment: "You asked how the injury happened."),
                    CriterionResult(id: "associated_symptoms", label: "Associated symptoms", met: false, points: 0, maxPoints: 6, method: "keyword", evidence: nil, comment: "You did not ask about numbness or altered sensation."),
                ]),
                CategoryResult(id: "examination", title: "Physical examination", score: 30, maxScore: 40, criteria: []),
                CategoryResult(id: "communication", title: "Communication", score: 10, maxScore: 20, criteria: []),
                CategoryResult(id: "reasoning", title: "Clinical reasoning", score: 10, maxScore: 10, criteria: []),
            ],
            strengths: ["You palpated the anatomical snuffbox and elicited marked tenderness."],
            missed: ["You did not ask about numbness or altered sensation."],
            relevantFindings: ["Right anatomical snuffbox: marked tenderness (pain 8/10)"],
            nextSteps: diagnosis == nil ? [] : ["Request dedicated scaphoid-view radiographs."],
            documentation: [],
            management: ManagementAssessment(title: "Investigation and management", score: 0, maxScore: 20, criteria: []),
            investigations: [],
            fitting: FittingAssessment(title: "Measurement and orthosis fitting", score: 0, maxScore: 20, criteria: []),
            replay: [],
            disclaimer: "Educational simulation only."
        )
    }
}

/// `scripted == false`: never connects, which forces the local-speech fallback path.
/// `scripted == true` (launch argument `-mockVoice`): a deterministic stand-in for the live
/// agent. It "connects", shows a live microphone, and answers every examination event with
/// the example line quoted in the stage direction. No network, no audio of its own.
@MainActor
@Observable
final class MockVoiceService: VoiceService {
    private(set) var status: VoiceStatus = .disconnected
    private(set) var micStatus: MicStatus = .unknown
    private(set) var isAgentSpeaking = false
    @ObservationIgnored var onTranscript: ((TranscriptTurn) -> Void)?
    @ObservationIgnored var onAction: ((String) -> String)?
    @ObservationIgnored var onOrder: ((String) async -> String)?
    @ObservationIgnored var onTeamAction: ((String) async -> String)?
    @ObservationIgnored private let scripted: Bool

    init(scripted: Bool = false) { self.scripted = scripted }

    func start(caseContext: String, voiceId: String?) async {
        guard scripted else { return }
        summaryPolls = 0
        status = .connecting
        try? await Task.sleep(nanoseconds: 600_000_000)
        status = .connected
        micStatus = .live
        onTranscript?(TranscriptTurn(role: .patient, text: "Hello, doctor."))
    }

    /// Deterministic stand-in for the live agent hearing the learner: the phrase is recorded as
    /// learner speech and, if it asks for a movement, the same action hook the client tool uses fires.
    func hear(_ text: String) async {
        guard scripted, status == .connected else { return }
        onTranscript?(TranscriptTurn(role: .learner, text: text))
        let phrases: [(String, [String])] = [
            ("sit_down", ["sit", "seat"]), ("extend_both_arms", ["stretch", "hold", "extend"]),
            ("relax_arms", ["relax", "rest your"]), ("indicate_right_wrist", ["which wrist", "show me", "where"]),
        ]
        let orders: [(String, [String])] = [
            ("rt_xray_forearm", ["x-ray of his forearm", "x-ray of her forearm", "x-ray of the forearm", "forearm x-ray"]),
            ("right_wrist_xray", ["x-ray", "xray", "radiograph"]), ("right_wrist_mri", ["mri"]),
            ("right_wrist_ct", ["ct scan", "a ct"]),
        ]
        // Requests to the medical team of a journey case (a case without a team answers "failure").
        let team: [(String, [String])] = [
            ("scene_safety", ["scene safe", "is it safe"]), ("observations", ["observations", "obs", "vital signs"]),
            ("haemorrhage_control", ["pressure on", "control the bleeding", "dressing on"]),
            ("photograph_wound", ["photo"]), ("splint_arm", ["splint"]), ("iv_analgesia", ["iv pain relief", "morphine"]),
            ("analgesia", ["pain relief", "penthrox"]), ("iv_access", ["cannula", "iv access"]),
            ("pre_alert", ["pre-alert", "prealert"]), ("iv_antibiotics", ["antibiotic"]), ("tetanus", ["tetanus booster"]),
            ("orthopaedic_referral", ["orthopaedic", "ortho team"]),
        ]
        let lower = text.lowercased()
        var reply = "Okay."
        if let request = team.first(where: { $0.1.contains { lower.contains($0) } })?.0,
           let result = await onTeamAction?(request), !result.hasPrefix("failure") {
            SmokeLog.mark("heard \"\(text)\" team=\(request) result=\(result)")
        } else if let order = orders.first(where: { $0.1.contains { lower.contains($0) } })?.0 {
            let result = await onOrder?(order) ?? "failure: unavailable"
            SmokeLog.mark("heard \"\(text)\" order=\(order) result=\(result)")
        } else if let action = phrases.first(where: { $0.1.contains { lower.contains($0) } })?.0 {
            let result = onAction?(action) ?? "failure: unavailable"
            SmokeLog.mark("heard \"\(text)\" action=\(action) result=\(result)")
            reply = result.hasPrefix("success") ? "Of course." : "Sorry, I can't do that right now."
        }
        isAgentSpeaking = true
        try? await Task.sleep(nanoseconds: 150_000_000)
        onTranscript?(TranscriptTurn(role: .patient, text: reply))
        isAgentSpeaking = false
    }

    func setMicMuted(_ muted: Bool) async {
        if status == .connected { micStatus = muted ? .muted : .live }
    }

    func stop() async {
        status = .disconnected
        micStatus = .unknown
        isAgentSpeaking = false
    }

    func sendContext(_ text: String) async {}

    func sendExaminationEvent(_ text: String) async {
        guard scripted, status == .connected else { return }
        // The stage direction ends with: for example: "<line>"]
        let parts = text.components(separatedBy: "\"")
        let line = parts.count >= 3 ? parts[parts.count - 2] : "Okay."
        isAgentSpeaking = true
        try? await Task.sleep(nanoseconds: 700_000_000)
        onTranscript?(TranscriptTurn(role: .patient, text: line))
        try? await Task.sleep(nanoseconds: 900_000_000)
        isAgentSpeaking = false
    }

    private struct NoSummary: LocalizedError {
        var errorDescription: String? { "No voice conversation was recorded, so there is nothing to summarise." }
    }

    /// Scripted: a fixed draft after one "still processing" poll. Otherwise there is no conversation.
    @ObservationIgnored private var summaryPolls = 0

    func fetchSummary() async throws -> String? {
        guard scripted else { throw NoSummary() }
        summaryPolls += 1
        guard summaryPolls > 1 else { return nil }
        return "Mock summary: the student greeted Alex and asked about the injury to the right wrist. "
            + "With a live ElevenLabs agent this is the agent's generated call summary."
    }
}
