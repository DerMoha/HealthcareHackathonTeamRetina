import SwiftUI

/// Bundled example images (Resources/Radiology). Licences: assets/radiology/README.md.
enum RadiologyImage {
    static func url(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Radiology")
            ?? Bundle.main.url(forResource: name, withExtension: "jpg")
    }
}

/// Floating result viewer, its own movable panel beside the notebook.
/// The header names the study only. Findings are in the report body, from the case engine.
struct RadiologyViewer: View {
    @Environment(AppModel.self) private var model
    let result: InvestigationResult
    @State private var pinchStart = 1.0

    private static let zoomRange = 1.0...4.0
    private static let frameHeight = 300.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "rays").font(.title2).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.label).font(.title3.bold())
                    Text("\(result.modality) · \(result.title)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.closeViewer() } label: { Label("Close", systemImage: "xmark") }
            }
            if let name = result.image, let url = RadiologyImage.url(name), let image = UIImage(contentsOfFile: url.path) {
                picture(image)
            } else {
                Label("Simulated report only. No image for this study.", systemImage: "doc.text.magnifyingglass")
                    .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Simulated radiology report").font(.headline)
                    Text(result.report).font(.callout)
                    Text("Impression: \(result.impression)").font(.callout.bold())
                    Text(result.imageCredit).font(.caption).foregroundStyle(.secondary)
                    Text("Requested \(result.orderedAt) · training simulation, not a real patient")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func picture(_ image: UIImage) -> some View {
        let zoom = model.viewerZoom
        let width = Self.frameHeight * image.size.width / max(image.size.height, 1)
        return VStack(spacing: 8) {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image).resizable()
                    .frame(width: width * zoom, height: Self.frameHeight * zoom)
            }
            .defaultScrollAnchor(.center)
            .frame(maxWidth: .infinity).frame(height: Self.frameHeight)
            .background(.black, in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .gesture(MagnifyGesture()
                .onChanged { setZoom(pinchStart * $0.magnification) }
                .onEnded { _ in pinchStart = model.viewerZoom })
            HStack {
                Button { step(-0.5) } label: { Image(systemName: "minus.magnifyingglass") }
                    .disabled(zoom <= Self.zoomRange.lowerBound).accessibilityLabel("Zoom out")
                Text("\(Int(zoom * 100)) %").font(.callout.monospacedDigit()).frame(width: 64)
                Button { step(0.5) } label: { Image(systemName: "plus.magnifyingglass") }
                    .disabled(zoom >= Self.zoomRange.upperBound).accessibilityLabel("Zoom in")
                Button("Reset") { step(-10) }.disabled(zoom == 1)
            }
        }
    }

    private func setZoom(_ value: Double) {
        model.viewerZoom = min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    private func step(_ delta: Double) {
        setZoom(model.viewerZoom + delta)
        pinchStart = model.viewerZoom
    }
}
