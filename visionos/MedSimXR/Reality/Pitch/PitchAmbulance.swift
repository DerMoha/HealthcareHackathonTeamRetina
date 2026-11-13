import RealityKit

/// Pitch dressing: the back of the ambulance (rt-04). Return false to keep EnvironmentSet's procedural place.
@MainActor
enum PitchAmbulance {
    static func build(into set: Entity, seat: Float, avatarRoot: Entity) -> Bool {
        false
    }
}
