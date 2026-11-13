import RealityKit

/// Pitch-only places (launch argument `-pitch`): EnvironmentSet.show() asks here first and keeps its
/// own procedural room when this returns false. One file per place, so each can be dressed on its own.
/// Returning true means the place is fully built into `set`, the patient's seat included (roadside,
/// ambulance, resus); the clinic and antenatal rooms keep the avatar's own stool / the scan couch.
/// See README.md in this folder.
@MainActor
enum PitchDressing {
    /// `set`: empty entity in avatar space (patient at the origin facing +Z, wearer ~1.7 m in front),
    /// added to the scene after this returns and removed on the next place change.
    /// `seat`: the patient's seat height. `avatarRoot`: the patient's root, parent of the place; light it here.
    static func build(_ kind: EnvironmentSet.Kind, into set: Entity, seat: Float, avatarRoot: Entity) -> Bool {
        PitchKit.clearLight(avatarRoot) // the previous place's light
        switch kind {
        case .clinic: return PitchClinic.build(into: set, seat: seat, avatarRoot: avatarRoot)
        case .antenatal: return PitchAntenatal.build(into: set, seat: seat, avatarRoot: avatarRoot)
        case .roadside: return PitchRoadside.build(into: set, seat: seat, night: false, avatarRoot: avatarRoot)
        case .roadsideNight: return PitchRoadside.build(into: set, seat: seat, night: true, avatarRoot: avatarRoot)
        case .ambulance: return PitchAmbulance.build(into: set, seat: seat, avatarRoot: avatarRoot)
        case .traumaBay: return PitchTraumaBay.build(into: set, seat: seat, avatarRoot: avatarRoot)
        }
    }
}
