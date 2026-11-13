import Foundation

// Patient body behaviour: a pure, deterministic state machine. No RealityKit, no timers.
// PatientBehaviorController drives it; scripts/check_patient_behavior.sh tests it on macOS.

enum PatientState: String, Sendable {
    case standingIdle = "standing_idle"
    case sittingDown = "sitting_down"
    case seatedIdle = "seated_idle"
    case extendingArms = "extending_arms"
    case armsExtended = "arms_extended"
    case indicatingWrist = "indicating_wrist"
    case painRecoil = "pain_recoil"
    case returningToRest = "returning_to_rest"

    /// Seconds the body takes to reach this state's pose.
    var duration: Double {
        switch self {
        case .sittingDown: 1.8
        case .extendingArms, .standingIdle: 1.0
        case .indicatingWrist: 0.8
        case .painRecoil: 0.14
        default: 0.5
        }
    }

    /// Seconds the pose is held before the machine moves on by itself.
    var hold: Double {
        switch self {
        case .indicatingWrist: 1.8
        case .painRecoil: 0.65
        default: 0
        }
    }
}

/// The only body actions the voice agent (or anything else) may request.
enum PatientAction: String, CaseIterable, Sendable {
    case sitDown = "sit_down"
    case extendBothArms = "extend_both_arms"
    case relaxArms = "relax_arms"
    case indicateRightWrist = "indicate_right_wrist"
}

enum ActionResult: Equatable, Sendable {
    case success(String), invalidState(String), failure(String)

    /// What the voice agent gets back as the tool result.
    var text: String {
        switch self {
        case .success(let m): "success: \(m)"
        case .invalidState(let m): "invalid_state: \(m)"
        case .failure(let m): "failure: \(m)"
        }
    }
}

struct PatientBehavior: Equatable, Sendable {
    private(set) var state: PatientState
    /// Posture the patient returns to after a recoil or after indicating the wrist.
    private(set) var armsOut = false
    /// Whether the current recoil pulls the right arm away (strong pain) or is only a flinch.
    private(set) var withdrawArm = false
    /// False when only the primitive fallback body is available: the patient stays seated.
    let animated: Bool
    /// Lying on an examination couch (the ultrasound patient): examinable from the start, always in
    /// the model's rest pose. Stand, sit and arm movements do not apply to her.
    let recumbent: Bool

    init(animated: Bool = true, recumbent: Bool = false) {
        self.animated = animated
        self.recumbent = recumbent
        state = animated && !recumbent ? .standingIdle : .seatedIdle
    }

    /// Examination zones are reachable only once the patient is seated.
    var canExamine: Bool { state != .standingIdle && state != .sittingDown }

    mutating func request(_ action: PatientAction) -> ActionResult {
        if recumbent {
            return action == .relaxArms ? .success("The patient is already resting on the couch.")
                                        : .failure("This movement is not available: the patient is lying on the examination couch.")
        }
        switch (state, action) {
        case (.standingIdle, .sitDown):
            state = .sittingDown
            return .success("Alex is sitting down.")
        case (_, .sitDown):
            return .success("Alex is already seated.")
        case (.standingIdle, _):
            return .invalidState("Alex is standing. He has to sit down first.")
        case (.sittingDown, _):
            return .invalidState("Alex is still sitting down. Try again in a moment.")
        case (.painRecoil, _):
            return .invalidState("Alex is reacting to pain. Try again in a moment.")
        default:
            break
        }
        guard animated else {
            return action == .relaxArms ? .success("Alex's arms are already resting.")
                                        : .failure("This movement is not available.")
        }
        switch action {
        case .extendBothArms:
            if armsOut, state == .armsExtended || state == .extendingArms {
                return .success("Alex is already holding both arms out.")
            }
            armsOut = true
            state = .extendingArms
            return .success("Alex is holding both arms out.")
        case .relaxArms:
            if !armsOut, state != .indicatingWrist { return .success("Alex's arms are already resting.") }
            armsOut = false
            state = .returningToRest
            return .success("Alex is resting his arms.")
        case .indicateRightWrist:
            if state == .indicatingWrist { return .success("Alex is already showing his right wrist.") }
            state = .indicatingWrist
            return .success("Alex is showing his right wrist.")
        case .sitDown:
            return .success("Alex is already seated.")
        }
    }

    /// A real examination hurt. Returns true when a recoil starts (never twice at once).
    mutating func pain(withdrawArm: Bool) -> Bool {
        guard animated, !recumbent, canExamine, state != .painRecoil else { return false }
        self.withdrawArm = withdrawArm
        state = .painRecoil
        return true
    }

    /// The current state's animation and hold are over.
    mutating func finished() {
        switch state {
        case .sittingDown: state = .seatedIdle
        case .extendingArms: state = .armsExtended
        case .indicatingWrist, .painRecoil: state = .returningToRest
        case .returningToRest: state = armsOut ? .armsExtended : .seatedIdle
        case .standingIdle, .seatedIdle, .armsExtended: break
        }
    }

    /// Target pose: degrees about the model's X axis (positive = forward/down), on top of the
    /// seated rest pose the model was exported in. Always the same joint set.
    var pose: [String: Float] {
        var p: [String: Float] = [
            "thigh_l": 0, "thigh_r": 0, "calf_l": 0, "calf_r": 0, "upperarm_l": 0, "upperarm_r": 0,
            "lowerarm_l": 0, "lowerarm_r": 0, "spine_01": 0, "head": 0,
        ]
        if state == .standingIdle {
            // legs straight, left arm hanging, injured right arm held guarded in front
            p.merge(["thigh_l": 86, "thigh_r": 86, "calf_l": -86, "calf_r": -86,
                     "upperarm_l": 8, "lowerarm_l": 48, "lowerarm_r": 10]) { $1 }
            return p
        }
        if armsOut {
            p.merge(["upperarm_l": -55, "upperarm_r": -55, "lowerarm_l": 35, "lowerarm_r": 35]) { $1 }
        }
        switch state {
        case .indicatingWrist: // lifts the right wrist and looks at it
            p["upperarm_r"] = armsOut ? -62 : -30
            p["lowerarm_r"] = armsOut ? 12 : -28
            p["head"] = 10
        case .painRecoil: // leans back; strong pain also pulls the right arm in
            p["spine_01"] = -7
            p["head"] = -6
            if withdrawArm {
                p["upperarm_r", default: 0] += 24
                p["lowerarm_r", default: 0] -= 22
            }
        default:
            break
        }
        return p
    }

    /// Peak forward lean of the torso (degrees) in the middle of the move.
    var lean: Float { state == .sittingDown ? 24 : 0 }
}
