import SwiftUI

/// Bundled example images (Resources/Radiology). Licences: assets/radiology/README.md.
enum RadiologyImage {
    static func url(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Radiology")
            ?? Bundle.main.url(forResource: name, withExtension: "jpg")
    }

    static func load(_ name: String) -> UIImage? { url(name).flatMap { UIImage(contentsOfFile: $0.path) } }
}

/// Pitch run only: extra views and a stand-in image for the report-only forearm study
/// (Resources/Pitch, licences in assets/pitch/CREDITS-uiimaging.md).
private enum PitchStudy {
    static func views(_ result: InvestigationResult) -> [(label: String, image: String)]? {
        guard SmokeLog.pitch else { return nil }
        switch result.investigationId {
        case "right_wrist_xray": return [("PA", "wrist_xray_pa"), ("LAT", "uiimaging_xray_wrist_lat")]
        case "rt_xray_forearm": return [("AP", "uiimaging_xray_forearm_ap"), ("LAT", "uiimaging_xray_forearm_lat")]
        default: return nil
        }
    }

    static func credit(_ result: InvestigationResult) -> String? {
        guard SmokeLog.pitch else { return nil }
        switch result.investigationId {
        case "right_wrist_xray":
            return "Illustrative example images: a normal wrist (mirrored), PA and lateral, by Mikael Häggström, M.D., CC0, Wikimedia Commons. Not this patient."
        case "rt_xray_forearm":
            return "Illustrative example images: displaced forearm fractures (mirrored), by Hellerhoff, CC BY-SA 4.0, Wikimedia Commons. Not this patient."
        default: return nil
        }
    }
}

/// Floating PACS-style result viewer, its own movable panel beside the notebook: a dark image well
/// with the views side by side, window presets and zoom, then the structured report.
/// The header names the study only. Findings are in the report body, from the case engine.
struct RadiologyViewer: View {
    @Environment(AppModel.self) private var model
    let result: InvestigationResult
    @State private var pinchStart = 1.0
    @State private var window = Window.standard
    @State private var inverted = false

    private static let zoomRange = 1.0...4.0
    private static let wellSize = CGSize(width: 672, height: 372) // NotebookPage: 720 wide, 24 padding

    /// Display presets, applied as brightness and contrast to the bundled 8-bit image.
    enum Window: String, CaseIterable {
        case standard = "Default", bone = "Bone", soft = "Soft tissue"
        var brightness: Double { switch self { case .standard: 0; case .bone: -0.06; case .soft: 0.1 } }
        var contrast: Double { switch self { case .standard: 1; case .bone: 1.4; case .soft: 0.72 } }
        var readout: String { switch self { case .standard: "W 4096  L 2048"; case .bone: "W 1800  L 1200"; case .soft: "W 600  L 2600" } }
    }

    private struct Frame: Identifiable { var id: Int; var label: String; var image: UIImage }

    private var frames: [Frame] {
        let named = PitchStudy.views(result) ?? result.image.map { [("", $0)] } ?? []
        return named.enumerated().compactMap { i, v in RadiologyImage.load(v.image).map { Frame(id: i, label: v.label, image: $0) } }
    }

    private var patient: PatientInfo? { model.session?.case.patient }

    var body: some View {
        let frames = frames
        VStack(alignment: .leading, spacing: 14) {
            header(images: frames.count)
            if frames.isEmpty { noImage } else { well(frames); controls }
            report
        }
    }

    // MARK: Header

