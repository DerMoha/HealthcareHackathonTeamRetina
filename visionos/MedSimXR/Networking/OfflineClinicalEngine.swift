import Foundation

/// Failure reported by the offline engine (mirrors the backend's 404 / no-session cases).
struct OfflineEngineError: LocalizedError {
    let errorDescription: String?
}

/// Implements the contract's examination + rubric rules from the bundled scenario JSON.
/// Foundation only, so scripts/check_offline_engine.sh can compile it on macOS.
@MainActor
final class OfflineClinicalEngine: ClinicalEngine {
    let modeLabel = "Offline"

    // MARK: Scenario model (private decoding of scenarios/<case_id>.json)

    private struct Scenario: Decodable {
        struct Zone: Decodable {
            struct Result: Decodable {
                var finding: String
                var painLevel: Int
                var reaction: String
                var patientResponse: String
                var animation: String
                var voiceContext: String
            }
            var id: String
            var label: String
            var attachTo: String
            var offset: [Float]
            var radius: Float
            var result: Result
        }
        struct Diagnosis: Decodable {
            var name: String
            var acceptedKeywords: [String]
            var partialKeywords: [String]
            var correctText: String
            var partialText: String
            var incorrectText: String
            var notSubmittedText: String
        }
        struct Criterion: Decodable {
            struct Check: Decodable {
                var type: String
                var keywords: [String]?
                var zones: [String]?
                var requiresExamined: [String]?
            }
            var id: String
            var label: String
            var points: Int
            var check: Check
            var metText: String
            var missedText: String
        }
        struct Category: Decodable {
            var id: String
            var title: String
            var maxScore: Int
            var criteria: [Criterion]
        }
        struct Rubric: Decodable { var categories: [Category] }
        struct Hidden: Decodable {
            var diagnosis: Diagnosis
            var nextSteps: [String]
            var rubric: Rubric
        }

        var caseId: String
        var title: String
        var learnerBrief: String
        var patient: PatientInfo
        var voiceContext: String
        var examinationZones: [Zone]
        var scriptedDialogue: [ScriptedLine]
        var hidden: Hidden
    }

    private struct Exam { var seq: Int; var zoneId: String; var pain: Int }
    private struct Turn { var seq: Int; var role: SpeakerRole; var text: String }

    private let scenario: Scenario
    private var sessionId: String?
    private var seq = 0
    private var exams: [Exam] = []
    private var turns: [Turn] = []
    private var diagnosis: String?

    init(scenarioData: Data) throws {
        scenario = try JSONDecoder.medsim.decode(Scenario.self, from: scenarioData)
    }

