import Foundation
import Observation

/// Owns the patient's body state and runs its animations one at a time.
/// Every body movement goes through here: voice tool calls, debug buttons, pain reactions.
@MainActor
@Observable
final class PatientBehaviorController {
    private(set) var machine = PatientBehavior()
    /// Set by the immersive view: moves the avatar to `machine.pose`. Nil = no avatar on screen.
    @ObservationIgnored private var animate: ((PatientBehavior) async -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?

    var state: PatientState { machine.state }
    var canExamine: Bool { machine.canExamine }

    func attach(animated: Bool, animate: @escaping (PatientBehavior) async -> Void) {
        self.animate = animate
        if animated != machine.animated { machine = PatientBehavior(animated: animated) }
        run()
    }

    /// New encounter: the patient is standing again.
    func reset() {
        machine = PatientBehavior(animated: machine.animated)
        SmokeLog.mark("behavior reset state=\(state.rawValue)")
        run()
    }

    /// `raw` comes from the LLM: anything outside `PatientAction` is rejected here.
    func perform(_ raw: String) -> ActionResult {
        guard let action = PatientAction(rawValue: raw) else {
            return .failure("Unknown action. Allowed: \(PatientAction.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        let before = machine
        let result = machine.request(action)
        if machine != before {
            SmokeLog.mark("behavior \(before.state.rawValue) -> \(state.rawValue)")
            run()
        }
        return result
    }

    func pain(withdrawArm: Bool) {
        let before = state
        guard machine.pain(withdrawArm: withdrawArm) else { return }
        SmokeLog.mark("behavior \(before.rawValue) -> \(state.rawValue)")
        run()
    }

    /// Animates to the current state, then follows the machine until it rests. Replaces any
    /// animation still running, so an interrupted move continues from wherever the body is.
    private func run() {
        task?.cancel()
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                let current = self.machine
                await self.animate?(current)
                try? await Task.sleep(nanoseconds: UInt64(current.state.hold * 1_000_000_000))
                if Task.isCancelled { return }
                self.machine.finished()
                if self.machine == current { return }
                SmokeLog.mark("behavior \(current.state.rawValue) -> \(self.state.rawValue)")
            }
        }
    }
}
