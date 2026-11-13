import Foundation

// MedSim Studio library and marketplace, as the in-headset Studio window shows them.
// Same JSON as the web Studio (docs/studio-api.md); decode with `JSONDecoder.medsim`.

/// Where a library scenario came from. `nil` on the row: created here.
struct StudioOrigin: Codable, Hashable, Sendable {
    var duplicatedFrom: String?
    var importedFrom: String?
    var downloadedFrom: String?
    var code: String?
    var version: Int?
    var claimedReviewState: String?
}

/// One scenario in the library (GET /studio/scenarios).
struct StudioScenarioRow: Codable, Hashable, Identifiable, Sendable {
    var scenarioId: String
    var code: String
    var title: String
    var version: Int
    var versions: Int
    var reviewState: String
    var publishedVersion: Int?
    var environment: String
    var difficulty: String
    var crowdedness: String
    var createdAt: String
    var aiGenerated: Bool
    var origin: StudioOrigin?
    /// Journey scenarios: place labels in order (absent from older servers and single encounters).
    var stages: [String]?
    var id: String { scenarioId }

    /// From the marketplace or a file, as opposed to created or duplicated here. Same split as
    /// the web Studio: every origin other than "duplicated here" is a download or an import.
    var isDownloaded: Bool { origin != nil && origin?.duplicatedFrom == nil }
    var isPublished: Bool { publishedVersion != nil }
}

/// A published scenario (GET /scenarios/published).
struct StudioMarketItem: Codable, Hashable, Identifiable, Sendable {
    var code: String
    var scenarioId: String
    var version: Int
    var title: String
    var description: String
    var reviewState: String
    var environment: String
    var difficulty: String
    var crowdedness: String
    /// Journey scenarios: place labels in order (absent from older servers and single encounters).
    var stages: [String]?
    var id: String { code }
}

/// The parts of a ScenarioDefinition (GET /studio/scenarios/{id}) the detail page shows.
struct StudioScenarioDetail: Codable, Hashable, Sendable {
    struct Review: Codable, Hashable, Sendable { var state: String; var reviewerName: String?; var reviewerRole: String? }
    struct Crowd: Codable, Hashable, Sendable { var label: String; var figures: [ScenarioRuntime.Figure] }
    struct Environment: Codable, Hashable, Sendable { var label: String; var brief: String; var ambientLevel: Double; var crowd: Crowd }
    struct Resource: Codable, Hashable, Identifiable, Sendable { var id: String; var label: String; var kind: String; var available: Bool; var deliverable: Bool }
    struct Teammate: Codable, Hashable, Sendable { var name: String; var roleLabel: String; var present: Bool }
    struct Bystander: Codable, Hashable, Sendable { var name: String; var roleLabel: String; var mood: String }
    struct Companions: Codable, Hashable, Sendable { var bystander: Bystander?; var teammate: Teammate }
    struct Difficulty: Codable, Hashable, Sendable { var label: String; var hintPolicy: String; var description: String }
    struct Dimension: Codable, Hashable, Identifiable, Sendable { var id: String; var title: String; var maxScore: Int; var achievableMax: Int }
    struct Choice: Codable, Hashable, Identifiable, Sendable { var id: String; var label: String }
    struct Assessment: Codable, Hashable, Sendable { var dimensions: [Dimension]; var learningObjectives: [Choice] }
    struct Narrative: Codable, Hashable, Sendable { var description: String; var aiGenerated: Bool }

    var scenarioId: String
    var version: Int
    var code: String
    var title: String
    var seed: Int
    var review: Review
    var published: Bool
    var environment: Environment
    var resources: [Resource]
    var companions: Companions
    var difficulty: Difficulty
    var assessment: Assessment
    var narrative: Narrative
    var origin: StudioOrigin?
}

/// A scenario session the backend knows about (GET /sessions/active), newest first.
struct StudioSession: Codable, Hashable, Identifiable, Sendable {
    var sessionId: String
    var startedAt: String
    var title: String
    var code: String
    var runtimeConnected: Bool
    var submitted: Bool
    var id: String { sessionId }
}

/// GET /sessions/{id}/debrief, the parts the headset shows.
struct StudioDebrief: Codable, Hashable, Sendable {
    struct Scenario: Codable, Hashable, Sendable {
        var code: String; var title: String; var reviewState: String
        var environment: String; var crowdedness: String; var difficulty: String
        var learningObjectives: [StudioScenarioDetail.Choice]
    }
    struct Resource: Codable, Hashable, Identifiable, Sendable {
        var id: String; var label: String
        var availableAtStart: Bool; var deliveredAtSeq: Int?; var availableAtEnd: Bool; var used: Bool
    }
    struct Line: Codable, Hashable, Sendable { var speaker: String; var text: String }
    struct Intervention: Codable, Hashable, Identifiable, Sendable {
        var seq: Int; var label: String; var at: String; var line: Line?; var acknowledged: Bool
        var id: Int { seq }
    }
    struct Score: Codable, Hashable, Sendable { var score: Int; var maxScore: Int; var achievableMax: Int? }
    struct Scores: Codable, Hashable, Sendable { var core: Score; var management: Score?; var fitting: Score? }
    struct Step: Codable, Hashable, Identifiable, Sendable { var seq: Int; var type: String; var label: String; var id: Int { seq } }

    var sessionId: String
    var scenario: Scenario
    var resources: [Resource]
    var interventions: [Intervention]
    var interpretation: [String]
    var scores: Scores?
    var timeline: [Step]
    var diagnosisSubmitted: String?
}

extension String {
    /// "clinician_reviewed" -> "Clinician-reviewed", "experimental" -> "Experimental".
    var reviewStateLabel: String {
        self == "clinician_reviewed" ? "Clinician-reviewed" : replacingOccurrences(of: "_", with: " ").capitalized
    }
}
