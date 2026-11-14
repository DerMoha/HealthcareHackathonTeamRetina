import RealityKit

/// The dressed places (models, photo textures, HDRI light, posed people). EnvironmentSet.show() builds
/// them in normal play when "Realistic environments" is on (AppConfig.realisticRooms) and always in the
/// pitch shots (`-pitch`); otherwise it keeps its own procedural room. One file per place.
/// Returning true means the place is fully built into `set`, the patient's seat included (roadside,
/// forest, ambulance, resus); the clinic and antenatal rooms keep the avatar's own stool / the scan couch.
/// The people of a place (crew, onlookers) are built separately by `people`, so a change of who is
/// there does not rebuild the place. See README.md in this folder.
@MainActor
enum PitchDressing {
    /// Who a dressed place shows. The default (all nil) is the pitch shots' cast.
    struct Cast: Equatable {
        /// Journey team member ids in the place ("sam", "lena", "omar", "priya"). nil: everyone the place has.
        var crew: Set<String>?
        /// Onlookers at the roadside / on the trail (a Studio scenario's background figures). nil: the place's default.
        var onlookers: Int?
        /// A Studio bystander stands at the place's `spots.bystander` (ScenarioStage builds it), so the
        /// onlooker who usually stands there steps aside.
        var speaker = false
    }

    /// Places that have a dressing. The night roadside keeps the procedural one.
    static func exists(_ kind: EnvironmentSet.Kind) -> Bool { kind != .roadsideNight }

    /// `set`: empty entity in avatar space (patient at the origin facing +Z, wearer ~1.7 m in front),
    /// added to the scene after this returns and removed on the next place change.
    /// `seat`: the patient's seat height. `avatarRoot`: the patient's root, parent of the place; light it here.
    static func build(_ kind: EnvironmentSet.Kind, into set: Entity, seat: Float, avatarRoot: Entity) -> Bool {
        PitchKit.clearLight(avatarRoot) // the previous place's light
        switch kind {
        case .clinic: return PitchClinic.build(into: set, seat: seat, avatarRoot: avatarRoot)
        case .antenatal: return PitchAntenatal.build(into: set, seat: seat, avatarRoot: avatarRoot)
        case .roadside: return PitchRoadside.build(into: set, seat: seat, night: false, forest: false, avatarRoot: avatarRoot)
        case .forest: return PitchRoadside.build(into: set, seat: seat, night: false, forest: true, avatarRoot: avatarRoot)
        case .roadsideNight: return PitchRoadside.build(into: set, seat: seat, night: true, forest: false, avatarRoot: avatarRoot)
        case .ambulance: return PitchAmbulance.build(into: set, seat: seat, avatarRoot: avatarRoot)
        case .traumaBay: return PitchTraumaBay.build(into: set, seat: seat, avatarRoot: avatarRoot)
        }
    }

    /// The place's own people (crew and onlookers) into `into` (avatar space, like `set`).
    static func people(_ kind: EnvironmentSet.Kind, cast: Cast, into: Entity) {
        switch kind {
        case .roadside: PitchRoadside.people(into, cast: cast, forest: false)
        case .forest: PitchRoadside.people(into, cast: cast, forest: true)
        case .ambulance: PitchAmbulance.people(into, cast: cast)
        case .traumaBay: PitchTraumaBay.people(into, cast: cast)
        case .clinic, .antenatal, .roadsideNight: break
        }
    }

    /// Where the crew member `id` stands (or sits) in the dressed place, feet on the floor; nil when the
    /// place has nobody for them (Sam drives the ambulance). ScenarioStage hangs names and speech there.
    static func crewSpot(_ kind: EnvironmentSet.Kind, _ id: String) -> SIMD3<Float>? {
        switch kind {
        case .roadside, .forest: PitchRoadside.crew[id]
        case .ambulance: PitchAmbulance.crew[id]
        case .traumaBay: PitchTraumaBay.crew[id]
        case .clinic, .antenatal, .roadsideNight: nil
        }
    }

    /// Outfits (PitchCrowd) for a Studio bystander and helper that no one else in the place wears.
    static func outfits(_ kind: EnvironmentSet.Kind) -> (bystander: String, helper: String) {
        switch kind {
        case .roadside: ("driver", "hiker_f")          // the onlooker in "driver" steps aside (Cast.speaker)
        case .forest: ("driver", "bystander_f2")
        default: ("bystander_m", "bystander_f2")
        }
    }

    /// Where a Studio scenario's bystander and helper stand in each dressed place: clear of the furniture,
    /// the crew and the panels beside the patient, and in the wearer's view.
    static func spots(_ kind: EnvironmentSet.Kind) -> (bystander: SIMD3<Float>, helper: SIMD3<Float>) {
        switch kind {
        case .clinic: ([1.25, 0, -0.75], [-1.35, 0, -0.55])
        case .antenatal: ([1.35, 0, -0.45], [-1.6, 0, -0.6])
        case .roadside: (PitchRoadside.speakerSpot(forest: false), [-1.7, 0, -0.85])
        case .forest: (PitchRoadside.speakerSpot(forest: true), [-1.7, 0, -0.85])
        case .ambulance: ([1.45, 0, 0.6], [-1.55, 0, 1.45])   // past the stretcher's foot end; by the bulkhead, clear of Lena
        case .traumaBay: ([1.95, 0, 0.35], [-1.75, 0, 0.3])
        case .roadsideNight: ([0.85, 0, -0.1], [-1.3, 0, -0.3])
        }
    }
}
