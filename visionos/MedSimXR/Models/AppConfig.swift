import Foundation

/// Runtime config. Precedence: in-app Settings (UserDefaults) > Info.plist
/// (filled from Config/*.xcconfig at build time) > hardcoded default.
enum AppConfig {
    static let backendHostKey = "MEDSIM_BACKEND_HOST"
    static let agentIdKey = "ELEVENLABS_AGENT_ID"
    /// Case preselected when nothing else was chosen and the default for tests.
    static let defaultCaseId = "wrist_trauma_001"
    /// Optional per-avatar ElevenLabs voice id (Settings). Needs voice overrides enabled on the agent.
    static let voiceIdKeyPrefix = "ELEVENLABS_VOICE_ID_"

    /// Launch arguments `-scenario <case_id>`, `-mood <m>`, `-avatar <a>` preselect the dashboard.
    static func launchArgument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), args.indices.contains(i + 1), !args[i + 1].hasPrefix("-") else { return nil }
        return args[i + 1]
    }

    /// `-dashboardOnly` with `-autoDemo`: show the dashboard and stop, no session.
    static var dashboardOnly: Bool { ProcessInfo.processInfo.arguments.contains("-dashboardOnly") }

    static func voiceId(for avatar: String) -> String? { value(voiceIdKeyPrefix + avatar.uppercased()) }

    /// Launch code of a published MedSim Studio scenario; empty = the fixed default case.
    /// Also settable as a launch argument: `-MEDSIM_SCENARIO_CODE K7Q2MX`.
    static let scenarioCodeKey = "MEDSIM_SCENARIO_CODE"
    static var scenarioCode: String? { value(scenarioCodeKey)?.uppercased() }

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

    /// Settings "Realistic environments": the dressed places of Reality/Pitch (models, photo textures,
    /// HDRI light, posed people) instead of the procedural rooms. Default on. Launch argument
    /// `-realisticRooms 0|1` overrides the setting (tests); pitch shots (`-pitch`) always use them.
    /// Read when a place is built, so a change shows from the next place or Start.
    static let realisticRoomsKey = "realisticRooms"
    static var realisticRooms: Bool {
        if SmokeLog.pitch { return true }
        if let arg = launchArgument("-realisticRooms") { return !["0", "false", "no", "off"].contains(arg.lowercased()) }
        return UserDefaults.standard.object(forKey: realisticRoomsKey) as? Bool ?? true
    }

    /// Public ElevenLabs agent ID. nil → fetch a conversation token from the backend.
    static var agentId: String? { value(agentIdKey) }
}
