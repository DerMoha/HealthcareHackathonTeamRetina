import Foundation
import RealityKit
import UIKit

/// Procedural seated patient. Facing +Z in its own space; origin on the floor.
/// Patient's RIGHT side is -X (they face the wearer). Anchor entities (right_wrist,
/// right_forearm, left_wrist, ...) live in `anchors` and are independent of any USDZ.
@MainActor
final class PatientAvatar {
    let root = Entity()
    /// Everything above the hips; flinches as a unit.
    private let upper = Entity()
    private let rightArm = Entity()
    private(set) var anchors: [String: Entity] = [:]
    var zoneEntities: [Entity] = []
    private var visuals: [ModelEntity] = []
    private var head = Entity()
    private var torso = Entity()
    private var idleTask: Task<Void, Never>?

    private let hipY: Float = 0.55

    private let skin = SimpleMaterial(color: UIColor(red: 0.87, green: 0.68, blue: 0.56, alpha: 1), isMetallic: false)
    private let shirt = SimpleMaterial(color: UIColor(red: 0.20, green: 0.42, blue: 0.62, alpha: 1), isMetallic: false)
    private let pants = SimpleMaterial(color: UIColor(red: 0.22, green: 0.24, blue: 0.30, alpha: 1), isMetallic: false)
    private let hair = SimpleMaterial(color: UIColor(red: 0.18, green: 0.12, blue: 0.09, alpha: 1), isMetallic: false)
    private let shoe = SimpleMaterial(color: UIColor(white: 0.9, alpha: 1), isMetallic: false)
    private let wood = SimpleMaterial(color: UIColor(red: 0.55, green: 0.40, blue: 0.27, alpha: 1), isMetallic: false)
    private let eyeWhite = SimpleMaterial(color: .white, isMetallic: false)
    private let eyeDark = SimpleMaterial(color: UIColor(white: 0.08, alpha: 1), isMetallic: false)

    init() {
        root.name = "patient"
        build()
    }

    // MARK: Build

