import AVFAudio
import Foundation
import Observation
import Speech

/// Tap-to-dictate for the notebook.
///
/// Live path (preferred, costs nothing): the microphone streams into Apple's speech recognizer
/// (on-device when the model is installed) and the words appear in `partial` while the learner
/// speaks. Server-side recognition ends a request after about a minute, so a finished segment is
/// kept and a new one starts on the same audio tap.
///
/// Fallback (live recognition not authorized, not available, or the audio engine cannot start
/// next to the voice agent): record a short m4a and transcribe it on stop with ElevenLabs Scribe
/// through the backend (`POST /elevenlabs/transcribe`, costs credits), then Apple's recognizer on
/// the same file. If both fail, the learner is pointed to the system keyboard's dictation key.
///
/// The notebook mutes or pauses the patient's conversation while it is open, so dictated notes
/// never reach the voice agent.
@MainActor
@Observable
final class NoteDictation {
    enum State: Equatable { case idle, recording, transcribing }
    enum Engine: String { case live, recorded }

    private(set) var state: State = .idle
    /// Which note the current recording or transcription belongs to.
    private(set) var target: String?
    private(set) var startedAt: Date?
    /// Live path: the words recognized so far in this dictation.
    private(set) var partial = ""
    private(set) var engine: Engine?
    /// Last problem, in words the learner can act on. Cleared on the next start.
    private(set) var message: String?
    /// Seconds of audio sent to ElevenLabs Scribe this session (credit counter).
    private(set) var scribeSeconds: TimeInterval = 0

    @ObservationIgnored private var deliver: ((String) -> Void)?
    /// Bumped by `cancel()` and every start, so callbacks of an old dictation are dropped.
    @ObservationIgnored private var generation = 0

    // Live path
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let feed = Feed()
    @ObservationIgnored private var committed = ""
    @ObservationIgnored private var segment = 0
    @ObservationIgnored private var segmentErrors = 0
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var finished: CheckedContinuation<Void, Never>?

    // Recorded path
    @ObservationIgnored private var recorder: AVAudioRecorder?
    /// After ElevenLabs fails (not configured, backend down), go straight to Apple for a while
    /// instead of paying the network round trip on every note.
    @ObservationIgnored private var skipElevenLabsUntil = Date.distantPast

    private static let maxDuration: TimeInterval = 5 * 60
    private static let elevenLabsRetryAfter: TimeInterval = 120
    /// How long Stop waits for the recognizer's final words before using what it has.
    private static let finalWait: TimeInterval = 2.5

    private struct DictationError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    func isActive(_ id: String) -> Bool { target == id && state != .idle }

