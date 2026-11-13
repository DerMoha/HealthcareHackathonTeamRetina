import Foundation

// Shared contracts. Mirrors docs/api-contract.md — change both together.
// JSON is snake_case; decode with `JSONDecoder.medsim`.

extension JSONDecoder {
    static var medsim: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
}

extension JSONEncoder {
    static var medsim: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }
}

// MARK: - Case / session

struct PatientInfo: Codable, Hashable, Sendable {
    var name: String
    var age: Int
    var appearance: String?
    var personality: String?
}

struct ZoneInfo: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var label: String
    /// Name of the avatar entity this zone is parented to (e.g. "right_wrist").
    var attachTo: String
    /// Metres, in the `attachTo` entity's local space.
    var offset: [Float]
    var radius: Float
}

struct ScriptedLine: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var learner: String
    var patient: String
}

/// An investigation the learner may request. The result stays with the clinical engine.
struct InvestigationInfo: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var label: String
}

struct MeasurementInfo: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var label: String
    /// circumference | length
    var kind: String
}

struct OrthosisSize: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var label: String
    /// [min, max] wrist circumference printed on the tray.
    var wristCm: [Double]
}

/// What the orthotics tray offers. Reference values and outcomes stay with the engine.
struct Orthotics: Codable, Hashable, Sendable {
    var measurements: [MeasurementInfo] = []
    var sizes: [OrthosisSize] = []
    var tightness: [String] = []
}

struct CaseInfo: Codable, Hashable, Sendable {
    var caseId: String
    var title: String
    var learnerBrief: String
    var patient: PatientInfo
    var voiceContext: String
    var zones: [ZoneInfo]
    var scriptedDialogue: [ScriptedLine]
    var investigations: [InvestigationInfo] = []
    var orthotics = Orthotics()
}

struct SessionInfo: Codable, Hashable, Sendable {
    var sessionId: String
    var startedAt: String
    var `case`: CaseInfo
}

// MARK: - Examination

struct ExaminationResult: Codable, Hashable, Sendable {
    var bodyPart: String
    var action: String
    var finding: String
    var painLevel: Int
    /// strong_pain | mild_pain | no_pain
    var reaction: String
    var patientResponse: String
    /// arm_withdrawal | flinch | none
    var animation: String
    var voiceContext: String
    var repeatCount: Int
}

// MARK: - Investigations

/// Predefined result from the case engine. Never produced by the voice model.
struct InvestigationResult: Codable, Hashable, Identifiable, Sendable {
    var investigationId: String
    var label: String
    var modality: String
    var title: String
    var report: String
    var impression: String
    /// Bundled image name (Resources/Radiology), or nil: report only.
    var image: String?
    var imageCredit: String
    var orderedAt: String
    var repeatCount: Int
    var id: String { investigationId }
}

// MARK: - Measurement and orthosis fitting

struct MeasurementResult: Codable, Hashable, Identifiable, Sendable {
    var measurementId: String
    var label: String
    var kind: String
    var valueCm: Double
    /// case (predefined) | avatar (measured between joints)
    var source: String
    var id: String { measurementId }
}

/// The support as it sits on the arm. `offsetCm`: its centre, from the wrist joint towards the elbow.
struct OrthosisFit: Codable, Hashable, Sendable {
    var size: String
    /// thumb_radial | thumb_ulnar
    var orientation: String
    var offsetCm: Double
    var tightness: String
}

struct FitAck: Codable, Hashable, Sendable {
    var attempt: Int
    /// Context for the voice agent; never spoken, never an outcome label.
    var voiceNote: String
}

struct FittingCheckResult: Codable, Hashable, Sendable {
    /// comfort | neurovascular
    var check: String
    /// before | after (a support is on the arm)
    var phase: String
    var finding: String?
    var patientResponse: String
    var voiceContext: String
    var comfortable: Bool
    var animation: String
}

struct FittingReference: Codable, Hashable, Sendable {
    var size: String
    var orientation: String
    var offsetCm: [Double]
    var tightness: String
}

/// Scored separately, not part of `totalScore`.
struct FittingAssessment: Codable, Hashable, Sendable {
    var title: String
    var score: Int
    var maxScore: Int
    var criteria: [CriterionResult]
    var finalFit: OrthosisFit?
    /// Nil before a diagnosis is submitted.
    var reference: FittingReference?
    var explanation: String?
}

// MARK: - Transcript

enum SpeakerRole: String, Codable, Sendable {
    case learner, patient
}

struct TranscriptTurn: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var role: SpeakerRole
    var text: String
    var timestamp = Date()

    enum CodingKeys: String, CodingKey { case role, text }
}

// MARK: - Feedback

struct DiagnosticAssessment: Codable, Hashable, Sendable {
    /// correct | partial | incorrect | not_submitted
    var verdict: String
    var explanation: String
    var expected: String?
}