    /// Position in `upper`'s frame (pivot sits at the hips).
    private func u(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { [x, y - hipY, z] }

    private func build() {
        // Stool.
        add(cyl: (0.04, 0.2), at: [0, 0.50, 0], mat: wood, name: "stool_seat", to: root)
        for (x, z) in [(-0.13, -0.13), (0.13, -0.13), (-0.13, 0.13), (0.13, 0.13)] as [(Float, Float)] {
            limb(from: [x, 0.0, z], to: [x * 1.05, 0.49, z * 1.05], radius: 0.015, mat: wood, name: "stool_leg", parent: root)
        }

        // Legs (static).
        for side in [Float(-1), 1] {
            let n = side < 0 ? "right" : "left"
            let hip: SIMD3<Float> = [side * 0.10, 0.57, 0.0]
            let knee: SIMD3<Float> = [side * 0.11, 0.58, 0.42]
            let ankle: SIMD3<Float> = [side * 0.11, 0.08, 0.46]
            limb(from: hip, to: knee, radius: 0.075, mat: pants, name: "\(n)_thigh", parent: root)
            limb(from: knee, to: ankle, radius: 0.052, mat: pants, name: "\(n)_shin", parent: root)
            add(box: [0.09, 0.06, 0.24], at: [side * 0.11, 0.03, 0.54], mat: shoe, name: "\(n)_foot", to: root)
        }

        // Upper body.
        upper.name = "upper_body"
        upper.position = [0, hipY, 0]
        root.addChild(upper)

        torso = add(box: [0.36, 0.52, 0.21], at: u(0, 0.84, 0), mat: shirt, name: "torso", to: upper, corner: 0.07)
        add(cyl: (0.07, 0.045), at: u(0, 1.12, 0), mat: skin, name: "neck", to: upper)

        let h = add(sphere: 0.105, at: u(0, 1.21, 0.0), mat: skin, name: "head", to: upper)
        head = h
        let cap = add(sphere: 0.11, at: [0, 0.03, -0.02], mat: hair, name: "hair", to: h)
        cap.scale = [1, 0.85, 1]
        for sx in [Float(-1), 1] {
            add(sphere: 0.017, at: [sx * 0.04, 0.015, 0.092], mat: eyeWhite, name: "eye_white", to: h)
            add(sphere: 0.009, at: [sx * 0.04, 0.015, 0.106], mat: eyeDark, name: "eye", to: h)
        }
        add(sphere: 0.014, at: [0, -0.012, 0.102], mat: skin, name: "nose", to: h)
        add(box: [0.04, 0.008, 0.01], at: [0, -0.05, 0.095], mat: eyeDark, name: "mouth", to: h)

        // Arms. Right = -X.
        rightArm.name = "right_arm"
        upper.addChild(rightArm)
        buildArm(side: -1, name: "right", parent: rightArm)
        let leftArm = Entity()
        leftArm.name = "left_arm"
        upper.addChild(leftArm)
        buildArm(side: 1, name: "left", parent: leftArm)
    }

    /// Forearm rests on the thigh; wrist is out front and reachable.
    private func buildArm(side s: Float, name n: String, parent: Entity) {
        let shoulder = u(s * 0.21, 1.03, 0.0)
        let elbow = u(s * 0.21, 0.73, 0.05)
        let wrist = u(s * 0.12, 0.705, 0.36)
        add(sphere: 0.05, at: shoulder, mat: shirt, name: "\(n)_shoulder", to: parent)
        limb(from: shoulder, to: elbow, radius: 0.048, mat: shirt, name: "\(n)_upper_arm", parent: parent)
        add(sphere: 0.04, at: elbow, mat: skin, name: "\(n)_elbow", to: parent)

        // Forearm entity origin = midpoint (zone offset [0,0,0] lands a hand's width above the wrist).
        anchors["\(n)_forearm"] = limb(from: elbow, to: wrist, radius: 0.036, mat: skin, name: "\(n)_forearm", parent: parent)
        anchors["\(n)_wrist"] = add(sphere: 0.034, at: wrist, mat: skin, name: "\(n)_wrist", to: parent)

        // Hand: thumb side up (resting neutral on the thigh).
        let handC = u(s * 0.115, 0.70, 0.435)
        add(box: [0.042, 0.085, 0.10], at: handC, mat: skin, name: "\(n)_hand", to: parent, corner: 0.015)
        add(box: [0.02, 0.02, 0.06], at: handC + [0, 0.05, -0.015], mat: skin, name: "\(n)_thumb", to: parent, corner: 0.008)
    }

    // MARK: Helpers

    @discardableResult
    private func add(sphere r: Float, at p: SIMD3<Float>, mat: SimpleMaterial, name: String, to parent: Entity) -> ModelEntity {
        attach(.generateSphere(radius: r), p, mat, name, parent)
    }

    @discardableResult
    private func add(box b: SIMD3<Float>, at p: SIMD3<Float>, mat: SimpleMaterial, name: String, to parent: Entity, corner: Float = 0) -> ModelEntity {
        attach(.generateBox(size: b, cornerRadius: corner), p, mat, name, parent)
    }

    @discardableResult
    private func add(cyl c: (Float, Float), at p: SIMD3<Float>, mat: SimpleMaterial, name: String, to parent: Entity) -> ModelEntity {
        attach(.generateCylinder(height: c.0, radius: c.1), p, mat, name, parent)
    }

    private func attach(_ mesh: MeshResource, _ p: SIMD3<Float>, _ mat: SimpleMaterial, _ name: String, _ parent: Entity) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [mat])
        e.name = name
        e.position = p
        parent.addChild(e)
        visuals.append(e)
        return e
    }

    @discardableResult
    private func limb(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: Float, mat: SimpleMaterial,
                      name: String, parent: Entity) -> ModelEntity {
        let d = b - a
        let len = simd_length(d)
        let e = attach(.generateCylinder(height: len, radius: radius), (a + b) / 2, mat, name, parent)
        e.orientation = simd_quatf(from: [0, 1, 0], to: d / len)
        return e
    }

    // MARK: Optional USDZ

    /// If a bundled Patient.usdz exists, use it for visuals; anchors/hierarchy stay as-is.
    func loadOptionalVisuals() async {
        guard Bundle.main.url(forResource: "Patient", withExtension: "usdz") != nil,
              let model = try? await Entity(named: "Patient") else { return }
        for v in visuals { v.components.remove(ModelComponent.self) }
        model.name = "patient_usdz"
        root.addChild(model)
    }

    // MARK: Idle + reactions

    func startIdle() {
        idleTask?.cancel()
        let headBase = head.transform
        let torsoBase = torso.transform
        idleTask = Task { @MainActor [weak self] in
            var phase = false
            while !Task.isCancelled {
                guard let self else { return }
                var h = headBase
                h.rotation = simd_quatf(angle: (phase ? 1 : -1) * 0.05, axis: [0, 1, 0]) * headBase.rotation
                self.head.move(to: h, relativeTo: self.head.parent, duration: 2.5, timingFunction: .easeInOut)
                var t = torsoBase
                t.scale = phase ? [1.02, 1.015, 1.03] : [1, 1, 1]
                self.torso.move(to: t, relativeTo: self.torso.parent, duration: 2.5, timingFunction: .easeInOut)
                phase.toggle()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    func stopIdle() { idleTask?.cancel() }

    func play(animation: String) async {
        guard animation == "arm_withdrawal" || animation == "flinch" else { return }
        SmokeLog.mark("animation \(animation)")
        // Fixed rest poses, so a reaction that starts mid-animation cannot drift.
        let upperBase = Transform(translation: [0, hipY, 0])
        let armBase = Transform.identity

        var flinch = upperBase
        flinch.translation += [0, 0, -0.03]
        flinch.rotation = simd_quatf(angle: -0.10, axis: [1, 0, 0]) * upperBase.rotation
        upper.move(to: flinch, relativeTo: upper.parent, duration: 0.12, timingFunction: .easeOut)

        if animation == "arm_withdrawal" {
            var pull = armBase
            pull.translation += [0, 0.03, -0.12]
            rightArm.move(to: pull, relativeTo: rightArm.parent, duration: 0.12, timingFunction: .easeOut)
        }
        try? await Task.sleep(nanoseconds: 650_000_000)
        upper.move(to: upperBase, relativeTo: upper.parent, duration: 0.45, timingFunction: .easeInOut)
        rightArm.move(to: armBase, relativeTo: rightArm.parent, duration: 0.45, timingFunction: .easeInOut)
    }
}
