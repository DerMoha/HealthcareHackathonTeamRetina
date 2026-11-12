import Foundation
import Observation

// Explicit, switchable development mocks. Selected in MedSimXRApp via
// the `-useMocks` launch argument; never the default in a demo build.

@MainActor
final class MockClinicalEngine: ClinicalEngine {
    let modeLabel = "Mock"
    private var counts: [String: Int] = [:]

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

    func startSession(caseId: String) async throws -> SessionInfo { counts = [:]; return info }
    func reset() async throws -> SessionInfo { counts = [:]; return info }
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

    func diagnose(_ diagnosis: String) async throws -> Feedback { makeFeedback(diagnosis) }
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
            disclaimer: "Educational simulation only."
        )
    }
}

/// Voice that never connects: forces the local-speech fallback path.
@MainActor
@Observable
final class MockVoiceService: VoiceService {
    private(set) var status: VoiceStatus = .disconnected
    private(set) var micStatus: MicStatus = .unknown
    private(set) var isAgentSpeaking = false
    var onTranscript: ((TranscriptTurn) -> Void)?

    func start(caseContext: String) async {}
    func stop() async {}
    func sendExaminationEvent(_ text: String) async {}
}
