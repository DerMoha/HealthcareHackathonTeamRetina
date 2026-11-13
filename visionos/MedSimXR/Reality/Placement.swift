import ARKit
import QuartzCore
import RealityKit

/// Places the stool ~1.7 m in front (the standing patient is ~0.4 m closer) of the wearer using the ARKit device pose.
@MainActor
final class Placement {
    private let session = ARKitSession()
    private let world = WorldTrackingProvider()
    private var started = false
    static let distance: Float = 1.7
    /// Metres to the wearer's right: just enough that the patient's head does not cover the
    /// control window, which opens straight ahead and further away.
    static let lateral: Float = 0.45

    /// Fallback when tracking is unavailable (simulator, denied, not yet tracking).
    static let fallback = place(head: .zero, forward: [0, 0, -1])

    /// Patient on the floor, `distance` ahead and `lateral` to the right of the head, turned to face it.
    static func place(head: SIMD3<Float>, forward: SIMD3<Float>) -> Transform {
        let right = simd_cross(forward, [0, 1, 0])
        var position = head + forward * distance + right * lateral
        let toWearer = simd_normalize(head - position)
        let yaw = atan2(toWearer.x, toWearer.z) // patient +Z faces the wearer
        position += debugOffset
        return Transform(rotation: simd_quatf(angle: yaw, axis: [0, 1, 0]), translation: position)
    }

    /// Test hook: launch argument `-patientOffset "@x,y,z"` (the "@" keeps a leading minus from
    /// being read as another argument) shifts the patient (metres), e.g. to
    /// bring the whole body into the simulator's fixed camera view.
    private static let debugOffset: SIMD3<Float> = {
        let parts = (UserDefaults.standard.string(forKey: "patientOffset") ?? "").dropFirst().split(separator: ",").compactMap { Float($0) }
        return parts.count == 3 ? [parts[0], parts[1], parts[2]] : .zero
    }()

    func transform() async -> Transform {
        if !started, WorldTrackingProvider.isSupported {
            do { try await session.run([world]); started = true } catch { return Self.fallback }
        }
        guard started else { return Self.fallback }
        for _ in 0..<15 {
            if let a = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()), a.isTracked {
                let m = a.originFromAnchorTransform
                let head = SIMD3<Float>(m.columns.3.x, 0, m.columns.3.z)
                var fwd = SIMD3<Float>(-m.columns.2.x, 0, -m.columns.2.z)
                if simd_length(fwd) < 0.1 { break } // looking straight up/down
                return Self.place(head: head, forward: simd_normalize(fwd))
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return Self.fallback
    }
}
