import Foundation

/// Backend first; the offline engine shadows every event so it can take over mid-session.
@MainActor
final class FallbackClinicalEngine: ClinicalEngine {
    private let primary: ClinicalEngine
    private let offline: OfflineClinicalEngine
    private var usingPrimary = true

    var modeLabel: String { usingPrimary ? primary.modeLabel : offline.modeLabel }

    init(primary: ClinicalEngine, offline: OfflineClinicalEngine) {
        self.primary = primary
        self.offline = offline
    }

    /// Runs `call` on the primary while healthy; any failure (unreachable, or a restarted
    /// backend answering 404 for our session) switches to `shadow` for the rest of the session.
    private func route<T>(_ call: () async throws -> T, shadow: () async throws -> T) async throws -> T {
        guard usingPrimary else { return try await shadow() }
        do { return try await call() }
        catch { usingPrimary = false; return try await shadow() }
    }

    var bundledCases: [CaseInfo] { offline.bundledCases }

    /// The backend's list wins for cases both know; bundled cases the server lacks stay available.
    func caseCatalog() async throws -> [CaseInfo] {
        let local = offline.bundledCases
        guard let remote = try? await primary.caseCatalog(), !remote.isEmpty else { return local }
        let localOnly = local.filter { l in !remote.contains { $0.caseId == l.caseId } }
        return remote + localOnly
    }

    func startSession(caseId: String, config: SessionConfig?) async throws -> SessionInfo {
        // A case only the server knows has no offline shadow; a bad config fails in both engines.
        let shadow = await Result { try await offline.startSession(caseId: caseId, config: config) }
        usingPrimary = true // a new session retries the backend
        return try await route({ try await primary.startSession(caseId: caseId, config: config) }, shadow: { try shadow.get() })
    }

    func reset() async throws -> SessionInfo {
        let shadow = try await offline.reset()
        return try await route({ try await primary.reset() }, shadow: { shadow })
    }

    func examine(zoneId: String, action: String) async throws -> ExaminationResult {
        let shadow = await Result { try await offline.examine(zoneId: zoneId, action: action) }
        return try await route({ try await primary.examine(zoneId: zoneId, action: action) }, shadow: { try shadow.get() })
    }

    func orderInvestigation(_ id: String) async throws -> InvestigationResult {
        let shadow = await Result { try await offline.orderInvestigation(id) }
        return try await route({ try await primary.orderInvestigation(id) }, shadow: { try shadow.get() })
    }

    func recordMeasurement(_ id: String, valueCm: Double?) async throws -> MeasurementResult {
        let shadow = await Result { try await offline.recordMeasurement(id, valueCm: valueCm) }
        return try await route({ try await primary.recordMeasurement(id, valueCm: valueCm) }, shadow: { try shadow.get() })
    }

    func recordFit(_ fit: OrthosisFit?) async throws -> FitAck {
        let shadow = await Result { try await offline.recordFit(fit) }
        return try await route({ try await primary.recordFit(fit) }, shadow: { try shadow.get() })
    }

    func fittingCheck(_ kind: String) async throws -> FittingCheckResult {
        let shadow = await Result { try await offline.fittingCheck(kind) }
        return try await route({ try await primary.fittingCheck(kind) }, shadow: { try shadow.get() })
    }

    func applyGel() async throws -> GelResult {
        let shadow = await Result { try await offline.applyGel() }
        return try await route({ try await primary.applyGel() }, shadow: { try shadow.get() })
    }

    func scan(regionId: String, gelApplied: Bool?) async throws -> ScanResult {
        let shadow = await Result { try await offline.scan(regionId: regionId, gelApplied: gelApplied) }
        return try await route({ try await primary.scan(regionId: regionId, gelApplied: gelApplied) }, shadow: { try shadow.get() })
    }

    func advanceStage(_ stageId: String) async throws -> StageResult {
        let shadow = await Result { try await offline.advanceStage(stageId) }
        return try await route({ try await primary.advanceStage(stageId) }, shadow: { try shadow.get() })
    }

    func requestTeamAction(_ actionId: String) async throws -> TeamActionResult {
        let shadow = await Result { try await offline.requestTeamAction(actionId) }
        return try await route({ try await primary.requestTeamAction(actionId) }, shadow: { try shadow.get() })
    }

    func recordInteraction(_ turn: TranscriptTurn) async {
        await offline.recordInteraction(turn)
        if usingPrimary { await primary.recordInteraction(turn) }
    }

    func diagnose(_ diagnosis: String, notes: ClinicalNotes) async throws -> Feedback {
        let shadow = try await offline.diagnose(diagnosis, notes: notes)
        return try await route({ try await primary.diagnose(diagnosis, notes: notes) }, shadow: { shadow })
    }

    func feedback() async throws -> Feedback {
        try await route({ try await primary.feedback() }, shadow: { try await offline.feedback() })
    }
}

private extension Result where Failure == Error {
    init(_ body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
