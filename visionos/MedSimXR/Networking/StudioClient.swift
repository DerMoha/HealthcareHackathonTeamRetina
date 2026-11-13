import Foundation

/// The library and marketplace endpoints the in-headset Studio uses (docs/studio-api.md).
/// Like ScenarioClient there is no offline fallback: without a backend the Studio says so.
enum StudioClient {
    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    private struct Detail: Decodable { var detail: String }

    private static func call<T: Decodable>(_ method: String, _ path: String) async throws -> T {
        var req = URLRequest(url: AppConfig.backendURL.appendingPathComponent(path), timeoutInterval: 6)
        req.httpMethod = method
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw Failure(message: "The MedSim backend at \(AppConfig.backendHost) is not reachable. Check Settings › Backend host.")
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSONDecoder().decode(Detail.self, from: data))?.detail
            throw Failure(message: detail ?? "The backend answered \(status).")
        }
        return try JSONDecoder.medsim.decode(T.self, from: data)
    }

    static func library() async throws -> [StudioScenarioRow] { try await call("GET", "/studio/scenarios") }
    static func published() async throws -> [StudioMarketItem] { try await call("GET", "/scenarios/published") }
    static func sessions() async throws -> [StudioSession] { try await call("GET", "/sessions/active") }
    static func scenario(_ id: String) async throws -> StudioScenarioDetail { try await call("GET", "/studio/scenarios/\(id)") }
    static func debrief(_ sessionId: String) async throws -> StudioDebrief { try await call("GET", "/sessions/\(sessionId)/debrief") }

    /// A draft copy of the published version behind `code`.
    static func download(_ code: String) async throws -> StudioScenarioDetail { try await call("POST", "/studio/marketplace/\(code)/download") }
    static func duplicate(_ id: String) async throws -> StudioScenarioDetail { try await call("POST", "/studio/scenarios/\(id)/duplicate") }
    /// A draft becomes experimental when published; nothing becomes clinician-reviewed this way.
    static func publish(_ id: String, _ on: Bool) async throws -> StudioScenarioDetail {
        try await call("POST", "/studio/scenarios/\(id)/\(on ? "publish" : "unpublish")")
    }
}