    /// Starts recording for note `id`, or stops it when that note is already recording.
    /// `deliver` receives the final transcript on the main actor.
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
        generation += 1
        partial = ""
        committed = ""
        do {
            try Self.prepareAudioSession()
            if await startLive() {
                engine = .live
            } else {
                try startRecorder()
                engine = .recorded
            }
        } catch {
            stopLiveAudio()
            message = "Could not start the microphone. Tap the note and use the keyboard's microphone key instead."
            return
        }
        self.deliver = deliver
        target = id
        startedAt = Date()
        state = .recording
        SmokeLog.mark("dictation start note=\(id) engine=\(engine?.rawValue ?? "none")")
    }

    /// Stops and delivers the words. Safe to call when idle.
    func stop() async {
        guard state == .recording else { return }
        let deliver = deliver
        let gen = generation
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        self.deliver = nil
        startedAt = nil
        state = .transcribing
        var text: String?
        if engine == .live {
            text = await finishLive()
        } else if let recorder {
            let url = recorder.url
            recorder.stop()
            self.recorder = nil
            defer { try? FileManager.default.removeItem(at: url) }
            text = await transcribeRecording(url, duration: duration, gen: gen)
        }
        guard gen == generation else { return }
        state = .idle
        target = nil
        partial = ""
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            if message == nil { message = "Nothing was heard. Tap Dictate and speak a little closer." }
            return
        }
        SmokeLog.mark("dictation done engine=\(engine?.rawValue ?? "none") chars=\(text.count) seconds=\(Int(duration))")
        deliver?(text)
    }

    /// Drops the recording and any transcript still in flight (new session, reset).
    func cancel() {
        generation += 1
        stopLiveAudio()
        finished?.resume()
        finished = nil
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        deliver = nil
        startedAt = nil
        state = .idle
        target = nil
        partial = ""
        message = nil
    }

    func resetCounters() { scribeSeconds = 0 }

    /// Records alongside the live voice agent if it already set up a recording session;
    /// otherwise sets one up that keeps the patient's sounds playing.
    private static func prepareAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord && session.category != .record {
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
        }
        try session.setActive(true)
    }

    // MARK: Live recognition

    /// Hands audio buffers from the realtime tap to the current request. The tap runs on the
    /// audio thread, so this is the only state it touches.
    private final class Feed: @unchecked Sendable {
        private let lock = NSLock()
        private var request: SFSpeechAudioBufferRecognitionRequest?
        func set(_ r: SFSpeechAudioBufferRecognitionRequest?) { lock.lock(); request = r; lock.unlock() }
        func append(_ buffer: AVAudioPCMBuffer) { lock.lock(); request?.append(buffer); lock.unlock() }
        func end() { lock.lock(); request?.endAudio(); lock.unlock() }
    }

    private func startLive() async -> Bool {
        var status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            status = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        }
        guard status == .authorized,
              let recognizer = SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else { return false }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        let feed = feed
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in feed.append(buffer) }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            return false
        }
        self.recognizer = recognizer
        audioEngine = engine
        stopping = false
        segmentErrors = 0
        beginSegment()
        return true
    }

    private func beginSegment() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        feed.set(request)
        segment += 1
        let seg = segment
        let gen = generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let noSpeech = (error as NSError?).map { $0.domain == "kAFAssistantErrorDomain" && $0.code == 1110 } ?? false
            Task { @MainActor in
                self?.recognized(text, final: isFinal, failed: error != nil && !noSpeech, ended: error != nil, seg: seg, gen: gen)
            }
        }
    }

    private func recognized(_ text: String?, final: Bool, failed: Bool, ended: Bool, seg: Int, gen: Int) {
        guard gen == generation, seg == segment else { return }
        if let text { partial = [committed, text].filter { !$0.isEmpty }.joined(separator: " ") }
        guard final || ended else { return }
        committed = partial
        if failed { segmentErrors += 1 }
        if stopping || segmentErrors > 1 {
            if segmentErrors > 1 && !stopping { message = "Live dictation stopped. Tap Stop to keep what was heard." }
            finished?.resume()
            finished = nil
        } else {
            beginSegment() // the recognizer ended its request (time limit or a glitch): carry on
        }
    }

    private func finishLive() async -> String {
        stopping = true
        feed.end()
        audioEngine?.stop()
        if task != nil, segmentErrors <= 1 {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                finished = c
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(Self.finalWait * 1_000_000_000))
                    self?.finished?.resume()
                    self?.finished = nil
                }
            }
        }
        let text = partial
        stopLiveAudio()
        return text
    }

    private func stopLiveAudio() {
        task?.cancel()
        task = nil
        feed.set(nil)
        if let audioEngine {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        recognizer = nil
    }

    // MARK: Recorded fallback

    private func startRecorder() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record(forDuration: Self.maxDuration) else { throw DictationError("Recorder did not start") }
        self.recorder = recorder
    }

    private func transcribeRecording(_ url: URL, duration: TimeInterval, gen: Int) async -> String? {
        if Date() >= skipElevenLabsUntil {
            do {
                let text = try await elevenLabs(url)
                scribeSeconds += duration
                return text
            } catch {
                skipElevenLabsUntil = Date().addingTimeInterval(Self.elevenLabsRetryAfter)
            }
        }
        guard gen == generation else { return nil }
        do {
            return try await apple(url)
        } catch {
            guard gen == generation else { return nil }
            message = "\(error.localizedDescription) Tap the note and use the keyboard's microphone key instead."
            return nil
        }
    }

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
