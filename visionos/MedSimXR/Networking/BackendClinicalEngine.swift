import Foundation

/// Non-2xx answer from the backend; `errorDescription` is the server's `detail`.
struct BackendHTTPError: LocalizedError {
    let status: Int
    let detail: String
    var errorDescription: String? { detail }
}

@MainActor
final class BackendClinicalEngine: ClinicalEngine {
    let modeLabel = "Backend"

    private let session: URLSession
    private var baseURL = AppConfig.backendURL
    private var sessionId: String?

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4
        cfg.timeoutIntervalForResource = 8
        session = URLSession(configuration: cfg)
    }

    private struct StartBody: Encodable { var caseId: String; var scenarioCode: String? = nil }
    private struct ExamineBody: Encodable { var bodyPart: String; var action: String }
    private struct InteractionBody: Encodable { var role: String; var text: String; var timestamp: String }
    private struct DiagnoseBody: Encodable { var diagnosis: String; var notes: ClinicalNotes }
    private struct InvestigationBody: Encodable { var investigationId: String }
    private struct MeasurementBody: Encodable { var measurementId: String; var valueCm: Double? }
    private struct FitBody: Encodable { var fit: OrthosisFit? }
    private struct CheckBody: Encodable { var check: String }
    private struct Detail: Decodable { var detail: String }

    func startSession(caseId: String) async throws -> SessionInfo {
        baseURL = AppConfig.backendURL // re-read so in-app settings changes apply
        sessionId = nil
        // A selected scenario configures the same case; the backend shapes the session to it.
        let info: SessionInfo = try await send("POST", "/sessions",
                                               StartBody(caseId: caseId, scenarioCode: AppConfig.scenarioCode))
        sessionId = info.sessionId
        return info
    }

    func reset() async throws -> SessionInfo {
        try await send("POST", "\(try path())/reset", Optional<StartBody>.none)
    }

    func examine(zoneId: String, action: String) async throws -> ExaminationResult {
        try await send("POST", "\(try path())/examine", ExamineBody(bodyPart: zoneId, action: action))
    }

    func orderInvestigation(_ id: String) async throws -> InvestigationResult {
        try await send("POST", "\(try path())/investigations", InvestigationBody(investigationId: id))
    }

    func recordMeasurement(_ id: String, valueCm: Double?) async throws -> MeasurementResult {
        try await send("POST", "\(try path())/measurements", MeasurementBody(measurementId: id, valueCm: valueCm))
    }

    func recordFit(_ fit: OrthosisFit?) async throws -> FitAck {
        try await send("POST", "\(try path())/fitting", FitBody(fit: fit))
    }

    func fittingCheck(_ kind: String) async throws -> FittingCheckResult {
        try await send("POST", "\(try path())/checks", CheckBody(check: kind))
    }

    func recordInteraction(_ turn: TranscriptTurn) async {
        guard let p = try? path() else { return }
        let body = InteractionBody(role: turn.role.rawValue, text: turn.text,
                                   timestamp: ISO8601DateFormatter().string(from: turn.timestamp))
        _ = try? await raw("POST", "\(p)/interactions", body)
    }

    func diagnose(_ diagnosis: String, notes: ClinicalNotes) async throws -> Feedback {
        try await send("POST", "\(try path())/diagnose", DiagnoseBody(diagnosis: diagnosis, notes: notes))
    }

    func feedback() async throws -> Feedback {
        try await send("GET", "\(try path())/feedback", Optional<StartBody>.none)
    }

    // MARK: HTTP

    private func path() throws -> String {
        guard let sessionId else { throw BackendHTTPError(status: 0, detail: "No active session.") }
        return "/sessions/\(sessionId)"
    }

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, _ body: B?) async throws -> T {
        try JSONDecoder.medsim.decode(T.self, from: try await raw(method, path, body))
    }

    private func raw<B: Encodable>(_ method: String, _ path: String, _ body: B?) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 4)
        req.httpMethod = method
        if let body {
            req.httpBody = try JSONEncoder.medsim.encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSONDecoder().decode(Detail.self, from: data))?.detail ?? "HTTP \(status)"
            throw BackendHTTPError(status: status, detail: detail)
        }
        return data
    }
}
