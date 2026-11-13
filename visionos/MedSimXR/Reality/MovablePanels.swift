import RealityKit
import SwiftUI

/// Makes the floating SwiftUI panels movable. Each panel sits on its own mover entity with a
/// grab bar under it (like a window bar): pinch and drag the bar to move the panel, use both
/// hands to turn or resize it. Only the bar is a hit target, so the panel's buttons keep working.
@MainActor
final class MovablePanels {
    static let handleName = "panel_grab_bar"
    /// Marks the bars so the scene's own tap and drag gestures leave them alone.
    struct GrabBar: Component {}

    private struct Panel {
        let mover: Entity
        let view: ViewAttachmentEntity
        let handle: Entity
        var home: Transform
    }
    private var panels: [Panel] = []
    /// Keeps the per-frame bar layout alive for the scene's lifetime.
    var updates: EventSubscription?

    /// Puts `view` on a new mover under `parent` at `position`, turned by `yaw` (radians) and
    /// scaled by `scale`. Returns the mover, which is what moves from then on.
    @discardableResult
    func add(_ view: ViewAttachmentEntity, to parent: Entity, at position: SIMD3<Float> = .zero,
             yaw: Float = 0, scale: Float = 1) -> Entity {
        let mover = Entity()
        mover.name = "panel_mover"
        mover.transform = Transform(scale: [scale, scale, scale], rotation: simd_quatf(angle: yaw, axis: [0, 1, 0]),
                                    translation: position)
        var manipulation = ManipulationComponent()
        manipulation.releaseBehavior = .stay
        manipulation.audioConfiguration = .none
        mover.components.set(manipulation)
        parent.addChild(mover)
        mover.addChild(view)

        let handle = ModelEntity(mesh: .generateBox(width: 0.1, height: 0.01, depth: 0.004, cornerRadius: 0.005),
                                 materials: [UnlitMaterial(color: UIColor(white: 1, alpha: 0.6))])
        handle.name = Self.handleName
        handle.components.set(CollisionComponent(shapes: [.generateBox(width: 0.16, height: 0.04, depth: 0.02)]))
        handle.components.set(InputTargetComponent())
        handle.components.set(HoverEffectComponent())
        handle.components.set(ManipulationComponent.HitTarget(redirectedEntity: mover))
        handle.components.set(GrabBar())
        mover.addChild(handle)
        panels.append(Panel(mover: mover, view: view, handle: handle, home: mover.transform))
        return mover
    }

    /// Call after the scene has placed the panels: `reset()` returns them here.
    func markHomes() {
        for i in panels.indices { panels[i].home = panels[i].mover.transform }
    }

    /// Every panel back to where the scene put it (used when the learner re-centres the patient).
    func reset() {
        for p in panels { p.mover.move(to: p.home, relativeTo: p.mover.parent, duration: 0.3) }
    }

    /// Keeps each bar just under its panel as the content changes size; hides it while the
    /// panel shows nothing.
    func layout() {
        for p in panels {
            let b = p.view.attachment.bounds
            let visible = p.view.isEnabled && b.extents.x > 0.01 && b.extents.y > 0.01
            p.handle.isEnabled = visible && !SmokeLog.pitch
            guard visible else { continue }
            p.handle.position = p.view.convert(position: [b.center.x, b.min.y - 0.025, b.center.z], to: p.mover)
        }
    }
}
