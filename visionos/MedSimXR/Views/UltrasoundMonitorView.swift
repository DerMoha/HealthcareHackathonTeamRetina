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

/// The simulated machine's screen, laid out like a modern cart scanner: a status bar, the B-mode
/// parameters on the left, the image with its depth scale and measurement box, the mode tabs and the
/// stored frames below. The picture is the real example image the engine returned for the region the
/// probe touches, or a dark sector without contact, or noise without gel. Labelled as simulated.
struct UltrasoundMonitorView: View {
    @Environment(AppModel.self) private var model

    static let size = CGSize(width: 760, height: 540)
    private static let accent = Color(red: 0.35, green: 0.85, blue: 0.95)
    private static let measure = Color(red: 1.0, green: 0.86, blue: 0.35)
    /// Pitch run only: crisp callipers drawn over the image's own, in unit image coordinates.
    private static let callipers: [String: [(CGPoint, CGPoint)]] = [
        "us_head_bpd": [(CGPoint(x: 0.533, y: 0.217), CGPoint(x: 0.512, y: 0.532))],
    ]

    private static let edge: [Gradient.Stop] = [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                                .init(color: .black, location: 0.92), .init(color: .clear, location: 1)]

    private enum Mode { case noContact, poor(ScanResult), good(ScanResult) }

