import SwiftUI

/// Bundled example sonograms (Resources/Ultrasound). Image ids come from the case engine and resolve
/// through `ultrasound_manifest.json`. Licences: assets/ultrasound/README.md.
enum UltrasoundImage {
    struct Entry: Decodable, Hashable {
        var id: String
        var file: String
        var title: String?
        var author: String?
        var license: String?
    }

    static let manifest: [String: Entry] = {
        guard let url = Bundle.main.url(forResource: "ultrasound_manifest", withExtension: "json", subdirectory: "Ultrasound")
                ?? Bundle.main.url(forResource: "ultrasound_manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [:] }
        return Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    }()

    static func url(_ id: String) -> URL? {
        let file = (manifest[id]?.file ?? "\(id).jpg") as NSString
        let name = file.deletingPathExtension, ext = file.pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Ultrasound")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }

    @MainActor private static var cache: [String: UIImage] = [:]

    @MainActor
    static func image(_ id: String) -> UIImage? {
        if let hit = cache[id] { return hit }
        guard let url = url(id), let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache[id] = image
        return image
    }
}

/// The simulated machine's screen: the real example image the engine returned for the region the probe
/// touches, or a dark sector without contact, or noise without gel. Labelled as simulated everywhere.
struct UltrasoundMonitorView: View {
    @Environment(AppModel.self) private var model

    static let size = CGSize(width: 760, height: 540)

    private enum Mode { case noContact, poor(ScanResult), good(ScanResult) }

    private var mode: Mode {
        guard model.probeRegion != nil, let scan = model.lastScan else { return .noContact }
        return scan.quality == "good" ? .good(scan) : .poor(scan)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: 0) {
                screen.frame(maxWidth: .infinity, maxHeight: .infinity)
                sidebar.frame(width: 190)
            }
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(red: 0.02, green: 0.03, blue: 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack {
            Text("MedSim US").font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
            Text("OB 2nd trimester").font(.system(size: 17, design: .monospaced)).foregroundStyle(.white.opacity(0.75))
            Spacer()
            if !SmokeLog.pitch { Text("Simulated scan, illustrative images")
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(.orange.opacity(0.9), in: Capsule())
                .foregroundStyle(.black) }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
    }

    // MARK: Picture

    @ViewBuilder
    private var screen: some View {
        ZStack {
            Color.black
            switch mode {
            case .noContact:
                FanShape().fill(LinearGradient(colors: [Color(white: 0.13), Color(white: 0.04)], startPoint: .top, endPoint: .bottom))
                    .padding(20)
                    .overlay(FanShape().stroke(Color.white.opacity(0.12), lineWidth: 1).padding(20))
                VStack(spacing: 6) {
                    Image(systemName: SmokeLog.pitch ? "dot.radiowaves.up.forward" : "waveform.slash").font(.system(size: 34))
                    Text(SmokeLog.pitch ? "Ready to scan" : "No contact").font(.system(size: 26, weight: .semibold)) // pitch: standby, not an error
                    Text(model.usHint ?? (model.gelApplied ? "Place the probe on the patient's belly."
                                                           : "Apply gel, then place the probe on the belly."))
                        .font(.system(size: 17)).multilineTextAlignment(.center).padding(.horizontal, 30)
                }
                .foregroundStyle(.white.opacity(0.6))
            case .poor(let scan):
                NoiseView().padding(20).clipShape(FanShape().inset(by: 20)).opacity(0.9)
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 32)).foregroundStyle(.orange)
                    Text(scan.title).font(.system(size: 26, weight: .bold))
                    Text("Apply ultrasound gel, then scan again.").font(.system(size: 18, weight: .medium))
                }
                .padding(14).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            case .good(let scan):
                if let id = scan.image, let image = UltrasoundImage.image(id) {
                    Image(uiImage: image).resizable().scaledToFit().padding(10)
                } else {
                    Text("Image file missing").foregroundStyle(.red)
                }
            }
        }
    }

    private var sidebar: some View {
        let scan = currentScan
        return VStack(alignment: .leading, spacing: 10) {
            readout("Depth", scan.map { String(format: "%.1f cm", $0.depthCm) } ?? "–")
            readout("Gain", scan.map { "\($0.gain) %" } ?? "–")
            readout("Freq", scan == nil ? "–" : "3.5 MHz")
            readout("Gel", model.gelApplied ? "on skin" : "none", color: model.gelApplied ? .green : .orange)
            readout("Frames", model.scanSerial == 0 ? "–" : "\(model.scanSerial)")
            Spacer()
            if case .good(let s) = mode, s.repeatCount > 1 {
                Text("Seen \(s.repeatCount)×").font(.system(size: 15)).foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.05))
    }

