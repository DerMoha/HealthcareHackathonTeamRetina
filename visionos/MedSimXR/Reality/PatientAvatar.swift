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
    /// Right forearm: origin at the wrist joint, +Y towards the hand, +Z the thumb (radial)
    /// side. Rides on the forearm joint, so anything parented to it follows the arm.
    let forearmFrame = Entity()
    /// Elbow joint to wrist joint, metres.
    private(set) var forearmLength: Float = 0.25
    /// Zones are only targetable while the patient is seated (PatientBehavior.canExamine).
    var zonesEnabled = true { didSet { zoneEntities.forEach { $0.isEnabled = zonesEnabled } } }
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

        // What a model swap must be able to go back to (the primitive body).
        proceduralAnchors = anchors.mapValues { $0.transform }
        proceduralForearmLength = forearmLength
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
        if s < 0 {
            forearmFrame.name = "right_forearm_frame"
            forearmFrame.transform = Transform(matrix: Self.limbFrame(elbow: elbow, wrist: wrist))
            forearmLength = simd_distance(elbow, wrist)
            parent.addChild(forearmFrame)
            anchors["right_forearm_frame"] = forearmFrame
        }

        // Hand: thumb side up (resting neutral on the thigh).
        let handC = u(s * 0.115, 0.70, 0.435)
        add(box: [0.042, 0.085, 0.10], at: handC, mat: skin, name: "\(n)_hand", to: parent, corner: 0.015)
        add(box: [0.02, 0.02, 0.06], at: handC + [0, 0.05, -0.015], mat: skin, name: "\(n)_thumb", to: parent, corner: 0.008)
    }

    /// Frame at `wrist` with +Y along the limb and +Z as close to "up" as the limb allows
    /// (the model rests with the thumb side up).
    private static func limbFrame(elbow: SIMD3<Float>, wrist: SIMD3<Float>) -> simd_float4x4 {
        let y = simd_normalize(wrist - elbow)
        let up = SIMD3<Float>(0, 1, 0)
        let z = simd_normalize(up - simd_dot(up, y) * y)
        let x = simd_cross(y, z)
        return simd_float4x4(SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(wrist, 1))
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

    // MARK: Realistic model (Patient.usdz), procedural body as fallback

    private struct Sidecar: Decodable {
        var seatHeight: Float
        var anchors: [String: [Float]]
        /// Outward surface normals of the anchors that lie on the skin (avatar space).
        var normals: [String: [Float]]?
        /// Only for a patient lying on an examination couch (Patient_pregnant).
        var couch: Couch?
    }

    /// Examination couch the recumbent patient lies on, in avatar space. The seat slab runs from the
    /// pivot towards +Z; the back-rest rises from the pivot towards -Z at `backRestAngleDeg`.
    struct Couch: Decodable {
        var seatHeight: Float
        var width: Float
        var thickness: Float
        var backRestAngleDeg: Float
        var backRestPivot: [Float]
        var backRestLength: Float
        var seatLength: Float
    }

    /// Skinned mesh of Patient.usdz; nil while the procedural body is in use.
    private var skinned: ModelEntity?
    private var restJoints: [Transform] = []
    /// Model-space rest rotation of each joint's parent (identity for roots).
    private var parentRotation: [simd_quatf] = []
    private var jointIndex: [String: Int] = [:]
    /// Current model-space rotation offsets per joint (short name), applied on top of the rest pose.
    private var jointDelta: [String: simd_quatf] = [:]
    private var model: Entity?
    private var parentIndex: [Int?] = []
    /// Rest-pose joint matrices in the skinned mesh's space, and that space -> avatar root.
    private var restWorld: [simd_float4x4] = []
    private var meshToRoot = matrix_identity_float4x4
    /// Exam anchors ride on these joints, so zones stay on the wrist in every pose.
    private static let anchorJoints = ["right_wrist": "hand_r", "right_forearm": "lowerarm_r", "left_wrist": "hand_l",
                                       "right_forearm_frame": "lowerarm_r"]
    private var anchorRest: [String: simd_float4x4] = [:]

    /// Anchors created from the sidecar (belly points); removed again when the model is unloaded.
    private var extraAnchors: [String] = []
    /// Outward skin normals by anchor name, avatar space.
    private(set) var anchorNormals: [String: SIMD3<Float>] = [:]
    /// True while a patient lying on a couch is shown (not the seated models).
    private(set) var isRecumbent = false
    /// Height of the seat the model sits on (stool or couch top), avatar space.
    private(set) var seatHeight: Float = 0.5
    /// Journey cases hide the clinic stool: the surroundings bring their own seat (wall, stretcher, trolley).
    var furnitureHidden = false { didSet { stoolParts.forEach { $0.isEnabled = !furnitureHidden } } }

    /// True when the skinned model is in use and can be posed.
    var isAnimated: Bool { skinned != nil }

    /// Procedural anchor transforms and forearm length, restored when a model is unloaded.
    private var proceduralAnchors: [String: Transform] = [:]
    private var proceduralForearmLength: Float = 0.25
    /// Components taken from the primitive body while a model is shown.
    private var hiddenVisuals: [(ModelEntity, ModelComponent)] = []
    private var stoolParts: [Entity] = []
    /// Bundled model currently shown ("Patient", "Patient_female", ...); nil = primitive body.
    private(set) var loadedModel: String?
    /// Bumped by every load so a slower, older load cannot overwrite a newer one.
    private var loadGeneration = 0

    /// Swaps the primitive body for the bundled seated human (assets/patient). The model was
    /// exported from Blender: Z up, facing -Y. Anchors come from the sidecar `<name>.json`, in avatar space.
    /// `variant` names the model (`Patient`, `Patient_female`, ...); a missing one falls back to
    /// `Patient`. May be called again to swap the model: the previous one is removed first, the
    /// anchors, zones and orthotics lab stay in place. Launch argument `-proceduralAvatar`
    /// keeps the primitive body.
    func loadOptionalVisuals(variant: String = "Patient") async {
        loadGeneration += 1
        let generation = loadGeneration
        unloadModel()
        guard !ProcessInfo.processInfo.arguments.contains("-proceduralAvatar") else {
            SmokeLog.mark("avatar procedural")
            SmokeLog.mark("avatar variant=\(variant) loaded=procedural")
            return
        }
        // pitch shots: a 20-week bump (same build, PREG=0.6) instead of the late-pregnancy one
        let pitchModel = SmokeLog.pitch && variant == "Patient_pregnant" ? ["antenatal_patient"] : []
        for name in pitchModel + (variant == "Patient" ? ["Patient"] : [variant, "Patient"]) {
            guard Bundle.main.url(forResource: name, withExtension: "usdz") != nil,
                  let json = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: json),
                  let sidecar = try? JSONDecoder.medsim.decode(Sidecar.self, from: data) else { continue }
            guard let model = try? await Entity(named: name) else { continue }
            guard generation == loadGeneration else { return } // a newer load took over
            show(model, sidecar: sidecar, name: name)
            SmokeLog.mark("avatar variant=\(variant) loaded=\(name)")
            return
        }
        guard generation == loadGeneration else { return }
        SmokeLog.mark("avatar procedural")
        SmokeLog.mark("avatar variant=\(variant) loaded=procedural")
    }

    private func show(_ model: Entity, sidecar: Sidecar, name: String) {
        hiddenVisuals = visuals.compactMap { v in v.components[ModelComponent.self].map { (v, $0) } }
        for v in visuals { v.components.remove(ModelComponent.self) }
        model.name = "patient_usdz"
        root.addChild(model)
        loadedModel = name
        // Stand the model up if the loader did not honour the stage's Z-up axis.
        let size = model.visualBounds(relativeTo: root).extents
        if size.z > size.y { model.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]) }
        if let couch = sidecar.couch { buildCouch(couch) } else { buildStool(seatHeight: sidecar.seatHeight) }
        isRecumbent = sidecar.couch != nil
        seatHeight = sidecar.couch?.seatHeight ?? sidecar.seatHeight
        stoolParts.forEach { $0.isEnabled = !furnitureHidden }
        for (name, p) in sidecar.anchors where p.count == 3 {
            if anchors[name] == nil { // belly points and the like: plain markers on the root
                let marker = Entity()
                marker.name = name
                root.addChild(marker)
                anchors[name] = marker
                extraAnchors.append(name)
            }
            anchors[name]?.setPosition([p[0], p[1], p[2]], relativeTo: root)
        }
        anchorNormals = (sidecar.normals ?? [:]).compactMapValues { $0.count == 3 ? SIMD3($0[0], $0[1], $0[2]) : nil }
        if let mesh = Self.findSkinned(model) {
            skinned = mesh
            restJoints = mesh.jointTransforms
            let names = mesh.jointNames
            let indexByPath = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
            var world = [simd_quatf](repeating: simd_quatf(angle: 0, axis: [0, 1, 0]), count: names.count)
            parentRotation = world
            parentIndex = names.map { _ in nil }
            for (i, path) in names.enumerated() { // parents precede children
                let parts = path.split(separator: "/")
                jointIndex[String(parts.last ?? "")] = i
                parentIndex[i] = indexByPath[parts.dropLast().joined(separator: "/")]
                if let parent = parentIndex[i] { parentRotation[i] = world[parent] }
                world[i] = parentRotation[i] * restJoints[i].rotation
            }
            self.model = model
            restWorld = forwardKinematics(restJoints)
            meshToRoot = mesh.transformMatrix(relativeTo: root)
            if let e = jointIndex["lowerarm_r"], let w = jointIndex["hand_r"] {
                func point(_ i: Int) -> SIMD3<Float> { let v = meshToRoot * restWorld[i].columns.3; return [v.x, v.y, v.z] }
                forearmFrame.setTransformMatrix(Self.limbFrame(elbow: point(e), wrist: point(w)), relativeTo: root)
                forearmLength = simd_distance(point(e), point(w))
            }
            for name in Self.anchorJoints.keys { anchorRest[name] = anchors[name]?.transformMatrix(relativeTo: root) }
        }
        let b = model.visualBounds(relativeTo: root)
        SmokeLog.mark("avatar usdz joints=\(restJoints.count) size=\(b.extents) minY=\(b.min.y)")
    }

    /// Removes the shown model and its stool and puts the primitive body, its anchors and the
    /// forearm frame back, ready for the next model or as the fallback.
    private func unloadModel() {
        guard loadedModel != nil else { return }
        model?.removeFromParent()
        root.children.first { $0.name == "patient_usdz" }?.removeFromParent()
        stoolParts.forEach { $0.removeFromParent() }
        stoolParts = []
        for name in extraAnchors { anchors[name]?.removeFromParent(); anchors[name] = nil }
        extraAnchors = []; anchorNormals = [:]; isRecumbent = false; seatHeight = 0.5
        for (visual, component) in hiddenVisuals { visual.components.set(component) }
        hiddenVisuals = []
        for (name, transform) in proceduralAnchors { anchors[name]?.transform = transform }
        forearmLength = proceduralForearmLength
        skinned = nil
        model = nil
        restJoints = []; parentRotation = []; parentIndex = []; restWorld = []
        jointIndex = [:]; jointDelta = [:]; anchorRest = [:]
        meshToRoot = matrix_identity_float4x4
        loadedModel = nil
    }

    private static func findSkinned(_ e: Entity) -> ModelEntity? {
        if let m = e as? ModelEntity, !m.jointNames.isEmpty { return m }
        for child in e.children { if let found = findSkinned(child) { return found } }
        return nil
    }

    /// Examination couch drawn from the sidecar: a seat/leg-rest slab, an inclined back-rest slab and a
    /// pedestal. Pale blue upholstery on a white frame.
    private func buildCouch(_ c: Couch) {
        let upholstery = SimpleMaterial(color: UIColor(red: 0.74, green: 0.85, blue: 0.93, alpha: 1), roughness: 0.55, isMetallic: false)
        let frame = SimpleMaterial(color: UIColor(white: 0.93, alpha: 1), roughness: 0.4, isMetallic: false)
        let steel = SimpleMaterial(color: UIColor(white: 0.78, alpha: 1), roughness: 0.3, isMetallic: true)
        let pivot = SIMD3<Float>(c.backRestPivot[0], c.backRestPivot[1], c.backRestPivot[2])
        let theta = c.backRestAngleDeg * .pi / 180
        func add(_ mesh: MeshResource, _ material: SimpleMaterial, _ position: SIMD3<Float>, _ rotation: simd_quatf = .init(angle: 0, axis: [1, 0, 0])) {
            let e = ModelEntity(mesh: mesh, materials: [material])
            e.name = "couch"
            e.position = position
            e.orientation = rotation
            root.addChild(e)
            stoolParts.append(e)
        }
        let t = c.thickness
        // seat and leg rest: top face at seatHeight, from the pivot forwards
        add(.generateBox(size: [c.width, t, c.seatLength], cornerRadius: 0.02), upholstery,
            [0, c.seatHeight - t / 2, pivot.z + c.seatLength / 2])
        // back-rest: top face on the plane through the pivot, rising towards -Z
        let along = SIMD3<Float>(0, sin(theta), -cos(theta)), normal = SIMD3<Float>(0, cos(theta), sin(theta))
        add(.generateBox(size: [c.width, t, c.backRestLength], cornerRadius: 0.02), upholstery,
            pivot + along * (c.backRestLength / 2) - normal * (t / 2), simd_quatf(angle: theta, axis: [1, 0, 0]))
        // pedestal and base under the seat, hinge cover where the two slabs meet
        let under = c.seatHeight - t
        add(.generateBox(size: [0.5, 0.05, 0.9], cornerRadius: 0.02), frame, [0, 0.025, pivot.z + c.seatLength * 0.45])
        add(.generateCylinder(height: under - 0.05, radius: 0.055), steel, [0, 0.05 + (under - 0.05) / 2, pivot.z + c.seatLength * 0.45])
        add(.generateBox(size: [c.width * 0.9, 0.04, 0.5], cornerRadius: 0.015), frame, [0, under - 0.02, pivot.z + c.seatLength * 0.45])
        add(.generateCylinder(height: c.width, radius: 0.03), frame, pivot + [0, -t / 2, 0], simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))
    }

    /// Examination stool matched to the model's seat height.
    private func buildStool(seatHeight h: Float) {
        let cushion = SimpleMaterial(color: UIColor(white: 0.12, alpha: 1), roughness: 0.8, isMetallic: false)
        let steel = SimpleMaterial(color: UIColor(white: 0.75, alpha: 1), roughness: 0.3, isMetallic: true)
        let parts: [(MeshResource, SIMD3<Float>, SimpleMaterial)] = [
            (.generateCylinder(height: 0.06, radius: 0.19), [0, h - 0.03, -0.02], cushion),
            (.generateCylinder(height: h - 0.08, radius: 0.025), [0, (h - 0.08) / 2 + 0.02, -0.02], steel),
            (.generateCylinder(height: 0.025, radius: 0.24), [0, 0.0125, -0.02], steel),
        ]
        for (mesh, position, material) in parts {
            let e = ModelEntity(mesh: mesh, materials: [material])
            e.name = "stool"
            e.position = position
            root.addChild(e)
            stoolParts.append(e)
        }
    }

    private func forwardKinematics(_ joints: [Transform]) -> [simd_float4x4] {
        var world = joints.map(\.matrix)
        for i in world.indices { if let parent = parentIndex[i] { world[i] = world[parent] * world[i] } }
        return world
    }

    /// Writes `jointDelta` to the skeleton, keeps the feet where they were (the pelvis moves
    /// instead) and moves the exam anchors with their joints.
    private func applyJoints() {
        guard let skinned, let model else { return }
        var joints = restJoints
        for (name, delta) in jointDelta {
            guard let i = jointIndex[name] else { continue }
            joints[i].rotation = parentRotation[i].inverse * delta * parentRotation[i] * restJoints[i].rotation
        }
        skinned.jointTransforms = joints
        let world = forwardKinematics(joints)
        var shift = SIMD4<Float>.zero
        let feet = ["foot_l", "foot_r"].compactMap { jointIndex[$0] }
        for i in feet { shift += (meshToRoot * (restWorld[i].columns.3 - world[i].columns.3)) / Float(feet.count) }
        model.position = [shift.x, shift.y, shift.z]
        var planted = matrix_identity_float4x4
        planted.columns.3 = [shift.x, shift.y, shift.z, 1]
        for (anchor, joint) in Self.anchorJoints {
            guard let i = jointIndex[joint], let rest = anchorRest[anchor] else { continue }
            anchors[anchor]?.setTransformMatrix(planted * meshToRoot * world[i] * restWorld[i].inverse * meshToRoot.inverse * rest,
                                                relativeTo: root)
        }
    }

    /// Eases joints to model-space rotation offsets (Blender axes: X = patient's left, -Y = front, Z = up).
    /// `lean` adds a forward torso lean that peaks mid-way. Stops where it is when cancelled.
    private func tweenJoints(_ target: [String: simd_quatf], duration: Double, lean: Float = 0) async {
        guard skinned != nil else { return }
        let start = target.keys.reduce(into: [String: simd_quatf]()) {
            $0[$1] = jointDelta[$1] ?? simd_quatf(angle: 0, axis: [0, 1, 0])
        }
        let frames = max(1, Int(duration * 60))
        for frame in 1...frames {
            if Task.isCancelled { return }
            let t = Float(frame) / Float(frames)
            let eased = t * t * (3 - 2 * t)
            for (name, goal) in target { jointDelta[name] = simd_slerp(start[name]!, goal, eased) }
            if lean != 0, let spine = jointDelta["spine_01"] {
                jointDelta["spine_01"] = Self.rot(lean * sin(.pi * t), [1, 0, 0]) * spine
            }
            applyJoints()
            if frame < frames { try? await Task.sleep(nanoseconds: 16_000_000) }
        }
    }

    /// Moves the body to the behaviour's pose. `snap` skips the animation (first appearance).
    func apply(_ behavior: PatientBehavior, snap: Bool = false) async {
        guard isAnimated else { return }
        await tweenJoints(behavior.pose.mapValues { Self.rot($0, [1, 0, 0]) },
                          duration: snap ? 0 : behavior.state.duration, lean: snap ? 0 : behavior.lean)
        guard !Task.isCancelled, let rest = anchorRest["right_wrist"], let wrist = anchors["right_wrist"] else { return }
        let moved = simd_distance(wrist.position(relativeTo: root), [rest.columns.3.x, rest.columns.3.y, rest.columns.3.z])
        SmokeLog.mark("pose \(behavior.state.rawValue) right_wrist moved=\(String(format: "%.2f", moved))")
    }

    private static func rot(_ degrees: Float, _ axis: SIMD3<Float>) -> simd_quatf {
        simd_quatf(angle: degrees * .pi / 180, axis: axis)
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
                // realistic model: slow head turn and a hint of breathing
                Task { await self.tweenJoints(["neck_01": Self.rot(phase ? 4 : -4, [0, 0, 1]),
                                               "spine_03": Self.rot(phase ? -1.2 : 0, [1, 0, 0])], duration: 2.4) }
                phase.toggle()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    func stopIdle() { idleTask?.cancel() }

    /// Primitive fallback body only; the skinned model recoils through `apply(_:)`.
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
