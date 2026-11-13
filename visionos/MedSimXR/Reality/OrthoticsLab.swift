import RealityKit
import UIKit

/// Command for the lab from outside the scene (scripted demo, panel fallback buttons):
/// puts an item at a point given in forearm coordinates and drops it there, through the
/// same snap logic a drag uses.
struct LabCommand: Equatable {
    let id = UUID()
    var item: String
    /// Centimetres from the wrist joint towards the elbow, and away from the forearm axis.
    var axialCm: Double
    var radialCm: Double
}

/// Tray with a measuring tape and wrist supports, and everything that happens when one of
/// them is dropped on the patient's right forearm. No physics: an item snaps to the forearm
/// frame when dropped within tolerance, otherwise it goes back to the tray. The lab only
/// reports what the learner did; whether it was right is decided by the clinical engine.
@MainActor
final class OrthoticsLab {
    static let tapeName = "tool_tape"
    static let orthosisPrefix = "orthosis_"
    /// Drop tolerance around the forearm axis, metres.
    static let snapRadius: Float = 0.09
    static let sleeveLength: Float = 0.15

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
    }

    // MARK: Tray

    func build(_ orthotics: Orthotics) {
        self.orthotics = orthotics
        Array(tray.children).forEach { $0.removeFromParent() }
        items.values.forEach { $0.removeFromParent() }
        items = [:]; homes = [:]; fitted = nil
        measurement.clear()
        setTeaching(nil, learner: nil)
        guard !orthotics.sizes.isEmpty else { return }

        let board = ModelEntity(mesh: .generateBox(size: [0.74, 0.012, 0.24], cornerRadius: 0.006),
                                materials: [SimpleMaterial(color: UIColor(white: 0.85, alpha: 1), roughness: 0.6, isMetallic: false)])
        tray.addChild(board)

        let count = orthotics.sizes.count + 1
        func slot(_ i: Int) -> Float { (Float(i) - Float(count - 1) / 2) * 0.18 }

        let tape = Entity()
        let reel = ModelEntity(mesh: .generateCylinder(height: 0.022, radius: 0.034),
                               materials: [SimpleMaterial(color: .systemYellow, roughness: 0.4, isMetallic: false)])
        let tongue = ModelEntity(mesh: .generateBox(size: [0.05, 0.003, 0.014]), materials: [UnlitMaterial(color: .white)])
        tongue.position = [0.05, 0, 0]
        tape.addChild(reel); tape.addChild(tongue)
        add(tape, name: Self.tapeName, label: "Tape", at: [slot(0), 0.02, 0], bounds: [0.14, 0.04, 0.08])

        for (i, size) in orthotics.sizes.enumerated() {
            let range = size.wristCm.map { String(format: "%g", $0) }.joined(separator: "–")
            let item = Self.orthosis(radius: Self.radius(i))
            add(item, name: Self.orthosisPrefix + size.id, label: "\(size.label) \(range) cm",
                at: [slot(i + 1), 0.006 + Self.sleeveLength / 2, 0], bounds: [0.1, Self.sleeveLength, 0.1]) // standing upright
        }
    }

    private static func radius(_ sizeIndex: Int) -> Float { 0.031 + 0.007 * Float(sizeIndex) }

    private func add(_ item: Entity, name: String, label: String, at position: SIMD3<Float>, bounds: SIMD3<Float>) {
        item.name = name
        item.position = position
        item.components.set(CollisionComponent(shapes: [.generateBox(size: bounds)]))
        item.components.set(InputTargetComponent())
        item.components.set(HoverEffectComponent())
        tray.addChild(item)
        items[name] = item
        homes[name] = item.transform

        let mesh = MeshResource.generateText(label, extrusionDepth: 0.001, font: .systemFont(ofSize: 0.013, weight: .semibold))
        let text = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .black)])
        text.position = [position.x - mesh.bounds.extents.x / 2, 0.012, 0.118] // upright on the front edge
        tray.addChild(text)
    }

    /// Simplified wrist support: a sleeve along Y, two straps, and a thumb loop on +Z at the hand end.
    private static func orthosis(radius r: Float) -> Entity {
        let e = Entity()
        let fabric = SimpleMaterial(color: UIColor(red: 0.16, green: 0.19, blue: 0.24, alpha: 1), roughness: 0.9, isMetallic: false)
        let strap = SimpleMaterial(color: UIColor(white: 0.92, alpha: 1), roughness: 0.7, isMetallic: false)
        e.addChild(ModelEntity(mesh: .generateCylinder(height: sleeveLength, radius: r), materials: [fabric]))
        for y in [Float(-0.045), 0.0] {
            let band = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: r + 0.002), materials: [strap])
            band.position = [0, y, 0]
            e.addChild(band)
        }
        let thumb = ModelEntity(mesh: .generateCylinder(height: 0.03, radius: 0.016),
                                materials: [SimpleMaterial(color: .systemTeal, roughness: 0.8, isMetallic: false)])
        thumb.position = [0, sleeveLength / 2 - 0.02, r + 0.006]
        thumb.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        e.addChild(thumb)
        return e
    }

    // MARK: Picking up, dragging, dropping

    /// The tray item a gesture hit, if any.
    func item(_ entity: Entity) -> Entity? { items[entity.name] === entity ? entity : nil }

    /// Raises the selected item slightly on the tray.
    func highlight(_ name: String?) {
        for (key, item) in items where item.parent === tray {
            var t = homes[key] ?? item.transform
            if key == name { t.translation.y += 0.025 }
            item.move(to: t, relativeTo: tray, duration: 0.15)
        }
    }

    func drag(_ item: Entity, to position: SIMD3<Float>) {
        guard let root = avatar?.root else { return }
        if item.parent !== root { item.setParent(root, preservingWorldTransform: true) }
        item.position = position
    }

    func run(_ command: LabCommand) {
        guard let item = items[command.item], let frame else { return }
        item.setParent(frame, preservingWorldTransform: true)
        item.position = [Float(command.radialCm) / 100, -Float(command.axialCm) / 100, 0]
        dropped(item)
    }

    /// End of a drag: snap to the forearm if close enough, else back to the tray.
    func dropped(_ item: Entity) {
        guard let avatar, let frame else { return }
        let p = item.position(relativeTo: frame)
        let axial = -p.y, radial = simd_length(SIMD2(p.x, p.z))
        let snapped = radial <= Self.snapRadius && axial >= -0.06 && axial <= avatar.forearmLength + 0.04
        SmokeLog.mark("lab drop \(item.name) axial=\(String(format: "%.1f", axial * 100))cm "
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

    /// Simplified wrist skeleton with the scaphoid highlighted, and the intended support
    /// position as a green ghost next to the learner's own placement. nil reference = off.
    func setTeaching(_ reference: FittingReference?, learner: OrthosisFit?) {
        Array(teaching.children).forEach { $0.removeFromParent() }
        if reference != nil { measurement.clear() }
        avatar?.setTranslucent(reference != nil)
        for (name, item) in items where name.hasPrefix(Self.orthosisPrefix) {
            if reference != nil, item.parent === frame { item.components.set(OpacityComponent(opacity: 0.35)) }
            else { item.components.remove(OpacityComponent.self) }
        }
        guard let reference, let avatar else { return }
        let bone = UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))
        let highlight = UnlitMaterial(color: .systemOrange)
        func add(_ mesh: MeshResource, _ material: UnlitMaterial, _ p: SIMD3<Float>, scale: SIMD3<Float> = [1, 1, 1]) {
            let e = ModelEntity(mesh: mesh, materials: [material])
            e.position = p; e.scale = scale
            teaching.addChild(e)
        }
        let shaft = avatar.forearmLength * 0.92
        add(.generateCylinder(height: shaft, radius: 0.008), bone, [0, -shaft / 2 - 0.004, 0.011])   // radius
        add(.generateCylinder(height: shaft, radius: 0.006), bone, [0, -shaft / 2 - 0.004, -0.012])  // ulna
        add(.generateSphere(radius: 0.0085), highlight, [0, 0.010, 0.014], scale: [1, 1.5, 1])       // scaphoid
        for z in [Float(0.002), -0.009, -0.017] { add(.generateSphere(radius: 0.0058), bone, [0, 0.010, z]) } // lunate, triquetrum, pisiform
        for z in [Float(0.016), 0.006, -0.004, -0.014] { add(.generateSphere(radius: 0.0058), bone, [0, 0.024, z]) } // distal row
        for z in [Float(0.022), 0.011, 0, -0.011, -0.021] {
            add(.generateCylinder(height: 0.04, radius: 0.0035), bone, [0, 0.054, z])                // metacarpal bases
        }
        let text = MeshResource.generateText("Scaphoid", extrusionDepth: 0.001, font: .systemFont(ofSize: 0.014, weight: .bold))
        let label = ModelEntity(mesh: text, materials: [highlight])
        label.position = [0, 0.012, 0.075]
        label.components.set(BillboardComponent())
        teaching.addChild(label)

        // Intended support: reference size, middle of the accepted range.
        let index = orthotics.sizes.firstIndex { $0.id == reference.size } ?? 0
        var green = UnlitMaterial(color: .systemGreen)
        green.blending = .transparent(opacity: 0.3)
        let centre = Float(reference.offsetCm.reduce(0, +) / Double(max(reference.offsetCm.count, 1))) / 100
        add(.generateCylinder(height: Self.sleeveLength, radius: Self.radius(index) + 0.004), green, [0, -centre, 0])
        SmokeLog.mark("teaching on reference=\(reference.size) centre=\(String(format: "%.1f", centre * 100))cm "
            + "learner=\(learner.map { "\($0.size)@\($0.offsetCm)cm" } ?? "none") bones=\(teaching.children.count)")
    }
}
