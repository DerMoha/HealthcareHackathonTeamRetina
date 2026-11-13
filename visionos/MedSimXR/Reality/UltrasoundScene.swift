import RealityKit
import UIKit

/// The ultrasound corner of the room: a machine trolley beside the couch (monitor, keyboard deck, probe
/// holder, gel bottle), tap targets on the patient's belly, and everything that happens when the learner
/// picks up the probe or the gel. Two ways to use them, as in the orthotics lab: pinch an item (select)
/// and then pinch a belly region, or drag the item onto the belly. No physics.
///
/// The scene only reports what the learner did (`onContact`, `onGel`); which image appears, what the
/// patient says and what counts is the engine's decision (AppModel -> ClinicalEngine.scan).
@MainActor
final class UltrasoundScene {
    static let probeName = "us_probe"
    static let gelName = "us_gel_bottle"
    /// Probe tip to skin point distance that counts as contact while dragging, metres.
    static let contactDistance: Float = 0.085
    /// Bottle to belly distance that counts as "put gel there", metres.
    static let gelDistance: Float = 0.16

    /// The whole corner. Disabled for cases without ultrasound.
    let root = Entity()
    /// Where the SwiftUI attachments (live monitor, buttons) are mounted.
    let monitorMount = Entity()
    let panelMount = Entity()
    /// Region id when the probe touches the belly (dragging or placed), nil in the air.
    var onContact: ((String?) -> Void)?
    /// The gel bottle was let go over the belly.
    var onGel: (() -> Void)?

