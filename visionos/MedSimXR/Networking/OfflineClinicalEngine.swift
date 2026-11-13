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
            var clinicalLabel: String?
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
                // investigation / management checks
                var investigations: [String]?
                var fields: [String]?
                var requiresOrdered: [String]?
                var ignoreNegated: Bool?
                var checks: [Check]?
                // fitting checks
                var measurements: [String]?
                var check: String?
            }
            var id: String
            var label: String
            var points: Int
            var check: Check
            var noteKeywords: [String]?
            var area: String?
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
        struct Management: Decodable {
            var title: String
            var maxScore: Int
            var criteria: [Criterion]
        }
        struct Investigation: Decodable {
            struct Result: Decodable {
                var title: String
                var report: String
                var impression: String
                var image: String?
                var imageCredit: String
            }
            var id: String
            var label: String
            var modality: String
            var result: Result
        }
        struct Hidden: Decodable {
            var diagnosis: Diagnosis
            var nextSteps: [String]
            var rubric: Rubric
            var management: Management
            var fitting: Fitting
        }
        struct Fitting: Decodable {
            struct Outcome: Decodable {
                var patientResponse: String
                var comfortable: Bool
                var animation: String
                var neurovascular: String
                var neurovascularResponse: String
                var explanation: String
            }
            // Whether dictionary keys pass through the snake_case strategy differs by platform: look up both forms.
            var measurements: [String: Double]
            var reference: FittingReference
            var outcomes: [String: Outcome]
            var rubric: Management
        }

        var caseId: String
        var title: String
        var learnerBrief: String
        var patient: PatientInfo
        var voiceContext: String
        var examinationZones: [Zone]
        var scriptedDialogue: [ScriptedLine]
        var investigations: [Investigation]
        var orthotics: Orthotics
        var hidden: Hidden
    }

    private struct Exam { var seq: Int; var zoneId: String; var pain: Int }
    private struct Turn { var seq: Int; var role: SpeakerRole; var text: String }

    private let scenario: Scenario
    private var sessionId: String?
    private var seq = 0
    private var exams: [Exam] = []
    private var turns: [Turn] = []
    /// Ordered investigation ids, in order (repeats included).
    private var orders: [String] = []
    private var measured: [(seq: Int, id: String)] = []
    private var fittings: [(seq: Int, fit: OrthosisFit?)] = []
    private var checks: [(seq: Int, kind: String)] = []
    private var diagnosis: String?
    private var notes = ClinicalNotes()

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

    func orderInvestigation(_ id: String) async throws -> InvestigationResult {
        guard sessionId != nil else { throw noSession }
        guard let inv = scenario.investigations.first(where: { $0.id == id }) else {
            throw OfflineEngineError(errorDescription: "Unknown investigation '\(id)'.")
        }
        seq += 1
        orders.append(id)
        let r = inv.result
        return InvestigationResult(
            investigationId: inv.id, label: inv.label, modality: inv.modality, title: r.title, report: r.report,
            impression: r.impression, image: r.image, imageCredit: r.imageCredit,
            orderedAt: ISO8601DateFormatter().string(from: Date()), repeatCount: orders.filter { $0 == id }.count
        )
    }

    func recordInteraction(_ turn: TranscriptTurn) async {
        guard sessionId != nil else { return }
        seq += 1
        turns.append(Turn(seq: seq, role: turn.role, text: turn.text))
    }

    func diagnose(_ diagnosis: String, notes: ClinicalNotes) async throws -> Feedback {
        guard sessionId != nil else { throw noSession }
        self.diagnosis = diagnosis
        self.notes = notes
        return try await feedback()
    }

    func feedback() async throws -> Feedback {
        guard let sessionId else { throw noSession }
        return buildFeedback(sessionId: sessionId)
    }

    // MARK: Session helpers

    private var noSession: OfflineEngineError { OfflineEngineError(errorDescription: "No active session.") }

    private func clear() -> SessionInfo {
        seq = 0; exams = []; turns = []; orders = []; measured = []; fittings = []; checks = []; diagnosis = nil; notes = ClinicalNotes()
        let s = scenario
        return SessionInfo(
            sessionId: sessionId ?? "", startedAt: ISO8601DateFormatter().string(from: Date()),
            case: CaseInfo(
                caseId: s.caseId, title: s.title, learnerBrief: s.learnerBrief, patient: s.patient,
                voiceContext: s.voiceContext,
                zones: s.examinationZones.map {
                    ZoneInfo(id: $0.id, label: $0.label, attachTo: $0.attachTo, offset: $0.offset, radius: $0.radius)
                },
                scriptedDialogue: s.scriptedDialogue,
                investigations: s.investigations.map { InvestigationInfo(id: $0.id, label: $0.label) },
                orthotics: s.orthotics
            )
        )
    }

    // MARK: Rubric engine

    private struct Outcome { var met: Bool; var points: Int; var method: String; var evidence: String? }

    private var learnerTurns: [Turn] { turns.filter { $0.role == .learner } }

    /// Whole word/phrase, case-insensitive; trailing "*" = stem ("numb*" matches "numbness").
    /// Must stay identical to `_hit` in backend/app/evaluation.py.
    private func hits(_ text: String, _ keywords: [String]) -> Bool {
        let t = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        return keywords.contains { keyword in
            let stem = keyword.hasSuffix("*")
            let body = keyword.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "* "))
            let pattern = "(?<!\\w)" + NSRegularExpression.escapedPattern(for: body) + (stem ? "" : "(?!\\w)")
            return t.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func firstLearnerQuote(_ keywords: [String], where include: (Turn) -> Bool = { _ in true }) -> String? {
        learnerTurns.first { include($0) && hits($0.text, keywords) }?.text
    }

    /// Anatomical name; only used in feedback after a diagnosis.
    private func label(_ zoneId: String) -> String {
        let zone = scenario.examinationZones.first { $0.id == zoneId }
        return zone?.clinicalLabel ?? zone?.label ?? zoneId
    }

    private func evaluate(_ c: Scenario.Criterion, diagnosis dx: String?, plan: String?) -> Outcome {
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
            let dxHit = plan.flatMap { hits($0, kw) ? $0 : nil }
            return keyword(firstLearnerQuote(kw) ?? dxHit)
        case "diagnosis_matches":
            let d = scenario.hidden.diagnosis
            let text = dx ?? ""
            if hits(text, d.acceptedKeywords) { return Outcome(met: true, points: full, method: "rule", evidence: dx) }
            if hits(text, d.partialKeywords) { return Outcome(met: false, points: full / 2, method: "rule", evidence: nil) }
            return Outcome(met: false, points: 0, method: "rule", evidence: nil)
        default:
            return Outcome(met: false, points: 0, method: "rule", evidence: nil)
        }
    }

    // MARK: Measurement and orthosis fitting (mirrors backend/app/fitting.py)

    private func camel(_ key: String) -> String {
        let parts = key.split(separator: "_")
        return ([String(parts.first ?? "")] + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }).joined()
    }

    func recordMeasurement(_ id: String, valueCm: Double?) async throws -> MeasurementResult {
        guard sessionId != nil else { throw noSession }
        guard let spec = scenario.orthotics.measurements.first(where: { $0.id == id }) else {
            throw OfflineEngineError(errorDescription: "Unknown measurement '\(id)'.")
        }
        let predefined = scenario.hidden.fitting.measurements[id] ?? scenario.hidden.fitting.measurements[camel(id)]
        guard let raw = predefined ?? valueCm else {
            throw OfflineEngineError(errorDescription: "Measurement '\(id)' needs a value from the avatar.")
        }
        seq += 1
        measured.append((seq, id))
        return MeasurementResult(measurementId: id, label: spec.label, kind: spec.kind,
                                 valueCm: (raw * 10).rounded() / 10, source: predefined != nil ? "case" : "avatar")
    }

    private func outcome(_ fit: OrthosisFit?) -> String {
        guard let fit else { return "none" }
        let ref = scenario.hidden.fitting.reference
        let sizes = scenario.orthotics.sizes.map(\.id), levels = scenario.orthotics.tightness
        func index(_ list: [String], _ value: String) -> Int { list.firstIndex(of: value) ?? -1 }
        if fit.offsetCm < ref.offsetCm[0] || fit.offsetCm > ref.offsetCm[1] { return "wrong_position" }
        if fit.orientation != ref.orientation { return "wrong_orientation" }
        if fit.size != ref.size { return index(sizes, fit.size) < index(sizes, ref.size) ? "too_small" : "too_large" }
        if fit.tightness != ref.tightness {
            return index(levels, fit.tightness) > index(levels, ref.tightness) ? "too_tight" : "too_loose"
        }
        return "appropriate"
    }

    private func outcomeSpec(_ fit: OrthosisFit?) -> Scenario.Fitting.Outcome {
        { let key = outcome(fit); let all = scenario.hidden.fitting.outcomes; return all[key] ?? all[camel(key)]! }()
    }

    private var currentFit: OrthosisFit? { fittings.last?.fit }

    func recordFit(_ fit: OrthosisFit?) async throws -> FitAck {
        guard sessionId != nil else { throw noSession }
        if let fit, !scenario.orthotics.sizes.contains(where: { $0.id == fit.size })
            || !scenario.orthotics.tightness.contains(fit.tightness) {
            throw OfflineEngineError(errorDescription: "Unknown orthosis size or tightness.")
        }
        seq += 1
        fittings.append((seq, fit))
        let note = fit == nil ? "[Context only, do not speak now. The wrist support was taken off again.]"
            : "[Context only, do not speak now. A wrist support was just put on or adjusted on your right wrist. "
              + "If the student asks how it feels, answer with this meaning: \"\(outcomeSpec(fit).patientResponse)\"]"
        return FitAck(attempt: fittings.filter { $0.fit != nil }.count, voiceNote: note)
    }

    func fittingCheck(_ kind: String) async throws -> FittingCheckResult {
        guard sessionId != nil else { throw noSession }
        guard kind == "comfort" || kind == "neurovascular" else {
            throw OfflineEngineError(errorDescription: "Unknown check '\(kind)'.")
        }
        let fit = currentFit, spec = outcomeSpec(fit), nv = kind == "neurovascular"
        seq += 1
        checks.append((seq, kind))
        let response = nv ? spec.neurovascularResponse : spec.patientResponse
        let lead = nv ? "[The student checks the colour, feeling and movement of your fingers."
                      : "[The student asks how the wrist support feels."
        return FittingCheckResult(
            check: kind, phase: fit == nil ? "before" : "after", finding: nv ? spec.neurovascular : nil,
            patientResponse: response,
            voiceContext: lead + " Answer out loud right now in one short sentence with this meaning: \"\(response)\"]",
            comfortable: spec.comfortable, animation: nv ? "none" : spec.animation)
    }

    private func buildFitting(redact: Bool) -> FittingAssessment {
        let spec = scenario.hidden.fitting, ref = spec.reference, fit = currentFit
        let firstFit = fittings.first { $0.fit != nil }?.seq ?? Int.max
        let lastChange = fittings.last?.seq ?? Int.max
        func met(_ c: Scenario.Criterion.Check) -> Bool {
            switch c.type {
            case "measured":
                return measured.contains { (c.measurements ?? []).contains($0.id) && $0.seq < firstFit }
            case "checked_before_fit":
                return checks.contains { $0.kind == c.check && $0.seq < firstFit }
            case "final_fit":
                guard let fit else { return false }
                return (c.fields ?? []).allSatisfy { field in
                    switch field {
                    case "size": fit.size == ref.size
                    case "orientation": fit.orientation == ref.orientation
                    case "tightness": fit.tightness == ref.tightness
                    case "offset_cm": fit.offsetCm >= ref.offsetCm[0] && fit.offsetCm <= ref.offsetCm[1]
                    default: false
                    }
                }
            case "checked_after_final_fit":
                guard fit != nil else { return false }
                if checks.contains(where: { $0.kind == c.check && $0.seq > lastChange }) { return true }
                return learnerTurns.contains { $0.seq > lastChange && hits($0.text, c.keywords ?? []) }
            default:
                return false
            }
        }
        let criteria = spec.rubric.criteria.map { c -> CriterionResult in
            let ok = met(c.check)
            return CriterionResult(id: c.id, label: c.label, met: ok, points: ok ? c.points : 0, maxPoints: c.points,
                                   method: "rule", evidence: nil, comment: ok ? c.metText : c.missedText, area: c.area)
        }
        return FittingAssessment(
            title: spec.rubric.title, score: criteria.reduce(0) { $0 + $1.points }, maxScore: spec.rubric.maxScore,
            criteria: redact ? [] : criteria, finalFit: fit, reference: redact ? nil : ref,
            explanation: redact ? nil : outcomeSpec(fit).explanation)
    }

    // MARK: Investigation and management (separate from the 100-point rubric)

    /// Must stay identical to `_management_check` in backend/app/evaluation.py.
    private func managementCheck(_ check: Scenario.Criterion.Check, ordered: [String], texts: [String: String]) -> Outcome {
        let kw = check.keywords ?? []
        switch check.type {
        case "ordered_any":
            let hit = ordered.first { (check.investigations ?? []).contains($0) }
            let label = hit.flatMap { id in scenario.investigations.first { $0.id == id }?.label }
            return Outcome(met: hit != nil, points: 0, method: "rule", evidence: label)
        case "any_of":
            var result = Outcome(met: false, points: 0, method: "rule", evidence: nil)
            for sub in check.checks ?? [] {
                result = managementCheck(sub, ordered: ordered, texts: texts)
                if result.met { break }
            }
            return result
        case "notes_avoided":
            let written = (check.fields ?? []).map { texts[$0] ?? "" }
            let met = written.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                && !written.contains { hits($0, kw) }
            return Outcome(met: met, points: 0, method: "keyword", evidence: nil)
        default: // notes_said
            var written = (check.fields ?? []).map { texts[$0] ?? "" }
            if check.ignoreNegated == true { // "no follow-up" must not count as arranging follow-up
                written = written.map {
                    $0.lowercased().replacingOccurrences(
                        of: "(?<!\\w)(?:no|not|without|kein\\w*|ohne)\\s+[\\w-]+(?:\\s+[\\w-]+)?",
                        with: " ", options: .regularExpression)
                }
            }
            var quote = written.first { hits($0, kw) }
            if let need = check.requiresOrdered, !ordered.contains(where: { need.contains($0) }) { quote = nil }
            return Outcome(met: quote != nil, points: 0, method: "keyword", evidence: quote)
        }
    }

    private func buildManagement(diagnosis dx: String?, redact: Bool) -> (ManagementAssessment, [String]) {
        let spec = scenario.hidden.management
        var seen = Set<String>()
        let ordered = orders.filter { seen.insert($0).inserted }
        let texts = ["diagnosis": dx ?? "", "assessment": notes.assessment, "interpretation": notes.interpretation,
                     "management": notes.management, "follow_up": notes.followUp]
        let criteria = spec.criteria.map { c -> CriterionResult in
            let o = managementCheck(c.check, ordered: ordered, texts: texts)
            return CriterionResult(id: c.id, label: c.label, met: o.met, points: o.met ? c.points : 0, maxPoints: c.points,
                                   method: o.method, evidence: o.met ? o.evidence : nil,
                                   comment: o.met ? c.metText : c.missedText, area: c.area)
        }
        let lines = ordered.compactMap { id in
            scenario.investigations.first { $0.id == id }.map { "\($0.label): \($0.result.impression)" }
        }
        return (ManagementAssessment(title: spec.title, score: criteria.reduce(0) { $0 + $1.points },
                                     maxScore: spec.maxScore, criteria: redact ? [] : criteria), lines)
    }

    private func buildFeedback(sessionId: String) -> Feedback {
        let h = scenario.hidden
        let dx = diagnosis.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        var strengths: [String] = [], missed: [String] = []
        var documentation: [DocumentationItem] = []
        let noteText = [notes.history, notes.examination, notes.assessment].joined(separator: "\n")
        let hasNotes = !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // The written assessment is read together with the diagnosis (reasoning, not examination).
        let written = [notes.assessment, notes.interpretation, notes.management, notes.followUp]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let plan = dx.map { ([$0] + written).joined(separator: "\n") }

        var categories = h.rubric.categories.map { cat -> CategoryResult in
            let criteria = cat.criteria.map { c -> CriterionResult in
                let o = evaluate(c, diagnosis: dx, plan: plan)
                if o.met { strengths.append(c.metText) } else { missed.append(c.missedText) }
                if hasNotes, let keywords = c.noteKeywords {
                    let noted = hits(noteText, keywords)
                    if noted || o.met {
                        let status = noted && o.met ? "documented" : noted ? "unsupported" : "undocumented"
                        let comment: String
                        switch status {
                        case "documented": comment = "Documented, and supported by the session record."
                        case "undocumented": comment = "You did this, but did not write it down."
                        default:
                            comment = "Your notes mention this, but no matching "
                                + (cat.id == "examination" ? "examination" : "question")
                                + " was recorded. Notes alone earn no points."
                        }
                        documentation.append(DocumentationItem(criterionId: c.id, label: c.label, status: status, comment: comment))
                    }
                }
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
            return "\(dx == nil ? z.label : label(z.id)): \(z.result.finding.replacingOccurrences(of: "_", with: " ")) (pain \(z.result.painLevel)/10)"
        }

        let transcript = !learnerTurns.isEmpty
        var summary = Self.composeSummary(transcriptAvailable: transcript, strengths: strengths, missed: missed, explanation: explanation)
        if dx == nil { // redact: rubric wording reveals the diagnosis
            categories = categories.map { var c = $0; c.criteria = []; return c }
            strengths = []; missed = []; documentation = []
            summary = "Submit a diagnosis to unlock detailed feedback."
        } else if documentation.contains(where: { $0.status == "unsupported" }) {
            summary += " Some of your notes are not supported by what was actually asked or examined."
        }
        let (management, investigations) = buildManagement(diagnosis: dx, redact: dx == nil)
        return Feedback(
            sessionId: sessionId, caseId: scenario.caseId, diagnosisSubmitted: dx,
            totalScore: categories.reduce(0) { $0 + $1.score }, maxScore: categories.reduce(0) { $0 + $1.maxScore },
            summary: summary,
            transcriptAvailable: transcript,
            diagnosticAssessment: DiagnosticAssessment(verdict: verdict, explanation: explanation, expected: dx == nil ? nil : d.name),
            categories: categories, strengths: strengths, missed: missed, relevantFindings: findings,
            nextSteps: dx == nil ? [] : h.nextSteps, documentation: documentation,
            management: management, investigations: investigations, fitting: buildFitting(redact: dx == nil),
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
