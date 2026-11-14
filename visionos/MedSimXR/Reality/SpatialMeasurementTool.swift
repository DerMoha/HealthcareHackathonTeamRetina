import RealityKit
import UIKit

/// Reusable measuring overlay. A length is the distance between two landmark entities (here
/// they ride on the patient's skeleton joints). A girth is only drawn: its value must come
/// from case data, never from a straight-line distance.
@MainActor
final class SpatialMeasurementTool {
    let overlay = Entity()
    static let tapeColor = UIColor(red: 1.0, green: 0.80, blue: 0.16, alpha: 1)
    private var labelPosition = SIMD3<Float>.zero
    private var caption = ""

    /// Distance between two landmarks in centimetres, rounded to millimetres.
    static func distanceCm(_ a: Entity, _ b: Entity) -> Double {
        let metres = simd_distance(a.position(relativeTo: nil), b.position(relativeTo: nil))
        return (Double(metres) * 1000).rounded() / 10
    }

    private static var printed: [Int: TextureResource] = [:]

    /// Printed tape face: millimetre, half and full centimetre ticks, centimetre numbers; one per length.
    private static func printedTape(cm: Int) -> TextureResource? {
        if let t = printed[cm] { return t }
        let pxPerCm: CGFloat = 80, height: CGFloat = 96
        let size = CGSize(width: max(CGFloat(cm), 1) * pxPerCm, height: height)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let g = ctx.cgContext
            tapeColor.setFill(); g.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.08, alpha: 1).setFill()
            for mm in 0...(cm * 10) {
                let x = CGFloat(mm) * pxPerCm / 10
                let h: CGFloat = mm % 10 == 0 ? 40 : mm % 5 == 0 ? 26 : 16
                g.fill(CGRect(x: x - 1.2, y: 0, width: mm % 10 == 0 ? 3 : 2, height: h))
            }
            let font = UIFont.monospacedDigitSystemFont(ofSize: 34, weight: .bold)
            for c in stride(from: 1, through: cm, by: 1) {
                let s = NSAttributedString(string: "\(c)", attributes: [.font: font, .foregroundColor: c % 10 == 0 ? UIColor.systemRed : UIColor(white: 0.08, alpha: 1)])
                let w = s.size().width
                s.draw(at: CGPoint(x: CGFloat(c) * pxPerCm - w - 6, y: 46))
            }
            UIColor(white: 0, alpha: 0.18).setFill()
            g.fill(CGRect(x: 0, y: height - 4, width: size.width, height: 4))
        }
        let t = image.cgImage.flatMap { try? TextureResource(image: $0, options: .init(semantic: .color)) }
        printed[cm] = t
        return t
    }

    /// Flat tape strip along +Y, `length` metres, printed face towards ±X.
    static func strip(length: Float, width: Float = 0.014) -> Entity {
        let e = Entity()
        var m = UnlitMaterial(color: tapeColor)
        if let t = printedTape(cm: Int((length * 100).rounded(.up))) {
            m.color = .init(tint: .white, texture: .init(t))
            m.textureCoordinateTransform.scale = [length * 100 / Float((length * 100).rounded(.up)), 1]
        }
        m.faceCulling = .none
        let band = ModelEntity(mesh: .generatePlane(width: length, height: width), materials: [m])
        // plane spans X (length) and Y (width): turn the length onto +Y and the face onto ±X
        band.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0]) * simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        band.position = [0, length / 2, 0]
        e.addChild(band)
        return e
    }

    func clear() { Array(overlay.children).forEach { $0.removeFromParent() } }

    /// Compact floating value next to the current measurement; always faces the viewer.
    func setLabel(_ text: String) {
        overlay.findEntity(named: "value")?.removeFromParent()
        guard !overlay.children.isEmpty else { return }
        let chip = Entity()
        chip.name = "value"
        chip.position = labelPosition
        chip.components.set(BillboardComponent())
        let plate = ZoneMarker.pill(title: text, detail: caption.uppercased(), color: Self.tapeColor, at: [0, 0, 0], scale: 1.45)
        // centre the pill on the label point
        plate.position.x = -(plate.visualBounds(relativeTo: chip).extents.x / 2)
        chip.addChild(plate)
        overlay.addChild(chip)
    }

    /// Small white end stop with a dark rim, marking a landmark the tape runs between.
    private func endStop(at p: SIMD3<Float>) {
        let stop = Entity()
        stop.position = p
        stop.components.set(BillboardComponent())
        let rim = ModelEntity(mesh: ZoneMarker.disc(0.0062), materials: [ZoneMarker.flat(UIColor(white: 0.08, alpha: 1), 0.9)])
        let dot = ModelEntity(mesh: ZoneMarker.disc(0.0044), materials: [ZoneMarker.flat(.white, 1)])
        dot.position.z = 0.0003
        stop.addChild(rim); stop.addChild(dot)
        overlay.addChild(stop)
    }

    /// Tape from `a` to `b`, drawn in `parent` space and lifted off the limb by `lift`.
    func showLength(from a: Entity, to b: Entity, in parent: Entity, lift: SIMD3<Float>, label: SIMD3<Float>) {
        clear()
        labelPosition = label
        caption = "Forearm length"
        parent.addChild(overlay)
        let p = a.position(relativeTo: parent) + lift, q = b.position(relativeTo: parent) + lift
        let d = q - p, length = simd_length(d)
        guard length > 0.001 else { return }
        let line = Self.strip(length: length)
        line.position = p
        line.orientation = simd_quatf(from: [0, 1, 0], to: d / length)
        overlay.addChild(line)
        endStop(at: p); endStop(at: q)
    }

    /// Tape band around `parent`'s Y axis at `position`.
    func showGirth(around parent: Entity, at position: SIMD3<Float>, radius: Float, label: SIMD3<Float>) {
        clear()
        labelPosition = label
        caption = "Wrist circumference"
        parent.addChild(overlay)
        var m = UnlitMaterial(color: Self.tapeColor)
        let cm = Int((2 * .pi * radius * 100).rounded(.up))
        if let t = Self.printedTape(cm: cm) { m.color = .init(tint: .white, texture: .init(t)) }
        m.faceCulling = .none
        overlay.addChild(ModelEntity(mesh: Self.band(radius: radius + 0.0015, width: 0.014, at: position.y), materials: [m]))
    }

    /// Open ring band around Y with the tape printed once around it.
    private static func band(radius: Float, width: Float, at y: Float, segments: Int = 64) -> MeshResource {
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], uvs: [SIMD2<Float>] = [], indices: [UInt32] = []
        for i in 0...segments {
            let u = Float(i) / Float(segments), a = u * 2 * .pi
            for (k, dy) in [-width / 2, width / 2].enumerated() {
                positions.append([cos(a) * radius, y + dy, sin(a) * radius])
                normals.append([cos(a), 0, sin(a)])
                uvs.append([u, Float(k)])
            }
        }
        for i in 0..<UInt32(segments) {
            let p = i * 2
            indices += [p, p + 2, p + 1, p + 1, p + 2, p + 3]
        }
        var d = MeshDescriptor(name: "band")
        d.positions = MeshBuffer(positions); d.normals = MeshBuffer(normals); d.textureCoordinates = MeshBuffer(uvs)
        d.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [d])) ?? .generateCylinder(height: width, radius: radius)
    }
}
