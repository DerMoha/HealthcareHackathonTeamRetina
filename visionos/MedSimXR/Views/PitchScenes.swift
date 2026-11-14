import SwiftUI

/// Staged scenes for pitch screenshots (launch argument `-pitch`, run by visionos/scripts/pitch_shots.sh).
/// Each scene is built through the same model calls the real controls make, then held still while
/// the script takes the screenshot. `-pitchHold <scene>` stops at that scene and keeps it on screen.
/// Pitch mode also tidies the room: no main window, no grab bars, no closed-notebook button, no
/// stand-in crew bodies, and spoken lines shown as subtitles (a slide has no sound).
@MainActor @Observable
final class Pitch {
    static let shared = Pitch()

    struct Line: Hashable {
        var speaker: String
        var text: String
        var learner = false
    }

    /// Subtitles above the patient, oldest first.
    var caption: [Line] = []
    /// Hide the case's room, so the patient sits in the wearer's own room (mixed reality).
    var hideRoom = false
    /// The equipment panel above the tray, shown only in the lab scene.
    var showFitting = false
}

/// The live conversation card beside the patient: who speaks (initials, role colour), what they
/// say, who is talking right now, and the learner's open mic. Journey stages add the people
/// around the patient cutting in, so the stress of the place reads in a still picture.
struct PitchCaption: View {
    @Environment(AppModel.self) private var model: AppModel?
    private let pitch = Pitch.shared

    private static let teal = Color(red: 0.2, green: 0.85, blue: 0.8)
    private static let orange = Color(red: 1, green: 0.6, blue: 0.2)
    private static let bystander = Color(red: 1, green: 0.36, blue: 0.42)

    /// Who cuts in at each journey stage, after a learner and patient exchange or a crew line.
    private static let interruptions: [String: Pitch.Line] = [
        "scene": Pitch.Line(speaker: "Driver", text: "I didn't see him, he came out of nowhere! Is he going to be OK?"),
        "ambulance": Pitch.Line(speaker: "Ambulance driver", text: "Hold on, sharp bend! About fifteen minutes out."),
    ]
    /// The learner and patient exchange that leads a stage's crew lines, so every stage shows you talking.
    private static let openers: [String: [Pitch.Line]] = [
        "ambulance": [Pitch.Line(speaker: "You", text: "Jordan, how's the pain now, out of ten?", learner: true),
                      Pitch.Line(speaker: "Jordan", text: "About a six. Better since the gas.")],
    ]
    /// Scripted replies a clinician would query in a still picture.
    private static let rewrites = ["Yes, that's me, Sarah. I'm thirty-one. It's lovely to meet you.":
                                   "Yes, Sarah Thompson, 14 March 1995. Lovely to meet you."]

    private var lines: [Pitch.Line] {
        var lines = pitch.caption.map { line in
            var line = line
            line.text = Self.rewrites[line.text] ?? line.text
            return line
        }
        if let stage = model?.currentStage?.id, let extra = Self.interruptions[stage], !lines.isEmpty, lines.count < 3,
           stage != "scene" || lines.contains(where: \.learner) {
            if !lines.contains(where: \.learner) { lines.insert(contentsOf: Self.openers[stage] ?? [], at: 0) }
            lines.append(extra)
        }
        return lines
    }

