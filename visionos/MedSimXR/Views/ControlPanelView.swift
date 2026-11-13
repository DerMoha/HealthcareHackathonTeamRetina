import SwiftUI

/// Session controls only. Notes, conversation, diagnosis and feedback live in the notebook
/// next to the patient (NotebookView); everything diagnostic is behind the Debug toggle.
struct ControlPanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @AppStorage(AppConfig.backendHostKey) private var backendHost = ""
    @AppStorage(AppConfig.agentIdKey) private var agentId = ""
    @AppStorage("fingertipExam") private var fingertip = false
    @AppStorage(AppConfig.voiceIdKeyPrefix + "MALE") private var maleVoiceId = ""
    @AppStorage(AppConfig.voiceIdKeyPrefix + "FEMALE") private var femaleVoiceId = ""

    /// Tracked by the model: the Studio window can open the patient's space too.
    private var immersed: Bool { model.immersiveOpen }
    /// Automation: scroll the dashboard to its Customize section.
    @State private var focusCustomize = false

    var body: some View {
        Group {
            if model.phase == .idle {
                ScenarioDashboardView(focusCustomize: focusCustomize, onStart: { Task { await start() } }) {
                    ScenarioCard()
                    settingsCard
                }
                .frame(width: Self.idleSize.width, height: Self.idleSize.height)
            } else {
                sessionPanel
                    .frame(width: Self.sessionSize.width, height: Self.sessionSize.height)
            }
        }
        // On the stable parent: the scripted run outlives the switch from dashboard to session.
        .task { await model.loadCatalog(); await autoDemo() }
    }

    /// The dashboard needs room for the scenario cards; a running session is a small palette.
    static let idleSize = CGSize(width: 680, height: 1020)
    static let sessionSize = CGSize(width: 400, height: 460)

    private func start() async {
        model.prepareStart() // settles case, mood and avatar before the scene loads its model
        if !immersed { _ = await openImmersiveSpace(id: "patient") }
        await model.startSession()
    }

    private var sessionPanel: some View {
        @Bindable var model = model
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "cross.case.fill").foregroundStyle(.teal).font(.title2)
                    Text("MedSim XR").font(.title2.bold())
                    Spacer()
                    if model.isBusy { ProgressView() }
                }
                Text(model.session?.case.learnerBrief
                     ?? "Start a session to meet your patient. Talk to them, examine them, and write your findings in the notebook beside them.")
                    .font(.callout).foregroundStyle(.secondary)
                ScenarioCard()
                JourneyPanel(compact: true)
                sessionButtons
                statusCard
                if let err = model.lastError, !model.notebookOpen {
                    Label(err, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
                }
                Toggle("Debug", isOn: $model.debugMode)
                if model.debugMode { debugCard }
                settingsCard
            }
            .padding(20)
        }
    }

    /// Scripted run of the whole demo, driven by launch argument `-autoDemo`.
    /// Used by visionos/scripts/simulator_smoke_test.sh; "STEP" lines are screenshot cues.
    private func autoDemo() async {
        guard SmokeLog.enabled, !SmokeLog.scenarioDemo else { return }
        func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        func state() -> String {
            "engine=\(model.engineModeLabel) voice=\(model.voice.status.label) mic=\(model.voice.micStatus.rawValue) "
                + "exams=\(model.examinations.count) turns=\(model.transcript.count) error=\(model.lastError ?? "none")"
        }
        func examine(_ zone: String) async {
            await model.examine(zoneId: zone, source: .script)
            let r = model.examinations.last
            SmokeLog.mark("examined \(zone) finding=\(r?.finding ?? "?") pain=\(r?.painLevel ?? -1) "
                + "animation=\(model.reaction?.animation ?? "?") speakLocally=\(model.reaction?.speakLocally ?? false) \(state())")
        }

        /// A spoken request: through the scripted voice when it is connected, else the same
        /// action hook directly (what the debug buttons do).
        func say(_ text: String, _ action: String) async {
            if let mock = model.voice as? MockVoiceService, mock.status == .connected {
                await mock.hear(text)
            } else {
                model.performPatientAction(action)
            }
        }

        func order(_ text: String, _ id: String) async {
            if let mock = model.voice as? MockVoiceService, mock.status == .connected {
                await mock.hear(text)
            } else {
                await model.orderInvestigation(id)
            }
        }

        // The dashboard is what the learner sees first.
        await pause(2.5)
        SmokeLog.mark("STEP 00-dashboard")
        if AppConfig.dashboardOnly {
            await pause(1.5)
            focusCustomize = true // mood and avatar pickers into view
            await pause(2.5)
            SmokeLog.mark("STEP 00-dashboard-customize")
            await pause(1)
            SmokeLog.mark("DONE")
            return
        }
        if model.selectedCase?.ultrasound != nil {
            await ultrasoundDemo()
            return
        }
        if model.selectedCase?.journey != nil {
            await journeyDemo()
            return
        }
        await pause(1)
        SmokeLog.mark("STEP 01-launch")
        await pause(3)

        model.prepareStart()
        let opened = await openImmersiveSpace(id: "patient")
        SmokeLog.mark("immersive opened=\({ if case .opened = opened { true } else { false } }())")
        await model.startSession()
        await pause(3.5)
        SmokeLog.mark("session id=\(model.session?.sessionId ?? "none") zones=\(model.zones.map(\.id)) \(state())")
        SmokeLog.mark("STEP 02-session")
        await pause(3)

        // Standing: the wrist cannot be examined yet, and a spoken request is never an examination.
        await model.examine(zoneId: "right_anatomical_snuffbox")
        SmokeLog.mark("standing examine state=\(model.behavior.state.rawValue) \(state())")
        SmokeLog.mark("STEP 03-sitting") // the script takes a burst of screenshots here
        await say("Please have a seat.", "sit_down")
        await say("Please sit down.", "sit_down") // repeated command
        await pause(3)
        SmokeLog.mark("STEP 03-seated")
        await pause(2)

        // Test hook: Stop -> change the avatar -> Start with the immersive space left open.
        if ProcessInfo.processInfo.arguments.contains("-swapTest") {
            for avatar in ["female", "male"] {
                await model.stopSession()
                model.selection.avatar = avatar
                await start()
                await pause(4)
                SmokeLog.mark("swap test avatar=\(avatar) model=\(model.activeAvatarModel) state=\(model.behavior.state.rawValue) "
                    + "zones=\(model.zones.count)")
                await say("Please have a seat.", "sit_down")
                await pause(3)
                await model.examine(zoneId: "right_anatomical_snuffbox", source: .script)
                SmokeLog.mark("swap test exam finding=\(model.examinations.last?.finding ?? "none")")
                await pause(2)
                SmokeLog.mark("STEP 03-swap-\(avatar)")
                model.labCommand = LabCommand(item: OrthoticsLab.orthosisPrefix + "medium", axialCm: 3, radialCm: 0, via: "swap")
                await pause(2)
                SmokeLog.mark("swap test fit=\(model.fit?.size ?? "none")")
            }
            SmokeLog.mark("DONE")
            return
        }

        for line in model.scriptedDialogue.prefix(2) {
            model.askScripted(line)
            SmokeLog.mark("asked \(line.id) \(state())")
            await pause(4.5)
        }
        SmokeLog.mark("STEP 03-conversation")
        await pause(2)

        // Interrupted: relax in the middle of extending, then extend again.
        await say("Could you stretch out both arms?", "extend_both_arms")
        await pause(0.3)
        await say("Actually, relax your arms.", "relax_arms")
        await pause(0.2)
        await say("Please hold both arms out for me.", "extend_both_arms")
        await pause(2)
        SmokeLog.mark("STEP 04-arms-extended")
        await pause(2)
        await say("Which wrist hurts?", "indicate_right_wrist")
        await pause(0.6)
        SmokeLog.mark("STEP 04-indicating")
        await pause(3.5)

        await examine("left_wrist")
        await pause(3.5)
        SmokeLog.mark("STEP 04-pain")
        await examine("right_anatomical_snuffbox")
        await pause(3)
        SmokeLog.mark("after recoil state=\(model.behavior.state.rawValue) \(state())")
        await pause(2)

        SmokeLog.mark("STEP 05-killwindow") // the script may kill the backend here
        await pause(8)
        await examine("right_distal_forearm")
        await pause(3)

        // Orthotics lab: the same drop/snap path a drag uses, driven by commands.
        func drop(_ item: String, _ axialCm: Double, _ radialCm: Double) async {
            model.selectedTool = item
            await pause(0.8)
            model.labCommand = LabCommand(item: item, axialCm: axialCm, radialCm: radialCm)
            await pause(1.5)
        }
        await model.fittingCheck("neurovascular") // before immobilising
        await pause(2.5)
        SmokeLog.mark("STEP 05-lab-0-tray")
        await pause(2)
        await drop(OrthoticsLab.tapeName, 1, 3)
        SmokeLog.mark("STEP 05-lab-1-measure-wrist")
        await pause(2.5)
        await drop(OrthoticsLab.tapeName, 14, 3)
        SmokeLog.mark("STEP 05-lab-2-measure-forearm")
        await pause(2.5)
        await drop(OrthoticsLab.orthosisPrefix + "large", 3, 30) // dragged, let go too far from the arm
        SmokeLog.mark("missed drop fit=\(model.fit == nil ? "none" : "SET")")
        model.selectedTool = OrthoticsLab.orthosisPrefix + "large"
        await pause(1.5)
        SmokeLog.mark("STEP 05-lab-2-selected")
        await pause(2)
        // select-then-pinch path: same placement call the forearm pinch makes
        model.labCommand = LabCommand(item: OrthoticsLab.orthosisPrefix + "large", axialCm: 3, radialCm: 0, via: "pinch")
        model.selectedTool = nil
        await pause(3.5) // nobody asks: the patient speaks up about the loose fit
        await model.stepTightness(1) // same complaint again: must stay quiet
        await pause(2.5)
        await model.fittingCheck("comfort")
        await pause(1.5)
        SmokeLog.mark("STEP 05-lab-3-too-large")
        await pause(2.5)
        await drop(OrthoticsLab.orthosisPrefix + "medium", 3, 2)
        await model.stepTightness(1) // continuous adjustment: one remark at the end, not three
        await pause(0.3)
        await model.stepTightness(1)
        await pause(3.5)
        SmokeLog.mark("STEP 05-lab-4-too-tight")
        await pause(2.5)
        await model.stepTightness(-1)
        await model.fittingCheck("neurovascular")
        await pause(2.5)
        await model.fittingCheck("comfort")
        await pause(1.5)
        SmokeLog.mark("fitted \(model.fit.map { "\($0.size) \($0.tightness) \($0.orientation) \($0.offsetCm)cm" } ?? "none") "
            + "state=\(model.behavior.state.rawValue) \(state())")
        SmokeLog.mark("STEP 05-lab-5-fitted")
        await pause(2.5)

        model.recenter()
        await pause(2)
        SmokeLog.mark("recentered token=\(model.recenterToken)")

        await model.loadFeedback()
        SmokeLog.mark("pre-diagnosis feedback verdict=\(model.feedback?.diagnosticAssessment.verdict ?? "?") "
            + "criteria=\(model.feedback?.categories.map(\.criteria.count) ?? [])")
        // Investigation: ordered by voice (or the same hook), result opens in the viewer.
        await order("I would like to order an X-ray of his right wrist.", "right_wrist_xray")
        await pause(2)
        SmokeLog.mark("viewer open=\(model.viewing?.investigationId ?? "none") notebook=\(model.notebookOpen) \(state())")
        SmokeLog.mark("STEP 05-xray-viewer")
        await pause(3)
        model.viewerZoom = 2.5
        await pause(1.5)
        SmokeLog.mark("STEP 05-xray-zoom")
        await pause(3)
        model.closeViewer()
        await pause(1.5)
        SmokeLog.mark("viewer closed=\(model.viewing == nil) tab=\(model.notebookTab.rawValue) \(state())")
        SmokeLog.mark("STEP 05-investigations")
        await pause(3)
        model.notebookTab = .history

        // The learner documents the case and formulates the diagnosis in the notebook.
        model.setNotebookOpen(true)
        model.notes.history = "Fell off bicycle yesterday, landed on outstretched right hand. Pain worse on gripping."
        await pause(2)
        SmokeLog.mark("notebook open=\(model.notebookOpen) \(state())")
        SmokeLog.mark("STEP 06-notebook-history")
        await pause(3)
        model.notebookTab = .examination
        // "Sensation normal" was never asked: the feedback must flag it as unsupported.
        model.notes.examination = "Tender at the base of the right thumb. Right forearm and left wrist not tender. Sensation normal."
        await pause(1.5)
        SmokeLog.mark("STEP 07-notebook-examination")
        await pause(3)
        model.notebookTab = .assessment
        model.diagnosis = "Suspected scaphoid fracture"
        model.notes.interpretation = "X-ray shows no fracture, but an occult scaphoid fracture cannot be excluded."
        model.notes.management = "Thumb spica splint and analgesia."
        model.notes.followUp = "MRI of the wrist, or review in the fracture clinic in 10 days."
        await pause(1.5)
        SmokeLog.mark("STEP 08-notebook-assessment")
        await pause(3)
        await model.submitDiagnosis()
        let f = model.feedback
        SmokeLog.mark("diagnosed score=\(f?.totalScore ?? -1)/\(f?.maxScore ?? -1) verdict=\(f?.diagnosticAssessment.verdict ?? "?") "
            + "categories=\(f?.categories.map { "\($0.id):\($0.score)" } ?? []) "
            + "management=\(f?.management.score ?? -1)/\(f?.management.maxScore ?? -1) "
            + "fitting=\(f?.fitting.score ?? -1)/\(f?.fitting.maxScore ?? -1) "
            + "\(f?.management.criteria.map { "\($0.id):\($0.met)" } ?? []) "
            + "notes=\(f?.documentation.map { "\($0.criterionId):\($0.status)" } ?? []) \(state())")
        await pause(1.5)
        SmokeLog.mark("STEP 09-feedback")
        await pause(4)
        model.startReplay()
        await pause(2)
        SmokeLog.mark("STEP 09-replay-1")
        await pause(2.5)
        model.replayStep = 1 // the painful snuffbox palpation
        await pause(1.5)
        SmokeLog.mark("STEP 09-replay-2-snuffbox")
        await pause(2.5)
        model.showAnatomy = false
        model.replayStep = model.replayStepCount - 1
        await pause(1.5)
        SmokeLog.mark("STEP 09-replay-support")
        await pause(2.5)
        model.showAnatomy = true
        await pause(1.5)
        SmokeLog.mark("STEP 09-teaching-anatomy")
        await pause(2.5)
        model.exitReplay()
        SmokeLog.mark("replay exited teaching=\(model.teachingMode) notebook=\(model.notebookOpen)")
        await pause(1)

        await model.reset()
        await pause(2)
        SmokeLog.mark("reset feedback=\(model.feedback == nil ? "cleared" : "STILL SET") notes=\(model.notes == ClinicalNotes() ? "blank" : "KEPT") \(state())")
        SmokeLog.mark("STEP 10-reset")
        await pause(3)
        // New encounter: a report-only study, requested from the notebook button path.
        await model.orderInvestigation("right_wrist_mri")
        await pause(2)
        SmokeLog.mark("STEP 10-mri-report")
        await pause(3)

        await model.stopSession()
        if immersed { await dismissImmersiveSpace() }
        SmokeLog.mark("STEP 11-stopped")
        SmokeLog.mark("DONE")
    }

    /// Scripted run of the obstetric ultrasound case (`-autoDemo -scenario obstetric_ultrasound_001`).
    /// The same model calls the probe drag, the pinches and the buttons make. "STEP" lines are screenshot cues.
    private func ultrasoundDemo() async {
        func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        func state() -> String {
            "engine=\(model.engineModeLabel) voice=\(model.voice.status.label) mic=\(model.voice.micStatus.rawValue) "
                + "exams=\(model.examinations.count) turns=\(model.transcript.count) error=\(model.lastError ?? "none")"
        }
        func ask(_ id: String) async {
            guard let line = model.scriptedDialogue.first(where: { $0.id == id }) else { return }
            model.askScripted(line)
            SmokeLog.mark("asked \(id) \(state())")
            await pause(3.2)
        }
        func scan(_ region: String, step: String? = nil, wait: Double = 2.6) async {
            await model.scan(regionId: region)
            await pause(wait)
            if step != nil { model.recenter(); await pause(1.2) } // re-frame in front of the wearer, wherever the simulator camera is now
            if let step { SmokeLog.mark("STEP \(step)") }
            if step != nil { await pause(4.2) } // the screenshot is taken while nothing moves
        }

        await pause(1)
        model.prepareStart()
        let opened = await openImmersiveSpace(id: "patient")
        SmokeLog.mark("immersive opened=\({ if case .opened = opened { true } else { false } }())")
        await model.startSession()
        await pause(4.5)
        SmokeLog.mark("session id=\(model.session?.sessionId ?? "none") regions=\(model.ultrasound?.regions.map(\.id) ?? []) "
            + "zones=\(model.zones.count) state=\(model.behavior.state.rawValue) recumbent=\(model.behavior.machine.recumbent) \(state())")
        model.recenter()
        await pause(1.5)
        SmokeLog.mark("STEP 01-us-session")
        await pause(4.5)

        // A request to stand or sit does not apply to a patient lying on the couch.
        let action = model.performPatientAction("sit_down")
        SmokeLog.mark("sit_down on the couch -> \(action)")

        await ask("us_greeting")
        await ask("us_consent")
        await ask("us_procedure")
        await ask("us_symptoms")
        await ask("us_movements")
        model.recenter()
        await pause(1.2)
        SmokeLog.mark("STEP 01-us-conversation")
        await pause(4)

        // Tapping a region with nothing in hand only reminds the learner.
        await model.tapRegion("abdomen_center")
        SmokeLog.mark("hint=\(model.usHint ?? "none") probe=\(model.probeRegion ?? "none")")
        await pause(1)

        // Dry probe: no usable image, and the patient notices.
        await scan("abdomen_upper", step: "02-us-no-gel")
        model.liftProbe()
        await pause(1.2)
        SmokeLog.mark("lifted probe=\(model.probeRegion ?? "none")")

        await model.applyGel()
        await pause(2.4)
        model.recenter()
        await pause(1.2)
        SmokeLog.mark("STEP 03-us-gel")
        await pause(4.2)

        await scan("abdomen_center", step: "04-us-overview")
        await scan("abdomen_lower", step: "04-us-head")
        await scan("abdomen_upper", step: "04-us-heart")
        await scan("abdomen_left", step: "04-us-spine")
        await scan("abdomen_right", step: "04-us-femur")
        await scan("abdomen_fundus", step: "04-us-placenta")
        // cycle: the same region again (rotate the probe) gives the next view there
        await model.rotateProbe()
        await pause(2)
        SmokeLog.mark("cycled region=\(model.probeRegion ?? "none") view=\(model.lastScan?.viewId ?? "none")")
        await scan("abdomen_upper")
        await model.rotateProbe()
        await pause(1.8)
        await scan("abdomen_lower")
        await model.rotateProbe()
        await pause(1.5)
        SmokeLog.mark("cycled region=\(model.probeRegion ?? "none") view=\(model.lastScan?.viewId ?? "none")")
        model.liftProbe()
        await pause(1.5)
        SmokeLog.mark("probe up: contact=\(model.probeRegion ?? "none")")
        model.recenter()
        await pause(1.2)
        SmokeLog.mark("STEP 04-us-no-contact")
        await pause(4.2)

        await ask("us_sex_question")
        await ask("us_sex_answer")
        await ask("us_reassure")

        model.setNotebookOpen(true)
        model.notebookTab = .examination
        model.notes.history = "G1P0, 20 weeks. Well, no bleeding or pain, feels the baby move. 12 week scan normal."
        model.notes.examination = "BPD 4.61 cm, HC 16.73 cm. AC 13.82 cm, EFW 289 g. FL 3.17 cm. Heart: four chamber view seen. Spine seen. "
            + "Posterior placenta. Liquor normal. Femur seen. Nuchal fold measured 3 mm."
        model.notes.assessment = "All measurements in keeping with 20 weeks. Explained the findings to the patient."
        model.diagnosis = "Normal singleton intrauterine pregnancy, about 20 weeks, posterior placenta, normal liquor"
        await pause(2)
        SmokeLog.mark("notebook open=\(model.notebookOpen) tab=\(model.notebookTab.rawValue) \(state())")
        model.recenter()
        await pause(1.2)
        SmokeLog.mark("STEP 05-us-notebook")
        await pause(4.5)
        await model.submitDiagnosis()
        let f = model.feedback
        SmokeLog.mark("diagnosed score=\(f?.totalScore ?? -1)/\(f?.maxScore ?? -1) verdict=\(f?.diagnosticAssessment.verdict ?? "?") "
            + "categories=\(f?.categories.map { "\($0.id):\($0.score)" } ?? []) "
            + "obtained=\(f?.scanReview?.filter(\.obtained).map(\.id) ?? []) management=\(f?.management.maxScore ?? -1) fitting=\(f?.fitting.maxScore ?? -1) "
            + "notes=\(f?.documentation.map { "\($0.criterionId):\($0.status)" } ?? []) \(state())")
        await pause(2)
        model.recenter()
        await pause(1.2)
        SmokeLog.mark("STEP 06-us-feedback")
        await pause(4.5)

        await model.stopSession()
        if immersed { await dismissImmersiveSpace() }
        SmokeLog.mark("STEP 07-us-stopped")
        SmokeLog.mark("DONE")
    }

    /// Scripted run of the road trauma journey (`-autoDemo -scenario road_trauma_journey_001`): roadside,
    /// ambulance, emergency department. Team requests go through the scripted voice when it is connected,
    /// else through the same model call the team buttons make. "STEP" lines are screenshot cues.
    private func journeyDemo() async {
        func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        func state() -> String {
            "engine=\(model.engineModeLabel) voice=\(model.voice.status.label) stage=\(model.currentStage?.id ?? "none") "
                + "team=\(model.teamLog.count) exams=\(model.examinations.count) turns=\(model.transcript.count) error=\(model.lastError ?? "none")"
        }
        func ask(_ id: String) async {
            guard let line = model.scriptedDialogue.first(where: { $0.id == id }) else { return }
            model.askScripted(line)
            SmokeLog.mark("asked \(id) \(state())")
            await pause(3.2)
        }
        func team(_ text: String, _ action: String) async {
            if let mock = model.voice as? MockVoiceService, mock.status == .connected {
                await mock.hear(text)
            } else {
                await model.requestTeamAction(action)
            }
            SmokeLog.mark("team asked \(action) last=\(model.teamLog.last.map { "\($0.actionId):\($0.done)" } ?? "none") \(state())")
            await pause(AppModel.speechSeconds(model.teamLog.last?.response ?? "") + 0.6)
        }
        func move() async {
            await model.advanceStage()
            await pause(5)
            SmokeLog.mark("moved \(state())")
        }

        await pause(1)
        model.prepareStart()
        let opened = await openImmersiveSpace(id: "patient")
        SmokeLog.mark("immersive opened=\({ if case .opened = opened { true } else { false } }())")
        await model.startSession()
        await pause(6) // Sam introduces the crew
        SmokeLog.mark("session id=\(model.session?.sessionId ?? "none") stages=\(model.journey?.stages.map(\.id) ?? []) \(state())")
        SmokeLog.mark("STEP 01-rt-roadside")
        await pause(2)

        await ask("rt_greeting")
        await team("Sam, is the scene safe?", "scene_safety")
        await ask("rt_mechanism")
        await ask("rt_head_neck")
        await team("Sam, please get pressure on that bleeding and a dressing on.", "haemorrhage_control")
        await team("Lena, can you get a set of observations?", "observations")
        await team("Lena, please take a photo of the wound first.", "photograph_wound")
        model.performPatientAction(PatientAction.sitDown.rawValue)
        await pause(3)
        await ask("rt_permission")
        await model.examine(zoneId: "rt_forearm_wound", source: .script)
        await pause(3)
        await ask("rt_empathy")
        await team("Sam, let's give some pain relief.", "analgesia")
        await team("Sam, can we splint the arm?", "splint_arm")
        await model.examine(zoneId: "rt_right_hand", source: .script)
        await pause(3)
        await ask("rt_allergies")
        SmokeLog.mark("STEP 02-rt-treated")
        await pause(2)

        await ask("rt_explain_transfer")
        await move()
        SmokeLog.mark("STEP 03-rt-ambulance")
        await team("Lena, could you repeat the observations?", "observations")
        await team("Lena, IV pain relief please.", "iv_analgesia") // refused: no cannula yet
        await team("Lena, please put in a cannula.", "iv_access")
        await team("Lena, IV pain relief please.", "iv_analgesia")
        await team("Sam, please pre-alert the hospital.", "pre_alert")
        await ask("rt_tetanus")
        SmokeLog.mark("STEP 04-rt-ambulance-treated")
        await pause(2)

        await move()
        SmokeLog.mark("STEP 05-rt-hospital")
        let handover = "Handover: Jordan, 34-year-old cyclist knocked off by a car about forty minutes ago. Bleeding wound over a "
            + "deformed right forearm, splinted, hand neurovascularly intact. Heart rate down to 104. We've given Penthrox and morphine."
        if let mock = model.voice as? MockVoiceService, mock.status == .connected { await mock.hear(handover) }
        else { model.askScripted(ScriptedLine(id: "rt_handover", learner: handover, patient: "Thank you.")) }
        await pause(3)
        await team("Priya, please give IV antibiotics.", "iv_antibiotics")
        await team("Priya, he needs a tetanus booster.", "tetanus")
        await team("Omar, can you refer him to the orthopaedic team?", "orthopaedic_referral")
        await model.orderInvestigation("rt_xray_forearm")
        await pause(2)
        SmokeLog.mark("viewer open=\(model.viewing?.investigationId ?? "none") \(state())")
        SmokeLog.mark("STEP 06-rt-xray")
        await pause(3)
        model.closeViewer()

        model.notebookTab = .team
        await pause(2)
        SmokeLog.mark("STEP 07-rt-team-log")
        model.notes.history = "34-year-old cyclist knocked off by a car. Helmet, no head injury, no neck pain. Penicillin allergy."
        model.notes.examination = "Bleeding wound over a deformed right distal forearm. Hand pink, sensation intact after the splint."
        model.notes.interpretation = "Displaced fractures of the radius and ulna with soft tissue gas."
        model.notes.management = "IV antibiotics and tetanus given. Urgent orthopaedic referral for debridement and fixation in theatre."
        model.notes.followUp = "Admit, nil by mouth."
        model.diagnosis = "Open fracture of the right distal radius and ulna"
        model.notebookTab = .assessment
        await pause(2)
        SmokeLog.mark("STEP 08-rt-notebook")
        await model.submitDiagnosis()
        let f = model.feedback
        SmokeLog.mark("diagnosed score=\(f?.totalScore ?? -1)/\(f?.maxScore ?? -1) verdict=\(f?.diagnosticAssessment.verdict ?? "?") "
            + "categories=\(f?.categories.map { "\($0.id):\($0.score)" } ?? []) "
            + "management=\(f?.management.score ?? -1)/\(f?.management.maxScore ?? -1) \(state())")
        await pause(2)
        SmokeLog.mark("STEP 09-rt-feedback")
        await pause(4)

        await model.stopSession()
        if immersed { await dismissImmersiveSpace() }
        SmokeLog.mark("STEP 10-rt-stopped")
        SmokeLog.mark("DONE")
    }

    // MARK: Sections

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow("brain.head.profile", "AI connection", voiceLabel, color: statusColor)
            if case .failed(let reason) = model.voice.status {
                Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            statusRow(model.voice.micStatus == .live ? "mic.fill" : "mic.slash", "Microphone", model.voice.micStatus.rawValue,
                      color: model.voice.micStatus == .live ? .green : .secondary)
            statusRow("server.rack", "Engine", model.engineModeLabel, color: .secondary)
            // One-tap fallback when nobody is listening: without it a standing patient cannot be examined.
            if model.phase == .running, model.behavior.state == .standingIdle, model.voice.status != .connected {
                Button("Ask \(model.session?.case.patient.name ?? "the patient") to sit down") {
                    model.performPatientAction(PatientAction.sitDown.rawValue)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusColor: Color {
        switch model.voice.status {
        case .connected: .green
        case .connecting, .failed: .orange
        case .disconnected: .secondary
        }
    }

    /// A failed voice connection is not fatal: the patient keeps talking through local clips.
    private var voiceLabel: String {
        if case .failed = model.voice.status { return "Unavailable · local voice" }
        return model.voice.status.label + (model.voice.isAgentSpeaking ? " · speaking" : "")
    }

    private var lastExamCard: some View {
        let exam = model.examinations.last
        let painful = (exam?.painLevel ?? 0) >= 5
        return HStack(spacing: 10) {
            Image(systemName: painful ? "exclamationmark.triangle.fill" : "hand.point.up.left.fill")
                .foregroundStyle(painful ? .red : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.zones.first { $0.id == exam?.bodyPart }?.label ?? "").font(.subheadline.bold())
                Text("\((exam?.finding ?? "").replacingOccurrences(of: "_", with: " ")) · pain \(exam?.painLevel ?? 0)/10")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(model.examinations.count) examined").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func statusRow(_ icon: String, _ title: String, _ value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 24).foregroundStyle(color)
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).foregroundStyle(color).lineLimit(2).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private var sessionButtons: some View {
        HStack {
            Button {
                Task {
                    await model.stopSession()
                    if immersed { await dismissImmersiveSpace() }
                }
            } label: { Label("Stop Session", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).tint(.red)
            Button { model.recenter() } label: { Label("Recenter Patient", systemImage: "scope") }
        }
        .disabled(model.isBusy)
    }

    /// Demo safety net: trigger examinations and scripted questions without touching the avatar.
    private var debugCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.examinations.isEmpty { lastExamCard }
            if !model.zones.isEmpty {
                Text("Examine").font(.subheadline.bold())
                ForEach(model.zones) { z in
                    Button(z.label) { Task { await model.examine(zoneId: z.id) } }
                        .buttonStyle(.bordered).disabled(model.phase != .running)
                }
            }
            if let ultrasound = model.ultrasound {
                // Fallback if gaze and pinch do not work: the same engine calls as the probe and the gel bottle.
                Text("Ultrasound").font(.subheadline.bold())
                Button("Apply gel") { Task { await model.applyGel() } }
                    .buttonStyle(.bordered).disabled(model.phase != .running)
                ForEach(ultrasound.regions) { region in
                    Button("Scan: \(region.label)") { Task { await model.scan(regionId: region.id) } }
                        .buttonStyle(.bordered).disabled(model.phase != .running)
                }
                HStack {
                    Button("Rotate probe") { Task { await model.rotateProbe() } }.disabled(model.probeRegion == nil)
                    Button("Lift probe") { model.liftProbe() }.disabled(model.probeRegion == nil)
                }
                .buttonStyle(.bordered)
                if let scan = model.lastScan, model.probeRegion != nil {
                    Text("\(scan.title) · \(scan.quality)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !model.behavior.machine.recumbent { // stand, sit and arm movements do not apply on the couch
                Text("Patient: \(model.behavior.state.rawValue.replacingOccurrences(of: "_", with: " "))").font(.subheadline.bold())
                ForEach(PatientAction.allCases, id: \.self) { action in
                    Button(action.rawValue.replacingOccurrences(of: "_", with: " ").capitalized) {
                        model.performPatientAction(action.rawValue)
                    }
                    .buttonStyle(.bordered).disabled(model.phase != .running)
                }
            }
            if model.behavior.canExamine, let orthotics = model.session?.case.orthotics, !orthotics.sizes.isEmpty {
                // Fallback if neither pinch nor drag works: same placement call, fixed spot on the arm.
                Text("Equipment").font(.subheadline.bold())
                Button("Measure wrist") { model.labCommand = LabCommand(item: OrthoticsLab.tapeName, axialCm: 1, radialCm: 0, via: "debug") }
                Button("Measure forearm") { model.labCommand = LabCommand(item: OrthoticsLab.tapeName, axialCm: 14, radialCm: 0, via: "debug") }
                ForEach(orthotics.sizes) { size in
                    Button("Put \(size.label) support on the wrist") {
                        model.labCommand = LabCommand(item: OrthoticsLab.orthosisPrefix + size.id, axialCm: 3, radialCm: 0, via: "debug")
                    }
                }
            }
            Text("Ask").font(.subheadline.bold())
            ForEach(model.scriptedDialogue) { line in
                Button(line.learner) { model.askScripted(line) }
                    .buttonStyle(.bordered).disabled(model.phase != .running)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var settingsCard: some View {
        DisclosureGroup("Settings") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Backend host (host:port)", text: $backendHost)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("ElevenLabs agent ID", text: $agentId)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Voice ID, male patient (optional)", text: $maleVoiceId)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Voice ID, female patient (optional)", text: $femaleVoiceId)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("Fingertip examination (experimental)", isOn: $fingertip)
                Text("Backend, agent and voice changes apply on the next Start. Voice IDs need the agent's voice override enabled.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }
}
