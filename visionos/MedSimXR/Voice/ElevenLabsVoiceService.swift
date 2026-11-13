import AVFAudio
import Combine
import ElevenLabs
import Foundation
import Observation

/// Live patient voice via the ElevenLabs Agents Swift SDK (3.4.0).
///
/// Case context: passed as dynamic variable `case_context` in `ConversationConfig.dynamicVariables`
/// at conversation start (the SDK sends it in the conversation-init event, see EventSerializer.swift).
/// No contextual-update fallback is needed or used.
///
/// Examination events: sent with `Conversation.sendMessage(_:)` (a text user message, which makes the
/// agent reply). `updateContext(_:)` is a contextual update and does NOT trigger speech.
///
/// Transcripts: taken from the finalized-event callbacks `onUserTranscript` / `onAgentResponse`
/// (tentative transcripts never reach them), de-duplicated per connection by event id.
@MainActor
@Observable
final class ElevenLabsVoiceService: VoiceService {
    private(set) var status: VoiceStatus = .disconnected
    private(set) var micStatus: MicStatus = .unknown
    private(set) var isAgentSpeaking = false
    @ObservationIgnored var onTranscript: ((TranscriptTurn) -> Void)?
    @ObservationIgnored var onAction: ((String) -> String)?
    @ObservationIgnored var onOrder: ((String) async -> String)?

    @ObservationIgnored private var conversation: Conversation?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var caseContext = ""
    @ObservationIgnored private var voiceId: String?
    /// Bumped on every start/stop/reconnect so late callbacks from old connections are ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var wantActive = false
    @ObservationIgnored private var reconnectUsed = false
    @ObservationIgnored private var emitted = Set<String>()
    /// ElevenLabs conversation ids since the last `start`, oldest first (a reconnect adds one).
    /// Kept after `stop()` so the post-call summary can be fetched.
    @ObservationIgnored private var conversationIds: [String] = []

    private static let connectTimeout: TimeInterval = 10

    private struct VoiceError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private final class Flag { var value = false }

    // MARK: VoiceService

    func start(caseContext: String, voiceId: String?) async {
        await stop()
        self.caseContext = caseContext
        conversationIds = []
        self.voiceId = voiceId
        wantActive = true
        reconnectUsed = false
        status = .connecting

        guard await AVAudioApplication.requestRecordPermission() else {
            wantActive = false
            micStatus = .denied
            status = .failed("Microphone access denied")
            return
        }
        guard wantActive else { return }
        await connect()
    }

    func stop() async {
        wantActive = false
        generation += 1
        let old = conversation
        cancellables.removeAll()
        conversation = nil
        isAgentSpeaking = false
        if micStatus == .live || micStatus == .muted { micStatus = .unknown }
        if status != .disconnected { status = .disconnected }
        await old?.endConversation()
    }

    func setMicMuted(_ muted: Bool) async {
        guard status == .connected, let conversation else { return }
        try? await conversation.setMuted(muted) // $isMuted updates micStatus
    }

    func sendContext(_ text: String) async {
        guard status == .connected, let conversation else { return }
        try? await conversation.updateContext(text)
    }

    func sendExaminationEvent(_ text: String) async {
        guard status == .connected, let conversation else { return }
        // Non-fatal on failure: the avatar reaction and pain sound are local anyway.
        try? await conversation.sendMessage(text)
    }

    // MARK: Connection

    private func connect() async {
        generation += 1
        let gen = generation
        emitted.removeAll()
        status = .connecting
        do {
            let conv = try await openConversation(gen: gen)
            guard gen == generation, wantActive else {
                await conv.endConversation()
                return
            }
            conversation = conv
            observe(conv, gen: gen)
        } catch {
            guard gen == generation, wantActive else { return }
            wantActive = false
            status = .failed(error.localizedDescription)
        }
    }

