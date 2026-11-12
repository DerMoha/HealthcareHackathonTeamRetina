import ARKit
import QuartzCore
import RealityKit

/// Places the patient ~1.4 m in front of the wearer using the ARKit device pose.
@MainActor
final class Placement {
    private let session = ARKitSession()
    private let world = WorldTrackingProvider()
    private var started = false
    static let distance: Float = 1.4

    /// Fallback when tracking is unavailable (simulator, denied, not yet tracking).
    static let fallback = Transform(translation: [0, 0, -distance])

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
                fwd = simd_normalize(fwd)
                let yaw = atan2(-fwd.x, -fwd.z) // patient +Z faces the wearer
                return Transform(rotation: simd_quatf(angle: yaw, axis: [0, 1, 0]), translation: head + fwd * Self.distance)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return Self.fallback
    }
}
