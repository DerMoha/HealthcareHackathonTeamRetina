import RealityKit

/// Pitch dressing: the clinic room (wrist case). Return false to keep EnvironmentSet's procedural place.
@MainActor
enum PitchClinic {
    static func build(into set: Entity, seat: Float, avatarRoot: Entity) -> Bool {
        false
    }
}
