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

/// A scan area on the patient's belly. Which views it yields stays with the engine.
struct UltrasoundRegion: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var label: String
    /// Anchor name in the avatar's sidecar (abdomen_fundus, ...).
    var attachTo: String
    var radius: Float
}

/// Present only for cases with an ultrasound machine, probe and gel.
struct UltrasoundInfo: Codable, Hashable, Sendable {
    var regions: [UltrasoundRegion]
}

/// Dashboard metadata of a case. Spoiler-free by contract: never names the diagnosis.
/// Mirrors `CaseCatalog` in backend/app/models.py, defaults included.
struct CaseCatalog: Codable, Hashable, Sendable {
    var summary = ""
    /// SF Symbol name.
    var icon: String?
    var setting: String?
    var skills: [String] = []
    var allowedMoods = ["calm"]
    var allowedAvatars = ["male"]
    var defaultMood = "calm"
    var defaultAvatar = "male"
    /// Bundled avatar model name that wins over the avatar choice (e.g. "Patient_pregnant").
    var avatarModel: String?

    init(summary: String = "", icon: String? = nil, setting: String? = nil, skills: [String] = [],
         allowedMoods: [String] = ["calm"], allowedAvatars: [String] = ["male"],
         defaultMood: String = "calm", defaultAvatar: String = "male", avatarModel: String? = nil) {
        self.summary = summary; self.icon = icon; self.setting = setting; self.skills = skills
        self.allowedMoods = allowedMoods.isEmpty ? ["calm"] : allowedMoods
        self.allowedAvatars = allowedAvatars.isEmpty ? ["male"] : allowedAvatars
        self.defaultMood = self.allowedMoods.contains(defaultMood) ? defaultMood : self.allowedMoods[0]
        self.defaultAvatar = self.allowedAvatars.contains(defaultAvatar) ? defaultAvatar : self.allowedAvatars[0]
        self.avatarModel = avatarModel
    }

    /// Tolerant: every key is optional, so old and hand-written JSON decodes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(summary: try c.decodeIfPresent(String.self, forKey: .summary) ?? "",
                  icon: try c.decodeIfPresent(String.self, forKey: .icon),
                  setting: try c.decodeIfPresent(String.self, forKey: .setting),
                  skills: try c.decodeIfPresent([String].self, forKey: .skills) ?? [],
                  allowedMoods: try c.decodeIfPresent([String].self, forKey: .allowedMoods) ?? ["calm"],
                  allowedAvatars: try c.decodeIfPresent([String].self, forKey: .allowedAvatars) ?? ["male"],
                  defaultMood: try c.decodeIfPresent(String.self, forKey: .defaultMood) ?? "calm",
                  defaultAvatar: try c.decodeIfPresent(String.self, forKey: .defaultAvatar) ?? "male",
                  avatarModel: try c.decodeIfPresent(String.self, forKey: .avatarModel))
    }

    /// Requested values checked against the case; omitted ones come from the defaults.
    /// Same rules as `resolve_config` in the backend (which answers 422).
    func resolve(_ requested: SessionConfig?) throws -> SessionConfig {
        try resolve(mood: requested?.mood, avatar: requested?.avatar)
    }

    func resolve(mood requestedMood: String?, avatar requestedAvatar: String?) throws -> SessionConfig {
        let mood = requestedMood ?? defaultMood, avatar = requestedAvatar ?? defaultAvatar
        guard allowedMoods.contains(mood) else {
            throw ConfigError(errorDescription: "Mood '\(mood)' is not available for this case. Allowed: \(allowedMoods.joined(separator: ", ")).")
        }
        guard allowedAvatars.contains(avatar) else {
            throw ConfigError(errorDescription: "Avatar '\(avatar)' is not available for this case. Allowed: \(allowedAvatars.joined(separator: ", ")).")
        }
        return SessionConfig(mood: mood, avatar: avatar)
    }

    /// A random combination the case allows ("Surprise me").
    func randomConfig() -> SessionConfig {
        SessionConfig(mood: allowedMoods.randomElement() ?? defaultMood, avatar: allowedAvatars.randomElement() ?? defaultAvatar)
    }

    /// Bundled model for an avatar choice: `Patient` for male, `Patient_<avatar>` otherwise,
    /// unless the case names its own model.
    func avatarModelName(for avatar: String) -> String {
        avatarModel ?? (avatar == "male" ? "Patient" : "Patient_\(avatar)")
    }
}

struct ConfigError: LocalizedError {
    let errorDescription: String?
}

/// What the patient is like in one encounter. Never changes findings or scoring.
struct SessionConfig: Codable, Hashable, Sendable {
    /// calm | nervous | angry (the case lists what it allows)
    var mood: String
    /// male | female
    var avatar: String
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
    /// Absent in older scenario files and servers.
    var catalog: CaseCatalog?
    /// Only cases with an ultrasound machine.
    var ultrasound: UltrasoundInfo?
}

