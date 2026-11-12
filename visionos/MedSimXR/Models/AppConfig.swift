import Foundation

/// Runtime config. Precedence: in-app Settings (UserDefaults) > Info.plist
/// (filled from Config/*.xcconfig at build time) > hardcoded default.
enum AppConfig {
    static let backendHostKey = "MEDSIM_BACKEND_HOST"
    static let agentIdKey = "ELEVENLABS_AGENT_ID"
    static let defaultCaseId = "wrist_trauma_001"

    private static func value(_ key: String) -> String? {
        let candidates = [
            UserDefaults.standard.string(forKey: key),
            Bundle.main.object(forInfoDictionaryKey: key) as? String,
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// `host:port`, no scheme.
    static var backendHost: String { value(backendHostKey) ?? "localhost:8000" }

    static var backendURL: URL {
        let host = backendHost
        return URL(string: host.contains("://") ? host : "http://\(host)") ?? URL(string: "http://localhost:8000")!
    }

    /// Public ElevenLabs agent ID. nil → fetch a conversation token from the backend.
    static var agentId: String? { value(agentIdKey) }
}
