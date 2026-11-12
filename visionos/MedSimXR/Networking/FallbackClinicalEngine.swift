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

    func startSession(caseId: String) async throws -> SessionInfo {
        let shadow = try await offline.startSession(caseId: caseId)
        usingPrimary = true // a new session retries the backend
        return try await route({ try await primary.startSession(caseId: caseId) }, shadow: { shadow })
    }

    func reset() async throws -> SessionInfo {
        let shadow = try await offline.reset()
        return try await route({ try await primary.reset() }, shadow: { shadow })
    }

    func examine(zoneId: String, action: String) async throws -> ExaminationResult {
        let shadow = await Result { try await offline.examine(zoneId: zoneId, action: action) }
        return try await route({ try await primary.examine(zoneId: zoneId, action: action) }, shadow: { try shadow.get() })
    }

    func recordInteraction(_ turn: TranscriptTurn) async {
        await offline.recordInteraction(turn)
        if usingPrimary { await primary.recordInteraction(turn) }
    }

    func diagnose(_ diagnosis: String) async throws -> Feedback {
        let shadow = try await offline.diagnose(diagnosis)
        return try await route({ try await primary.diagnose(diagnosis) }, shadow: { shadow })
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
