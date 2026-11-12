import AVFoundation

/// Plays bundled clips (Resources/Audio/<name>.*) and falls back to system TTS.
@MainActor
final class ReactionPlayer {
    private var players: [AVAudioPlayer] = []
    private let synth = AVSpeechSynthesizer()

    static func clipURL(_ name: String) -> URL? {
        for ext in ["m4a", "mp3", "wav", "aiff"] {
            if let u = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Audio")
                ?? Bundle.main.url(forResource: name, withExtension: ext) { return u }
        }
        return nil
    }

    @discardableResult
    func playClip(_ name: String) -> Bool {
        guard let url = Self.clipURL(name), let p = try? AVAudioPlayer(contentsOf: url) else { return false }
        players.removeAll { !$0.isPlaying }
        players.append(p)
        p.play()
        return true
    }

    func speak(_ text: String, clip: String?) {
        if let clip, playClip(clip) { return }
        synth.stopSpeaking(at: .immediate)
        synth.speak(AVSpeechUtterance(string: text))
    }

    func handle(_ r: ReactionEvent) async {
        if r.speakLocally {
            speak(r.text, clip: r.clip)
        } else if r.painLevel >= 5 {
            playClip("ouch") // instant; the live agent's spoken reply follows
        }
    }
}
