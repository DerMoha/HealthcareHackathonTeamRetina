import Foundation
// Self-check for the patient behaviour state machine. Run: scripts/check_patient_behavior.sh
var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("FAIL \(what)") }
}
func ok(_ r: ActionResult) -> Bool { if case .success = r { return true }; return false }
func invalid(_ r: ActionResult) -> Bool { if case .invalidState = r { return true }; return false }

var b = PatientBehavior()
check(b.state == .standingIdle && !b.canExamine, "starts standing, not examinable")
check(invalid(b.request(.extendBothArms)) && b.state == .standingIdle, "no arm extension while standing")
check(invalid(b.request(.indicateRightWrist)), "no wrist indication while standing")
check(!b.pain(withdrawArm: true) && b.state == .standingIdle, "no recoil while standing")

check(ok(b.request(.sitDown)) && b.state == .sittingDown, "sit_down starts sitting")
check(ok(b.request(.sitDown)) && b.state == .sittingDown, "repeated sit_down does not restart")
check(invalid(b.request(.extendBothArms)) && b.state == .sittingDown, "busy while sitting down")
check(!b.canExamine, "not examinable while sitting down")
b.finished()
check(b.state == .seatedIdle && b.canExamine, "seated and examinable")
check(b.pose.values.allSatisfy { $0 == 0 }, "seated pose is the model's rest pose")
check(ok(b.request(.sitDown)) && b.state == .seatedIdle, "sit_down when seated is a no-op success")
check(ok(b.request(.relaxArms)) && b.state == .seatedIdle, "relax when resting is a no-op success")

check(ok(b.request(.extendBothArms)) && b.state == .extendingArms, "extend starts")
let extending = b
check(ok(b.request(.extendBothArms)) && b == extending, "repeated extend does not restart")
// interrupted: relax in the middle of extending, then extend again
check(ok(b.request(.relaxArms)) && b.state == .returningToRest && !b.armsOut, "relax interrupts extend")
check(ok(b.request(.extendBothArms)) && b.state == .extendingArms, "extend interrupts the return")
b.finished()
check(b.state == .armsExtended && b.pose["upperarm_r"]! < 0, "arms extended")

// pain from the examination pose returns to the examination pose
check(b.pain(withdrawArm: true) && b.state == .painRecoil, "recoil starts")
check(!b.pain(withdrawArm: true), "no second recoil while recoiling")
check(invalid(b.request(.relaxArms)) && b.state == .painRecoil, "actions refused during recoil")
check(b.pose["upperarm_r"]! > PatientBehavior().pose["upperarm_r"]! - 55, "recoil pulls the arm back")
b.finished()
check(b.state == .returningToRest, "recoil then returns")
b.finished()
check(b.state == .armsExtended, "back to the examination pose after recoil")

check(ok(b.request(.indicateRightWrist)) && b.state == .indicatingWrist, "indicate from arms extended")
check(b.pain(withdrawArm: false) && b.state == .painRecoil && b.pose["upperarm_r"] == -55, "flinch keeps the arm")
b.finished(); b.finished()
check(b.state == .armsExtended, "arms still out after flinch")
check(ok(b.request(.indicateRightWrist)), "indicate again")
b.finished(); b.finished()
check(b.state == .armsExtended, "indicate returns to arms extended")
check(ok(b.request(.relaxArms)), "relax")
b.finished()
check(b.state == .seatedIdle, "seated after relax")
check(ok(b.request(.indicateRightWrist)), "indicate from rest")
b.finished(); b.finished()
check(b.state == .seatedIdle, "indicate returns to rest")

// only the four identifiers exist
check(PatientAction(rawValue: "wave") == nil && PatientAction(rawValue: "rotate_joint") == nil, "unknown actions rejected")
check(PatientAction.allCases.map(\.rawValue) == ["sit_down", "extend_both_arms", "relax_arms", "indicate_right_wrist"], "action list")

// primitive fallback body: seated from the start, movements fail honestly
var f = PatientBehavior(animated: false)
check(f.state == .seatedIdle && f.canExamine, "fallback starts seated")
check(ok(f.request(.sitDown)), "fallback sit is a no-op success")
if case .failure = f.request(.extendBothArms) {} else { check(false, "fallback extend reports failure") }
check(!f.pain(withdrawArm: true) && f.state == .seatedIdle, "fallback has no joint recoil")

if failures > 0 { fatalError() }

// recumbent patient (ultrasound couch): examinable at once, stand/sit/arm movements do not apply
var r = PatientBehavior(animated: true, recumbent: true)
check(r.state == .seatedIdle && r.canExamine, "recumbent patient is examinable from the start")
for action in PatientAction.allCases where action != .relaxArms {
    let before = r
    let result = r.request(action)
    check({ if case .failure = result { return true }; return false }() && r == before, "\(action.rawValue) does not run on a recumbent patient")
}
check(ok(r.request(.relaxArms)) && r.state == .seatedIdle, "relax is a harmless no-op")
check(!r.pain(withdrawArm: true) && r.state == .seatedIdle, "no recoil animation for the recumbent pose")
check(r.pose.values.allSatisfy { $0 == 0 }, "recumbent pose is the model's rest pose")
check(PatientBehavior(animated: true).recumbent == false, "default is not recumbent")

print(failures == 0 ? "patient behavior: all assertions passed" : "patient behavior: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