    /// Starts the conversation, failing with a readable error after ~10 s overall.
    private func openConversation(gen: Int) async throws -> Conversation {
        let timedOut = Flag()
        let config = makeConfig(gen: gen)
        let work = Task { @MainActor () -> Conversation in
            if let agentId = AppConfig.agentId {
                return try await ElevenLabs.startConversation(agentId: agentId, config: config)
            }
            let token = try await fetchToken()
            return try await ElevenLabs.startConversation(conversationToken: token, config: config)
        }
        let timer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.connectTimeout * 1_000_000_000))
            if !Task.isCancelled {
                timedOut.value = true
                work.cancel()
            }
        }
        defer { timer.cancel() }
        do {
            return try await work.value
        } catch {
            if timedOut.value { throw VoiceError("Voice connection timed out") }
            throw error
        }
    }

    private func makeConfig(gen: Int) -> ConversationConfig {
        // A per-avatar voice from Settings; the agent must allow voice overrides (elevenlabs/setup.md).
        var config = ConversationConfig(ttsOverrides: voiceId.map { TTSOverrides(voiceId: $0) },
                                        dynamicVariables: ["case_context": caseContext])
        config.onUserTranscript = { [weak self] text, eventId in
            Task { @MainActor in self?.emit(.learner, text, key: "u\(eventId)", gen: gen) }
        }
        config.onAgentResponse = { [weak self] text, eventId in
            Task { @MainActor in self?.emit(.patient, text, key: "a\(eventId)", gen: gen) }
        }
        config.onUnhandledClientToolCall = { [weak self] call in
            Task { @MainActor in await self?.handleTool(call, gen: gen) }
        }
        config.onConversationMetadata = { [weak self] metadata in
            let id = metadata.conversationId
            Task { @MainActor in
                guard let self, gen == self.generation, !self.conversationIds.contains(id) else { return }
                self.conversationIds.append(id)
            }
        }
        return config
    }

    /// Client tools `perform_patient_action(action:)` and `order_investigation(investigation:)`.
    /// Both strings are validated by the app; the agent always gets an explicit result back.
    private func handleTool(_ call: ClientToolCallEvent, gen: Int) async {
        guard gen == generation, let conversation else { return }
        var result = "failure: unknown tool \(call.toolName)"
        if call.toolName == "perform_patient_action" {
            let action = (try? call.getParameters())?["action"] as? String ?? ""
            result = onAction?(action) ?? "failure: unavailable"
        } else if call.toolName == "order_investigation" {
            // The app asks the clinical engine; the agent only learns that the order was placed.
            let id = (try? call.getParameters())?["investigation"] as? String ?? ""
            result = await onOrder?(id) ?? "failure: unavailable"
        }
        guard call.expectsResponse else { return conversation.markToolCallCompleted(call.toolCallId) }
        try? await conversation.sendToolResult(for: call.toolCallId, result: result, isError: !result.hasPrefix("success"))
    }

    private func fetchToken() async throws -> String {
        struct TokenResponse: Decodable { let token: String }
        var request = URLRequest(url: AppConfig.backendURL.appendingPathComponent("elevenlabs/conversation-token"))
        request.timeoutInterval = 5
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw VoiceError("No agent ID set and backend unreachable for voice token")
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let token = try? JSONDecoder().decode(TokenResponse.self, from: data).token, !token.isEmpty
        else {
            throw VoiceError("No agent ID set and backend has no voice token (ElevenLabs not configured)")
        }
        return token
    }

    // MARK: Post-call summary

    /// ElevenLabs generates the summary only after a conversation has ended. The backend
    /// fetches it with the API key; the app never holds the key.
    func fetchSummary() async throws -> String? {
        struct SummaryResponse: Decodable { let status: String; let summary: String? }
        guard !conversationIds.isEmpty else {
            throw VoiceError("No voice conversation was recorded, so there is nothing to summarise.")
        }
        var parts: [String] = []
        for id in conversationIds {
            let url = AppConfig.backendURL
                .appendingPathComponent("elevenlabs/conversations")
                .appendingPathComponent(id)
                .appendingPathComponent("summary")
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw VoiceError("Backend unreachable, so the summary could not be fetched")
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 503 { throw VoiceError("Summary unavailable: ElevenLabs is not configured on the backend") }
            guard code == 200, let body = try? JSONDecoder().decode(SummaryResponse.self, from: data) else {
                throw VoiceError("The backend could not fetch the summary (HTTP \(code))")
            }
            switch body.status {
            case "pending": return nil
            case "failed": throw VoiceError("ElevenLabs could not process the conversation")
            default:
                if let text = body.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    parts.append(text)
                }
            }
        }
        guard !parts.isEmpty else { throw VoiceError("ElevenLabs returned no summary for this conversation") }
        return parts.joined(separator: "\n\n")
    }

    // MARK: Observation

    private func observe(_ conv: Conversation, gen: Int) {
        cancellables.removeAll()
        conv.$state
            .sink { [weak self] state in
                Task { @MainActor in await self?.handle(state, gen: gen) }
            }
            .store(in: &cancellables)
        conv.$isMuted
            .sink { [weak self] muted in
                Task { @MainActor in
                    guard let self, gen == self.generation, self.status == .connected else { return }
                    self.micStatus = muted ? .muted : .live
                }
            }
            .store(in: &cancellables)
        conv.$agentState
            .sink { [weak self] state in
                Task { @MainActor in
                    guard let self, gen == self.generation else { return }
                    self.isAgentSpeaking = (state == .speaking)
                }
            }
            .store(in: &cancellables)
    }

    private func handle(_ state: ConversationState, gen: Int) async {
        guard gen == generation, wantActive else { return }
        switch state {
        case .idle, .connecting:
            status = .connecting
        case .active:
            status = .connected
            if let conv = conversation { micStatus = conv.isMuted ? .muted : .live }
        case .ended(let reason):
            if reason == .userEnded { status = .disconnected } else { await recover("Voice connection lost") }
        case .error(let error):
            await recover(error.localizedDescription)
        }
    }

    /// Unexpected drop while a session is active: reconnect once with the same context, then fail.
    private func recover(_ reason: String) async {
        cancellables.removeAll()
        let old = conversation
        conversation = nil
        isAgentSpeaking = false
        if reconnectUsed {
            wantActive = false
            generation += 1
            status = .failed(reason)
            await old?.endConversation()
            return
        }
        reconnectUsed = true
        await old?.endConversation()
        await connect()
    }

    // MARK: Transcript

    private func emit(_ role: SpeakerRole, _ text: String, key: String, gen: Int) {
        guard gen == generation else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Bracketed text is an examination stage direction, never a spoken turn.
        guard !trimmed.isEmpty, !trimmed.hasPrefix("["), emitted.insert(key).inserted else { return }
        onTranscript?(TranscriptTurn(role: role, text: trimmed))
    }
}
