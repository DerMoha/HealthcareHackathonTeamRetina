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

    /// Pulse highlight on the examined zone: red "Tender" when painful, green "Not tender" when not.
    func flashZone(_ id: String?, painful: Bool) async {
        guard let zone = zoneEntities.first(where: { $0.name == id }) as? ModelEntity else { return }
        zone.children.filter { $0.name == ZoneMarker.name }.forEach { $0.removeFromParent() }
        let marker = ZoneMarker.make(color: painful ? ZoneMarker.tender : ZoneMarker.clear,
                                     radius: 0.04, title: painful ? "Tender" : "Not tender")
        zone.addChild(marker)
        SmokeLog.mark("zone flash \(zone.name) painful=\(painful)")
        await ZoneMarker.pulse(marker, seconds: SmokeLog.pitch ? 4 : 1.2) // pitch: long enough for the screenshot
        marker.removeFromParent()
    }
}

/// Flat, camera-facing highlight drawn over the patient: a solid core, a soft glow, two rings
/// that ripple outwards, and an optional pill label. Used for the examination touch and the
/// debrief replay, so both speak the same visual language.
@MainActor
enum ZoneMarker {
    static let name = "zone_marker"
    static let tender = UIColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1)
    static let clear = UIColor(red: 0.20, green: 0.84, blue: 0.48, alpha: 1)
    static let missed = UIColor(red: 1.0, green: 0.70, blue: 0.20, alpha: 1)
    private static let group = ModelSortGroup(depthPass: nil)

    /// `badge` = a short number in the core (replay order); `title`/`detail` = the pill label.
    static func make(color: UIColor, radius r: Float, title: String? = nil, detail: String? = nil,
                     badge: String? = nil, emphasis: Bool = true) -> Entity {
        let root = Entity()
        root.name = name
        root.components.set(BillboardComponent())
        let face = Entity()
        face.position = [0, 0, 0.03] // just in front of the limb, towards the viewer
        root.addChild(face)
        func add(_ mesh: MeshResource, _ m: UnlitMaterial, order: Int32, z: Float = 0) -> ModelEntity {
            let e = ModelEntity(mesh: mesh, materials: [m])
            e.position.z = z
            e.components.set(ModelSortGroupComponent(group: group, order: order))
            face.addChild(e)
            return e
        }
        _ = add(.generatePlane(width: r * 3.2, height: r * 3.2), glow(color, emphasis ? 0.55 : 0.3), order: 10)
        for i in 0..<2 {
            let ring = add(annulus(r, width: emphasis ? 0.0022 : 0.0016), flat(color, 0.9), order: 11)
            ring.name = "ripple\(i)"
        }
        _ = add(annulus(r * 0.62, width: 0.0014), flat(.white, emphasis ? 0.9 : 0.6), order: 12)
        let core = badge == nil ? r * 0.22 : r * 0.42
        _ = add(disc(core + 0.0016), flat(.white, 1), order: 13)
        _ = add(disc(core), flat(color, 1), order: 14, z: 0.0002)
        if let badge {
            let t = text(badge, size: CGFloat(core * 1.25), weight: .heavy, color: .white, order: 15)
            t.position.z += 0.0004
            face.addChild(t)
        }
        if let title {
            face.addChild(pill(title: title, detail: detail, color: color, at: [r * 1.25 + 0.006, r * 0.9, 0.001], scale: max(1, r / 0.025)))
        }
        return root
    }

    /// Two rings expanding out of the core and fading, half a cycle apart. Returns after `seconds`.
    static func pulse(_ marker: Entity, seconds: Double) async {
        let rings = (0..<2).compactMap { marker.findEntity(named: "ripple\($0)") }
        let start = Date()
        while Date().timeIntervalSince(start) < seconds, marker.parent != nil {
            let t = Float(Date().timeIntervalSince(start))
            for (i, ring) in rings.enumerated() {
                let phase = (t / 1.4 + Float(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let s = 0.7 + phase * 1.1
                ring.scale = [s, s, s]
                ring.components.set(OpacityComponent(opacity: 1 - phase * phase))
            }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    /// Rings frozen mid-ripple, for markers that stay up (replay).
    static func settle(_ marker: Entity) {
        for (i, s) in [Float(1.0), 1.45].enumerated() {
            guard let ring = marker.findEntity(named: "ripple\(i)") else { continue }
            ring.scale = [s, s, s]
            ring.components.set(OpacityComponent(opacity: i == 0 ? 0.85 : 0.35))
        }
    }

    // MARK: Parts

    static func flat(_ color: UIColor, _ opacity: Float) -> UnlitMaterial {
        var m = UnlitMaterial(color: color)
        if opacity < 1 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        m.readsDepth = false; m.writesDepth = false
        m.faceCulling = .none
        return m
    }

    /// Dark glass pill with an accent dot, a title and an optional second line, left-aligned at `p`.
    static func pill(title: String, detail: String?, color: UIColor, at p: SIMD3<Float>, scale: Float = 1) -> Entity {
        let e = Entity()
        e.position = p
        let titleMesh = text(title, size: CGFloat(0.0125 * scale), weight: .semibold, color: .white, order: 22)
        let detailMesh = detail.map { text($0, size: CGFloat(0.0085 * scale), weight: .medium, color: UIColor(white: 1, alpha: 0.72), order: 22) }
        let tw = titleMesh.model?.mesh.bounds.extents.x ?? 0, dw = detailMesh?.model?.mesh.bounds.extents.x ?? 0
        let pad = 0.009 * scale, dot = 0.0042 * scale
        let height = (detailMesh == nil ? 0.026 : 0.038) * scale
        let width = pad * 2 + dot * 2 + 0.006 * scale + max(tw, dw)
        let plate = ModelEntity(mesh: .generateBox(size: [width, height, 0.0004], cornerRadius: min(height / 2, 0.013 * scale)),
                                materials: [flat(UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1), 0.82)])
        plate.position = [width / 2, 0, 0]
        plate.components.set(ModelSortGroupComponent(group: group, order: 20))
        e.addChild(plate)
        let accent = ModelEntity(mesh: disc(dot), materials: [flat(color, 1)])
        accent.position = [pad + dot, detailMesh == nil ? 0 : height * 0.18, 0.0004]
        accent.components.set(ModelSortGroupComponent(group: group, order: 21))
        e.addChild(accent)
        let x = pad + dot * 2 + 0.006 * scale
        titleMesh.position += [x + tw / 2, detailMesh == nil ? 0 : height * 0.18, 0.0006]
        e.addChild(titleMesh)
        if let detailMesh {
            detailMesh.position += [x + dw / 2, -height * 0.2, 0.0006]
            e.addChild(detailMesh)
        }
        return e
    }

    /// Text mesh centred on its own origin.
    static func text(_ string: String, size: CGFloat, weight: UIFont.Weight, color: UIColor, order: Int32) -> ModelEntity {
        let mesh = MeshResource.generateText(string, extrusionDepth: 0.0002, font: .systemFont(ofSize: size, weight: weight))
        let e = ModelEntity(mesh: mesh, materials: [flat(color, 1)])
        e.position = [-mesh.bounds.extents.x / 2 - mesh.bounds.min.x, -mesh.bounds.extents.y / 2 - mesh.bounds.min.y, 0]
        e.components.set(ModelSortGroupComponent(group: group, order: order))
        return e
    }

    /// Flat ring in the XY plane.
    static func annulus(_ radius: Float, width: Float, segments: Int = 72) -> MeshResource {
        var positions: [SIMD3<Float>] = [], indices: [UInt32] = []
        for i in 0...segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            positions += [[cos(a) * (radius - width / 2), sin(a) * (radius - width / 2), 0],
                          [cos(a) * (radius + width / 2), sin(a) * (radius + width / 2), 0]]
        }
        for i in 0..<UInt32(segments) {
            let p = i * 2
            indices += [p, p + 1, p + 2, p + 2, p + 1, p + 3]
        }
        var d = MeshDescriptor(name: "annulus")
        d.positions = MeshBuffer(positions)
        d.normals = MeshBuffer(Array(repeating: [0, 0, 1], count: positions.count))
        d.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [d])) ?? .generatePlane(width: radius, height: radius)
    }

    static func disc(_ radius: Float) -> MeshResource { annulus(radius / 2, width: radius) }

    private static var glowTexture: TextureResource?

    /// Soft radial glow sprite, tinted.
    static func glow(_ color: UIColor, _ opacity: Float) -> UnlitMaterial {
        if glowTexture == nil {
            let size = CGSize(width: 256, height: 256)
            let image = UIGraphicsImageRenderer(size: size).image { ctx in
                let colors = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0.35).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1])!
                ctx.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                                                 endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
            }
            glowTexture = image.cgImage.flatMap { try? TextureResource(image: $0, options: .init(semantic: .color)) }
        }
        var m = flat(color, opacity)
        if let glowTexture { m.color = .init(tint: color, texture: .init(glowTexture)) }
        return m
    }
}
