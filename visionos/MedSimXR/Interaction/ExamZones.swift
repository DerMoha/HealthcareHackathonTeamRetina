import RealityKit
import UIKit

extension PatientAvatar {
    /// Rebuild exam zones from the case. Entity name = zone id; parented to the `attachTo` anchor.
    func rebuildZones(_ zones: [ZoneInfo]) {
        zoneEntities.forEach { $0.removeFromParent() }
        zoneEntities = []
        for zone in zones {
            guard let parent = anchors[zone.attachTo] else { continue }
            let e = ModelEntity(mesh: .generateSphere(radius: zone.radius), materials: [Self.zoneMaterial(.white, Self.idleOpacity)])
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

    /// Pitch shots: the zones are invisible until examined.
    private static var idleOpacity: Float { SmokeLog.pitch ? 0 : 0.07 }

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
        try? await Task.sleep(nanoseconds: SmokeLog.pitch ? 4_000_000_000 : 900_000_000) // pitch: long enough for the screenshot
        zone.model?.materials = [Self.zoneMaterial(.white, Self.idleOpacity)]
    }
}
