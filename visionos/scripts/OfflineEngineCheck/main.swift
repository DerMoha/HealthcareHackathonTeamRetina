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

extension OfflineClinicalEngine {
    func diagnose(_ diagnosis: String) async throws -> Feedback { try await diagnose(diagnosis, notes: ClinicalNotes()) }
}
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
    check(f.categories.allSatisfy { $0.criteria.isEmpty } && f.strengths.isEmpty && f.missed.isEmpty, "rubric detail redacted before diagnosis")
    let g = try await e.diagnose("unsure")
    check(!g.transcriptAvailable && g.summary.hasPrefix("No conversation transcript"), "empty run summary")
    check(!met(g, "respectful").met, "learner_avoided needs a learner turn")
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
    let f = try await e.diagnose("unsure")
    check(!met(f, "permission").met, "permission after exam earns nothing")
    check(met(f, "responded_to_pain").met, "empathy after painful exam earns responded_to_pain")
}
do {
    let e = try await fresh()
    await say(e, "I'm sorry about your fall.")
    _ = try await e.examine(zoneId: snuff, action: "palpation")
    let f = try await e.diagnose("unsure")
    check(!met(f, "responded_to_pain").met, "empathy before painful exam does not count")
}

// Whole-word keyword matching: former substring false positives must not score
do {
    let e = try await fresh()
    for t in ["I once toured Scotland by a waterfall.", "That is an accurate broadcast.",
              "What a scandal, I'm a bit worried.", "Where is the doctor? Let me scan it quickly.",
              "Can I ask you something?"] { await say(e, t) }
    let f = try await e.diagnose("unsure")
    for id in ["mechanism", "severity", "introduction", "permission"] {
        check(!met(f, id).met, "substring false positive on \(id)")
    }
    check(met(f, "location").met, "'Where ...' still counts as a location question")
}
do {
    let e = try await fresh()
    await say(e, "Hi, I\u{2019}m a medical student. Any numbness or tingling?")
    await say(e, "Is it okay if I examine your wrist?")
    _ = try await e.examine(zoneId: snuff, action: "palpation")
    await say(e, "I apologise, I\u{2019}ll be gentle.")
    let f = try await e.diagnose("Scaphoidfraktur, X-rays and a CT needed")
    for id in ["introduction", "associated_symptoms", "permission", "responded_to_pain", "scaphoid_considered", "further_assessment"] {
        check(met(f, id).met, "stem/apostrophe match on \(id)")
    }
}

// Notes are compared with the record and never earn examination points
do {
    let e = try await fresh()
    let f = try await e.diagnose("scaphoid fracture", notes: ClinicalNotes(
        history: "Fell off bike yesterday.", examination: "Marked snuffbox tenderness on the right, left wrist normal."))
    check(f.categories.first { $0.id == "examination" }?.score == 0, "claimed examination earns no points")
    check(f.documentation.first { $0.criterionId == "examined_snuffbox" }?.status == "unsupported", "claimed exam flagged unsupported")
    check(f.summary.contains("not supported"), "summary mentions unsupported notes")
}
do {
    let e = try await fresh()
    _ = try await e.examine(zoneId: snuff, action: "palpation")
    let pre = try await e.feedback()
    check(pre.relevantFindings == ["Right wrist, thumb side: marked tenderness (pain 8/10)"] && pre.documentation.isEmpty, "neutral label before diagnosis")
    let f = try await e.diagnose("sprain", notes: ClinicalNotes(assessment: "Plan: X-ray."))
    check(met(f, "further_assessment").met, "written plan counts as reasoning")
    check(f.documentation.first { $0.criterionId == "examined_snuffbox" }?.status == "undocumented", "examined but not written down")
}

// Investigations and management (separate 20 points)
do {
    let e = try await fresh()
    let x = try await e.orderInvestigation("right_wrist_xray")
    check(x.impression == "No definite fracture visible." && x.image == "wrist_xray_pa" && x.repeatCount == 1, "x-ray result")
    check(!(x.label + x.title + x.report + x.impression).lowercased().contains("scaphoid fracture"), "x-ray reveals nothing")
    do { _ = try await e.orderInvestigation("biopsy"); check(false, "unknown investigation should throw") } catch {}
    await say(e, "I will order an MRI and put you in a splint.")
    let f = try await e.diagnose("Wrist sprain", notes: ClinicalNotes(
        interpretation: "X-ray normal, fracture ruled out.", management: "Just a sprain, no follow-up."))
    check(f.maxScore == 100 && f.management.maxScore == 20 && f.management.score == 4, "unsafe plan scores 4/20, total stays /100")
    check(f.investigations == ["Right wrist radiographs: No definite fracture visible."], "ordered list")
    let m = try await e.orderInvestigation("right_wrist_mri")
    check(m.image == nil && m.impression.contains("scaphoid"), "mri result")
    let g = try await e.diagnose("Scaphoid fracture", notes: ClinicalNotes(
        interpretation: "Occult fracture not excluded by X-ray; MRI confirms it.", management: "Thumb spica cast."))
    check(g.management.score == 20, "safe plan scores 20/20")
    _ = try await e.reset()
    check(try await e.feedback().investigations.isEmpty, "reset clears orders")
}

