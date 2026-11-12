import ARKit
import RealityKit

/// Direct touch: index fingertip entering a zone sphere triggers `examine`.
/// Gaze+pinch keeps working regardless. Unverified on hardware.
@MainActor
final class FingertipExaminer {
    private let session = ARKitSession()
    private let hands = HandTrackingProvider()

    func run(avatar: PatientAvatar, model: AppModel) async {
        guard HandTrackingProvider.isSupported else { return }
        let auth = await session.requestAuthorization(for: [.handTracking])
        guard auth[.handTracking] == .allowed else { return }
        do { try await session.run([hands]) } catch { return }
        var inside: Set<String> = []
        for await update in hands.anchorUpdates {
            if Task.isCancelled { break }
            let a = update.anchor
            guard a.isTracked, let tip = a.handSkeleton?.joint(.indexFingerTip), tip.isTracked else { continue }
            let m = a.originFromAnchorTransform * tip.anchorFromJointTransform
            let p = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
            for z in model.zones {
                guard let e = avatar.zoneEntities.first(where: { $0.name == z.id }) else { continue }
                let key = "\(a.chirality)-\(z.id)"
                if simd_distance(e.position(relativeTo: nil), p) < z.radius {
                    if inside.insert(key).inserted { await model.examine(zoneId: z.id) }
                } else {
                    inside.remove(key)
                }
            }
        }
        session.stop()
    }
}