struct SessionInfo: Codable, Hashable, Sendable {
    var sessionId: String
    var startedAt: String
    var `case`: CaseInfo
    /// The mood and avatar this session runs with (nil from an older server).
    var config: SessionConfig?
    /// Set when the session was launched from a published MedSim Studio scenario.
    var scenario: ScenarioRuntime? = nil
}

// MARK: - MedSim Studio scenario (docs/studio-api.md)

/// How a published scenario presents the case: setting, companions, equipment, coaching.
/// It never carries findings; `CaseInfo` in the same session is already shaped to it.
struct ScenarioRuntime: Codable, Hashable, Sendable {
    struct Figure: Codable, Hashable, Sendable { var angleDeg: Float; var distanceM: Float }
    struct Bystander: Codable, Hashable, Sendable {
        var name: String
        var roleLabel: String
        /// calm | anxious
        var mood: String
        var lines: [String: [String]]
        var interjectEveryS: Double
    }
    struct Teammate: Codable, Hashable, Sendable { var name: String; var roleLabel: String; var present: Bool }
    struct Equipment: Codable, Hashable, Identifiable, Sendable {
        var id: String; var label: String; var kind: String; var available: Bool
    }
    var scenarioId: String
    var version: Int
    var code: String
    var title: String
    /// draft | experimental | clinician_reviewed
    var reviewState: String
    var seed: Int
    var environmentId: String
    var environmentLabel: String
    var difficulty: String
    /// auto | on_request | off
    var hintPolicy: String
    /// 0...1
    var noiseLevel: Double
    var crowdFigures: [Figure]
    var bystander: Bystander?
    var teammate: Teammate
    var equipment: [Equipment]

    var reviewLabel: String {
        reviewState == "clinician_reviewed" ? "Clinician-reviewed" : "\(reviewState.capitalized) · not clinician-reviewed"
    }
}

/// A published scenario as the launch list shows it.
struct ScenarioSummary: Codable, Hashable, Identifiable, Sendable {
    var code: String
    var title: String
    var reviewState: String
    var environment: String
    var difficulty: String
    var crowdedness: String
    var id: String { code }
}

/// One instructor event from the Live Director, with the scenario and case as they are after it.
struct DirectorEventMessage: Codable, Sendable {
    struct Line: Codable, Hashable, Sendable { var speaker: String; var text: String }
    var type: String
    var seq: Int
    var eventId: String
    var kind: String
    var label: String
    var line: Line?
    var voiceContext: String?
    var scenario: ScenarioRuntime
    var `case`: CaseInfo
}

/// The parts of GET /sessions/{id}/debrief the app shows next to the feedback.
struct ScenarioDebrief: Codable, Hashable, Sendable {
    struct Intervention: Codable, Hashable, Sendable { var seq: Int; var label: String; var acknowledged: Bool }
    struct Hint: Codable, Hashable, Sendable { var seq: Int; var text: String }
    struct Step: Codable, Hashable, Sendable { var seq: Int; var type: String; var label: String }
    var interpretation: [String]
    var interventions: [Intervention]
    var hints: [Hint]
    var timeline: [Step]
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

// MARK: - Ultrasound

struct GelResult: Codable, Hashable, Sendable {
    var applied: Bool
    var patientResponse: String
    var voiceContext: String
    var repeatCount: Int
}

struct ScanMeasurement: Codable, Hashable, Sendable {
    var label: String
    var value: Double
    var unit: String

    /// "BPD 4.61 cm"
    var text: String { "\(label) \(String(format: "%g", value)) \(unit)" }
}

/// One probe contact as answered by the case engine. The images are real example sonograms
/// from different pregnancies (Resources/Ultrasound), not this patient.
struct ScanResult: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var regionId: String
    /// Nil: no usable image (no gel).
    var viewId: String?
    /// Id in ultrasound_manifest.json, or nil.
    var image: String?
    var title: String
    var caption: String
    var measurements: [ScanMeasurement]
    var imageCredit: String
    /// Decoration of the simulated machine.
    var depthCm: Double
    var gain: Int
    /// good | poor
    var quality: String
    var gelApplied: Bool
    /// May be empty: the patient says nothing.
    var patientResponse: String
    var voiceContext: String
    var repeatCount: Int

    enum CodingKeys: String, CodingKey {
        case regionId, viewId, image, title, caption, measurements, imageCredit, depthCm, gain, quality
        case gelApplied, patientResponse, voiceContext, repeatCount
    }
}