// Measurement and orthosis fitting (separate 20 points)
do {
    let e = try await fresh()
    let good = OrthosisFit(size: "medium", orientation: "thumb_radial", offsetCm: 3, tightness: "snug")
    let c = try await e.recordMeasurement("right_wrist_circumference", valueCm: 99)
    check(c.valueCm == 16.8 && c.source == "case", "circumference is predefined")
    check(try await e.recordMeasurement("right_forearm_length", valueCm: 25.26).valueCm == 25.3, "length from avatar")
    do { _ = try await e.recordMeasurement("right_forearm_length", valueCm: nil); check(false, "length needs a value") } catch {}
    let before = try await e.fittingCheck("neurovascular")
    check(before.phase == "before" && before.finding!.contains("under 2 seconds"), "baseline neurovascular")
    var tight = good; tight.tightness = "tight"
    _ = try await e.recordFit(tight)
    let t = try await e.fittingCheck("comfort")
    check(!t.comfortable && t.patientResponse.contains("too tight") && t.animation == "flinch", "too tight outcome")
    check(try await e.fittingCheck("neurovascular").finding!.contains("about 3 seconds"), "tight neurovascular")
    var wrong = good; wrong.orientation = "thumb_ulnar"
    _ = try await e.recordFit(wrong)
    check(try await e.fittingCheck("comfort").patientResponse.contains("wrong side"), "orientation outcome")
    _ = try await e.recordFit(good)
    _ = try await e.fittingCheck("neurovascular"); _ = try await e.fittingCheck("comfort")
    let f = try await e.diagnose("scaphoid fracture")
    check(f.fitting.score == 20 && f.maxScore == 100 && f.fitting.reference?.size == "medium", "perfect fitting 20/20, total /100")
    _ = try await e.recordFit(nil)
    check(try await e.feedback().fitting.finalFit == nil, "removed support")
}

// Optional parity replay against the backend's fixtures
let fx = root.appendingPathComponent("backend/tests/fixtures")
if let inData = try? Data(contentsOf: fx.appendingPathComponent("parity_input.json")),
   let exData = try? Data(contentsOf: fx.appendingPathComponent("parity_expected.json")) {
    let input = try JSONSerialization.jsonObject(with: inData) as! [String: Any]
    let e = try await fresh()
    var f = try await e.feedback()
    for step in input["steps"] as? [[String: Any]] ?? [] {
        switch step["op"] as? String {
        case "examine":
            _ = try await e.examine(zoneId: step["body_part"] as! String, action: step["action"] as? String ?? "palpation")
        case "interaction":
            await say(e, step["text"] as! String, SpeakerRole(rawValue: step["role"] as! String) ?? .learner)
        case "measure":
            let b = step["body"] as! [String: Any]
            _ = try await e.recordMeasurement(b["measurement_id"] as! String, valueCm: b["value_cm"] as? Double)
        case "check":
            _ = try await e.fittingCheck((step["body"] as! [String: Any])["check"] as! String)
        case "fit":
            let b = (step["body"] as! [String: Any])["fit"] as? [String: Any]
            _ = try await e.recordFit(b.map {
                OrthosisFit(size: $0["size"] as! String, orientation: $0["orientation"] as! String,
                            offsetCm: $0["offset_cm"] as! Double, tightness: $0["tightness"] as! String)
            })
        case "investigate":
            _ = try await e.orderInvestigation(step["investigation_id"] as! String)
        default:
            let n = step["notes"] as? [String: String] ?? [:]
            f = try await e.diagnose(step["diagnosis"] as! String, notes: ClinicalNotes(
                history: n["history"] ?? "", examination: n["examination"] ?? "", assessment: n["assessment"] ?? "",
                interpretation: n["interpretation"] ?? "", management: n["management"] ?? "", followUp: n["follow_up"] ?? ""))
        }
    }
    let enc = JSONEncoder.medsim
    var got = try JSONSerialization.jsonObject(with: enc.encode(f)) as! [String: Any]
    var want = try JSONSerialization.jsonObject(with: exData) as! [String: Any]
    got["session_id"] = nil; want["session_id"] = nil
    var diffs = 0
    func diff(_ a: Any?, _ b: Any?, _ path: String) {
        // Swift omits nil keys, the backend writes JSON null: same thing.
        let a: Any? = a is NSNull ? nil : a, b: Any? = b is NSNull ? nil : b
        if let a = a as? [String: Any], let b = b as? [String: Any] {
            for k in Set(a.keys).union(b.keys).sorted() { diff(a[k], b[k], "\(path).\(k)") }
        } else if let a = a as? [Any], let b = b as? [Any], a.count == b.count {
            for i in a.indices { diff(a[i], b[i], "\(path)[\(i)]") }
        } else if "\(a ?? "nil")" != "\(b ?? "nil")" {
            diffs += 1; print("PARITY DIFF \(path)\n  swift:   \(a ?? "nil")\n  backend: \(b ?? "nil")")
        }
    }
    diff(got, want, "")
    print("parity: \(diffs) field difference(s)"); failures += diffs
} else {
    print("parity: fixtures not present, skipped")
}

print(failures == 0 ? "OfflineEngineCheck: all assertions passed" : "OfflineEngineCheck: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
