import AVFoundation
import RealityKit
import UIKit

/// Something a companion says out loud. Never a transcript turn, so it cannot earn points.
struct SceneLine: Identifiable, Equatable {
    let id = UUID()
    var speaker: String
    var text: String
}

/// Everything a MedSim Studio scenario adds to the room: a sign naming the setting, the
/// bystander, the helper, people in the background, and room noise. Rebuilt from
/// `ScenarioRuntime` whenever it changes (session start, instructor events); with no
/// scenario the room is exactly the fixed default one.
///
/// The people are deliberately plain figures and the noise is synthesised: this shows that
/// the scenario reached the scene, it is not an attempt at a realistic ward.
@MainActor
final class ScenarioStage {
    let root = Entity()
    private var ambient: AVAudioPlayer?
    private let synth = AVSpeechSynthesizer()
    private var bubble: Entity?
    private var bubbleTask: Task<Void, Never>?
    private var speakers: [String: Entity] = [:]

    private static let bystanderSpot: SIMD3<Float> = [0.85, 0, -0.1]   // the patient's left, wearer's right
    private static let helperSpot: SIMD3<Float> = [-1.3, 0, -0.3]      // behind the equipment tray

    func install(on avatar: PatientAvatar) {
        root.name = "scenario_stage"
        avatar.root.addChild(root)
    }

    /// One line for the smoke log and the acknowledgement sent back to the instructor.
    private(set) var status = "no scenario"

    func sync(_ scenario: ScenarioRuntime?) {
        Array(root.children).forEach { $0.removeFromParent() }
        speakers = [:]; bubble = nil
        guard let s = scenario else {
            ambient?.stop(); ambient = nil
            status = "no scenario"
            return
        }
        let sign = Self.text("\(s.environmentLabel)  ·  \(s.difficulty.capitalized)", size: 0.045, color: .white)
        sign.position = [0, 2.05, -0.6]
        root.addChild(sign)

        if let b = s.bystander {
            let anxious = b.mood == "anxious"
            let figure = Self.person(shirt: anxious ? .systemOrange : .systemGreen, height: 1.68,
                                     label: "\(b.name) · \(b.roleLabel)\(anxious ? " · anxious" : "")")
            figure.position = Self.bystanderSpot
            figure.orientation = simd_quatf(angle: -0.5, axis: [0, 1, 0])
            root.addChild(figure)
            speakers[b.name] = figure
        }
        if s.teammate.present {
            let figure = Self.person(shirt: .systemIndigo, height: 1.72, label: "\(s.teammate.name) · \(s.teammate.roleLabel)")
            figure.position = Self.helperSpot
            figure.orientation = simd_quatf(angle: 0.6, axis: [0, 1, 0])
            root.addChild(figure)
            speakers[s.teammate.name] = figure
        }
        // People in the background: more of them as the noise goes up.
        let extra = max(0, Int((s.noiseLevel * 6).rounded()) - s.crowdFigures.count)
        let crowd = s.crowdFigures + (0..<extra).map { ScenarioRuntime.Figure(angleDeg: 135 + Float($0) * 31, distanceM: 3.6) }
        for (i, f) in crowd.enumerated() {
            let figure = Self.person(shirt: UIColor(white: 0.45 + 0.08 * CGFloat(i % 3), alpha: 1), height: 1.6 + 0.05 * Float(i % 3), label: nil)
            let a = f.angleDeg * .pi / 180
            figure.position = [sin(a) * f.distanceM, 0, cos(a) * f.distanceM]
            figure.orientation = simd_quatf(angle: a + .pi, axis: [0, 1, 0]) // facing the patient
            root.addChild(figure)
        }
        setNoise(s.noiseLevel, seed: UInt64(s.seed))
        status = "sign=\(s.environmentId) figures=\(speakers.count + crowd.count) "
            + "bystander=\(s.bystander?.mood ?? "none") helper=\(s.teammate.present) "
            + "noise=\(String(format: "%.2f", s.noiseLevel)) noisePlaying=\(ambient?.isPlaying ?? false)"
    }

    /// Speaks the line with the system voice and shows it above whoever said it.
    func say(_ line: SceneLine) {
        synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: line.text)
        utterance.pitchMultiplier = 1.25 // told apart from the patient's fallback voice
        synth.speak(utterance)