/// One expected (or optional) view versus what the learner obtained. Only after a diagnosis.
struct ScanReviewItem: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var label: String
    var expected: Bool
    var obtained: Bool
    var viewId: String?
    /// Manifest id: the learner's own view, or an example when missed.
    var image: String?
    var explanation: String
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
    /// What the patient says unprompted when the fit is uncomfortable (the app debounces it).
    var comfortable: Bool
    var patientResponse: String
    var voiceContext: String
    var animation: String
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

// MARK: - Spatial Clinical Replay

/// Teaching content for one examination zone. Only sent after a diagnosis.
struct ReplayZone: Codable, Hashable, Identifiable, Sendable {
    var zoneId: String
    var label: String
    var important: Bool
    var examined: Bool
    var finding: String?
    var painLevel: Int?
    var explanation: String
    var id: String { zoneId }
}

/// How an examination reached the engine. Only `touch` and `fingertip` are physical
/// interactions with the patient in the room.
enum ExamSource: String, Sendable {
    case touch = "gaze and pinch on the patient"
    case fingertip = "fingertip contact"
    case button = "fallback button, not a touch"
    case script = "scripted test, not a touch"
}

/// One examination as it happened, recorded by the app for the replay.
struct ExamEvent: Identifiable, Hashable, Sendable {
    var id: Int
    var zoneId: String
    var action: String
    var finding: String
    var painLevel: Int
    /// Seconds since the session started.
    var time: TimeInterval
    /// PatientState raw value when it happened.
    var pose: String
    /// Contact point in the zone's own space (metres); nil when no point exists (buttons).
    var contact: SIMD3<Float>?
    var source: ExamSource
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
    var replay: [ReplayZone]
    /// Ultrasound cases only (absent from older servers).
    var scanReview: [ScanReviewItem]? = nil
    var disclaimer: String
}

// MARK: - Service interfaces

/// Source of truth for clinical findings and scoring. One active session at a time.
@MainActor
protocol ClinicalEngine: AnyObject {
    /// Short human-readable mode for the status UI, e.g. "Backend", "Offline".
    var modeLabel: String { get }
    /// Cases bundled with the app, available instantly and offline (empty for a pure backend engine).
    var bundledCases: [CaseInfo] { get }
    /// Every case the engine can start. The backend answers `GET /cases`.
    func caseCatalog() async throws -> [CaseInfo]
    /// `config` nil = the case's defaults. A value the case does not allow is an error.
    func startSession(caseId: String, config: SessionConfig?) async throws -> SessionInfo
    func examine(zoneId: String, action: String) async throws -> ExaminationResult
    /// Records the order and returns the scenario's predefined result.
    func orderInvestigation(_ id: String) async throws -> InvestigationResult
    /// `valueCm` is the avatar measurement; the engine overrides it when the case predefines one.
    func recordMeasurement(_ id: String, valueCm: Double?) async throws -> MeasurementResult
    /// Records the support's current state (nil = removed). The outcome stays with the engine.
    func recordFit(_ fit: OrthosisFit?) async throws -> FitAck
    /// comfort | neurovascular, answered for the current fit.
    func fittingCheck(_ kind: String) async throws -> FittingCheckResult
    /// Ultrasound: records a gel application.
    func applyGel() async throws -> GelResult
    /// Ultrasound: one probe contact with a belly region. `gelApplied` is what the scene shows;
    /// the engine's own gel record decides, the flag can only make the scan worse.
    func scan(regionId: String, gelApplied: Bool?) async throws -> ScanResult
    /// Best effort; must never throw into the UI.
    func recordInteraction(_ turn: TranscriptTurn) async
    func diagnose(_ diagnosis: String, notes: ClinicalNotes) async throws -> Feedback
    func feedback() async throws -> Feedback
    func reset() async throws -> SessionInfo
}

extension ClinicalEngine {
    var bundledCases: [CaseInfo] { [] }
    func startSession(caseId: String) async throws -> SessionInfo { try await startSession(caseId: caseId, config: nil) }
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
    /// `voiceId` (optional) overrides the agent's TTS voice for this conversation; the agent
    /// must allow voice overrides (elevenlabs/setup.md). `resumeLine` continues a paused
    /// consultation: the patient opens with it instead of the agent's greeting (needs the
    /// first-message override; without it the agent greets as usual).
    func start(caseContext: String, voiceId: String?, resumeLine: String?) async
    func stop() async
    /// Note-taking mode: while muted the agent must not hear the learner (dictated notes).
    func setMicMuted(_ muted: Bool) async
    /// Background information for the agent. Must not make it speak.
    func sendContext(_ text: String) async
    /// Forwards `ExaminationResult.voiceContext`; the agent must speak a reaction.
    func sendExaminationEvent(_ text: String) async
}

extension VoiceService {
    func start(caseContext: String) async { await start(caseContext: caseContext, voiceId: nil, resumeLine: nil) }
}
