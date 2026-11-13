import RealityKit

/// Pitch dressing: the roadside, by day and at night (road trauma rt-01..03). Return false to keep EnvironmentSet's procedural place.
@MainActor
enum PitchRoadside {
    static func build(into set: Entity, seat: Float, night: Bool, avatarRoot: Entity) -> Bool {
        false
    }
}