        bubble?.removeFromParent()
        let text = Self.text("\(line.speaker): \u{201C}\(line.text)\u{201D}", size: 0.028, color: .systemYellow)
        text.position = (speakers[line.speaker]?.position ?? [0, 0, 0]) + [0, 2.0, 0.05]
        root.addChild(text)
        bubble = text
        bubbleTask?.cancel()
        bubbleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled, self?.bubble === text else { return }
            text.removeFromParent()
        }
        SmokeLog.mark("scene line speaker=\(line.speaker) shown=\(speakers[line.speaker] != nil) text=\"\(line.text)\"")
    }

    func stop() {
        ambient?.stop(); ambient = nil
        synth.stopSpeaking(at: .immediate)
    }

    // MARK: Room noise

    private func setNoise(_ level: Double, seed: UInt64) {
        guard level > 0.01 else { ambient?.stop(); ambient = nil; return }
        if ambient == nil, let player = try? AVAudioPlayer(data: Self.murmur(seed: seed)) {
            player.numberOfLoops = -1
            ambient = player
        }
        // Kept well below speech so the patient and the voice agent stay intelligible.
        ambient?.volume = Float(min(1, level)) * 0.5
        if ambient?.isPlaying == false { ambient?.play() }
    }

    /// Four seconds of band-limited noise with a slow swell: a room murmur, not recorded voices.
    private static func murmur(seed: UInt64) -> Data {
        let rate = 22_050, count = rate * 4
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        var low: Float = 0, lower: Float = 0
        var pcm = Data(capacity: count * 2)
        for i in 0..<count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let white = Float(Int32(truncatingIfNeeded: state >> 33)) / Float(Int32.max)
            low += 0.09 * (white - low)
            lower += 0.012 * (white - lower)
            let t = Float(i) / Float(rate)
            let swell = 0.65 + 0.35 * sin(2 * .pi * 0.75 * t) * sin(2 * .pi * 2.5 * t) // whole cycles in 4 s: loops cleanly
            let sample = Int16(max(-1, min(1, (low - lower) * 7 * swell)) * 26_000)
            withUnsafeBytes(of: sample.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var wav = Data()
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + pcm.count)); wav.append(contentsOf: Array("WAVEfmt ".utf8))
        put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(UInt32(rate)); put(UInt32(rate * 2)); put(UInt16(2)); put(UInt16(16))
        wav.append(contentsOf: Array("data".utf8)); put(UInt32(pcm.count))
        return wav + pcm
    }

    // MARK: Meshes

    private static func person(shirt: UIColor, height: Float, label: String?) -> Entity {
        let e = Entity()
        let body = ModelEntity(mesh: .generateCylinder(height: height * 0.52, radius: 0.17),
                               materials: [SimpleMaterial(color: shirt, isMetallic: false)])
        body.position = [0, height * 0.62, 0]
        let legs = ModelEntity(mesh: .generateCylinder(height: height * 0.36, radius: 0.13),
                               materials: [SimpleMaterial(color: UIColor(white: 0.18, alpha: 1), isMetallic: false)])
        legs.position = [0, height * 0.18, 0]
        let head = ModelEntity(mesh: .generateSphere(radius: 0.105),
                               materials: [SimpleMaterial(color: UIColor(red: 0.85, green: 0.68, blue: 0.58, alpha: 1), isMetallic: false)])
        head.position = [0, height * 0.94, 0]
        for part in [body, legs, head] { e.addChild(part) }
        if let label {
            let caption = text(label, size: 0.03, color: .white)
            caption.position = [0, height + 0.12, 0]
            e.addChild(caption)
        }
        return e
    }

    /// Centred text that always reads from the front of the room.
    private static func text(_ string: String, size: CGFloat, color: UIColor) -> Entity {
        let mesh = MeshResource.generateText(string, extrusionDepth: 0.001, font: .systemFont(ofSize: size, weight: .semibold))
        let model = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
        model.position = [-mesh.bounds.extents.x / 2 - mesh.bounds.min.x, 0, 0]
        let holder = Entity()
        holder.addChild(model)
        return holder
    }
}
