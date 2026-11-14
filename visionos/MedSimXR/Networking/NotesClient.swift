import Foundation

/// One dictation after the backend's AI tidy. `source == "raw"` means the words came back unchanged.
struct TidyResult: Codable, Hashable, Sendable {
    var text: String
    var source: String
    var note: String
}

/// The learner's notes compared with the conversation, for the debrief. Never scored.
struct NotesReview: Codable, Hashable, Sendable {
    struct Point: Codable, Hashable, Sendable { var point: String; var quote: String }
    struct Inaccurate: Codable, Hashable, Sendable { var note: String; var quote: String; var correction: String }
    /// ai | unavailable
    var source: String
    var captured: [Point]
    var missed: [Point]
    var inaccurate: [Inaccurate]
    var note: String
}

/// Credits on the ElevenLabs plan, as the backend read them.
struct VoiceCredits: Codable, Hashable, Sendable {
    var tier: String
    var creditsUsed: Int
    var creditsLimit: Int
    var creditsRemaining: Int
}

/// Backend calls for the notebook's AI help and the credit read-out. Stateless: works with the
/// backend or the offline engine running the session. Every call is best effort.
enum NotesClient {
    private struct TidyBody: Encodable { var text: String; var field: String }
    private struct Turn: Encodable { var role: String; var text: String }
    private struct ReviewBody: Encodable { var caseId: String; var diagnosis: String; var notes: ClinicalNotes; var transcript: [Turn] }

    private static func call<T: Decodable>(_ method: String, _ path: String, body: (some Encodable)?, timeout: TimeInterval) async -> T? {
        var req = URLRequest(url: AppConfig.backendURL.appendingPathComponent(path), timeoutInterval: timeout)
        req.httpMethod = method
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            req.httpBody = try? JSONEncoder.medsim.encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder.medsim.decode(T.self, from: data)
    }

    /// nil = backend unreachable; the caller keeps the raw dictation.
    static func tidy(_ text: String, field: String) async -> TidyResult? {
        await call("POST", "/notes/tidy", body: TidyBody(text: String(text.prefix(4000)), field: field), timeout: 30)
    }

    static func review(caseId: String, diagnosis: String, notes: ClinicalNotes, transcript: [TranscriptTurn]) async -> NotesReview? {
        let turns = transcript.suffix(400).map { Turn(role: $0.role.rawValue, text: $0.text) }
        return await call("POST", "/notes/review",
                          body: ReviewBody(caseId: caseId, diagnosis: diagnosis, notes: notes, transcript: Array(turns)),
                          timeout: 60)
    }

    /// Reading the balance costs no credits. nil = no key, no permission, or no backend.
    static func credits() async -> VoiceCredits? {
        await call("GET", "/elevenlabs/usage", body: Optional<TidyBody>.none, timeout: 8)
    }
}
