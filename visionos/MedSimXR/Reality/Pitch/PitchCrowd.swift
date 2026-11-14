import RealityKit
import SwiftUI
import UIKit

/// People around the patient in the dressed places (bystanders, crew, police, hospital staff): the bundled
/// avatars (Patient.usdz / Patient_female.usdz) in poses baked in Blender (`BakedPose`, crowd_<pose>_<m|f>.usdz
/// from visionos/scripts/pitch_crowd_poses.py), re-dressed with a recoloured clothing texture
/// (roadside_crowd_<outfit>.jpg from visionos/scripts/pitch_crowd_textures.py). Without a baked file they fall
/// back to a rigged clone posed by a few joints at runtime. Children of the place, so they share the patient's HDRI light.
@MainActor
enum PitchCrowd {
    /// Joint rotations in degrees about the model's axes (Blender: X = the person's left, Z = up),
    /// the same convention as PatientBehavior.pose. Positive X lifts a limb forwards.
    typealias Pose = [String: SIMD3<Float>]
    nonisolated static let relaxed: Pose = ["upperarm_l": [6, 0, 0], "upperarm_r": [6, 0, 0], "lowerarm_l": [18, 0, 0], "lowerarm_r": [18, 0, 0]]
    nonisolated static let worried: Pose = ["upperarm_l": [30, 0, -10], "upperarm_r": [30, 0, 10], "lowerarm_l": [105, 0, 0], "lowerarm_r": [105, 0, 0],
                                "neck_01": [8, 0, 0]]
    nonisolated static let filming: Pose = ["upperarm_r": [62, 0, 12], "lowerarm_r": [70, 0, 0], "upperarm_l": [8, 0, 0], "lowerarm_l": [25, 0, 0]]
    nonisolated static let pointing: Pose = ["upperarm_r": [75, 0, 0], "lowerarm_r": [12, 0, 0], "upperarm_l": [20, 0, 0], "lowerarm_l": [60, 0, 0]]
    nonisolated static let working: Pose = ["upperarm_l": [28, 0, 0], "upperarm_r": [28, 0, 0], "lowerarm_l": [62, 0, 0], "lowerarm_r": [62, 0, 0],
                                "spine_02": [10, 0, 0], "neck_01": [14, 0, 0]]
    nonisolated static let armsFolded: Pose = ["upperarm_l": [22, 0, -14], "upperarm_r": [22, 0, 14], "lowerarm_l": [95, 0, 0], "lowerarm_r": [95, 0, 0]]

    // MARK: - Baked poses

    /// Poses made in Blender (visionos/scripts/pitch_crowd_poses.py): crowd_<rawValue>_<m|f>.usdz, a static
    /// mesh of the avatar with the original mesh/UV/material layout, origin on the floor under the pelvis,
    /// facing +Z. No skinning, so one load per file and every person is a cheap clone (PitchKit.model).
    enum BakedPose: String, CaseIterable {
        case standRelaxed = "stand_relaxed", standWorried = "stand_worried", armsCrossed = "arms_crossed"
        case phoneFilming = "phone_filming", pointing, kneelWork = "kneel_work", standLeanWork = "stand_lean_work"
        case standHandsFront = "stand_hands_front"

        /// The runtime joint pose used when the baked file is missing.
        var fallback: Pose {
            switch self {
            case .standRelaxed, .standHandsFront: PitchCrowd.relaxed
            case .standWorried: PitchCrowd.worried
            case .armsCrossed: PitchCrowd.armsFolded
            case .phoneFilming: PitchCrowd.filming
            case .pointing: PitchCrowd.pointing
            case .kneelWork, .standLeanWork: PitchCrowd.working
            }
        }

        /// Contact shadow footprint (x, z) and centre z: the kneeling pose spreads front to back.
        var footprint: (size: SIMD2<Float>, z: Float) {
            switch self {
            case .kneelWork: ([0.45, 0.8], 0.02)
            case .standLeanWork: ([0.5, 0.45], 0.04)
            default: ([0.42, 0.32], 0.02)
            }
        }
    }

