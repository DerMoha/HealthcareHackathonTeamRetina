import RealityKit
import UIKit

/// Command for the lab from outside the scene (pinch on the forearm, panel and debug
/// buttons, scripted demo): puts an item at a point given in forearm coordinates and drops
/// it there, through the same snap logic a drag ends in.
struct LabCommand: Equatable {
    let id = UUID()
    var item: String
    /// Centimetres from the wrist joint towards the elbow, and away from the forearm axis.
    var axialCm: Double
    var radialCm: Double
    /// How it was triggered; only for the log.
    var via = "command"
}

/// Equipment tray with a measuring tape and wrist supports, and everything that happens when
/// one of them is put on the patient's right forearm. Two ways to do that: drag the item and
/// let go near the arm, or pinch the item (select) and then pinch the forearm. No physics.
/// The lab only reports what the learner did; whether it was right is the engine's decision.
@MainActor
final class OrthoticsLab {
    static let tapeName = "tool_tape"
    static let orthosisPrefix = "orthosis_"
    static let forearmTargetName = "forearm_target"
    /// Drop tolerance around the forearm axis, metres.
    static let snapRadius: Float = 0.09
    static let sleeveLength: Float = 0.16

    let tray = Entity()
    let measurement = SpatialMeasurementTool()
    /// (measurement id, value measured on the avatar or nil when the case predefines it)
    var onMeasure: ((String, Double?) -> Void)?
    /// (size id, centre offset in cm from the wrist towards the elbow); nil offset = taken off
    var onPlace: ((String, Double?) -> Void)?

