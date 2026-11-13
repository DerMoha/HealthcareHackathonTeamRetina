import RealityKit
import UIKit

/// Reusable measuring overlay. A length is the distance between two landmark entities (here
/// they ride on the patient's skeleton joints). A girth is only drawn: its value must come
/// from case data, never from a straight-line distance.
@MainActor
final class SpatialMeasurementTool {
    let overlay = Entity()
    static let tape = UnlitMaterial(color: .systemYellow)
    static let ink = UnlitMaterial(color: UIColor(white: 0.1, alpha: 1))
    private var labelPosition = SIMD3<Float>.zero

    /// Distance between two landmarks in centimetres, rounded to millimetres.
    static func distanceCm(_ a: Entity, _ b: Entity) -> Double {
        let metres = simd_distance(a.position(relativeTo: nil), b.position(relativeTo: nil))
        return (Double(metres) * 1000).rounded() / 10
    }

    /// Flat tape strip along +Y, `length` metres, with a tick every centimetre (longer every 5).
    static func strip(length: Float, width: Float = 0.014) -> Entity {
        let e = Entity()
        let band = ModelEntity(mesh: .generateBox(size: [0.0012, length, width]), materials: [tape])
        band.position = [0, length / 2, 0]
        e.addChild(band)
        for cm in 0...Int(length * 100) {
            let long = cm % 5 == 0
            let tick = ModelEntity(mesh: .generateBox(size: [0.0016, 0.0012, long ? width * 0.75 : width * 0.4]), materials: [ink])
            tick.position = [0, Float(cm) / 100, long ? 0 : width * 0.3]
            e.addChild(tick)
        }
        return e
    }

    func clear() { Array(overlay.children).forEach { $0.removeFromParent() } }

    /// Compact floating value next to the current measurement; always faces the viewer.
    func setLabel(_ text: String) {
        overlay.findEntity(named: "value")?.removeFromParent()
        guard !overlay.children.isEmpty else { return }
        let mesh = MeshResource.generateText(text, extrusionDepth: 0.001, font: .systemFont(ofSize: 0.018, weight: .bold))
        let size = mesh.bounds.extents
        let plate = ModelEntity(mesh: .generateBox(size: [size.x + 0.016, size.y + 0.012, 0.002], cornerRadius: 0.005),
                                materials: [UnlitMaterial(color: UIColor(white: 0.08, alpha: 1))])
        plate.name = "value"
        plate.position = labelPosition
        plate.components.set(BillboardComponent())
        let value = ModelEntity(mesh: mesh, materials: [Self.tape])
        value.position = [-size.x / 2 - mesh.bounds.min.x, -size.y / 2 - mesh.bounds.min.y, 0.002]
        plate.addChild(value)
        overlay.addChild(plate)
    }

    /// Tape from `a` to `b`, drawn in `parent` space and lifted off the limb by `lift`.
    func showLength(from a: Entity, to b: Entity, in parent: Entity, lift: SIMD3<Float>, label: SIMD3<Float>) {
        clear()
        labelPosition = label
        parent.addChild(overlay)
        let p = a.position(relativeTo: parent) + lift, q = b.position(relativeTo: parent) + lift
        let d = q - p, length = simd_length(d)
        guard length > 0.001 else { return }
        let line = Self.strip(length: length)
        line.position = p
        line.orientation = simd_quatf(from: [0, 1, 0], to: d / length)
        overlay.addChild(line)
    }

    /// Tape band around `parent`'s Y axis at `position`.
    func showGirth(around parent: Entity, at position: SIMD3<Float>, radius: Float, label: SIMD3<Float>) {
        clear()
        labelPosition = label
        parent.addChild(overlay)
        let band = ModelEntity(mesh: .generateCylinder(height: 0.014, radius: radius), materials: [Self.tape])
        band.position = position
        overlay.addChild(band)
        for i in 0..<24 { // centimetre ticks around the band
            let angle = Float(i) / 24 * 2 * .pi
            let tick = ModelEntity(mesh: .generateBox(size: [0.0012, i % 5 == 0 ? 0.011 : 0.006, 0.0012]), materials: [Self.ink])
            tick.position = position + [cos(angle) * (radius + 0.0004), 0, sin(angle) * (radius + 0.0004)]
            overlay.addChild(tick)
        }
    }
}
