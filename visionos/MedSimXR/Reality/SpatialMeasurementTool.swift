import RealityKit
import UIKit

/// Reusable measuring overlay. A length is the distance between two landmark entities (here
/// they ride on the patient's skeleton joints). A girth is only drawn: its value must come
/// from case data, never from a straight-line distance.
@MainActor
final class SpatialMeasurementTool {
    let overlay = Entity()
    private static let tape = UnlitMaterial(color: .systemYellow)

    /// Distance between two landmarks in centimetres, rounded to millimetres.
    static func distanceCm(_ a: Entity, _ b: Entity) -> Double {
        let metres = simd_distance(a.position(relativeTo: nil), b.position(relativeTo: nil))
        return (Double(metres) * 1000).rounded() / 10
    }

    private var labelPosition = SIMD3<Float>.zero

    func clear() { Array(overlay.children).forEach { $0.removeFromParent() } }

    /// Compact floating value next to the current measurement; always faces the viewer.
    func setLabel(_ text: String) {
        overlay.findEntity(named: "value")?.removeFromParent()
        guard !overlay.children.isEmpty else { return }
        let mesh = MeshResource.generateText(text, extrusionDepth: 0.001, font: .systemFont(ofSize: 0.022, weight: .bold))
        let size = mesh.bounds.extents
        let plate = ModelEntity(mesh: .generateBox(size: [size.x + 0.02, size.y + 0.016, 0.002], cornerRadius: 0.006),
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
        let line = ModelEntity(mesh: .generateCylinder(height: length, radius: 0.0025), materials: [Self.tape])
        line.position = (p + q) / 2
        line.orientation = simd_quatf(from: [0, 1, 0], to: d / length)
        overlay.addChild(line)
        for end in [p, q] {
            let tick = ModelEntity(mesh: .generateSphere(radius: 0.007), materials: [Self.tape])
            tick.position = end
            overlay.addChild(tick)
        }
    }

    /// Tape band around `parent`'s Y axis at `position`.
    func showGirth(around parent: Entity, at position: SIMD3<Float>, radius: Float, label: SIMD3<Float>) {
        clear()
        labelPosition = label
        parent.addChild(overlay)
        var material = Self.tape
        material.blending = .transparent(opacity: 0.85)
        let band = ModelEntity(mesh: .generateCylinder(height: 0.012, radius: radius), materials: [material])
        band.position = position
        overlay.addChild(band)
    }
}