    enum Gender: String {
        case m, f
        var avatar: String { self == .m ? "Patient" : "Patient_female" }
    }

    /// A baked-pose person at `p` (floor at p.y) facing `target`. `outfit`: roadside_crowd_<outfit>.jpg
    /// (nil = the avatar's own clothes, e.g. for a caller that puts scrubs on). `hair`/`skin` tint those
    /// textures. The materials are the original avatar's (loaded once), so `dress` works as on the rigged
    /// clones. Falls back to the runtime-posed rigged clone when the baked file is missing.
    @discardableResult
    static func person(_ pose: BakedPose, _ gender: Gender, outfit: String?, in parent: Entity, at p: SIMD3<Float>,
                       facing target: SIMD3<Float> = .zero, hair: UIColor? = nil, skin: UIColor? = nil, height: Float = 1) -> Entity? {
        let file = "crowd_\(pose.rawValue)_\(gender.rawValue)"
        guard Bundle.main.url(forResource: file, withExtension: "usdz") != nil, let m = PitchKit.model(file) else {
            SmokeLog.mark("pitch crowd baked missing \(file), runtime pose")
            return person(gender.avatar, outfit: outfit ?? "bystander_\(gender.rawValue)", in: parent, at: p, facing: target,
                          pose: pose.fallback, hair: hair, skin: skin, height: height, phone: pose == .phoneFilming)
        }
        let holder = Entity()
        holder.name = "crowd_\(outfit ?? pose.rawValue)"
        m.scale *= height
        holder.addChild(m)
        if let body = body(of: holder) {
            if let mats = originalMaterials(gender), var mc = body.model, mc.materials.count == mats.count {
                mc.materials = mats
                body.model = mc
            } else {
                SmokeLog.mark("pitch crowd \(file) materials \(body.model?.materials.count ?? -1) vs \(originalMaterials(gender)?.count ?? -1)")
            }
            dress(body, outfit: outfit, hair: hair, skin: skin)
        }
        let fp = pose.footprint
        PitchKit.contactShadow(holder, at: [0, 0, fp.z], size: fp.size, opacity: 0.5)
        let d = target - p
        holder.position = p
        holder.orientation = simd_quatf(angle: atan2(d.x, d.z), axis: [0, 1, 0]) // the model faces +Z
        parent.addChild(holder)
        return holder
    }

    /// The avatar mesh of a baked person (the prim "body"; a phone is a separate entity).
    static func body(of e: Entity) -> ModelEntity? {
        if let b = e.findEntity(named: "body") as? ModelEntity { return b }
        return firstModel(e) { ($0.model?.materials.count ?? 0) >= 7 }
    }

    /// The head joint of a baked person (an Xform in the file, turned with the head): hats and masks go here.
    static func headAnchor(of e: Entity) -> Entity? { e.findEntity(named: "anchor_head") }

    private static var materialCache: [Gender: [any RealityKit.Material]] = [:]

    /// The textured materials of the rigged avatar (one load per gender, via PitchKit's model cache).
    private static func originalMaterials(_ g: Gender) -> [any RealityKit.Material]? {
        if let m = materialCache[g] { return m }
        guard let avatar = PitchKit.model(g.avatar), let mesh = findSkinned(avatar) ?? firstModel(avatar, where: { _ in true }),
              let mats = mesh.model?.materials else { return nil }
        materialCache[g] = mats
        return mats
    }

    private static func firstModel(_ e: Entity, where ok: (ModelEntity) -> Bool) -> ModelEntity? {
        if let m = e as? ModelEntity, ok(m) { return m }
        for c in e.children { if let f = firstModel(c, where: ok) { return f } }
        return nil
    }

    // MARK: - Runtime-posed rigged clones (fallback)

