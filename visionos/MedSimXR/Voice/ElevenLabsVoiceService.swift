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

    @ObservationIgnored private var conversation: Conversation?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var caseContext = ""
    /// Bumped on every start/stop/reconnect so late callbacks from old connections are ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var wantActive = false
    @ObservationIgnored private var reconnectUsed = false
    @ObservationIgnored private var emitted = Set<String>()

    private static let connectTimeout: TimeInterval = 10

    private struct VoiceError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private final class Flag { var value = false }

    // MARK: VoiceService

    func start(caseContext: String) async {
        await stop()
        self.caseContext = caseContext
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
        var config = ConversationConfig(dynamicVariables: ["case_context": caseContext])
        config.onUserTranscript = { [weak self] text, eventId in
            Task { @MainActor in self?.emit(.learner, text, key: "u\(eventId)", gen: gen) }
        }
        config.onAgentResponse = { [weak self] text, eventId in
            Task { @MainActor in self?.emit(.patient, text, key: "a\(eventId)", gen: gen) }
        }
        return config
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