    private let cart = Entity()
    private let regionRoot = Entity()
    private let gelRoot = Entity()
    private let highlight = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 0.06),
                                        materials: [UnlitMaterial(color: .systemTeal)])
    private var probe = Entity()
    private var bottle = Entity()
    private var homes: [String: Transform] = [:]
    private var avatar: PatientAvatar?
    private var regions: [UltrasoundRegion] = []
    private var zoneEntities: [Entity] = []
    private var dragging = false
    /// Region the probe is currently resting on (scene side; the model keeps the engine's truth).
    private var touching: String?
    private var built = false
    /// The notebook attachment, so it can move beside the couch instead of beside a seated patient.
    var notebook: Entity?

    // MARK: Install

    func install(on avatar: PatientAvatar) {
        self.avatar = avatar
        root.name = "ultrasound_corner"
        avatar.root.addChild(root)
        guard !built else { return }
        built = true
        buildCart()
        probe = Self.makeProbe()
        probe.name = Self.probeName
        bottle = Self.makeBottle()
        bottle.name = Self.gelName
        for (item, home) in [(probe, Transform(translation: [0.325, 0.865, 0.06])),
                             (bottle, Transform(translation: [-0.17, 0.875, 0.30]))] {
            item.components.set(CollisionComponent(shapes: [.generateBox(size: [0.16, 0.24, 0.12]).offsetBy(translation: [0, 0.09, 0])]))
            item.components.set(InputTargetComponent())
            item.components.set(HoverEffectComponent())
            cart.addChild(item)
            item.transform = home
            homes[item.name] = home
        }
        root.addChild(regionRoot)
        gelRoot.isEnabled = false
        root.addChild(gelRoot)
        root.isEnabled = false
    }

    /// Builds (or removes) what depends on the case: the belly regions and the gel patches. Call after
    /// the avatar's model has loaded, since the anchors come from its sidecar.
    func build(_ info: UltrasoundInfo?) {
        zoneEntities.forEach { $0.removeFromParent() }
        zoneEntities = []
        Array(gelRoot.children).forEach { $0.removeFromParent() }
        regions = info?.regions.filter { avatar?.anchors[$0.attachTo] != nil } ?? []
        root.isEnabled = info != nil
        reset()
        guard let avatar, info != nil else { return }
        let faint = Self.overlay(.white, 0.07)
        for region in regions {
            guard let anchor = avatar.anchors[region.attachTo] else { continue }
            let normal = avatar.anchorNormals[region.attachTo] ?? [0, 1, 0]
            let position = anchor.position(relativeTo: avatar.root)
            let zone = ModelEntity(mesh: .generateSphere(radius: region.radius), materials: [faint])
            zone.name = region.id
            zone.position = position + normal * 0.01
            zone.components.set(CollisionComponent(shapes: [.generateSphere(radius: region.radius)]))
            zone.components.set(InputTargetComponent())
            zone.components.set(HoverEffectComponent())
            regionRoot.addChild(zone)
            zoneEntities.append(zone)

            let patch = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 0.045),
                                    materials: [Self.overlay(UIColor(red: 0.62, green: 0.88, blue: 1, alpha: 1), 0.38, depth: true)])
            patch.position = position + normal * 0.004
            patch.orientation = simd_quatf(from: [0, 1, 0], to: normal)
            gelRoot.addChild(patch)
        }
        SmokeLog.mark("ultrasound scene built regions=\(regions.map(\.id))")
    }

    /// Where things go for the kind of patient: a couch needs less sideways offset so the notebook still fits beside it.
    /// Returns true when the placement changed (the caller then re-places the patient).
    @discardableResult
    func arrange(recumbent: Bool) -> Bool {
        notebook?.position = recumbent ? [0.45, 1.2, 0.5] : [0.42, 1.3, 0.5]
        notebook?.orientation = simd_quatf(angle: recumbent ? -0.45 : -0.35, axis: [0, 1, 0])
        notebook?.scale = recumbent ? [0.95, 0.95, 0.95] : [1, 1, 1]
        let extra: Float = 0, lateral: Float? = recumbent ? 0.3 : nil
        let changed = Placement.extraDistance != extra || Placement.lateralOverride != lateral
        Placement.extraDistance = extra
        Placement.lateralOverride = lateral
        return changed
    }

    /// Belly regions can be tapped only while a session runs.
    func setEnabled(_ on: Bool) { regionRoot.isEnabled = on }

    /// Back to the start: probe and bottle in their holders, no gel on the belly.
    func reset() {
        touching = nil; dragging = false
        select(nil)
        gelRoot.isEnabled = false
        for item in [probe, bottle] { sendHome(item, animated: false) }
    }

    // MARK: Hit testing

    /// The probe or bottle a gesture hit, if any.
    func item(_ entity: Entity) -> Entity? {
        entity === probe ? probe : entity === bottle ? bottle : nil
    }

    /// The belly region a gesture hit, if any.
    func region(_ entity: Entity) -> String? {
        zoneEntities.contains { $0 === entity } ? entity.name : nil
    }

    // MARK: Selecting, dragging, dropping

    /// Selected item lifts a little and gets a lit base.
    func select(_ name: String?) {
        highlight.removeFromParent()
        for item in [probe, bottle] where item.parent === cart {
            var t = homes[item.name] ?? item.transform
            if item.name == name { t.translation.y += 0.04 }
            item.move(to: t, relativeTo: cart, duration: 0.15)
        }
        if let name, let item = [probe, bottle].first(where: { $0.name == name }), item.parent === cart, let home = homes[name] {
            highlight.position = [home.translation.x, home.translation.y - 0.004, home.translation.z]
            cart.addChild(highlight)
        }
    }

    func drag(_ item: Entity, to position: SIMD3<Float>) {
        guard let avatar else { return }
        dragging = true
        if item.parent !== avatar.root { item.stopAllAnimations(); item.setParent(avatar.root, preservingWorldTransform: true) }
        if item === probe, let hit = nearestRegion(to: position, within: Self.contactDistance) {
            item.position = hit.position
            item.orientation = Self.orientation(normal: hit.normal, turns: 0)
            if touching != hit.id { touching = hit.id; onContact?(hit.id) }
        } else {
            item.position = position
            item.orientation = item === probe ? simd_quatf(angle: 0.35, axis: [1, 0, 0]) : simd_quatf(angle: 0, axis: [0, 1, 0])
            if item === probe, touching != nil { touching = nil; onContact?(nil) }
        }
    }

    /// End of a drag. The probe stays where it touches the belly, otherwise both items go home.
    func dropped(_ item: Entity) {
        dragging = false
        guard let avatar else { return }
        if item === bottle {
            let near = nearestRegion(to: item.position(relativeTo: avatar.root), within: Self.gelDistance) != nil
            sendHome(item, animated: true)
            if near { onGel?() }
        } else if touching == nil {
            sendHome(item, animated: true)
        }
    }

    // MARK: Following the model

    /// The engine-recorded state: the region the probe rests on (nil = in the holder or in the air) and a
    /// counter that turns the probe a quarter turn with every scan of the same region.
    func sync(region: String?, scans: Int) {
        guard !dragging else { return }
        touching = region
        guard let region, let hit = regionPose(region) else { sendHome(probe, animated: true); return }
        guard let avatar else { return }
        if probe.parent !== avatar.root { probe.stopAllAnimations(); probe.setParent(avatar.root, preservingWorldTransform: true) }
        probe.move(to: Transform(scale: [1, 1, 1], rotation: Self.orientation(normal: hit.normal, turns: scans), translation: hit.position),
                   relativeTo: avatar.root, duration: 0.25)
    }

    func showGel(_ on: Bool) { gelRoot.isEnabled = on }

    private func sendHome(_ item: Entity, animated: Bool) {
        guard let home = homes[item.name] else { return }
        if item.parent !== cart { item.stopAllAnimations(); item.setParent(cart, preservingWorldTransform: true) }
        if animated { item.move(to: home, relativeTo: cart, duration: 0.3) } else { item.transform = home }
    }

    private func regionPose(_ id: String) -> (position: SIMD3<Float>, normal: SIMD3<Float>)? {
        guard let avatar, let region = regions.first(where: { $0.id == id }), let anchor = avatar.anchors[region.attachTo] else { return nil }
        return (anchor.position(relativeTo: avatar.root), avatar.anchorNormals[region.attachTo] ?? [0, 1, 0])
    }

    private func nearestRegion(to p: SIMD3<Float>, within limit: Float) -> (id: String, position: SIMD3<Float>, normal: SIMD3<Float>)? {
        regions.compactMap { r -> (String, SIMD3<Float>, SIMD3<Float>, Float)? in
            guard let pose = regionPose(r.id) else { return nil }
            return (r.id, pose.position, pose.normal, simd_distance(p, pose.position))
        }
        .filter { $0.3 <= limit }
        .min { $0.3 < $1.3 }
        .map { ($0.0, $0.1, $0.2) }
    }

    /// Probe up axis (+Y, handle) along the skin normal, turned about it by quarter turns.
    private static func orientation(normal: SIMD3<Float>, turns: Int) -> simd_quatf {
        simd_quatf(from: [0, 1, 0], to: simd_normalize(normal)) * simd_quatf(angle: Float(turns % 4) * .pi / 2, axis: [0, 1, 0])
    }

    // MARK: Materials

    private static func solid(_ color: UIColor, roughness: Float = 0.5, metallic: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: metallic)
        m.faceCulling = .none
        return m
    }

    private static func overlay(_ color: UIColor, _ opacity: Float, depth: Bool = false) -> UnlitMaterial {
        var m = UnlitMaterial(color: color)
        if opacity < 1 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        if !depth { m.readsDepth = false; m.writesDepth = false }
        return m
    }

    // MARK: Meshes

    /// Convex polygon (counter-clockwise, XY plane) extruded along Z.
    private static func prism(_ poly: [SIMD2<Float>], depth: Float) -> MeshResource {
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, _ n: SIMD3<Float>) {
            let base = UInt32(positions.count)
            positions += [a, b, c, d]; normals += [n, n, n, n]
            indices += [base, base + 2, base + 1, base, base + 3, base + 2]
        }
        let h = depth / 2
        for i in poly.indices {
            let p = poly[i], q = poly[(i + 1) % poly.count]
            let e = q - p
            let n = simd_normalize(SIMD3<Float>(e.y, -e.x, 0))
            quad([p.x, p.y, h], [q.x, q.y, h], [q.x, q.y, -h], [p.x, p.y, -h], n)
        }
        for z in [h, -h] {
            let base = UInt32(positions.count)
            for p in poly { positions.append([p.x, p.y, z]); normals.append([0, 0, z > 0 ? 1 : -1]) }
            for i in 1..<(poly.count - 1) {
                let (a, b, c) = (base, base + UInt32(i), base + UInt32(i + 1))
                indices += z > 0 ? [a, b, c] : [a, c, b]
            }
        }
        var descriptor = MeshDescriptor(name: "prism")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor])) ?? .generateBox(size: [0.08, 0.02, depth])
    }

    /// Convex transducer: handle with a curved footprint. Origin = centre of the footprint, +Y along the handle.
    private static func makeProbe() -> Entity {
        let e = Entity()
        let radius: Float = 0.075, span: Float = 0.55
        var poly: [SIMD2<Float>] = (0...10).map { i in
            let a = -span + 2 * span * Float(i) / 10
            return [radius * sin(a), radius * (1 - cos(a))]
        }
        let top: Float = 0.024
        poly += [[poly.last!.x, top], [poly.first!.x, top]]
        let face = ModelEntity(mesh: prism(poly, depth: 0.024), materials: [solid(UIColor(white: 0.93, alpha: 1), roughness: 0.25)])
        let head = ModelEntity(mesh: prism(poly.map { [$0.x * 1.0, $0.y] }, depth: 0.026),
                               materials: [solid(UIColor(red: 0.10, green: 0.45, blue: 0.55, alpha: 1), roughness: 0.4)])
        head.position.y = 0.004
        head.scale = [0.97, 0.9, 1]
        let handle = ModelEntity(mesh: .generateBox(size: [0.05, 0.11, 0.028], cornerRadius: 0.013),
                                 materials: [solid(UIColor(red: 0.16, green: 0.17, blue: 0.21, alpha: 1), roughness: 0.45)])
        handle.position = [0, top + 0.05, 0]
        let band = ModelEntity(mesh: .generateBox(size: [0.052, 0.012, 0.03], cornerRadius: 0.005),
                               materials: [solid(.systemTeal, roughness: 0.4)])
        band.position = [0, top + 0.012, 0]
        let marker = ModelEntity(mesh: .generateSphere(radius: 0.005), materials: [solid(.systemYellow)])
        marker.position = [0.026, top + 0.02, 0.0]
        let cable = ModelEntity(mesh: .generateCylinder(height: 0.05, radius: 0.007),
                                materials: [solid(UIColor(white: 0.1, alpha: 1), roughness: 0.7)])
        cable.position = [0, top + 0.13, 0]
        for part in [face, head, handle, band, marker, cable] { e.addChild(part) }
        return e
    }

    private static func makeBottle() -> Entity {
        let e = Entity()
        let body = ModelEntity(mesh: .generateCylinder(height: 0.12, radius: 0.028),
                               materials: [solid(UIColor(red: 0.45, green: 0.75, blue: 0.95, alpha: 1), roughness: 0.3)])
        body.position.y = 0.06
        let label = ModelEntity(mesh: .generateCylinder(height: 0.05, radius: 0.0285), materials: [solid(.white, roughness: 0.6)])
        label.position.y = 0.06
        let neck = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 0.013), materials: [solid(.white, roughness: 0.5)])
        neck.position.y = 0.13
        let nozzle = ModelEntity(mesh: .generateCylinder(height: 0.028, radius: 0.0065), materials: [solid(.white, roughness: 0.5)])
        nozzle.position.y = 0.154
        for part in [body, label, neck, nozzle] { e.addChild(part) }
        return e
    }

    /// Trolley with a keyboard deck, a monitor on an arm, and a probe holder on the patient's side.
    private func buildCart() {
        cart.name = "ultrasound_cart"
        // Patient's right (-X), level with her hip, monitor turned towards the wearer.
        cart.position = [-0.9, 0, 0.4]
        cart.orientation = simd_quatf(angle: 0.45, axis: [0, 1, 0])
        root.addChild(cart)
        let white = Self.solid(UIColor(white: 0.94, alpha: 1), roughness: 0.35)
        let slate = Self.solid(UIColor(red: 0.20, green: 0.23, blue: 0.28, alpha: 1), roughness: 0.5)
        let dark = Self.solid(UIColor(white: 0.07, alpha: 1), roughness: 0.4)
        func part(_ mesh: MeshResource, _ material: PhysicallyBasedMaterial, _ p: SIMD3<Float>, to parent: Entity? = nil) {
            let m = ModelEntity(mesh: mesh, materials: [material])
            m.position = p
            (parent ?? cart).addChild(m)
        }
        part(.generateBox(size: [0.56, 0.06, 0.62], cornerRadius: 0.02), slate, [0, 0.03, 0])
        for x in [Float(-0.24), 0.24] { for z in [Float(-0.26), 0.26] { part(.generateSphere(radius: 0.035), dark, [x, 0.035, z]) } }
        part(.generateBox(size: [0.5, 0.78, 0.52], cornerRadius: 0.03), white, [0, 0.45, 0])
        part(.generateBox(size: [0.52, 0.03, 0.32], cornerRadius: 0.01), Self.solid(UIColor(white: 0.84, alpha: 1), roughness: 0.5), [0, 0.855, 0.34])
        for row in 0..<2 {
            for k in 0..<9 {
                part(.generateBox(size: [0.034, 0.008, 0.026], cornerRadius: 0.003), dark,
                     [-0.2 + 0.05 * Float(k), 0.874, 0.40 - 0.045 * Float(row)])
            }
        }
        part(.generateCylinder(height: 0.012, radius: 0.026), slate, [0.19, 0.876, 0.24])
        for k in 0..<5 { part(.generateCylinder(height: 0.014, radius: 0.011), slate, [-0.2 + 0.045 * Float(k), 0.877, 0.26]) }
        part(.generateCylinder(height: 0.4, radius: 0.026), slate, [0, 1.04, -0.2])
        part(.generateBox(size: [0.86, 0.62, 0.06], cornerRadius: 0.02), dark, [0, 1.32, -0.2])
        // probe holder on the patient's side of the trolley, with a back plate
        part(.generateBox(size: [0.085, 0.06, 0.1], cornerRadius: 0.01), slate, [0.325, 0.83, 0.06])
        part(.generateBox(size: [0.075, 0.2, 0.012], cornerRadius: 0.005), slate, [0.325, 0.93, 0.0])
        monitorMount.name = "ultrasound_monitor_mount"
        monitorMount.position = [0, 1.32, -0.168]
        cart.addChild(monitorMount)
        panelMount.name = "ultrasound_panel_mount"
        panelMount.position = [0, 0.55, 0.31]
        panelMount.scale = [1.5, 1.5, 1.5]
        cart.addChild(panelMount)
    }
}