    /// A person standing at `p` (feet on p.y) facing `target`. `model`: "Patient" or "Patient_female".
    /// `outfit`: roadside_crowd_<outfit>.jpg. `hair`/`skin` tint those textures (nil = as modelled).
    /// `phone` puts a phone in the right hand (bystander filming).
    @discardableResult
    static func person(_ model: String, outfit: String, in parent: Entity, at p: SIMD3<Float>, facing target: SIMD3<Float> = .zero,
                       pose: Pose = relaxed, hair: UIColor? = nil, skin: UIColor? = nil, height: Float = 1, phone: Bool = false) -> Entity? {
        let holder = Entity()
        holder.name = "crowd_\(outfit)"
        PitchKit.contactShadow(holder, at: .zero, size: [0.42, 0.3], opacity: 0.5)
        let d = target - p
        holder.position = p
        holder.orientation = simd_quatf(angle: atan2(d.x, d.z), axis: [0, 1, 0]) // the model faces +Z
        parent.addChild(holder)
        // A fresh load per person: clones share one skeleton pose, so they could not stand differently.
        Task { @MainActor in
            guard let m = try? await Entity(named: model) else { return SmokeLog.mark("pitch crowd missing \(model)") }
            dressAndPose(m, in: holder, outfit: outfit, pose: pose, hair: hair, skin: skin, height: height, phone: phone)
        }
        return holder
    }