    convenience init(caseId: String, bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: caseId, withExtension: "json") else {
            throw OfflineEngineError(errorDescription: "Scenario \(caseId).json is not bundled.")
        }
        try self.init(scenarioData: Data(contentsOf: url))
    }

    // MARK: ClinicalEngine

    func startSession(caseId: String) async throws -> SessionInfo {
        guard caseId == scenario.caseId else {
            throw OfflineEngineError(errorDescription: "Unknown case \(caseId).")
        }
        sessionId = UUID().uuidString.lowercased()
        return clear()
    }

    func reset() async throws -> SessionInfo {
        guard sessionId != nil else { throw noSession }
        return clear()
    }

    func examine(zoneId: String, action: String) async throws -> ExaminationResult {
        guard sessionId != nil else { throw noSession }
        guard let zone = scenario.examinationZones.first(where: { $0.id == zoneId }) else {
            throw OfflineEngineError(errorDescription: "Unknown examination zone '\(zoneId)'.")
        }
        seq += 1
        exams.append(Exam(seq: seq, zoneId: zoneId, pain: zone.result.painLevel))
        let r = zone.result
        return ExaminationResult(
            bodyPart: zoneId, action: action, finding: r.finding, painLevel: r.painLevel,
            reaction: r.reaction, patientResponse: r.patientResponse, animation: r.animation,
            voiceContext: r.voiceContext, repeatCount: exams.filter { $0.zoneId == zoneId }.count
        )
    }

    func recordInteraction(_ turn: TranscriptTurn) async {
        guard sessionId != nil else { return }
        seq += 1
        turns.append(Turn(seq: seq, role: turn.role, text: turn.text))
    }

    func diagnose(_ diagnosis: String) async throws -> Feedback {
        guard sessionId != nil else { throw noSession }
        self.diagnosis = diagnosis
        return try await feedback()
    }

    func feedback() async throws -> Feedback {
        guard let sessionId else { throw noSession }
        return buildFeedback(sessionId: sessionId)
    }

    // MARK: Session helpers

    private var noSession: OfflineEngineError { OfflineEngineError(errorDescription: "No active session.") }

    private func clear() -> SessionInfo {
        seq = 0; exams = []; turns = []; diagnosis = nil
        let s = scenario
        return SessionInfo(
            sessionId: sessionId ?? "", startedAt: ISO8601DateFormatter().string(from: Date()),
            case: CaseInfo(
                caseId: s.caseId, title: s.title, learnerBrief: s.learnerBrief, patient: s.patient,
                voiceContext: s.voiceContext,
                zones: s.examinationZones.map {
                    ZoneInfo(id: $0.id, label: $0.label, attachTo: $0.attachTo, offset: $0.offset, radius: $0.radius)
                },
                scriptedDialogue: s.scriptedDialogue
            )
        )
    }

    // MARK: Rubric engine

    private struct Outcome { var met: Bool; var points: Int; var method: String; var evidence: String? }

    private var learnerTurns: [Turn] { turns.filter { $0.role == .learner } }

    private func hits(_ text: String, _ keywords: [String]) -> Bool {
        let t = text.lowercased()
        return keywords.contains { t.contains($0.lowercased()) }
    }

    private func firstLearnerQuote(_ keywords: [String], where include: (Turn) -> Bool = { _ in true }) -> String? {
        learnerTurns.first { include($0) && hits($0.text, keywords) }?.text
    }

    private func label(_ zoneId: String) -> String {
        scenario.examinationZones.first { $0.id == zoneId }?.label ?? zoneId
    }

    private func evaluate(_ c: Scenario.Criterion, diagnosis dx: String?) -> Outcome {
        let kw = c.check.keywords ?? []
        let full = c.points
        func keyword(_ quote: String?) -> Outcome {
            Outcome(met: quote != nil, points: quote != nil ? full : 0, method: "keyword", evidence: quote)
        }
        switch c.check.type {
        case "learner_said":
            return keyword(firstLearnerQuote(kw))
        case "learner_said_before_exam":
            let firstExam = exams.first?.seq ?? Int.max
            return keyword(firstLearnerQuote(kw) { $0.seq < firstExam })
        case "learner_said_after_pain":
            guard let firstPain = exams.first(where: { $0.pain >= 5 })?.seq else { return keyword(nil) }
            return keyword(firstLearnerQuote(kw) { $0.seq > firstPain })
        case "learner_avoided":
            let ok = !learnerTurns.isEmpty && firstLearnerQuote(kw) == nil
            return Outcome(met: ok, points: ok ? full : 0, method: "keyword", evidence: nil)
        case "examined_any":
            let zones = c.check.zones ?? []
            let hit = exams.first { zones.contains($0.zoneId) }
            return Outcome(met: hit != nil, points: hit != nil ? full : 0, method: "rule", evidence: hit.map { label($0.zoneId) })
        case "diagnosis_or_learner_said":
            let required = c.check.requiresExamined ?? []
            guard required.isEmpty || exams.contains(where: { required.contains($0.zoneId) }) else { return keyword(nil) }
            let dxHit = dx.flatMap { hits($0, kw) ? $0 : nil }
            return keyword(dxHit ?? firstLearnerQuote(kw))
        case "diagnosis_matches":
            let d = scenario.hidden.diagnosis
            let text = dx ?? ""
            if hits(text, d.acceptedKeywords) { return Outcome(met: true, points: full, method: "rule", evidence: dx) }
            if hits(text, d.partialKeywords) { return Outcome(met: false, points: full / 2, method: "rule", evidence: dx) }
            return Outcome(met: false, points: 0, method: "rule", evidence: nil)
        default:
            return Outcome(met: false, points: 0, method: "rule", evidence: nil)
        }
    }

    private func buildFeedback(sessionId: String) -> Feedback {
        let h = scenario.hidden
        let dx = diagnosis.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        var strengths: [String] = [], missed: [String] = []

        let categories = h.rubric.categories.map { cat -> CategoryResult in
            let criteria = cat.criteria.map { c -> CriterionResult in
                let o = evaluate(c, diagnosis: dx)
                if o.met { strengths.append(c.metText) } else { missed.append(c.missedText) }
                return CriterionResult(id: c.id, label: c.label, met: o.met, points: o.points, maxPoints: c.points,
                                       method: o.method, evidence: o.evidence, comment: o.met ? c.metText : c.missedText)
            }
            return CategoryResult(id: cat.id, title: cat.title, score: criteria.reduce(0) { $0 + $1.points },
                                  maxScore: cat.maxScore, criteria: criteria)
        }

        let d = h.diagnosis
        let verdict: String, explanation: String
        if let dx {
            if hits(dx, d.acceptedKeywords) { (verdict, explanation) = ("correct", d.correctText) }
            else if hits(dx, d.partialKeywords) { (verdict, explanation) = ("partial", d.partialText) }
            else { (verdict, explanation) = ("incorrect", d.incorrectText) }
        } else {
            (verdict, explanation) = ("not_submitted", d.notSubmittedText)
        }

        var seen = Set<String>()
        let findings = exams.compactMap { e -> String? in
            guard seen.insert(e.zoneId).inserted,
                  let z = scenario.examinationZones.first(where: { $0.id == e.zoneId }) else { return nil }
            return "\(z.label): \(z.result.finding.replacingOccurrences(of: "_", with: " ")) (pain \(z.result.painLevel)/10)"
        }

        let transcript = !learnerTurns.isEmpty
        return Feedback(
            sessionId: sessionId, caseId: scenario.caseId, diagnosisSubmitted: dx,
            totalScore: categories.reduce(0) { $0 + $1.score }, maxScore: categories.reduce(0) { $0 + $1.maxScore },
            summary: Self.composeSummary(transcriptAvailable: transcript, strengths: strengths, missed: missed, explanation: explanation),
            transcriptAvailable: transcript,
            diagnosticAssessment: DiagnosticAssessment(verdict: verdict, explanation: explanation, expected: dx == nil ? nil : d.name),
            categories: categories, strengths: strengths, missed: missed, relevantFindings: findings,
            nextSteps: dx == nil ? [] : h.nextSteps,
            disclaimer: "Educational simulation only. Not a clinical diagnostic tool. Transcript-based criteria use simple keyword heuristics."
        )
    }

    /// Summary template. Isolated here so it can be aligned with backend/app/evaluation.py.
    static func composeSummary(transcriptAvailable: Bool, strengths: [String], missed: [String], explanation: String) -> String {
        var parts: [String] = []
        if !transcriptAvailable {
            parts.append("No conversation transcript was recorded, so history-taking and communication could not be assessed.")
        }
        if let s = strengths.first { parts.append(s) }
        if let m = missed.first { parts.append("However, " + m.prefix(1).lowercased() + m.dropFirst()) }
        parts.append(explanation)
        return parts.joined(separator: " ")
    }
}