    var body: some View {
        let lines = lines
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(Array(lines.enumerated()), id: \.element) { i, line in
                    row(line, latest: i == lines.count - 1)
                        .padding(.top, i == 0 ? 0 : 18)
                }
                listening(live: lines.last?.learner == true).padding(.top, 22)
            }
            .padding(.horizontal, 30).padding(.top, 24).padding(.bottom, 26)
            .frame(width: 770, alignment: .leading)
            .background(Color(red: 0.06, green: 0.08, blue: 0.1).opacity(0.55), in: .rect(cornerRadius: 40))
            .glassBackgroundEffect(in: .rect(cornerRadius: 40))
            .frame(width: 930, alignment: .leading) // nudged towards the patient: the wide card stays in frame
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle().fill(.red).frame(width: 12, height: 12).shadow(color: .red, radius: 5)
                Text("LIVE").font(.system(size: 17, weight: .heavy)).tracking(1.6)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.red.opacity(0.22), in: .capsule)
            Text("Voice conversation").font(.system(size: 22, weight: .semibold))
            Spacer()
            Label("Hands-free", systemImage: "waveform").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(.bottom, 20)
    }

    /// The learner's open mic: always on, no button to press. Its level meter moves only while the
    /// learner is the one talking; while someone else speaks it waits, flat.
    private func listening(live: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "mic.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(.black.opacity(0.8))
                .frame(width: 40, height: 40).background(Self.teal.opacity(live ? 1 : 0.6), in: .circle)
            Text(live ? "Listening to you" : "Mic open · your turn next").font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Self.teal.opacity(live ? 1 : 0.75))
            Waveform(tint: Self.teal.opacity(live ? 1 : 0.35), bars: 22, height: 26, live: live)
            Spacer(minLength: 0)
            Text("Just talk").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Self.teal.opacity(live ? 0.12 : 0.06), in: .capsule)
        .overlay(Capsule().strokeBorder(Self.teal.opacity(live ? 0.35 : 0.2), lineWidth: 1.5))
    }

    private func row(_ line: Pitch.Line, latest: Bool) -> some View {
        let who = speaker(line)
        let pain = model?.reaction.flatMap { $0.painLevel > 0 && $0.text == line.text ? $0.painLevel : nil }
        let accent: Color? = who.interrupts ? who.tint : pain != nil ? Self.orange : nil
        return HStack(alignment: .top, spacing: 18) {
            SpeakerBadge(name: who.name, tint: who.tint, size: 64, symbol: line.learner ? "stethoscope" : nil)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    Text(who.name).font(.system(size: 25, weight: .bold)).foregroundStyle(who.tint)
                    Text(who.role.uppercased()).font(.system(size: 20, weight: .bold)).tracking(1.2)
                        .foregroundStyle(.white.opacity(0.6))
                    if who.interrupts {
                        Label("CUTS IN", systemImage: "exclamationmark.bubble.fill").font(.system(size: 17, weight: .heavy)).tracking(1)
                            .foregroundStyle(.white).padding(.horizontal, 9).padding(.vertical, 4)
                            .background(who.tint.opacity(0.85), in: .capsule)
                    }
                    if let pain {
                        Label("PAIN \(pain)/10", systemImage: "bolt.heart.fill").font(.system(size: 24, weight: .heavy)).tracking(1)
                            .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Self.orange, in: .capsule)
                    }
                    Spacer(minLength: 8)
                    if latest, !line.learner {
                        Text("SPEAKING").font(.system(size: 13, weight: .heavy)).tracking(1.2).foregroundStyle(who.tint)
                        Waveform(tint: who.tint, bars: 9, height: 26)
                    }
                }
                Text(line.text)
                    .font(.system(size: 31, weight: latest ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(latest ? 1 : 0.8))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(accent != nil ? 14 : 0)
        .background {
            if let accent {
                RoundedRectangle(cornerRadius: 22).fill(accent.opacity(0.14))
                    .overlay(alignment: .leading) { Capsule().fill(accent).frame(width: 5).padding(.vertical, 12) }
            }
        }
    }

    /// Learner teal, patient orange, each crew member their own colour, bystanders red.
    private func speaker(_ line: Pitch.Line) -> (name: String, role: String, tint: Color, interrupts: Bool) {
        if line.learner { return ("You", "Medical student", Self.teal, false) }
        if line.speaker == (model?.session?.case.patient.name ?? line.speaker) { return (line.speaker, "Patient", Self.orange, false) }
        if let journey = model?.journey, let member = journey.team.first(where: { $0.name == line.speaker }) {
            let title = ["Paramedic": "Paramedic", "Emergency nurse": "Nurse", "Emergency medical technician": "EMT"][member.role]
            return (title.map { "\($0) \(member.name)" } ?? member.name, member.role, journey.tint(member), false)
        }
        return (line.speaker, line.speaker.hasPrefix("Ambulance") ? "Crew" : "Bystander", Self.bystander, true)
    }

    /// Bars of a voice level meter: this voice is live.
    private struct Waveform: View {
        var tint: Color
        var bars: Int
        var height: CGFloat
        var live = true
        var body: some View {
            TimelineView(.animation(paused: !live)) { context in
                let t = live ? context.date.timeIntervalSinceReferenceDate : 0
                HStack(spacing: 3.5) {
                    ForEach(0..<bars, id: \.self) { i in
                        let base = 0.35 + 0.65 * abs(sin(Double(i) * 1.7 + 0.4))
                        Capsule().fill(tint)
                            .frame(width: 4.5, height: live ? 4 + (height - 4) * base * (0.55 + 0.45 * abs(sin(t * 5 + Double(i) * 0.9))) : 4)
                    }
                }
                .frame(height: height)
            }
        }
    }
}