    private var avatar: PatientAvatar?
    private var orthotics = Orthotics()
    private var items: [String: Entity] = [:]
    private var homes: [String: Transform] = [:]
    private let elbow = Entity()
    private let teaching = Entity()
    private let forearmTarget = Entity()
    private let selectionDisc = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 0.07),
                                            materials: [UnlitMaterial(color: .systemTeal)])
    private var replayMarkers: [Entity] = []
    private var fitted: String?

    private var frame: Entity? { avatar?.forearmFrame }

    func install(on avatar: PatientAvatar) {
        self.avatar = avatar
        tray.name = "orthotics_tray"
        tray.position = [-0.58, 0.95, 0.55] // beside the patient's right arm, wearer's left
        tray.orientation = simd_quatf(angle: 0.35, axis: [0, 1, 0])
        avatar.root.addChild(tray)
        elbow.position = [0, -avatar.forearmLength, 0]
        avatar.forearmFrame.addChild(elbow)
        avatar.forearmFrame.addChild(teaching)

        // Pinch target covering the whole forearm; only live while a tray item is selected,
        // so it never takes pinches meant for the examination zones.
        let length = avatar.forearmLength + 0.1
        forearmTarget.name = Self.forearmTargetName
        forearmTarget.position = [0, -avatar.forearmLength / 2 + 0.02, 0]
        forearmTarget.components.set(CollisionComponent(shapes: [.generateBox(size: [0.13, length, 0.13])]))
        forearmTarget.components.set(InputTargetComponent())
        forearmTarget.components.set(HoverEffectComponent())
        let glow = ModelEntity(mesh: .generateCylinder(height: length, radius: 0.058),
                               materials: [Self.overlay(.systemTeal, 0.16, depth: true)])
        forearmTarget.addChild(glow)
        forearmTarget.isEnabled = false
        avatar.forearmFrame.addChild(forearmTarget)
    }

    // MARK: Meshes

    private static func fabric(_ color: UIColor, roughness: Float = 0.9, metallic: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: metallic)
        m.faceCulling = .none
        return m
    }

    /// Flat colour that can be drawn over the patient (`depth: false`) for the teaching overlays.
    private static func overlay(_ color: UIColor, _ opacity: Float, depth: Bool = false) -> UnlitMaterial {
        var m = UnlitMaterial(color: color)
        if opacity < 1 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        if !depth { m.readsDepth = false; m.writesDepth = false }
        return m
    }

    /// Open tube along Y, lofted through elliptical rings: half-widths `a` (X) and `b` (Z)
    /// scaled per ring. `arc` leaves a gap, as on a brace that opens along the back of the hand.
    private static func tube(_ profile: [(y: Float, s: Float)], a: Float, b: Float,
                             arc: ClosedRange<Float> = 0...(2 * .pi), segments: Int = 32) -> MeshResource {
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        for ring in profile {
            for i in 0...segments {
                let t = arc.lowerBound + (arc.upperBound - arc.lowerBound) * Float(i) / Float(segments)
                positions.append([a * ring.s * cos(t), ring.y, b * ring.s * sin(t)])
                normals.append(simd_normalize([cos(t) / a, 0, sin(t) / b]))
            }
        }
        let n = UInt32(segments + 1)
        for r in 0..<UInt32(profile.count - 1) {
            for i in 0..<UInt32(segments) {
                let p = r * n + i
                indices += [p, p + n, p + 1, p + 1, p + n, p + n + 1]
            }
        }
        var descriptor = MeshDescriptor(name: "tube")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor])) ?? .generateCylinder(height: sleeveLength, radius: a)
    }

    /// Outline of a wrist brace along Y (+Y = hand end): wide on the forearm, waisted at the
    /// wrist, flaring over the palm.
    private static let braceProfile: [(y: Float, s: Float)] = [
        (-0.085, 1.20), (-0.05, 1.12), (-0.015, 1.02), (0.01, 1.0), (0.035, 1.06), (0.06, 1.14), (0.075, 1.12),
    ]

    private static func scale(at y: Float) -> Float {
        let p = braceProfile
        guard let i = p.firstIndex(where: { $0.y >= y }), i > 0 else { return y < p[0].y ? p[0].s : p[p.count - 1].s }
        let t = (y - p[i - 1].y) / (p[i].y - p[i - 1].y)
        return p[i - 1].s + (p[i].s - p[i - 1].s) * t
    }

    /// Simplified wrist brace: neoprene body open along the back, three straps with buckles,
    /// a palmar stay, and a thumb opening on +Z (the thumb side) near the hand end.
    /// `ghost` = one flat colour, for the reference position in teaching mode.
    private static func brace(radius r: Float, ghost: UnlitMaterial? = nil) -> Entity {
        let e = Entity()
        let a = r * 0.9, b = r * 1.12
        func part(_ mesh: MeshResource, _ material: any Material, at p: SIMD3<Float> = .zero) -> ModelEntity {
            let m = ModelEntity(mesh: mesh, materials: [ghost ?? material])
            m.position = p
            e.addChild(m)
            return m
        }
        let gap: Float = 0.42
        _ = part(tube(braceProfile, a: a, b: b, arc: gap...(2 * .pi - gap)),
                 fabric(UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1)))
        guard ghost == nil else { return e }
        let strap = fabric(UIColor(white: 0.88, alpha: 1), roughness: 0.7)
        let metal = fabric(UIColor(white: 0.6, alpha: 1), roughness: 0.3, metallic: 1)
        for y in [Float(-0.062), -0.022, 0.05] {
            let s = scale(at: y)
            _ = part(tube([(y - 0.011, s), (y + 0.011, s)], a: a + 0.0025, b: b + 0.0025), strap)
            _ = part(.generateBox(size: [0.004, 0.016, 0.02], cornerRadius: 0.002), metal, at: [(a + 0.004) * s, y, 0])
        }
        // palmar stay: the stiff strip that holds the wrist
        _ = part(.generateBox(size: [0.004, 0.12, 0.024], cornerRadius: 0.002), fabric(UIColor(white: 0.32, alpha: 1), roughness: 0.5),
                 at: [-(a + 0.002), -0.005, 0])
        // thumb opening
        let hole = part(tube([(-0.006, 1), (0.006, 1)], a: 0.016, b: 0.016), fabric(.systemTeal, roughness: 0.8),
                        at: [0, 0.04, b * scale(at: 0.04) + 0.002])
        hole.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        let disc = part(.generateCylinder(height: 0.003, radius: 0.015), fabric(UIColor(white: 0.02, alpha: 1)),
                        at: [0, 0.04, b * scale(at: 0.04) - 0.001])
        disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        return e
    }

    /// Retractable measuring tape: case, a length of tape pulled out, end hook.
    private static func tapeMeasure() -> Entity {
        let e = Entity()
        let body = ModelEntity(mesh: .generateBox(size: [0.066, 0.03, 0.066], cornerRadius: 0.014),
                               materials: [fabric(.systemYellow, roughness: 0.4)])
        let hub = ModelEntity(mesh: .generateCylinder(height: 0.032, radius: 0.016),
                              materials: [fabric(UIColor(white: 0.15, alpha: 1), roughness: 0.4)])
        e.addChild(body); e.addChild(hub)
        let strip = SpatialMeasurementTool.strip(length: 0.09, width: 0.016)
        strip.position = [0.03, -0.008, 0]
        strip.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1]) // lying flat, pulled out to +X
        e.addChild(strip)
        let hook = ModelEntity(mesh: .generateBox(size: [0.003, 0.012, 0.018]), materials: [fabric(UIColor(white: 0.7, alpha: 1), roughness: 0.3, metallic: 1)])
        hook.position = [0.121, -0.008, 0]
        e.addChild(hook)
        return e
    }

    private static func radius(_ sizeIndex: Int) -> Float { 0.031 + 0.007 * Float(sizeIndex) }

    private static func text(_ string: String, size: CGFloat, material: any Material) -> ModelEntity {
        let mesh = MeshResource.generateText(string, extrusionDepth: 0.001, font: .systemFont(ofSize: size, weight: .bold))
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.position = [-mesh.bounds.extents.x / 2 - mesh.bounds.min.x, -mesh.bounds.extents.y / 2 - mesh.bounds.min.y, 0]
        return e
    }

    // MARK: Tray

    func build(_ orthotics: Orthotics) {
        self.orthotics = orthotics
        Array(tray.children).forEach { $0.removeFromParent() }
        items.values.forEach { $0.removeFromParent() }
        items = [:]; homes = [:]; fitted = nil
        measurement.clear()
        setTeaching(anatomy: false, reference: nil)
        showReplay([], events: [], current: nil)
        select(nil)
        guard !orthotics.sizes.isEmpty else { return }

        let count = orthotics.sizes.count + 1
        let pitch: Float = 0.16
        let board = ModelEntity(mesh: .generateBox(size: [pitch * Float(count) + 0.04, 0.012, 0.2], cornerRadius: 0.006),
                                materials: [Self.fabric(UIColor(white: 0.2, alpha: 1), roughness: 0.6)])
        tray.addChild(board)
        func slot(_ i: Int) -> Float { (Float(i) - Float(count - 1) / 2) * pitch }

        add(Self.tapeMeasure(), name: Self.tapeName, label: "Tape", at: [slot(0) - 0.02, 0.022, 0])
        for (i, size) in orthotics.sizes.enumerated() {
            let range = size.wristCm.map { String(format: "%g", $0) }.joined(separator: "–")
            add(Self.brace(radius: Self.radius(i)), name: Self.orthosisPrefix + size.id, label: "\(size.label.prefix(1)) · \(range) cm",
                at: [slot(i + 1), 0.006 + 0.085, 0])
        }
    }

    private func add(_ item: Entity, name: String, label: String, at position: SIMD3<Float>) {
        item.name = name
        item.position = position
        // generous pinch target: easier to hit than the mesh itself
        item.components.set(CollisionComponent(shapes: [.generateBox(size: [0.14, 0.19, 0.14])]))
        item.components.set(InputTargetComponent())
        item.components.set(HoverEffectComponent())
        tray.addChild(item)
        items[name] = item
        homes[name] = item.transform

        let caption = Entity()
        caption.addChild(Self.text(label, size: 0.012, material: UnlitMaterial(color: .white)))
        caption.position = [position.x, 0.02, 0.102] // on the tray's front edge
        tray.addChild(caption)
    }

    // MARK: Selecting, dragging, dropping

    /// The tray item a gesture hit, if any.
    func item(_ entity: Entity) -> Entity? { items[entity.name] === entity ? entity : nil }

    /// Selected state: the item lifts and gets a lit base (on the tray), and the forearm
    /// becomes a pinch target with a soft glow over its whole length.
    func select(_ name: String?) {
        for (key, item) in items where item.parent === tray {
            var t = homes[key] ?? item.transform
            if key == name { t.translation.y += 0.03 }
            item.move(to: t, relativeTo: tray, duration: 0.15)
        }
        selectionDisc.removeFromParent()
        if let name, let item = items[name], item.parent === tray, let home = homes[name] {
            selectionDisc.position = [home.translation.x, 0.009, home.translation.z]
            tray.addChild(selectionDisc)
        }
        forearmTarget.isEnabled = name != nil
    }

    func drag(_ item: Entity, to position: SIMD3<Float>) {
        guard let root = avatar?.root else { return }
        if item.parent !== root { item.stopAllAnimations(); item.setParent(root, preservingWorldTransform: true) }
        item.position = position
    }

    /// Second pinch of select-then-pinch: `point` is where the forearm was pinched, in world space.
    func place(_ name: String, atWorld point: SIMD3<Float>) {
        guard let frame else { return }
        let p = frame.convert(position: point, from: nil)
        run(LabCommand(item: name, axialCm: Double(-p.y * 100), radialCm: 0, via: "pinch"))
    }

    func run(_ command: LabCommand) {
        guard let item = items[command.item] else { return }
        // Resolved from the given point itself: a tray lift animation may still own the item's transform.
        resolve(item, axial: Float(command.axialCm) / 100, radial: Float(command.radialCm) / 100, via: command.via)
    }

    /// End of a drag: where the item was let go, in forearm coordinates.
    func dropped(_ item: Entity) {
        guard let frame else { return }
        let p = item.position(relativeTo: frame)
        resolve(item, axial: -p.y, radial: simd_length(SIMD2(p.x, p.z)), via: "drag")
    }

    /// Snap to the forearm if close enough, else back to the tray.
    private func resolve(_ item: Entity, axial: Float, radial: Float, via: String) {
        guard let avatar else { return }
        let snapped = radial <= Self.snapRadius && axial >= -0.06 && axial <= avatar.forearmLength + 0.04
        SmokeLog.mark("lab drop \(item.name) via=\(via) axial=\(String(format: "%.1f", axial * 100))cm "
            + "radial=\(String(format: "%.1f", radial * 100))cm snapped=\(snapped)")

        if item.name == Self.tapeName {
            if snapped { measure(nearWrist: axial < 0.07) }
            sendHome(item)
        } else {
            let size = String(item.name.dropFirst(Self.orthosisPrefix.count))
            if snapped {
                onPlace?(size, (Double(axial) * 1000).rounded() / 10)
            } else {
                if fitted == size { onPlace?(size, nil) }
                sendHome(item)
            }
        }
    }

    private func measure(nearWrist: Bool) {
        guard let avatar, let frame else { return }
        let kind = nearWrist ? "circumference" : "length"
        guard let spec = orthotics.measurements.first(where: { $0.kind == kind }) else { return }
        if nearWrist {
            measurement.showGirth(around: frame, at: [0, -0.012, 0], radius: 0.036, label: [0, -0.012, 0.06])
            onMeasure?(spec.id, nil)
        } else {
            measurement.showLength(from: elbow, to: frame, in: frame, lift: [0, 0, 0.045], label: [0, -avatar.forearmLength / 2, 0.07])
            onMeasure?(spec.id, SpatialMeasurementTool.distanceCm(elbow, avatar.forearmFrame))
        }
    }

    private func sendHome(_ item: Entity) {
        guard let home = homes[item.name] else { return }
        item.setParent(tray, preservingWorldTransform: true)
        item.move(to: home, relativeTo: tray, duration: 0.3)
    }

    // MARK: Rendering the engine-recorded fit

    /// Shows the support exactly as recorded: size, position along the forearm, rotation, tension.
    func sync(_ fit: OrthosisFit?) {
        guard let frame else { return }
        fitted = fit?.size
        for (name, item) in items where name.hasPrefix(Self.orthosisPrefix) {
            if let fit, name == Self.orthosisPrefix + fit.size {
                item.setParent(frame, preservingWorldTransform: true)
                let level = orthotics.tightness.firstIndex(of: fit.tightness) ?? 1
                let squeeze = 1.08 - 0.07 * Float(level) // looser straps: visibly wider
                item.move(to: Transform(scale: [squeeze, 1, squeeze],
                                        rotation: simd_quatf(angle: fit.orientation == "thumb_radial" ? 0 : .pi, axis: [0, 1, 0]),
                                        translation: [0, -Float(fit.offsetCm) / 100, 0]),
                          relativeTo: frame, duration: 0.2)
            } else if item.parent !== tray {
                sendHome(item)
            }
        }
    }

    // MARK: Teaching overlay (only after the plan was submitted)

    private static let sortGroup = ModelSortGroup(depthPass: nil)

    private func overlayPart(_ mesh: MeshResource, _ material: UnlitMaterial, _ p: SIMD3<Float>, order: Int32,
                             scale: SIMD3<Float> = [1, 1, 1]) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.position = p; e.scale = scale
        e.components.set(ModelSortGroupComponent(group: Self.sortGroup, order: order))
        teaching.addChild(e)
        return e
    }

    /// Label set off to the side of the anatomy, joined to it by a thin leader line.
    private func callout(_ string: String, from bone: SIMD3<Float>, to p: SIMD3<Float>, color: UIColor) {
        let d = p - bone, length = simd_length(d)
        let leader = overlayPart(.generateCylinder(height: length * 0.82, radius: 0.0008), Self.overlay(color, 1), bone + d * 0.45, order: 3)
        leader.orientation = simd_quatf(from: [0, 1, 0], to: d / length)
        let holder = Entity()
        holder.position = p
        holder.components.set(BillboardComponent())
        let label = Self.text(string, size: 0.011, material: Self.overlay(color, 1))
        label.components.set(ModelSortGroupComponent(group: Self.sortGroup, order: 4))
        holder.addChild(label)
        teaching.addChild(holder)
    }

    /// Schematic wrist skeleton drawn over the injured forearm only: the forearm is washed
    /// out with a pale shell (the rest of the patient stays as it is), bones are drawn on top,
    /// the scaphoid is highlighted. With a `reference`, the intended support position is
    /// shown as a green outline beside the learner's own, which turns translucent.
    func setTeaching(anatomy: Bool, reference: FittingReference?) {
        Array(teaching.children).forEach { $0.removeFromParent() }
        let active = anatomy || reference != nil
        if active { measurement.clear() }
        for (name, item) in items where name.hasPrefix(Self.orthosisPrefix) {
            if active, item.parent === frame { item.components.set(OpacityComponent(opacity: 0.3)) }
            else { item.components.remove(OpacityComponent.self) }
        }
        guard let avatar else { return }
        let length = avatar.forearmLength

        if anatomy {
            _ = overlayPart(Self.tube([(-length * 0.96, 1.25), (-0.04, 0.9), (0.0, 0.85), (0.05, 1.15), (0.1, 1.1)], a: 0.03, b: 0.036),
                            Self.overlay(UIColor(red: 0.75, green: 0.88, blue: 1, alpha: 1), 0.55), .zero, order: 0)
            let bone = Self.overlay(UIColor(white: 0.97, alpha: 1), 1), highlight = Self.overlay(.systemOrange, 1)
            let shaft = length * 0.92
            _ = overlayPart(.generateCylinder(height: shaft, radius: 0.008), bone, [0, -shaft / 2 - 0.004, 0.011], order: 1)   // radius
            _ = overlayPart(.generateCylinder(height: shaft, radius: 0.006), bone, [0, -shaft / 2 - 0.004, -0.012], order: 1)  // ulna
            for z in [Float(0.002), -0.009, -0.017] { _ = overlayPart(.generateSphere(radius: 0.0058), bone, [0, 0.010, z], order: 1) }
            for z in [Float(0.016), 0.006, -0.004, -0.014] { _ = overlayPart(.generateSphere(radius: 0.0058), bone, [0, 0.024, z], order: 1) }
            for z in [Float(0.022), 0.011, 0, -0.011, -0.021] {
                _ = overlayPart(.generateCylinder(height: 0.04, radius: 0.0035), bone, [0, 0.054, z], order: 1)
            }
            _ = overlayPart(.generateSphere(radius: 0.0088), highlight, [0, 0.010, 0.014], order: 2, scale: [1, 1.5, 1])       // scaphoid
            callout("Scaphoid", from: [0, 0.010, 0.014], to: [0, 0.03, 0.105], color: .systemOrange)
            callout("Radius", from: [0, -length * 0.45, 0.011], to: [0, -length * 0.45, 0.095], color: .white)
            callout("Ulna", from: [0, -length * 0.45, -0.012], to: [0, -length * 0.45, -0.095], color: .white)
        }
        if let reference {
            let index = orthotics.sizes.firstIndex { $0.id == reference.size } ?? 0
            let centre = Float(reference.offsetCm.reduce(0, +) / Double(max(reference.offsetCm.count, 1))) / 100
            let ghost = Self.brace(radius: Self.radius(index) + 0.004, ghost: Self.overlay(.systemGreen, 0.45))
            ghost.position = [0, -centre, 0]
            ghost.orientation = simd_quatf(angle: reference.orientation == "thumb_radial" ? 0 : .pi, axis: [0, 1, 0])
            ghost.children.forEach { $0.components.set(ModelSortGroupComponent(group: Self.sortGroup, order: 0)) }
            teaching.addChild(ghost)
            callout("Intended position", from: [0, -centre, 0.04], to: [0, -centre - 0.03, 0.12], color: .systemGreen)
        }
        SmokeLog.mark("teaching anatomy=\(anatomy) reference=\(reference?.size ?? "none") parts=\(teaching.children.count)")
    }

    // MARK: Spatial Clinical Replay

    /// Marks the examination zones on the patient: examined (green, or red when it hurt),
    /// missed (amber), and the step being reviewed (larger, with its recorded contact point).
    /// Markers sit on the zone entities, so they follow the arm. Only discrete zone events
    /// exist; nothing here draws a hand path.
    func showReplay(_ zones: [ReplayZone], events: [ExamEvent], current: ExamEvent?) {
        replayMarkers.forEach { $0.removeFromParent() }
        replayMarkers = []
        guard let avatar else { return }
        for zone in zones {
            guard let entity = avatar.zoneEntities.first(where: { $0.name == zone.zoneId }) else { continue }
            let isCurrent = current?.zoneId == zone.zoneId
            let color: UIColor = !zone.examined ? .systemOrange : (zone.painLevel ?? 0) >= 5 ? .systemRed : .systemGreen
            let radius = (entity.visualBounds(relativeTo: entity).extents.x / 2) * (isCurrent ? 1.25 : 0.9)
            let marker = ModelEntity(mesh: .generateSphere(radius: max(radius, 0.02)),
                                     materials: [Self.overlay(color, isCurrent ? 0.75 : zone.examined ? 0.4 : 0.28)])
            marker.components.set(ModelSortGroupComponent(group: Self.sortGroup, order: 5))
            entity.addChild(marker)
            replayMarkers.append(marker)

            let order = events.firstIndex { $0.zoneId == zone.zoneId }.map { "\($0 + 1)" } ?? "missed"
            let holder = Entity()
            holder.position = [0, max(radius, 0.02) + 0.022, 0]
            holder.components.set(BillboardComponent())
            let label = Self.text(order, size: zone.examined ? 0.02 : 0.011, material: Self.overlay(color, 1))
            label.components.set(ModelSortGroupComponent(group: Self.sortGroup, order: 6))
            holder.addChild(label)
            entity.addChild(holder)
            replayMarkers.append(holder)

            if isCurrent, let contact = current?.contact {
                let dot = ModelEntity(mesh: .generateSphere(radius: 0.006), materials: [Self.overlay(.white, 1)])
                dot.position = contact
                dot.components.set(ModelSortGroupComponent(group: Self.sortGroup, order: 6))
                entity.addChild(dot)
                replayMarkers.append(dot)
            }
        }
    }
}
