import RealityKit
import UIKit

extension PatientAvatar {
    /// Rebuild exam zones from the case. Entity name = zone id; parented to the `attachTo` anchor.
    func rebuildZones(_ zones: [ZoneInfo]) {
        zoneEntities.forEach { $0.removeFromParent() }
        zoneEntities = []
        for zone in zones {
            guard let parent = anchors[zone.attachTo] else { continue }
            var mat = UnlitMaterial(color: .white)
            mat.blending = .transparent(opacity: .init(floatLiteral: 0.07))
            let e = ModelEntity(mesh: .generateSphere(radius: zone.radius), materials: [mat])
            e.name = zone.id
            let o = zone.offset
            e.position = o.count == 3 ? [o[0], o[1], o[2]] : .zero
            e.components.set(CollisionComponent(shapes: [.generateSphere(radius: zone.radius)]))
            e.components.set(InputTargetComponent())
            e.components.set(HoverEffectComponent())
            parent.addChild(e)
            zoneEntities.append(e)
        }
    }
}