/// In the main window: opens the patient's space, then closes the window so neither it nor its
/// window bar is in the pictures. PitchDemo takes over inside the space.
struct PitchLauncher: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Color.clear.task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            model.prepareStart()
            _ = await openImmersiveSpace(id: "patient")
            dismissWindow(id: "studio")
        }
    }
}

/// The scripted pitch run inside the immersive space: one case per launch (`-scenario`), its scenes in order.
struct PitchDemo: View {
    @Environment(AppModel.self) private var model
    private let pitch = Pitch.shared
    private let hold = AppConfig.launchArgument("-pitchHold")

    var body: some View {
        Color.clear.task { await run() }
    }

    private func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    /// Settle, cue the screenshot, keep still while it is taken. With `-pitchHold <name>` it stays here.
    private func shot(_ name: String, settle: Double = 2.5) async {
        if settle > 1 { model.recenter() } // panels back home; a quick shot (mid-flinch) must not move the patient
        await pause(settle)
        SmokeLog.mark("STEP \(name)")
        if hold == name {
            SmokeLog.mark("HOLD \(name)")
            while true { await pause(3600) }
        }
        await pause(2.5)
    }

    private var patient: String { model.session?.case.patient.name ?? "Patient" }

    /// Asks a scripted line and subtitles the exchange.
    private func ask(_ id: String, show: Bool = true) async {
        guard let line = model.scriptedDialogue.first(where: { $0.id == id }) else { return }
        model.askScripted(line)
        let turns = model.transcript.suffix(2)
        if show { pitch.caption = turns.map { Pitch.Line(turn: $0, patient: patient) } }
        await pause(2.5)
    }

    private func team(_ action: String) async {
        _ = await model.requestTeamAction(action)
        if let r = model.teamLog.last {
            pitch.caption = [Pitch.Line(speaker: r.member.name, text: r.response)]
        }
        await pause(AppModel.speechSeconds(model.teamLog.last?.response ?? "") + 0.5)
    }

    private func run() async {
        await pause(1)
        await model.startSession()
        await pause(4)
        if model.isUltrasound { await ultrasound() } else if model.journey != nil { await journey() } else { await wrist() }
        SmokeLog.mark("DONE")
    }

    /// Lines asked off camera, so the feedback reflects a complete encounter.
    private func history(_ ids: [String]) async {
        for id in ids { await ask(id, show: false) }
    }

