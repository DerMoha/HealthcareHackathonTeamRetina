import RealityKit

/// Pitch dressing: the resus bay (rt-05..08). Return false to keep EnvironmentSet's procedural place.
@MainActor
enum PitchTraumaBay {
    static func build(into set: Entity, seat: Float, avatarRoot: Entity) -> Bool {
        false
    }
}
