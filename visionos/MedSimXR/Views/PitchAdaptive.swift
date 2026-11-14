import RealityKit
import SwiftUI

/// Pitch concept (`-pitch -pitchAdaptive`): heart-rate adaptive difficulty. An Apple Watch heart rate
/// would steer the scene: too calm and the sim pushes (more bystanders shouting, the patient drifting
/// off, louder sirens), overloaded and it eases off (crowd moved back, a hint from the crew, quieter,
/// a more cooperative patient). Nothing reads a watch: every number here is staged for the screenshots.
@MainActor
enum PitchAdaptive {
    static let on = SmokeLog.pitch && ProcessInfo.processInfo.arguments.contains("-pitchAdaptive")

    struct Change: Hashable {
        var icon: String
        var text: String
        var detail: String? = nil
    }

    /// What the heart-rate panel shows.
    struct State: Equatable {
        enum Mode { case steady, harder, easier, debrief }
        var mode: Mode
        var bpm: Int
        /// The last minute of heart rate, oldest first.
        var trace: [Double]
        /// 1 (easiest) ... 5 (hardest).
        var difficulty: Int
        /// Ambient sound level, 0...1.
        var sound: Double
        var changes: [Change]
    }

    /// Bystanders who only appear when the sim raises the challenge, and the ones the police move
    /// back when it eases off (PitchRoadside.street fills these).
    static var extraCrowd: [Entity] = []
    static var calmedCrowd: [Entity] = []

    static func showCrowd(_ mode: State.Mode?) {
        for e in extraCrowd { e.isEnabled = mode == .harder }
        for e in calmedCrowd { e.isEnabled = mode != .easier }
        PitchRoadside.setChip(mode == .harder ? "Crowd 7  ·  Distraction max"
                              : mode == .easier ? "Crowd 2  ·  Distraction low" : "Crowd 4  ·  Distraction high")
    }

    // MARK: Staged data

    /// A deterministic, slightly noisy heart-rate trace from `from` to `to`.
    static func trace(_ from: Double, _ to: Double, count: Int = 60, wobble: Double = 2.5, seed: Double = 1) -> [Double] {
        (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            let s = t * t * (3 - 2 * t)
            return from + (to - from) * s + wobble * (sin(Double(i) * 0.9 + seed) * 0.6 + sin(Double(i) * 2.3 + seed * 2) * 0.4)
        }
    }

    static let steady = State(mode: .steady, bpm: 104, trace: trace(101, 104), difficulty: 3, sound: 0.55, changes: [])

    static let harder = State(mode: .harder, bpm: 72, trace: trace(76, 72, wobble: 1.5, seed: 3), difficulty: 5, sound: 0.92, changes: [
        Change(icon: "person.3.fill", text: "3 more bystanders, shouting", detail: "Crowd 4 → 7"),
        Change(icon: "zzz", text: "Jordan drifting off", detail: "GCS 15 → 12"),
        Change(icon: "speaker.wave.3.fill", text: "Sirens and traffic louder", detail: "+12 dB"),
    ])

    static let easier = State(mode: .easier, bpm: 148, trace: trace(112, 148, wobble: 3, seed: 5), difficulty: 2, sound: 0.25, changes: [
        Change(icon: "lightbulb.fill", text: "Lena offers a hint", detail: "Pulse before splint"),
        Change(icon: "person.2.slash.fill", text: "Police move the crowd back", detail: "Crowd 4 → 2"),
        Change(icon: "speaker.wave.1.fill", text: "Background noise down", detail: "−10 dB"),
        Change(icon: "hand.thumbsup.fill", text: "Jordan more cooperative", detail: "Holds still"),
    ])

    static let debrief = State(mode: .debrief, bpm: 108, trace: timeline, difficulty: 3, sound: 0.5, changes: [])

