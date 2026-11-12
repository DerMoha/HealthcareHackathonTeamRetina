import Foundation

// Usage: OfflineEngineCheck <repo-root>

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if !cond { failures += 1; print("FAIL: \(msg)") }
}

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let data = try Data(contentsOf: root.appendingPathComponent("scenarios/wrist_trauma_001.json"))
let caseId = "wrist_trauma_001"
let snuff = "right_anatomical_snuffbox", forearm = "right_distal_forearm", leftWrist = "left_wrist"

@MainActor func fresh() async throws -> OfflineClinicalEngine {
    let e = try OfflineClinicalEngine(scenarioData: data)
    _ = try await e.startSession(caseId: caseId)
    return e
}
@MainActor func say(_ e: OfflineClinicalEngine, _ text: String, _ role: SpeakerRole = .learner) async {
    await e.recordInteraction(TranscriptTurn(role: role, text: text))
}
func met(_ f: Feedback, _ id: String) -> CriterionResult {
    f.categories.flatMap(\.criteria).first { $0.id == id }!
}

// Findings, errors, repeat_count, reset
do {
    let e = try await fresh()
    let a = try await e.examine(zoneId: snuff, action: "palpation")
    check(a.finding == "marked_tenderness" && a.painLevel == 8 && a.reaction == "strong_pain" && a.animation == "arm_withdrawal", "snuffbox finding")
    let b = try await e.examine(zoneId: forearm, action: "palpation")
    check(b.finding == "no_focal_tenderness" && b.painLevel == 1, "forearm finding")
    let c = try await e.examine(zoneId: leftWrist, action: "palpation")
    check(c.finding == "normal" && c.painLevel == 0, "left wrist finding")
    check(a.repeatCount == 1, "first repeat_count")
    check(try await e.examine(zoneId: snuff, action: "palpation").repeatCount == 2, "repeat_count increments")
    do { _ = try await e.examine(zoneId: "nope", action: "palpation"); check(false, "unknown zone should throw") } catch {}
    _ = try await e.reset()
    check(try await e.examine(zoneId: snuff, action: "palpation").repeatCount == 1, "reset clears exam counts")
    await say(e, "What happened?")
    _ = try await e.reset()
    let f = try await e.feedback()
    check(!f.transcriptAvailable && f.relevantFindings.isEmpty && f.totalScore == 0, "reset clears transcript/exams")
}

// Perfect run
do {
    let e = try await fresh()
    for t in ["Hello, I'm a medical student. What brings you here today?", "When did it start and how did you fall?",
              "Where exactly does it hurt? How bad is the pain on a scale from zero to ten?",
              "Any numbness or tingling?", "Is it okay if I examine your wrist?"] { await say(e, t) }
    _ = try await e.examine(zoneId: snuff, action: "palpation")
    await say(e, "I'm sorry, I know that hurt.")
    _ = try await e.examine(zoneId: leftWrist, action: "palpation")
    _ = try await e.examine(zoneId: forearm, action: "palpation")
    await say(e, "I suspect a scaphoid fracture, we need an X-ray.")
    let f = try await e.diagnose("Suspected scaphoid fracture")
    check(f.totalScore == 100 && f.maxScore == 100, "perfect run scores 100/100, got \(f.totalScore)/\(f.maxScore)")
    check(f.diagnosticAssessment.verdict == "correct" && f.diagnosticAssessment.expected != nil, "verdict correct")
    check(f.missed.isEmpty && f.strengths.count == 15, "no missed items, 15 strengths")
    check(f.relevantFindings.first == "Right anatomical snuffbox: marked tenderness (pain 8/10)", "relevant finding format")
    check(!f.nextSteps.isEmpty && f.transcriptAvailable, "next steps and transcript")
}

// Empty run
do {
    let e = try await fresh()
    let f = try await e.feedback()
    check(f.diagnosticAssessment.verdict == "not_submitted" && f.diagnosticAssessment.expected == nil && f.nextSteps.isEmpty, "empty run hides hidden data")
    check(!f.transcriptAvailable && f.summary.hasPrefix("No conversation transcript"), "empty run summary")
    check(!met(f, "respectful").met, "learner_avoided needs a learner turn")
}

// Partial diagnosis, permission ordering, pain response ordering
do {
    let e = try await fresh()
    let f = try await e.diagnose("wrist fracture")
    let s = met(f, "scaphoid_considered")
    check(s.points == 3 && !s.met && f.diagnosticAssessment.verdict == "partial", "partial diagnosis gives half points")
}
do {
    let e = try await fresh()
    _ = try await e.examine(zoneId: snuff, action: "palpation")
    await say(e, "Is it okay if I examine your wrist?")
    await say(e, "I'm sorry, I know that hurt.")
    let f = try await e.feedback()
    check(!met(f, "permission").met, "permission after exam earns nothing")
    check(met(f, "responded_to_pain").met, "empathy after painful exam earns responded_to_pain")
}
do {
    let e = try await fresh()
    await say(e, "I'm sorry about your fall.")
    _ = try await e.examine(zoneId: snuff, action: "palpation")
    let f = try await e.feedback()
    check(!met(f, "responded_to_pain").met, "empathy before painful exam does not count")
}

// Optional parity replay against the backend's fixtures
let fx = root.appendingPathComponent("backend/tests/fixtures")
if let inData = try? Data(contentsOf: fx.appendingPathComponent("parity_input.json")),
   let exData = try? Data(contentsOf: fx.appendingPathComponent("parity_expected.json")) {
    let input = try JSONSerialization.jsonObject(with: inData) as! [String: Any]
    let e = try await fresh()
    for ev in input["events"] as? [[String: Any]] ?? [] {
        if ev["type"] as? String == "examine" {
            _ = try await e.examine(zoneId: ev["body_part"] as! String, action: ev["action"] as? String ?? "palpation")
        } else {
            await say(e, ev["text"] as! String, SpeakerRole(rawValue: ev["role"] as! String) ?? .learner)
        }
    }
    let f: Feedback
    if let d = input["diagnosis"] as? String { f = try await e.diagnose(d) } else { f = try await e.feedback() }
    let enc = JSONEncoder.medsim
    var got = try JSONSerialization.jsonObject(with: enc.encode(f)) as! [String: Any]
    var want = try JSONSerialization.jsonObject(with: exData) as! [String: Any]
    got["session_id"] = nil; want["session_id"] = nil
    var diffs = 0
    func diff(_ a: Any?, _ b: Any?, _ path: String) {
        if let a = a as? [String: Any], let b = b as? [String: Any] {
            for k in Set(a.keys).union(b.keys).sorted() { diff(a[k], b[k], "\(path).\(k)") }
        } else if let a = a as? [Any], let b = b as? [Any], a.count == b.count {
            for i in a.indices { diff(a[i], b[i], "\(path)[\(i)]") }
        } else if "\(a ?? "nil")" != "\(b ?? "nil")" {
            diffs += 1; print("PARITY DIFF \(path)\n  swift:   \(a ?? "nil")\n  backend: \(b ?? "nil")")
        }
    }
    diff(got, want, "")
    print("parity: \(diffs) field difference(s)")
} else {
    print("parity: fixtures not present, skipped")
}

print(failures == 0 ? "OfflineEngineCheck: all assertions passed" : "OfflineEngineCheck: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