    private func wrist() async {
        _ = model.performPatientAction(PatientAction.sitDown.rawValue)
        await pause(3)

        // The patient in your own room: mixed reality.
        pitch.hideRoom = true
        await ask("greeting")
        await shot("wrist-01-in-your-room")
        pitch.hideRoom = false

        await ask("mechanism")
        await shot("wrist-02-conversation")
        await history(["location", "severity", "numbness", "permission"])

        await model.examine(zoneId: "left_wrist", source: .script)
        await pause(2.5)
        await model.examine(zoneId: "right_anatomical_snuffbox", source: .script)
        pitch.caption = [Pitch.Line(speaker: "You", text: "I'm going to press here, at the base of your thumb.", learner: true),
                         Pitch.Line(speaker: patient, text: model.reaction?.text ?? "Ow!")]
        await shot("wrist-03-pain-reaction", settle: 0.4) // the flinch peaks within a second
        await pause(1)
        await ask("empathy", show: false)
        await model.examine(zoneId: "right_distal_forearm", source: .script)
        await pause(2.5)

        pitch.caption = []
        _ = await model.orderInvestigation("right_wrist_xray")
        model.setNotebookOpen(false)
        await shot("wrist-04-xray")
        model.closeViewer()

        // Orthotics lab: check the hand, measure, fit the right size, check again.
        pitch.showFitting = true
        await model.fittingCheck("neurovascular")
        await pause(2)
        model.labCommand = LabCommand(item: OrthoticsLab.tapeName, axialCm: 1, radialCm: 3)
        await pause(1.5)
        model.labCommand = LabCommand(item: OrthoticsLab.tapeName, axialCm: 14, radialCm: 3)
        await pause(1.5)
        model.labCommand = LabCommand(item: OrthoticsLab.orthosisPrefix + "medium", axialCm: 3, radialCm: 0, via: "pinch")
        await pause(2.5)
        await model.stepTightness(1) // the straps from loose to snug: the correct fit
        await pause(2)
        await model.fittingCheck("neurovascular")
        await pause(2)
        await model.fittingCheck("comfort")
        if let r = model.lastCheck {
            pitch.caption = [Pitch.Line(speaker: "You", text: "How does that feel?", learner: true),
                             Pitch.Line(speaker: patient, text: r.patientResponse)]
        }
        await shot("wrist-05-orthotics-lab")
        pitch.showFitting = false
        pitch.caption = []

        model.setNotebookOpen(true)
        model.notebookTab = .assessment
        model.notes.history = "Fell off bicycle yesterday onto outstretched right hand. Pain 3/10 at rest, 7-8/10 gripping. No numbness."
        model.notes.examination = "Tender in the right anatomical snuffbox. Right distal forearm and left wrist not tender."
        model.diagnosis = "Suspected scaphoid fracture"
        model.notes.interpretation = "X-ray: no fracture visible; an occult scaphoid fracture is not excluded."
        model.notes.management = "Thumb spica splint and analgesia."
        model.notes.followUp = "MRI of the wrist, or fracture clinic review in 10 days."
        await shot("wrist-06-notebook")

        await model.submitDiagnosis()
        await shot("wrist-07-feedback")

        model.startReplay()
        await pause(1)
        model.replayStep = 1
        model.showAnatomy = true
        await shot("wrist-08-replay-anatomy")
    }