    /// The whole roadside stage, one sample every 10 s for 12 minutes: settles, goes flat (too easy),
    /// the sim pushes at 04:10, overshoots to 148 at 06:40, Lena's hint at 06:50, back in the zone.
    static let timeline: [Double] = {
        let parts = [trace(92, 102, count: 12, seed: 1), trace(100, 74, count: 13, seed: 2), trace(74, 120, count: 10, seed: 3),
                     trace(122, 148, count: 6, wobble: 2, seed: 4), trace(146, 112, count: 6, seed: 5), trace(112, 108, count: 25, seed: 6)]
        return parts.flatMap { $0 }
    }()

    /// Event markers on the debrief timeline: sample index, label, colour.
    static let events: [(at: Int, label: String, tint: Color)] = [
        (24, "Too easy: sim pushes", .cyan),
        (40, "Peak 148", .red),
        (41, "Lena's hint", .green),
    ]
}

/// Moves the scene when the staged heart rate changes: the crowd, the chip and Jordan's posture.
struct PitchAdaptSync: ViewModifier {
    let avatar: PatientAvatar

    func body(content: Content) -> some View {
        content.onChange(of: Pitch.shared.adapt?.mode) { _, mode in
            guard PitchAdaptive.on else { return }
            PitchAdaptive.showCrowd(mode)
            Task { await avatar.pitchDrowsy(mode == .harder) }
            SmokeLog.mark("pitch adapt \(String(describing: mode))")
        }
    }
}

/// The heart-rate panel beside the patient (left of him; the conversation card is on his right).
struct PitchAdaptPanel: View {
    private let pitch = Pitch.shared

    static let low = Color(red: 0.35, green: 0.7, blue: 1)
    static let zone = Color(red: 0.25, green: 0.85, blue: 0.55)
    static let high = Color(red: 1, green: 0.38, blue: 0.38)
    static let heart = Color(red: 1, green: 0.32, blue: 0.4)

    var body: some View {
        if let s = pitch.adapt {
            Group {
                if s.mode == .debrief { PitchAdaptDebrief(state: s) } else { live(s) }
            }
            .padding(.horizontal, 30).padding(.top, 24).padding(.bottom, 28)
            .background(Color(red: 0.06, green: 0.08, blue: 0.1).opacity(0.55), in: .rect(cornerRadius: 40))
            .glassBackgroundEffect(in: .rect(cornerRadius: 40))
        }
    }

    private func zoneInfo(_ bpm: Int) -> (String, Color) {
        bpm < 95 ? ("UNDER-CHALLENGED", Self.low) : bpm > 130 ? ("OVERLOADED", Self.high) : ("IN THE ZONE", Self.zone)
    }

