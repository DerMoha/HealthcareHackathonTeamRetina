import Foundation
import Observation

/// Backend calls that only exist for MedSim Studio scenarios. None of them is needed for the
/// fixed default case, so nothing here has an offline fallback: without a backend they fail
/// and the app carries on without the scenario feature.
enum ScenarioClient {
    enum Lookup { case found(ScenarioSummary), unknown, unreachable }

    private struct HintReply: Decodable { struct Hint: Decodable { var text: String }; var hint: Hint? }

    private static func get<T: Decodable>(_ path: String) async throws -> (T?, Int) {
        var req = URLRequest(url: AppConfig.backendURL.appendingPathComponent(path), timeoutInterval: 4)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        return (status == 200 ? try JSONDecoder.medsim.decode(T.self, from: data) : nil, status)
    }

    static func published() async -> [ScenarioSummary] {
        ((try? await get("/scenarios/published")) as ([ScenarioSummary]?, Int)?)?.0 ?? []
    }

    /// Checked before a session starts, so a mistyped code is an error and not a silent
    /// fall back to the default case.
    static func lookup(_ code: String) async -> Lookup {
        guard let (summary, status): (ScenarioSummary?, Int) = try? await get("/scenarios/launch/\(code)") else { return .unreachable }
        if let summary { return .found(summary) }
        return status == 404 ? .unknown : .unreachable
    }

    /// The next coaching hint for this session, if the scenario offers one right now.
    static func hint(sessionId: String) async -> String? {
        ((try? await get("/sessions/\(sessionId)/hint")) as (HintReply?, Int)?)?.0?.hint?.text
    }

    static func debrief(sessionId: String) async -> ScenarioDebrief? {
        ((try? await get("/sessions/\(sessionId)/debrief")) as (ScenarioDebrief?, Int)?)?.0
    }
}

/// The app's end of the Live Director WebSocket (docs/studio-api.md). Receives instructor
/// events, hands each one to `onEvent` exactly once, and acknowledges it. Reconnects on its
/// own; the server then re-sends whatever was not acknowledged, and an event id that was
/// already applied is acknowledged again without being applied twice.
@MainActor
@Observable
final class DirectorLink {
    private(set) var connected = false
    /// Applies the event; returns whether it was applied and a short description for the instructor.
    @ObservationIgnored var onEvent: ((DirectorEventMessage) async -> (applied: Bool, detail: String))?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var acks: [String: (applied: Bool, detail: String)] = [:]
    /// Test hook: keeps the link down for this long after `drop()`.
    @ObservationIgnored private var holdUntil = Date.distantPast

    private struct Ack: Encodable { var type = "ack"; var eventId: String; var applied: Bool; var detail: String }

    func connect(sessionId: String) {
        disconnect()
        acks = [:]
        var parts = URLComponents(url: AppConfig.backendURL.appendingPathComponent("/ws/sessions/\(sessionId)"),
                                  resolvingAgainstBaseURL: false)!
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        parts.queryItems = [URLQueryItem(name: "role", value: "runtime")]
        let url = parts.url!
        loop = Task { [weak self] in
            var delay = 1.0
            while !Task.isCancelled {
                if await self?.run(url) == true { delay = 1 }
                guard let self, !Task.isCancelled else { return }
                self.connected = false
                let wait = max(delay, self.holdUntil.timeIntervalSinceNow)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                delay = min(delay * 2, 5)
            }
        }
    }

    func disconnect() {
        loop?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        loop = nil; socket = nil; connected = false
    }

    /// Cuts the connection as a network drop would; the loop reconnects after `seconds`.
    func drop(for seconds: TimeInterval) {
        holdUntil = Date().addingTimeInterval(seconds)
        socket?.cancel(with: .abnormalClosure, reason: nil)
    }

    /// One connection, until it fails. Returns whether it was ever established.
    private func run(_ url: URL) async -> Bool {
        let ws = URLSession.shared.webSocketTask(with: url)
        socket = ws
        ws.resume()
        var established = false
        do {
            try await ws.send(.string(#"{"type":"hello"}"#)) // completes only once the socket is open
            established = true
            connected = true
            SmokeLog.mark("director link connected")
            while !Task.isCancelled {
                guard case .string(let text) = try await ws.receive(),
                      let event = try? JSONDecoder.medsim.decode(DirectorEventMessage.self, from: Data(text.utf8)),
                      event.type == "event" else { continue }
                let known = acks[event.eventId]
                let result: (applied: Bool, detail: String)
                if let known {
                    result = known
                    SmokeLog.mark("director duplicate ignored event=\(event.eventId) kind=\(event.kind)")
                } else {
                    result = await onEvent?(event) ?? (false, "the app has no session")
                    acks[event.eventId] = result
                }
                let ack = Ack(eventId: event.eventId, applied: result.applied, detail: result.detail)
                try await ws.send(.string(String(decoding: try JSONEncoder.medsim.encode(ack), as: UTF8.self)))
            }
        } catch {
            if established { SmokeLog.mark("director link lost") }
        }
        ws.cancel(with: .goingAway, reason: nil)
        return established
    }
}
