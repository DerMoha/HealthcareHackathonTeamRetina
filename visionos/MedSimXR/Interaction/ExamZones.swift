import RealityKit
import UIKit

extension PatientAvatar {
    /// Rebuild exam zones from the case. Entity name = zone id; parented to the `attachTo` anchor.
    func rebuildZones(_ zones: [ZoneInfo]) {
        zoneEntities.forEach { $0.removeFromParent() }
        zoneEntities = []
        for zone in zones {
            guard let parent = anchors[zone.attachTo] else { continue }
            let e = ModelEntity(mesh: .generateSphere(radius: zone.radius), materials: [Self.zoneMaterial(.white, 0.07)])
            e.name = zone.id
            let o = zone.offset
            e.position = o.count == 3 ? [o[0], o[1], o[2]] : .zero
            e.components.set(CollisionComponent(shapes: [.generateSphere(radius: zone.radius)]))
            e.components.set(InputTargetComponent())
            e.components.set(HoverEffectComponent())
            e.isEnabled = zonesEnabled
            parent.addChild(e)
            zoneEntities.append(e)
        }
    }

    private static func zoneMaterial(_ color: UIColor, _ opacity: Float) -> UnlitMaterial {
        var mat = UnlitMaterial(color: color)
        mat.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return mat
    }

    /// Brief coloured pulse on the examined zone: red when painful, green when not.
    func flashZone(_ id: String?, painful: Bool) async {
        guard let zone = zoneEntities.first(where: { $0.name == id }) as? ModelEntity else { return }
        zone.model?.materials = [Self.zoneMaterial(painful ? .systemRed : .systemGreen, 0.55)]
        SmokeLog.mark("zone flash \(zone.name) painful=\(painful)")
        try? await Task.sleep(nanoseconds: 900_000_000)
        zone.model?.materials = [Self.zoneMaterial(.white, 0.07)]
    }
}