    private func live(_ s: PitchAdaptive.State) -> some View {
        let (zone, tint) = zoneInfo(s.bpm)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "applewatch").font(.system(size: 26, weight: .semibold))
                Text("Apple Watch").font(.system(size: 22, weight: .semibold))
                Text("·  live heart rate").font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Label("Adaptive", systemImage: "dial.medium.fill").font(.system(size: 17, weight: .heavy)).tracking(0.8)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(.white.opacity(0.12), in: .capsule)
            }
            .foregroundStyle(.white)

            HStack(alignment: .center, spacing: 22) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "heart.fill").font(.system(size: 40)).foregroundStyle(Self.heart)
                        Text("\(s.bpm)").font(.system(size: 84, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            .monospacedDigit()
                        Text("BPM").font(.system(size: 24, weight: .bold)).foregroundStyle(Self.heart)
                    }
                    Text(zone).font(.system(size: 17, weight: .heavy)).tracking(1.4).foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, 12).padding(.vertical, 5).background(tint, in: .capsule)
                }
                Sparkline(values: s.trace, tint: tint).frame(height: 110)
            }
            .padding(.top, 18)
            Text("Target zone 95–125 bpm  ·  last 60 s").font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary)
                .padding(.top, 10)

            difficulty(s).padding(.top, 22)

            if !s.changes.isEmpty {
                Text("SIM ADJUSTED  ·  JUST NOW").font(.system(size: 16, weight: .heavy)).tracking(1.6)
                    .foregroundStyle(.white.opacity(0.6)).padding(.top, 22).padding(.bottom, 10)
                VStack(spacing: 10) {
                    ForEach(s.changes, id: \.self) { change(s, $0) }
                }
            }
            sound(s).padding(.top, 18)
        }
        .frame(width: 640, alignment: .leading)
    }

    private func difficulty(_ s: PitchAdaptive.State) -> some View {
        let (label, icon, tint): (String, String, Color) = switch s.mode {
        case .harder: ("Raising the challenge", "arrow.up.right.circle.fill", Self.low)
        case .easier: ("Easing off", "arrow.down.right.circle.fill", Self.high)
        default: ("Holding steady", "equal.circle.fill", Self.zone)
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Difficulty").font(.system(size: 21, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Label(label, systemImage: icon).font(.system(size: 21, weight: .bold)).foregroundStyle(tint)
            }
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { i in
                    Capsule().fill(i <= s.difficulty ? tint : .white.opacity(0.15)).frame(height: 12)
                }
            }
            HStack {
                Text("Easier").font(.system(size: 15, weight: .medium))
                Spacer()
                Text("Harder").font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(.secondary)
        }
    }

    private func change(_ s: PitchAdaptive.State, _ c: PitchAdaptive.Change) -> some View {
        let tint = s.mode == .harder ? Self.low : Self.zone
        return HStack(spacing: 14) {
            Image(systemName: c.icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(.black.opacity(0.8))
                .frame(width: 40, height: 40).background(tint, in: .circle)
            Text(c.text).font(.system(size: 23, weight: .semibold)).foregroundStyle(.white)
            Spacer(minLength: 8)
            if let d = c.detail {
                Text(d).font(.system(size: 18, weight: .bold)).foregroundStyle(tint).monospacedDigit()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 18))
    }

    private func sound(_ s: PitchAdaptive.State) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s.sound > 0.7 ? "speaker.wave.3.fill" : s.sound < 0.35 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
                .font(.system(size: 20, weight: .semibold)).frame(width: 30)
            Text("Scene sound").font(.system(size: 19, weight: .semibold))
            HStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { i in
                    let on = Double(i) / 24 < s.sound
                    Capsule().fill(on ? (i > 17 ? Self.high : i > 11 ? Color.orange : .white) : .white.opacity(0.12))
                        .frame(width: 6, height: 8 + CGFloat(i) * 0.9)
                }
            }
            Spacer(minLength: 0)
            Text("Sirens · traffic · crowd").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
    }
}

/// A heart-rate line with the target zone shaded.
private struct Sparkline: View {
    var values: [Double]
    var tint: Color
    var range: ClosedRange<Double> = 60...160
    var zone: ClosedRange<Double> = 95...125

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let y = { (v: Double) in h * (1 - (v - range.lowerBound) / (range.upperBound - range.lowerBound)) }
            ZStack {
                Rectangle().fill(PitchAdaptPanel.zone.opacity(0.13))
                    .frame(height: y(zone.lowerBound) - y(zone.upperBound)).position(x: w / 2, y: (y(zone.lowerBound) + y(zone.upperBound)) / 2)
                Path { p in
                    for (i, v) in values.enumerated() {
                        let pt = CGPoint(x: w * Double(i) / Double(max(values.count - 1, 1)), y: y(v))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                if let last = values.last {
                    Circle().fill(tint).frame(width: 14, height: 14).shadow(color: tint, radius: 6).position(x: w, y: y(last))
                }
            }
        }
    }
}