    private static func dressAndPose(_ m: Entity, in holder: Entity, outfit: String, pose: Pose, hair: UIColor?, skin: UIColor?,
                                     height: Float, phone: Bool) {
        holder.addChild(m)
        let size = m.visualBounds(relativeTo: holder).extents
        if size.z > size.y { m.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]) } // as PatientAvatar: stand it up
        m.scale *= height
        let skinned = findSkinned(m)
        let b = m.visualBounds(relativeTo: holder) // seated rest pose, feet on the floor
        m.position -= [b.center.x, b.min.y, b.center.z]
        var hand: simd_float4x4?
        if let skinned {
            dress(skinned, outfit: outfit, hair: hair, skin: skin)
            let posed = applyPose(skinned, standing.merging(pose) { $1 })
            hand = posed.hand
            // Standing straightens the legs below the seat; keep the feet where they were (as PatientAvatar).
            let toHolder = skinned.transformMatrix(relativeTo: holder)
            let shift = toHolder * posed.footRest - toHolder * posed.footPosed
            m.position += [shift.x, shift.y, shift.z]
        }
        if phone, let skinned, let hand {
            let at = skinned.transformMatrix(relativeTo: holder) * hand
            let device = ModelEntity(mesh: .generateBox(size: [0.075, 0.15, 0.009], cornerRadius: 0.008),
                                     materials: [SimpleMaterial(color: UIColor(white: 0.08, alpha: 1), roughness: 0.2, isMetallic: true)])
            device.position = [at.columns.3.x, at.columns.3.y + 0.05, at.columns.3.z + 0.02]
            holder.addChild(device)
        }
    }

    /// Pitch shots only: `-pitchEnv forest` (or env PITCH_ENV=forest, e.g. SIMCTL_CHILD_PITCH_ENV) moves the road
    /// case's first stage to a forest trail (AppModel.environmentKind -> .forest). Normal play gets the trail
    /// from the case's own setting text instead.
    static let forest = (AppConfig.launchArgument("-pitchEnv") ?? ProcessInfo.processInfo.environment["PITCH_ENV"]) == "forest"
    /// Who shouts from the crowd: bystanders on the street, hikers on the trail.
    static var bystander: String { forest ? "Hiker" : "Bystander" }

    /// Caption colours: teal learner, orange patient, these for the people around them.
    static let crowdSpeakers: Set<String> = ["Bystander", "Driver", "Hiker", "Passer-by"]
    static func speakerColor(_ speaker: String, learner: Bool) -> Color {
        if learner { return .teal }
        if crowdSpeakers.contains(speaker) { return Color(red: 0.98, green: 0.45, blue: 0.7) }
        if ["Sam", "Lena", "Priya", "Dr Omar"].contains(speaker) { return Color(red: 0.45, green: 0.85, blue: 0.5) }
        return .orange
    }

    // MARK: - Internals

    /// Material slots follow the mesh's subsets: body, suit, shoes, hair, eyebrows, eyelashes, eyes.
    private static func dress(_ e: ModelEntity, outfit: String?, hair: UIColor?, skin: UIColor?) {
        guard var mc = e.model else { return }
        func retint(_ i: Int, _ change: (inout PhysicallyBasedMaterial) -> Void) {
            guard mc.materials.indices.contains(i), var pbr = mc.materials[i] as? PhysicallyBasedMaterial else { return }
            change(&pbr)
            mc.materials[i] = pbr
        }
        if let outfit, let tex = PitchKit.texture("roadside_crowd_\(outfit).jpg") {
            retint(1) { $0.baseColor = .init(tint: .white, texture: .init(tex)) }
        }
        if let hair { retint(3) { $0.baseColor.tint = hair } }
        if let skin { retint(0) { $0.baseColor.tint = skin } }
        e.model = mc
    }

    /// The file's rest pose is seated; these straighten the legs (PatientBehavior's standing pose).
    nonisolated static let standing: Pose = ["thigh_l": [86, 0, 0], "thigh_r": [86, 0, 0], "calf_l": [-86, 0, 0], "calf_r": [-86, 0, 0]]

    /// Writes the pose to the skeleton; returns the right hand's transform and the mean foot position
    /// before and after (mesh space).
    private static func applyPose(_ skinned: ModelEntity, _ pose: Pose) -> (hand: simd_float4x4?, footRest: SIMD4<Float>, footPosed: SIMD4<Float>) {
        let rest = skinned.jointTransforms
        let names = skinned.jointNames
        let indexByPath = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
        var parent = [Int?](repeating: nil, count: names.count)
        for (i, path) in names.enumerated() { parent[i] = indexByPath[path.split(separator: "/").dropLast().joined(separator: "/")] }
        var world = [simd_quatf](repeating: simd_quatf(angle: 0, axis: [0, 1, 0]), count: names.count)
        var parentRot = world
        var byName: [String: Int] = [:]
        for (i, path) in names.enumerated() { // parents precede children
            let parts = path.split(separator: "/")
            byName[String(parts.last ?? "")] = i
            if let p = parent[i] { parentRot[i] = world[p] }
            world[i] = parentRot[i] * rest[i].rotation
        }
        var joints = rest
        for (name, deg) in pose {
            guard let i = byName[name] else { continue }
            let r = deg * .pi / 180
            let delta = simd_quatf(angle: r.z, axis: [0, 0, 1]) * simd_quatf(angle: r.y, axis: [0, 1, 0]) * simd_quatf(angle: r.x, axis: [1, 0, 0])
            joints[i].rotation = parentRot[i].inverse * delta * parentRot[i] * rest[i].rotation
        }
        skinned.jointTransforms = joints
        Task { @MainActor in // once more after it is in the scene
            try? await Task.sleep(nanoseconds: 300_000_000)
            skinned.jointTransforms = joints
        }
        func fk(_ js: [Transform]) -> [simd_float4x4] {
            var m = js.map(\.matrix)
            for i in m.indices { if let p = parent[i] { m[i] = m[p] * m[i] } }
            return m
        }
        let before = fk(rest), after = fk(joints)
        let feet = ["foot_l", "foot_r"].compactMap { byName[$0] }
        func mean(_ m: [simd_float4x4]) -> SIMD4<Float> {
            feet.isEmpty ? [0, 0, 0, 1] : feet.map { m[$0].columns.3 }.reduce(.zero, +) / Float(feet.count)
        }
        return (byName["hand_r"].map { after[$0] }, mean(before), mean(after))
    }

    private static func findSkinned(_ e: Entity) -> ModelEntity? {
        if let m = e as? ModelEntity, !m.jointNames.isEmpty { return m }
        for child in e.children { if let found = findSkinned(child) { return found } }
        return nil
    }
}
