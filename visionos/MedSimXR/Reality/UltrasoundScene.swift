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
    private let couchExtras = Entity() // pitch only: paper sheet, roll, pillow
    private let cable = Entity() // pitch only: probe cable from the handle back to the cart
    private let glove = Entity() // pitch only: the learner's gloved right hand on the probe handle (child of the probe)
    private let arm = Entity() // pitch only: gloved forearm and sleeve running out of frame towards the wearer
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
        root.addChild(couchExtras)
        root.addChild(cable)
        if SmokeLog.pitch { buildHand() }
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
        if SmokeLog.pitch { PitchAntenatal.dressCouch(avatar.root, extras: couchExtras) }
        let faint = Self.overlay(.white, SmokeLog.pitch ? 0 : 0.07) // pitch shots: no visible hit spheres
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

            let patch = SmokeLog.pitch ? Self.smear() : ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 0.045),
                                    materials: [Self.overlay(UIColor(red: 0.62, green: 0.88, blue: 1, alpha: 1), 0.38, depth: true)])
            patch.name = region.id
            patch.isEnabled = !SmokeLog.pitch // pitch: only the smear under the probe shows (see sync)
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
        if SmokeLog.pitch { // pitch shots: clear of the centred patient, turned to the camera
            notebook?.position = recumbent ? [0.5, 1.25, 0.5] : [0.74, 1.32, 0.45]
            notebook?.orientation = simd_quatf(angle: recumbent ? -0.3 : -0.2, axis: [0, 1, 0])
        } else {
            notebook?.position = recumbent ? [0.45, 1.2, 0.5] : [0.42, 1.3, 0.5]
            notebook?.orientation = simd_quatf(angle: recumbent ? -0.45 : -0.35, axis: [0, 1, 0])
        }
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
        if SmokeLog.pitch {
            PitchAntenatal.mirror(region: region)
            gelRoot.children.forEach { $0.isEnabled = $0.name == region }
            cable.isEnabled = region != nil
            glove.isEnabled = region != nil
            arm.isEnabled = region != nil
        }
        guard let region, let hit = regionPose(region) else { sendHome(probe, animated: true); return }
        guard let avatar else { return }
        if probe.parent !== avatar.root { probe.stopAllAnimations(); probe.setParent(avatar.root, preservingWorldTransform: true) }
        let pose = Transform(scale: [1, 1, 1], rotation: Self.orientation(normal: hit.normal, turns: scans), translation: hit.position)
        probe.move(to: pose, relativeTo: avatar.root, duration: 0.25)
        if SmokeLog.pitch { layCable(from: pose); layArm(from: pose) }
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
        // pitch shots: the handle leans ~25 degrees towards the sonographer's side, like a held transducer
        let lean = simd_quatf(angle: SmokeLog.pitch ? 0.44 : 0, axis: [0, 0, 1])
        // pitch shots: one fixed turn that puts the gripping hand's forearm towards the wearer (no quarter turns)
        if SmokeLog.pitch { return simd_quatf(from: [0, 1, 0], to: simd_normalize(normal)) * lean * simd_quatf(angle: handYaw, axis: [0, 1, 0]) }
        return simd_quatf(from: [0, 1, 0], to: simd_normalize(normal)) * lean * simd_quatf(angle: Float(turns % 4) * .pi / 2, axis: [0, 1, 0])
    }

    // MARK: Pitch hand

    /// Probe turn about its handle so the hand's forearm (+X in probe space) points to the wearer's right side.
    private static let handYaw: Float = -0.8
    /// Where the glove model's cuff stub ends, and its direction (probe space; see scripts/pitch_glove_antenatal2.py).
    private static let cuffEnd: SIMD3<Float> = [0.088, 0.080, 0.030] + simd_normalize(SIMD3<Float>(1, 0, 0.45)) * 0.06
    private static let cuffDir = simd_normalize(SIMD3<Float>(1, 0, 0.45))

    /// Light-blue nitrile: soft sheen, slightly translucent-looking pale blue.
    private static var nitrile: PhysicallyBasedMaterial {
        var m = solid(UIColor(red: 0.53, green: 0.72, blue: 0.96, alpha: 1), roughness: 0.42)
        m.clearcoat = .init(floatLiteral: 0.35); m.clearcoatRoughness = .init(floatLiteral: 0.25)
        return m
    }

    private func buildHand() {
        glove.name = "us_glove"
        if let model = PitchKit.model("antenatal2_glove") {
            let b = model.visualBounds(relativeTo: nil)
            if b.center.z < -0.03 { model.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0]) * model.orientation } // undo the Z-up import turn
            SmokeLog.mark("pitch glove bounds center=\(b.center) extents=\(b.extents)")
            func paint(_ e: Entity) {
                if var m = e.components[ModelComponent.self] { m.materials = m.materials.map { _ in Self.nitrile }; e.components.set(m) }
                e.children.forEach(paint)
            }
            paint(model)
            glove.addChild(model)
        }
        glove.isEnabled = false
        probe.addChild(glove)
        // forearm in the glove's cuff, then a scrubs sleeve over it, both along the cuff direction
        let forearm = ModelEntity(mesh: Self.tube(length: 0.11, r0: 0.0255, r1: 0.029), materials: [Self.nitrile])
        let sleeve = ModelEntity(mesh: Self.tube(length: 1.1, r0: 0.035, r1: 0.046, cap: true),
                                 materials: [Self.solid(UIColor(red: 0.16, green: 0.24, blue: 0.36, alpha: 1), roughness: 0.9)])
        sleeve.position.y = 0.085
        forearm.addChild(sleeve)
        arm.addChild(forearm)
        arm.isEnabled = false
        root.addChild(arm)
    }

    /// Pitch shots: the forearm continues the glove's cuff stub, in the probe's resting pose.
    private func layArm(from pose: Transform) {
        guard let avatar else { return }
        let start = pose.matrix * SIMD4<Float>(Self.cuffEnd - Self.cuffDir * 0.01, 1)
        let dir = pose.rotation.act(Self.cuffDir)
        arm.position = root.convert(position: [start.x, start.y, start.z], from: avatar.root)
        arm.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(root.convert(direction: dir, from: avatar.root)))
    }

    /// Open truncated cone along +Y from radius r0 (y = 0) to r1 (y = length), smooth normals; `cap` closes the start with a disc.
    private static func tube(length: Float, r0: Float, r1: Float, cap: Bool = false) -> MeshResource {
        let n = 40
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        let slope = (r0 - r1) / length
        for i in 0...n {
            let a = Float(i) / Float(n) * 2 * .pi
            let c = cos(a), s = sin(a)
            positions += [[r0 * c, 0, r0 * s], [r1 * c, length, r1 * s]]
            let nrm = simd_normalize(SIMD3<Float>(c, slope, s))
            normals += [nrm, nrm]
        }
        for i in 0..<n {
            let b = UInt32(2 * i)
            indices += [b, b + 1, b + 2, b + 1, b + 3, b + 2]
        }
        if cap {
            let centre = UInt32(positions.count)
            positions.append([0, 0, 0]); normals.append([0, -1, 0])
            for i in 0...n {
                let a = Float(i) / Float(n) * 2 * .pi
                positions.append([r0 * cos(a), 0, r0 * sin(a)]); normals.append([0, -1, 0])
            }
            for i in 0..<UInt32(n) { indices += [centre, centre + 1 + i, centre + 2 + i] }
        }
        var d = MeshDescriptor(name: "tube")
        d.positions = MeshBuffer(positions); d.normals = MeshBuffer(normals); d.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [d])) ?? .generateCylinder(height: length, radius: r0)
    }

    /// Pitch shots: a sagging cable from the probe handle to the cart's probe port (segmented tube).
    private func layCable(from pose: Transform) {
        guard let avatar else { return }
        let toRoot = { (p: SIMD3<Float>) in self.root.convert(position: p, from: avatar.root) }
        let m = pose.matrix
        let tip4 = m * SIMD4<Float>(0, 0.18, 0, 1), up4 = m * SIMD4<Float>(0, 1, 0, 0)
        let p0 = toRoot([tip4.x, tip4.y, tip4.z]), up = simd_normalize(SIMD3<Float>(up4.x, up4.y, up4.z))
        let p3 = cart.convert(position: [0.3, 0.72, 0.2], to: root)
        let p1 = p0 + up * 0.12, p2 = p3 + [0, -0.35, 0.1]
        let n = 24
        if cable.children.isEmpty {
            for _ in 0..<n {
                cable.addChild(ModelEntity(mesh: .generateCylinder(height: 1, radius: 0.0045),
                                           materials: [Self.solid(UIColor(white: 0.16, alpha: 1), roughness: 0.55)]))
            }
        }
        func bez(_ t: Float) -> SIMD3<Float> {
            let u = 1 - t
            return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
        }
        for (i, seg) in cable.children.enumerated() {
            let a = bez(Float(i) / Float(n)), b = bez(Float(i + 1) / Float(n))
            seg.position = (a + b) / 2
            seg.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(b - a))
            seg.scale = [1, simd_distance(a, b) + 0.004, 1]
        }
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

    /// Pitch shots: clear, glossy gel instead of a flat tinted disc.
    private static var gel: PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: 0.8, green: 0.92, blue: 1, alpha: 1))
        m.roughness = .init(floatLiteral: 0.05); m.clearcoat = .init(floatLiteral: 1); m.clearcoatRoughness = .init(floatLiteral: 0.02)
        m.blending = .transparent(opacity: 0.32)
        return m
    }

    /// Pitch shots: one irregular, glossy smear of gel (overlapping flattened blobs) under the probe.
    private static func smear() -> Entity {
        let e = Entity()
        let blobs: [(Float, Float, Float)] = [(0, 0, 0.05), (0.032, 0.022, 0.036), (-0.036, -0.012, 0.034), (0.008, -0.036, 0.028), (-0.02, 0.03, 0.026)]
        for (x, z, r) in blobs {
            let blob = ModelEntity(mesh: .generateSphere(radius: r), materials: [gel])
            blob.position = [x, 0, z]
            blob.scale = [1, 0.1, 0.82]
            e.addChild(blob)
        }
        return e
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
        let pitch = SmokeLog.pitch // pitch shots: light-grey curvilinear transducer with a grey lens
        let face = ModelEntity(mesh: prism(poly, depth: 0.024), materials: [solid(UIColor(white: pitch ? 0.42 : 0.93, alpha: 1), roughness: 0.25)])
        let head = ModelEntity(mesh: prism(poly.map { [$0.x * 1.0, $0.y] }, depth: 0.026),
                               materials: [pitch ? PitchAntenatal.gloss(UIColor(white: 0.86, alpha: 1)) : solid(UIColor(red: 0.10, green: 0.45, blue: 0.55, alpha: 1), roughness: 0.4)])
        head.position.y = 0.004
        head.scale = [0.97, 0.9, 1]
        let handle = ModelEntity(mesh: .generateBox(size: [0.05, 0.11, 0.028], cornerRadius: 0.013),
                                 materials: [pitch ? PitchAntenatal.gloss(UIColor(white: 0.9, alpha: 1)) : solid(UIColor(red: 0.16, green: 0.17, blue: 0.21, alpha: 1), roughness: 0.45)])
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
        let pitch = SmokeLog.pitch // pitch shots: glossy moulded plastics
        let white = pitch ? PitchAntenatal.gloss(UIColor(white: 0.95, alpha: 1)) : Self.solid(UIColor(white: 0.94, alpha: 1), roughness: 0.35)
        let slate = pitch ? PitchAntenatal.gloss(UIColor(red: 0.36, green: 0.39, blue: 0.44, alpha: 1), roughness: 0.45)
                          : Self.solid(UIColor(red: 0.20, green: 0.23, blue: 0.28, alpha: 1), roughness: 0.5)
        let dark = pitch ? PitchAntenatal.gloss(UIColor(white: 0.06, alpha: 1), roughness: 0.3) : Self.solid(UIColor(white: 0.07, alpha: 1), roughness: 0.4)
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
        if SmokeLog.pitch { PitchAntenatal.dressCart(cart) }
        panelMount.name = "ultrasound_panel_mount"
        panelMount.position = [0, 0.55, 0.31]
        panelMount.scale = [1.5, 1.5, 1.5]
        cart.addChild(panelMount)
    }
}