    private var currentScan: ScanResult? {
        switch mode { case .noContact: nil; case .poor(let s), .good(let s): s }
    }

    private func readout(_ title: String, _ value: String, color: Color = .cyan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(.system(size: 13, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
            Text(value).font(.system(size: 22, weight: .semibold, design: .monospaced)).foregroundStyle(color)
        }
    }

    // MARK: Caption

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch mode {
            case .noContact:
                if SmokeLog.pitch { // pitch: the booked patient, as a real scanner shows before the first frame
                    Text("Sarah Thompson  ·  DOB 14/03/1995  ·  20+0 weeks").font(.system(size: 21, weight: .semibold))
                    Text("Mid-trimester fetal anomaly scan  ·  transabdominal").font(.system(size: 16)).foregroundStyle(.white.opacity(0.6))
                } else {
                    Text("Probe not on the patient").font(.system(size: 21, weight: .semibold))
                    Text("The live image appears here while the probe touches the belly.").font(.system(size: 16)).foregroundStyle(.white.opacity(0.6))
                }
            case .poor(let scan):
                Text(scan.title).font(.system(size: 21, weight: .semibold)).foregroundStyle(.orange)
                Text(scan.caption).font(.system(size: 16)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
            case .good(let scan):
                Text(scan.title).font(.system(size: 21, weight: .semibold)).lineLimit(1)
                if !scan.measurements.isEmpty {
                    Text(scan.measurements.map(\.text).joined(separator: "   ·   "))
                        .font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(.yellow)
                }
                Text(scan.caption).font(.system(size: 16)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                Text(scan.imageCredit).font(.system(size: 12)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
    }
}

/// Ultrasound fan: the apex at the top centre, an arc at the bottom.
struct FanShape: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        let apex = CGPoint(x: r.midX, y: r.minY)
        let radius = r.height
        let half = Angle.degrees(36)
        path.move(to: apex)
        path.addArc(center: apex, radius: radius, startAngle: .degrees(90) - half, endAngle: .degrees(90) + half, clockwise: false)
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> FanShape { FanShape(inset: inset + amount) }
}

/// Static speckle, the picture of a probe without gel.
private struct NoiseView: View {
    var body: some View {
        Canvas { context, size in
            var rng = SeededGenerator(seed: 7)
            for _ in 0..<5200 {
                let x = Double.random(in: 0..<size.width, using: &rng), y = Double.random(in: 0..<size.height, using: &rng)
                let g = Double.random(in: 0.1...0.75, using: &rng)
                context.fill(Path(CGRect(x: x, y: y, width: 3, height: 3)), with: .color(Color(white: g)))
            }
        }
        .background(Color(white: 0.06))
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}

/// Buttons mounted beside the machine: gaze+pinch alternative to dragging, same model calls.
struct UltrasoundPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.phase == .running, model.ultrasound != nil {
            VStack(alignment: .leading, spacing: 10) {
                Label("Ultrasound", systemImage: "waveform.path.ecg").font(.headline)
                Text(status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button { Task { await model.applyGel() } } label: { Label("Apply gel", systemImage: "drop.fill") }
                    Button { Task { await model.rotateProbe() } } label: { Label("Rotate probe", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(model.probeRegion == nil)
                    Button { model.liftProbe() } label: { Label("Lift probe", systemImage: "arrow.up.circle") }
                        .disabled(model.probeRegion == nil)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(16)
            .frame(width: 400, alignment: .leading)
            .glassBackgroundEffect()
        }
    }

    private var status: String {
        if let tool = model.selectedTool == UltrasoundScene.probeName ? "probe" : model.selectedTool == UltrasoundScene.gelName ? "gel" : nil {
            return "The \(tool) is selected: pinch the patient's belly to use it there."
        }
        if model.probeRegion != nil { return "Probe on the belly. Rotate it, or pinch another spot to move it." }
        return "Pinch the probe or the gel bottle on the trolley, then the belly. Or drag them there."
    }
}