    private func header(images: Int) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "rays")
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 46, height: 46)
                .background(.teal.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(result.label).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                Text([result.modality, result.title, images == 0 ? "report only" : "\(images) image\(images == 1 ? "" : "s")"]
                    .joined(separator: "  ·  "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { model.closeViewer() } label: { Image(systemName: "xmark") }
                .buttonBorderShape(.circle).accessibilityLabel("Close")
        }
    }

    // MARK: Image well

    private func well(_ frames: [Frame]) -> some View {
        let zoom = model.viewerZoom, size = Self.wellSize
        let height = (size.height - 24) * zoom
        return ZStack {
            Color(white: 0.02)
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(frames) { frame in
                        Image(uiImage: frame.image).resizable()
                            .frame(width: height * frame.image.size.width / max(frame.image.size.height, 1), height: height)
                            .brightness(window.brightness).contrast(window.contrast)
                            .modifier(Invert(on: inverted))
                            .overlay(alignment: .topLeading) {
                                if !frame.label.isEmpty { Text(frame.label).font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.8)).padding(8) }
                            }
                    }
                }
                .frame(minWidth: size.width, minHeight: size.height)
            }
            .defaultScrollAnchor(.center)
            .gesture(MagnifyGesture()
                .onChanged { setZoom(pinchStart * $0.magnification) }
                .onEnded { _ in pinchStart = model.viewerZoom })
            overlays(images: frames.count).allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }

    /// The four-corner annotation of a PACS display.
    private func overlays(images: Int) -> some View {
        let name = (patient?.name ?? "Patient").uppercased()
        let tl = [name, patient.map { "\($0.age) y" } ?? "", SmokeLog.pitch ? "MRN 4471-2093" : ""]
        let tr = [result.modality == "X-ray" ? "CR · \(result.modality)" : result.modality, Self.time(result.orderedAt), SmokeLog.pitch ? "Acc 26-118734" : ""]
        let bl = [window.readout, "Zoom \(Int(model.viewerZoom * 100)) %"]
        let br = ["Se 1 · \(images) im", "Simulated"]
        return VStack {
            HStack(alignment: .top) { corner(tl, .leading); Spacer(); corner(tr, .trailing) }
            Spacer()
            HStack(alignment: .bottom) { corner(bl, .leading); Spacer(); corner(br, .trailing) }
        }
        .padding(12)
    }

    private func corner(_ lines: [String], _ alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            ForEach(lines.filter { !$0.isEmpty }, id: \.self) { Text($0) }
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.72))
        .shadow(color: .black, radius: 2)
    }

    private var controls: some View {
        let zoom = model.viewerZoom
        return HStack(spacing: 12) {
            Picker("Window", selection: $window) {
                ForEach(Window.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).frame(width: 300)
            Toggle(isOn: $inverted) { Image(systemName: "circle.lefthalf.filled") }
                .toggleStyle(.button).accessibilityLabel("Invert")
            Spacer()
            HStack(spacing: 6) {
                Button { step(-0.5) } label: { Image(systemName: "minus.magnifyingglass") }
                    .disabled(zoom <= Self.zoomRange.lowerBound).accessibilityLabel("Zoom out")
                Text("\(Int(zoom * 100)) %").font(.callout.monospacedDigit()).frame(width: 58)
                Button { step(0.5) } label: { Image(systemName: "plus.magnifyingglass") }
                    .disabled(zoom >= Self.zoomRange.upperBound).accessibilityLabel("Zoom in")
                Button { step(-10) } label: { Image(systemName: "arrow.counterclockwise") }
                    .disabled(zoom == 1).accessibilityLabel("Reset zoom")
            }
            .buttonBorderShape(.circle)
        }
        .controlSize(.small)
    }

    private var noImage: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 28)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Report only").font(.headline)
                Text("No image is shown for this study.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Report

    private var report: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Report").font(.headline)
                    Text("Simulated").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Requested \(Self.time(result.orderedAt))").font(.caption).foregroundStyle(.tertiary)
                }
                Text(result.report).font(.callout).foregroundStyle(.primary.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 12) {
                    Capsule().fill(.teal).frame(width: 4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("IMPRESSION").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.teal)
                        Text(result.impression).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Text(PitchStudy.credit(result) ?? result.imageCredit).font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let display: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM yyyy  HH:mm"
        return f
    }()

    /// "2026-11-13T21:10:39Z" as a local "13 Nov 2026  22:10"; anything else unchanged.
    private static func time(_ iso: String) -> String {
        ISO8601DateFormatter().date(from: iso).map { display.string(from: $0) } ?? iso
    }

    private func setZoom(_ value: Double) {
        model.viewerZoom = min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    private func step(_ delta: Double) {
        setZoom(model.viewerZoom + delta)
        pinchStart = model.viewerZoom
    }
}

private struct Invert: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View {
        if on { content.colorInvert() } else { content }
    }
}
