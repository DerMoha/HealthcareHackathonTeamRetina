import AVFAudio
import Foundation
import Observation
import Speech

/// Tap-to-dictate for the notebook. Records the learner to a short m4a, then transcribes it:
/// ElevenLabs Scribe through the backend (`POST /elevenlabs/transcribe`, the API key stays on the
/// backend) and, when that is not configured or unreachable, Apple's speech recognizer on the
/// same recording. If both fail, the learner is pointed to the system keyboard's dictation key.
///
/// The notebook mutes the patient's microphone while it is open, so dictated notes never reach
/// the voice agent.
@MainActor
@Observable
final class NoteDictation {
    enum State: Equatable { case idle, recording, transcribing }

    private(set) var state: State = .idle
    /// Which note the current recording or transcription belongs to.
    private(set) var target: String?
    private(set) var startedAt: Date?
    /// Last problem, in words the learner can act on. Cleared on the next start.
    private(set) var message: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var deliver: ((String) -> Void)?
    /// After ElevenLabs fails (not configured, backend down), go straight to Apple for a while
    /// instead of paying the network round trip on every note.
    @ObservationIgnored private var skipElevenLabsUntil = Date.distantPast
    /// Bumped by `cancel()` so a transcript still in flight is dropped.
    @ObservationIgnored private var generation = 0

    private static let maxDuration: TimeInterval = 5 * 60
    private static let elevenLabsRetryAfter: TimeInterval = 120

    private struct DictationError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    func isActive(_ id: String) -> Bool { target == id && state != .idle }

    /// Starts recording for note `id`, or stops it when that note is already recording.
    /// `deliver` receives the transcript on the main actor.
    func toggle(_ id: String, deliver: @escaping (String) -> Void) async {
        if state == .recording, target == id { return await stop() }
        if state == .recording { await stop() }
        guard state == .idle else { return }
        await start(id, deliver: deliver)
    }

    private func start(_ id: String, deliver: @escaping (String) -> Void) async {
        message = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            message = "Microphone access is off. Allow it for MedSim XR in Settings, or use the keyboard's microphone key."
            return
        }
        guard state == .idle else { return }
        do {
            try Self.prepareAudioSession()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("dictation-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record(forDuration: Self.maxDuration) else { throw DictationError("Recorder did not start") }
            self.recorder = recorder
            self.deliver = deliver
            target = id
            startedAt = Date()
            state = .recording
        } catch {
            message = "Could not start the microphone. Tap the note and use the keyboard's microphone key instead."
        }
    }

    /// Stops recording and transcribes. Safe to call when idle.
    func stop() async {
        guard state == .recording, let recorder else { return }
        let url = recorder.url
        let deliver = deliver
        let gen = generation
        recorder.stop()
        self.recorder = nil
        self.deliver = nil
        startedAt = nil
        state = .transcribing
        defer {
            try? FileManager.default.removeItem(at: url)
            if gen == generation {
                state = .idle
                target = nil
            }
        }

        var text: String?
        if Date() >= skipElevenLabsUntil {
            do {
                text = try await elevenLabs(url)
            } catch {
                skipElevenLabsUntil = Date().addingTimeInterval(Self.elevenLabsRetryAfter)
            }
        }
        guard gen == generation else { return }
        if text == nil {
            do {
                text = try await apple(url)
            } catch {
                guard gen == generation else { return }
                message = "\(error.localizedDescription) Tap the note and use the keyboard's microphone key instead."
                return
            }
        }
        guard gen == generation else { return }
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            message = "Nothing was heard. Tap Dictate and speak a little closer."
            return
        }
        deliver?(text)
    }

    /// Drops the recording and any transcript still in flight (new session, reset).
    func cancel() {
        generation += 1
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        deliver = nil
        startedAt = nil
        state = .idle
        target = nil
        message = nil
    }

    /// Records alongside the live voice agent if it already set up a recording session;
    /// otherwise sets one up that keeps the patient's sounds playing.
    private static func prepareAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord && session.category != .record {
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
        }
        try session.setActive(true)
    }

    // MARK: ElevenLabs (backend proxy)

    private func elevenLabs(_ url: URL) async throws -> String {
        struct Response: Decodable { let text: String }
        var request = URLRequest(url: AppConfig.backendURL.appendingPathComponent("elevenlabs/transcribe"))
        request.httpMethod = "POST"
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DictationError("ElevenLabs unavailable") }
        return try JSONDecoder().decode(Response.self, from: data).text
    }

    // MARK: Apple speech recognition (fallback)

    private func apple(_ url: URL) async throws -> String {
        let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard status == .authorized else {
            throw DictationError("Speech recognition is off for MedSim XR.")
        }
        guard let recognizer = SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable
        else { throw DictationError("Speech recognition is not available right now.") }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        // Works without a network when the device has the on-device model.
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let once = Once()
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
            once.task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    once.run { c.resume(returning: result.bestTranscription.formattedString) }
                } else if let error {
                    // "No speech detected" is an empty note, not a failure.
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1110 {
                        once.run { c.resume(returning: "") }
                    } else {
                        once.run { c.resume(throwing: DictationError("Speech recognition failed.")) }
                    }
                }
            }
        }
    }

    /// Resumes the recognizer's continuation exactly once; its callback can fire more than once
    /// and on any queue. Also keeps the recognition task alive until then.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        var task: SFSpeechRecognitionTask?

        func run(_ body: () -> Void) {
            lock.lock()
            let first = !done
            done = true
            lock.unlock()
            if first {
                body()
                task = nil
            }
        }
    }
}