/// The debrief: heart rate over the roadside stage, the zone shaded, where the sim adjusted.
private struct PitchAdaptDebrief: View {
    let state: PitchAdaptive.State

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 26, weight: .semibold)).foregroundStyle(PitchAdaptPanel.heart)
                Text("Debrief  ·  Your heart rate").font(.system(size: 26, weight: .bold))
                Spacer()
                Label("Apple Watch", systemImage: "applewatch").font(.system(size: 17, weight: .heavy))
                    .padding(.horizontal, 12).padding(.vertical, 6).background(.white.opacity(0.12), in: .capsule)
            }
            .foregroundStyle(.white)
            Text("At the roadside  ·  12 min").font(.system(size: 19, weight: .medium)).foregroundStyle(.secondary).padding(.top, 4)

            chart.frame(height: 240).padding(.top, 22)
            HStack {
                ForEach(["00:00", "03:00", "06:00", "09:00", "12:00"], id: \.self) { t in
                    Text(t).font(.system(size: 15, weight: .medium)).monospacedDigit()
                    if t != "12:00" { Spacer() }
                }
            }
            .foregroundStyle(.secondary).padding(.top, 6)

            HStack(spacing: 14) {
                stat("71%", "time in the zone", PitchAdaptPanel.zone)
                stat("148", "peak bpm, 06:40", PitchAdaptPanel.high)
                stat("40 s", "back in the zone after the hint", PitchAdaptPanel.low)
            }
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 10) {
                note("arrow.up.right.circle.fill", PitchAdaptPanel.low, "04:10", "Heart rate flat at 74: the sim added bystanders and Jordan drifted off.")
                note("exclamationmark.triangle.fill", PitchAdaptPanel.high, "06:40", "Two people shouting at once: you stopped talking to Jordan for 25 s.")
                note("lightbulb.fill", PitchAdaptPanel.zone, "06:50", "Lena's hint, crowd moved back. You checked the pulse and recovered.")
            }
            .padding(.top, 22)
        }
        .frame(width: 760, alignment: .leading)
    }

    private var chart: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, values = state.trace
            let lo = 60.0, hi = 160.0
            let x = { (i: Int) in w * Double(i) / Double(values.count - 1) }
            let y = { (v: Double) in h * (1 - (v - lo) / (hi - lo)) }
            ZStack(alignment: .topLeading) {
                Rectangle().fill(PitchAdaptPanel.zone.opacity(0.14))
                    .frame(width: w, height: y(95) - y(125)).offset(y: y(125))
                Text("TARGET ZONE").font(.system(size: 13, weight: .heavy)).tracking(1.2).foregroundStyle(PitchAdaptPanel.zone)
                    .offset(x: 8, y: y(125) + 6)
                ForEach([80.0, 100, 120, 140], id: \.self) { v in
                    Path { p in p.move(to: CGPoint(x: 0, y: y(v))); p.addLine(to: CGPoint(x: w, y: y(v))) }
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
                Path { p in
                    for (i, v) in values.enumerated() {
                        if i == 0 { p.move(to: CGPoint(x: x(i), y: y(v))) } else { p.addLine(to: CGPoint(x: x(i), y: y(v))) }
                    }
                }
                .stroke(LinearGradient(colors: [PitchAdaptPanel.high, PitchAdaptPanel.zone, PitchAdaptPanel.low],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                ForEach(Array(PitchAdaptive.events.enumerated()), id: \.offset) { n, e in
                    let px = x(e.at), py = y(values[e.at])
                    Path { p in p.move(to: CGPoint(x: px, y: py)); p.addLine(to: CGPoint(x: px, y: h)) }
                        .stroke(e.tint.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    Circle().fill(e.tint).frame(width: 16, height: 16).shadow(color: e.tint, radius: 5).position(x: px, y: py)
                    Text(e.label).font(.system(size: 15, weight: .bold)).foregroundStyle(e.tint)
                        .fixedSize()
                        .position(x: px + (n == 2 ? 62 : n == 1 ? -44 : 92), y: n == 0 ? py + 4 : py - 18) // first label beside its dashed line, not across it
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(tint)
            Text(label).font(.system(size: 16, weight: .medium)).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 18))
    }

    private func note(_ icon: String, _ tint: Color, _ time: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint).frame(width: 28)
            Text(time).font(.system(size: 18, weight: .bold)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
            Text(text).font(.system(size: 19, weight: .medium)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
        }
    }
}