    private func ultrasound() async {
        await ask("us_greeting")
        await shot("us-01-greeting")
        await history(["us_consent", "us_procedure", "us_symptoms", "us_previous_scan", "us_worries", "us_comfort"])
        await model.applyGel()
        await pause(1.5)
        let views = [("abdomen_lower", "us-02-head-bpd"), ("abdomen_upper", "us-03-heart"), ("abdomen_center", "us-04-overview"),
                     ("abdomen_left", nil), ("abdomen_right", nil), ("abdomen_fundus", nil)]
        for (region, name) in views {
            await model.scan(regionId: region)
            await pause(2)
            guard let name else { continue }
            pitch.caption = []
            if name == "us-03-heart" { await ask("us_movements") }
            await shot(name)
        }
        await model.rotateProbe() // the fundus again: amniotic fluid
        await pause(2)
        await model.scan(regionId: "abdomen_upper")
        await model.rotateProbe() // abdomen with AC and EFW
        await pause(2)
        await model.scan(regionId: "abdomen_lower") // the head again: the monitor shows a scan behind the feedback
        pitch.caption = []
        await history(["us_reassure"])
        model.setNotebookOpen(true)
        model.notes.history = "G1P0, 20 weeks. Well, no bleeding or pain, feels the baby move. 12 week scan normal."
        model.notes.examination = "BPD 4.61 cm, HC 16.73 cm. AC 13.82 cm, EFW 289 g. FL 3.17 cm. Heart: four chamber view seen. Spine seen. "
            + "Posterior placenta. Liquor normal."
        model.notes.assessment = "All measurements in keeping with 20 weeks. Explained the findings to Sarah."
        model.diagnosis = "Normal singleton intrauterine pregnancy, about 20 weeks, posterior placenta, normal liquor"
        await model.submitDiagnosis()
        await shot("us-05-feedback")
    }

    private func journey() async {
        await ask("rt_greeting")
        await shot("rt-01-roadside")
        await team("scene_safety")
        await history(["rt_mechanism", "rt_head_neck"])
        await team("haemorrhage_control")
        await team("observations")
        await shot("rt-02-crew")
        await team("photograph_wound")
        _ = model.performPatientAction(PatientAction.sitDown.rawValue)
        await pause(3)
        await history(["rt_permission"])
        await model.examine(zoneId: "rt_forearm_wound", source: .script)
        await pause(3)
        await history(["rt_empathy"])
        await team("analgesia")
        await team("splint_arm")
        await model.examine(zoneId: "rt_right_hand", source: .script)
        await pause(3)
        await ask("rt_allergies")
        await shot("rt-03-splinted")

        await history(["rt_explain_transfer"])
        await model.advanceStage()
        await pause(5)
        await team("observations")
        await team("iv_access")
        await shot("rt-04-ambulance")
        await team("iv_analgesia")
        await team("pre_alert")
        await history(["rt_tetanus"])

        await model.advanceStage()
        await pause(5)
        let handover = "Handover: Jordan, 34, cyclist knocked off by a car forty minutes ago. Open-looking deformed right forearm, "
            + "splinted, hand neurovascularly intact. Heart rate down to 104. Penthrox and morphine given."
        model.askScripted(ScriptedLine(id: "rt_handover", learner: handover, patient: "Thank you."))
        await pause(3)
        await team("iv_antibiotics")
        await shot("rt-05-resus")
        await team("tetanus")
        await team("orthopaedic_referral")
        pitch.caption = []
        _ = await model.orderInvestigation("rt_xray_forearm")
        model.setNotebookOpen(false)
        await shot("rt-06-xray")
        model.closeViewer()

        model.setNotebookOpen(true)
        model.notebookTab = .team
        await shot("rt-07-team-log")
        model.notes.history = "34-year-old cyclist knocked off by a car. Helmet, no head injury, no neck pain. Penicillin allergy."
        model.notes.examination = "Bleeding wound over a deformed right distal forearm. Hand pink, sensation intact after the splint."
        model.notes.interpretation = "Displaced fractures of the radius and ulna with soft tissue gas."
        model.notes.management = "IV antibiotics and tetanus given. Urgent orthopaedic referral for debridement and fixation in theatre."
        model.notes.followUp = "Admit, nil by mouth."
        model.diagnosis = "Open fracture of the right distal radius and ulna"
        model.notebookTab = .assessment
        await model.submitDiagnosis()
        await shot("rt-08-feedback")
    }
}

private extension Pitch.Line {
    init(turn: TranscriptTurn, patient: String) {
        self.init(speaker: turn.role == .learner ? "You" : patient, text: turn.text, learner: turn.role == .learner)
    }
}