struct CriterionResult: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var label: String
    var met: Bool
    var points: Int
    var maxPoints: Int
    /// rule | keyword
    var method: String
    var evidence: String?
    var comment: String
    /// Management criteria only: investigation | interpretation | management | safety
    var area: String? = nil
}

struct CategoryResult: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var score: Int
    var maxScore: Int
    var criteria: [CriterionResult]
}

/// The learner's notebook. Compared with the session record; never a source of points.
struct ClinicalNotes: Codable, Hashable, Sendable {
    var history = ""
    var examination = ""
    var assessment = ""
    /// What the investigation results mean.
    var interpretation = ""
    /// Immediate management.
    var management = ""
    /// Further imaging or follow-up plan.
    var followUp = ""
}

struct DocumentationItem: Codable, Hashable, Identifiable, Sendable {
    var criterionId: String
    var label: String
    /// documented | undocumented | unsupported
    var status: String
    var comment: String
    var id: String { criterionId }
}

/// Investigation and management: scored separately, not part of `totalScore`.
struct ManagementAssessment: Codable, Hashable, Sendable {
    var title: String
    var score: Int
    var maxScore: Int
    var criteria: [CriterionResult]
}

struct Feedback: Codable, Hashable, Sendable {
    var sessionId: String
    var caseId: String
    var diagnosisSubmitted: String?
    var totalScore: Int
    var maxScore: Int
    var summary: String
    var transcriptAvailable: Bool
    var diagnosticAssessment: DiagnosticAssessment
    var categories: [CategoryResult]
    var strengths: [String]
    var missed: [String]
    var relevantFindings: [String]
    var nextSteps: [String]
    var documentation: [DocumentationItem]
    var management: ManagementAssessment
    /// "<label>: <impression>" for each investigation that was ordered.
    var investigations: [String]
    var fitting: FittingAssessment
    var disclaimer: String
}

// MARK: - Service interfaces

/// Source of truth for clinical findings and scoring. One active session at a time.
@MainActor
protocol ClinicalEngine: AnyObject {
    /// Short human-readable mode for the status UI, e.g. "Backend", "Offline".
    var modeLabel: String { get }
    func startSession(caseId: String) async throws -> SessionInfo
    func examine(zoneId: String, action: String) async throws -> ExaminationResult
    /// Records the order and returns the scenario's predefined result.
    func orderInvestigation(_ id: String) async throws -> InvestigationResult
    /// `valueCm` is the avatar measurement; the engine overrides it when the case predefines one.
    func recordMeasurement(_ id: String, valueCm: Double?) async throws -> MeasurementResult
    /// Records the support's current state (nil = removed). The outcome stays with the engine.
    func recordFit(_ fit: OrthosisFit?) async throws -> FitAck
    /// comfort | neurovascular, answered for the current fit.
    func fittingCheck(_ kind: String) async throws -> FittingCheckResult
    /// Best effort; must never throw into the UI.
    func recordInteraction(_ turn: TranscriptTurn) async
    func diagnose(_ diagnosis: String, notes: ClinicalNotes) async throws -> Feedback
    func feedback() async throws -> Feedback
    func reset() async throws -> SessionInfo
}

enum VoiceStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .failed(let message): "Error: \(message)"
        }
    }
}

enum MicStatus: String, Sendable {
    case unknown = "Unknown"
    case denied = "Denied"
    case muted = "Muted"
    case live = "Live"
}

/// Live conversational patient. Implementations must be `@Observable` so
/// SwiftUI tracks `status` / `micStatus` / `isAgentSpeaking` through the existential.
@MainActor
protocol VoiceService: AnyObject {
    var status: VoiceStatus { get }
    var micStatus: MicStatus { get }
    var isAgentSpeaking: Bool { get }
    /// Called on the main actor for every finalized learner/patient utterance.
    /// Must NOT be called for bracketed examination stage directions.
    var onTranscript: ((TranscriptTurn) -> Void)? { get set }
    /// Called when the agent's client tool `perform_patient_action` fires, with the raw
    /// `action` string. Returns the tool result ("success: …", "invalid_state: …", "failure: …").
    var onAction: ((String) -> String)? { get set }
    /// Called when the agent's client tool `order_investigation` fires, with the raw
    /// `investigation` string. Returns the tool result; it never contains the test result.
    var onOrder: ((String) async -> String)? { get set }

    /// Connects and passes `caseContext` as dynamic variable `case_context`.
    func start(caseContext: String) async
    func stop() async
    /// Note-taking mode: while muted the agent must not hear the learner (dictated notes).
    func setMicMuted(_ muted: Bool) async
    /// Background information for the agent. Must not make it speak.
    func sendContext(_ text: String) async
    /// Forwards `ExaminationResult.voiceContext`; the agent must speak a reaction.
    func sendExaminationEvent(_ text: String) async
}