    private var mode: Mode {
        guard model.probeRegion != nil, let scan = model.lastScan else { return .noContact }
        return scan.quality == "good" ? .good(scan) : .poor(scan)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            HStack(spacing: 0) {
                parameters.frame(width: 124)
                Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
                viewport.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(red: 0.012, green: 0.016, blue: 0.022))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .dark)
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "waveform").font(.system(size: 15, weight: .bold)).foregroundStyle(Self.accent)
                Text("MedSim").font(.system(size: 16, weight: .semibold)) + Text(" US").font(.system(size: 16, weight: .light))
            }
            divider
            if let p = model.session?.case.patient {
                Text(p.name.uppercased()).font(.system(size: 15, weight: .semibold)).tracking(0.6)
                Text("\(p.age) y").font(.system(size: 15)).foregroundStyle(.white.opacity(0.6))
            }
            if SmokeLog.pitch { Text("ID 4471-2093").font(.system(size: 13, design: .monospaced)).foregroundStyle(.white.opacity(0.45)) }
            Spacer(minLength: 4)
            Text("OB · 2nd trim").font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Self.accent.opacity(0.16), in: Capsule()).foregroundStyle(Self.accent)
            Text("C1-6").font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.75))
            if SmokeLog.pitch {
                Text("MI 0.9  TIs 0.3").font(.system(size: 13, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            }
            divider
            Text(Date.now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                .font(.system(size: 15, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.8))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).frame(height: 40)
        .background(Color.white.opacity(0.055))
    }

    private var divider: some View { Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 18) }

    // MARK: Parameters

    private var parameters: some View {
        let scan = currentScan
        return VStack(alignment: .leading, spacing: 11) {
            Text("B-MODE").font(.system(size: 12, weight: .bold)).tracking(1.4).foregroundStyle(Self.accent)
            readout("Frq", scan == nil ? "–" : "3.5", "MHz")
            readout("Gn", scan.map { "\($0.gain)" } ?? "–", "%")
            readout("D", scan.map { String(format: "%.1f", $0.depthCm) } ?? "–", "cm")
            if SmokeLog.pitch {
                readout("DR", scan == nil ? "–" : "66", "dB")
                readout("FR", scan == nil ? "–" : "31", "Hz")
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Circle().fill(model.gelApplied ? Color.green : .orange).frame(width: 8, height: 8)
                Text(model.gelApplied ? "Gel on" : "No gel").font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.8))
            Text(model.scanSerial == 0 ? "No frames" : "Frames \(model.scanSerial)")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func readout(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.45))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 20, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                if value != "–" { Text(unit).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)) }
            }
        }
    }

    private var currentScan: ScanResult? {
        switch mode { case .noContact: nil; case .poor(let s), .good(let s): s }
    }

    // MARK: Picture

    private var viewport: some View {
        ZStack {
            Color.black
            switch mode {
            case .noContact:
                FanShape().fill(LinearGradient(colors: [Color(white: 0.11), Color(white: 0.03)], startPoint: .top, endPoint: .bottom))
                    .padding(24)
                    .overlay(FanShape().stroke(Color.white.opacity(0.12), lineWidth: 1).padding(24))
                VStack(spacing: 8) {
                    Image(systemName: "waveform.slash").font(.system(size: 30))
                    Text("No contact").font(.system(size: 24, weight: .semibold))
                    Text(model.usHint ?? (model.gelApplied ? "Place the probe on the patient's belly."
                                                           : "Apply gel, then place the probe on the belly."))
                        .font(.system(size: 16)).multilineTextAlignment(.center).padding(.horizontal, 40)
                }
                .foregroundStyle(.white.opacity(0.6))
            case .poor(let scan):
                NoiseView().padding(24).clipShape(FanShape().inset(by: 24)).opacity(0.9)
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 30)).foregroundStyle(.orange)
                    Text(scan.title).font(.system(size: 24, weight: .bold))
                    Text("Apply ultrasound gel, then scan again.").font(.system(size: 17, weight: .medium))
                }
                .padding(16).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            case .good(let scan):
                if let id = scan.image, let image = UltrasoundImage.image(id) {
                    picture(image, id: id).padding(.vertical, 10).padding(.horizontal, 40)
                } else {
                    Text("Image file missing").foregroundStyle(.red)
                }
            }
            HStack { Spacer(); depthScale(currentScan?.depthCm ?? 10) }.padding(.vertical, 14).padding(.trailing, 12)
            if case .good(let scan) = mode {
                VStack(alignment: .leading) {
                    HStack(alignment: .top) {
                        if !scan.measurements.isEmpty { measurementBox(scan.measurements) }
                        Spacer()
                        live
                    }
                    Spacer()
                }
                .padding(12).padding(.trailing, 30)
            }
        }
        .clipped()
    }

    /// The example image, neutral grey, its rectangular edges faded into the black screen.
    private func picture(_ image: UIImage, id: String) -> some View {
        Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            .saturation(0).contrast(1.08).brightness(-0.02)
            .overlay {
                if SmokeLog.pitch, let lines = Self.callipers[id] {
                    GeometryReader { geo in
                        ForEach(lines.indices, id: \.self) { i in
                            calliper(lines[i], in: geo.size, index: i + 1)
                        }
                    }
                }
            }
            .mask(LinearGradient(stops: Self.edge, startPoint: .top, endPoint: .bottom))
            .mask(LinearGradient(stops: Self.edge, startPoint: .leading, endPoint: .trailing))
    }

    private func calliper(_ line: (CGPoint, CGPoint), in size: CGSize, index: Int) -> some View {
        let a = CGPoint(x: line.0.x * size.width, y: line.0.y * size.height)
        let b = CGPoint(x: line.1.x * size.width, y: line.1.y * size.height)
        return ZStack {
            Path { p in p.move(to: a); p.addLine(to: b) }
                .stroke(Self.measure.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            ForEach([a, b], id: \.x) { point in
                Path { p in
                    p.move(to: CGPoint(x: point.x - 7, y: point.y)); p.addLine(to: CGPoint(x: point.x + 7, y: point.y))
                    p.move(to: CGPoint(x: point.x, y: point.y - 7)); p.addLine(to: CGPoint(x: point.x, y: point.y + 7))
                }
                .stroke(Self.measure, lineWidth: 2)
            }
            Text("\(index)").font(.system(size: 13, weight: .bold)).foregroundStyle(Self.measure)
                .position(x: a.x + 14, y: a.y - 4)
        }
    }

    private func measurementBox(_ items: [ScanMeasurement]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, m in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(i + 1)").font(.system(size: 13, weight: .bold)).foregroundStyle(Self.measure)
                    Text(m.label).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    Text("\(String(format: "%.2f", m.value)) \(m.unit)").font(.system(size: 16, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Self.measure)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.12)))
    }

    private var live: some View {
        HStack(spacing: 5) {
            Circle().fill(Color.green).frame(width: 7, height: 7)
            Text("LIVE").font(.system(size: 12, weight: .bold)).tracking(1)
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.black.opacity(0.5), in: Capsule())
    }

    /// Centimetre ticks down the right edge, a label every 5 cm, the focus marker at two thirds.
    private func depthScale(_ depth: Double) -> some View {
        GeometryReader { geo in
            let h = geo.size.height, n = max(Int(depth.rounded()), 1)
            ZStack(alignment: .topTrailing) {
                ForEach(0...n, id: \.self) { cm in
                    let y = h * Double(cm) / depth
                    Rectangle().fill(.white.opacity(cm % 5 == 0 ? 0.7 : 0.4))
                        .frame(width: cm % 5 == 0 ? 10 : 5, height: 1.5)
                        .position(x: geo.size.width - (cm % 5 == 0 ? 5 : 2.5), y: y)
                    if cm % 5 == 0 {
                        Text("\(cm)").font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.65))
                            .position(x: geo.size.width - 22, y: y)
                    }
                }
                Image(systemName: "arrowtriangle.left.fill").font(.system(size: 9)).foregroundStyle(Self.accent)
                    .position(x: geo.size.width - 16, y: h * 0.62)
            }
        }
        .frame(width: 34)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                modeTabs
                switch mode {
                case .noContact:
                    Text("Probe not on the patient").font(.system(size: 19, weight: .semibold))
                    Text("The live image appears here while the probe touches the belly.").font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                case .poor(let scan):
                    Text(scan.title).font(.system(size: 19, weight: .semibold)).foregroundStyle(.orange).lineLimit(1)
                    Text(scan.caption).font(.system(size: 14)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                case .good(let scan):
                    Text(scan.title).font(.system(size: 19, weight: .semibold)).lineLimit(1)
                    Text(scan.caption).font(.system(size: 14)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    Text("Simulated scan · \(scan.imageCredit)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            frames
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(height: 120)
        .background(Color.white.opacity(0.035))
    }

    private var modeTabs: some View {
        HStack(spacing: 4) {
            ForEach(["B", "M", "CF", "PW", "3D"], id: \.self) { tab in
                Text(tab).font(.system(size: 13, weight: .bold))
                    .frame(minWidth: 34).padding(.vertical, 3)
                    .background(tab == "B" ? Self.accent.opacity(0.2) : .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(tab == "B" ? Self.accent : .white.opacity(0.45))
            }
        }
        .padding(.bottom, 3)
    }

    /// The last stored frames, newest on the right, the one on screen outlined.
    private var frames: some View {
        let ids = model.scanLog.compactMap { $0.quality == "good" ? $0.image : nil }
        var seen = Set<String>()
        let recent = Array(ids.reversed().filter { seen.insert($0).inserted }.prefix(3).reversed())
        return HStack(spacing: 8) {
            ForEach(recent, id: \.self) { id in
                ZStack {
                    Color.black
                    if let image = UltrasoundImage.image(id) { Image(uiImage: image).resizable().scaledToFill().saturation(0) }
                }
                .frame(width: 78, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(id == currentScan?.image ? Self.accent : .white.opacity(0.15), lineWidth: id == currentScan?.image ? 2 : 1))
            }
        }
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
