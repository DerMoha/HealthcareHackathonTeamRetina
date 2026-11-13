import SwiftUI

/// Scripted runs for the smoke tests, attached to the main window so switching tabs does not
/// cancel them. `-autoDemo`: visionos/scripts/simulator_smoke_test.sh; `-scenarioDemo` and
/// `-studioDemo`: visionos/scripts/scenario_smoke_test.sh. "STEP" lines are screenshot cues.
struct SmokeDemos: View {
    @Environment(AppModel.self) private var model
    @Environment(StudioState.self) private var studio
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        Color.clear.task {
            await autoDemo()
            await scenarioDemo()
            await studioDemo()
        }
    }

    private func start() async {
        model.prepareStart()
        if !model.immersiveOpen { _ = await openImmersiveSpace(id: "patient") }
        await model.startSession()
    }

    /// Scripted run of the whole demo, driven by launch argument `-autoDemo`.
    /// Used by visionos/scripts/simulator_smoke_test.sh; "STEP" lines are screenshot cues.
    private func autoDemo() async {
        guard SmokeLog.enabled, !SmokeLog.scenarioDemo else { return }
        studio.tab = .session
        #if DEBUG
        SmokeLog.mark("voice policy selfcheck ok=\(VoiceMemory.selfCheck())")
        #endif
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
            if let mock = model.voice as? MockVoiceService, mock.micStatus == .live {
                await mock.hear(text)
            } else {
                model.performPatientAction(action)
            }
        }

        func order(_ text: String, _ id: String) async {
            if let mock = model.voice as? MockVoiceService, mock.micStatus == .live {
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
            studio.focusCustomize = true // mood and avatar pickers into view
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

        // Credit-saving pause, then "Talk to patient": the patient must not greet a second time.
        if let mock = model.voice as? MockVoiceService, mock.status == .connected {
            let greetings = { model.transcript.filter { $0.text == "Hello, doctor." }.count }
            let before = greetings()
            mock.pause()
            await pause(0.5)
            SmokeLog.mark("voice paused \(state())")
            await model.talkToPatient()
            SmokeLog.mark("voice resumed newGreetings=\(greetings() - before) \(state())")
        }

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
        if model.immersiveOpen { await dismissImmersiveSpace() }
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
        if model.immersiveOpen { await dismissImmersiveSpace() }
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
            if let mock = model.voice as? MockVoiceService, mock.micStatus == .live {
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
        if let mock = model.voice as? MockVoiceService, mock.micStatus == .live { await mock.hear(handover) }
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
        if model.immersiveOpen { await dismissImmersiveSpace() }
        SmokeLog.mark("STEP 10-rt-stopped")
        SmokeLog.mark("DONE")
    }
    /// Scripted scenario run for visionos/scripts/scenario_smoke_test.sh (launch argument
    /// `-scenarioDemo`, with `-MEDSIM_SCENARIO_CODE <code>`). The script plays the instructor:
    /// it sends director events while this waits at the "await-director" steps.
    /// `-eventsA N` / `-eventsB N`: how many events to wait for before and after the link drop.
    private func scenarioDemo() async {
        guard SmokeLog.scenarioDemo, !SmokeLog.studioDemo else { return }
        studio.tab = .session
        func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        func events(_ count: Int, within seconds: Double) async {
            let end = Date().addingTimeInterval(seconds)
            while model.directorLog.count < count, Date() < end { await pause(0.25) }
            SmokeLog.mark("director events seen=\(model.directorLog.count) expected=\(count) \(model.directorLog)")
        }
        let eventsA = UserDefaults.standard.integer(forKey: "eventsA"), eventsB = UserDefaults.standard.integer(forKey: "eventsB")
        // `-eventWait S`: how long to wait for the instructor (longer when a person clicks in the Studio).
        let eventWait = UserDefaults.standard.object(forKey: "eventWait") == nil ? 25 : UserDefaults.standard.double(forKey: "eventWait")

        await pause(3)
        SmokeLog.mark("STEP s01-launch")
        await pause(2)
        let opened = await openImmersiveSpace(id: "patient")
        SmokeLog.mark("immersive opened=\({ if case .opened = opened { true } else { false } }())")
        await model.startSession()
        await pause(3)
        SmokeLog.mark("session id=\(model.session?.sessionId ?? "none") scenario=\(model.scenario?.code ?? "none") "
            + "phase=\(model.phase) notice=\(model.scenarioNotice ?? "none") error=\(model.lastError ?? "none")")
        guard model.phase == .running else { SmokeLog.mark("DONE"); return }
        await pause(5) // the bystander, if any, speaks up on their own
        SmokeLog.mark("STEP s02-scenario")
        await pause(2)

        // Same clinical case in every scenario: the finding must not depend on the setting.
        model.performPatientAction(PatientAction.sitDown.rawValue)
        await pause(3)
        model.performPatientAction(PatientAction.extendBothArms.rawValue)
        await pause(2.5)
        await model.examine(zoneId: "right_anatomical_snuffbox", source: .script)
        let exam = model.examinations.last
        SmokeLog.mark("examined right_anatomical_snuffbox finding=\(exam?.finding ?? "?") pain=\(exam?.painLevel ?? -1) engine=\(model.engineModeLabel)")
        await pause(3)
        let order = await model.orderInvestigation("right_wrist_xray")
        SmokeLog.mark("order right_wrist_xray -> \(order.prefix(60)) results=\(model.investigationResults.count)")
        model.closeViewer()
        await model.requestHint()
        SmokeLog.mark("hint before events=\(model.hint ?? "none")")
        await pause(1)

        SmokeLog.mark("STEP s03-await-director") // the script sends events now
        await events(eventsA, within: eventWait)
        await pause(2)
        SmokeLog.mark("STEP s04-after-events")
        await pause(2)
        await model.requestHint()
        SmokeLog.mark("hint after events=\(model.hint ?? "none")")

        if eventsB > 0 {
            model.director.drop(for: 4)
            SmokeLog.mark("STEP s05-link-dropped") // the script sends one more event while the link is down
            await events(eventsA + eventsB, within: eventWait)
            await pause(2)
            SmokeLog.mark("STEP s06-after-reconnect")
            await pause(2)
        }

        // Fit a support from what the tray has now (the medium one only after it was delivered).
        let sizes = model.session?.case.orthotics.sizes.map(\.id) ?? []
        if let size = sizes.contains("medium") ? "medium" : sizes.first {
            model.labCommand = LabCommand(item: OrthoticsLab.orthosisPrefix + size, axialCm: 3, radialCm: 0, via: "script")
            await pause(2)
            await model.stepTightness(1)
            await pause(1)
        }
        SmokeLog.mark("fitted \(model.fit.map { "\($0.size) \($0.tightness)" } ?? "none") exams=\(model.examinations.count) error=\(model.lastError ?? "none")")
        SmokeLog.mark("STEP s07-fitted")
        await pause(2)

        model.setNotebookOpen(true)
        model.notebookTab = .assessment
        model.diagnosis = "Suspected scaphoid fracture"
        model.notes.management = "Thumb spica splint and analgesia."
        model.notes.followUp = "Refer for imaging; review in the fracture clinic in 10 days."
        await pause(1)
        await model.submitDiagnosis()
        let f = model.feedback, d = model.debrief
        SmokeLog.mark("diagnosed score=\(f?.totalScore ?? -1)/\(f?.maxScore ?? -1) management=\(f?.management.score ?? -1)/\(f?.management.maxScore ?? -1) "
            + "fitting=\(f?.fitting.score ?? -1)/\(f?.fitting.maxScore ?? -1)")
        SmokeLog.mark("debrief loaded=\(d != nil) interventions=\(d?.interventions.count ?? -1) acknowledged=\(d?.interventions.filter(\.acknowledged).count ?? -1) "
            + "hints=\(d?.hints.count ?? -1) timeline=\(d?.timeline.map(\.type) ?? [])")
        for line in d?.interpretation ?? [] { SmokeLog.mark("debrief note: \(line)") }
        await pause(2)
        SmokeLog.mark("STEP s08-debrief")
        await pause(3)

        await model.stopSession()
        await dismissImmersiveSpace()
        SmokeLog.mark("DONE")
    }

    /// Scripted run of the in-headset Studio for `scenario_smoke_test.sh --variant studio`
    /// (launch argument `-studioDemo`, no launch code). Opens the Studio, downloads a marketplace
    /// copy, launches the walk-in scenario from the Marketplace, waits while the script sends
    /// one director event, submits, then shows that session's debrief in the Studio.
    private func studioDemo() async {
        guard SmokeLog.studioDemo else { return }
        func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        let walkIn = "5344E7"

        await pause(3)
        studio.tab = .overview
        await pause(4)
        SmokeLog.mark("studio opened library=\(studio.library.count) market=\(studio.market.map(\.code)) error=\(studio.error ?? "none")")
        SmokeLog.mark("STEP t01-overview")
        await pause(2)

        studio.tab = .marketplace
        await pause(3)
        SmokeLog.mark("STEP t02-marketplace")
        await pause(2)

        if let item = studio.market.first(where: { $0.code == walkIn }) { await studio.download(item) }
        await pause(3)
        let copy = studio.downloaded.first { $0.origin?.code == walkIn }
        SmokeLog.mark("studio downloaded tab=\(studio.tab.rawValue) copy=\(copy?.scenarioId ?? "none") state=\(copy?.reviewState ?? "none") "
            + "published=\(copy?.isPublished ?? false) inMine=\(studio.mine.contains { $0.scenarioId == copy?.scenarioId }) error=\(studio.error ?? "none")")
        SmokeLog.mark("STEP t03-downloaded")
        await pause(2)

        studio.tab = .mine
        studio.selected = studio.mine.first?.scenarioId
        await pause(3)
        SmokeLog.mark("STEP t04-mine")
        await pause(2)

        studio.tab = .marketplace
        await pause(2)
        await studio.launch(code: walkIn, model: model, openSpace: openImmersiveSpace)
        await pause(4)
        SmokeLog.mark("session id=\(model.session?.sessionId ?? "none") scenario=\(model.scenario?.code ?? "none") phase=\(model.phase) "
            + "immersive=\(model.immersiveOpen) error=\(model.lastError ?? "none")")
        SmokeLog.mark("STEP t05-launched")
        guard model.phase == .running else { SmokeLog.mark("DONE"); return }
        await pause(2)

        SmokeLog.mark("STEP t06-await-director") // the script sends one event now
        let end = Date().addingTimeInterval(25)
        while model.directorLog.isEmpty, Date() < end { await pause(0.25) }
        SmokeLog.mark("director events seen=\(model.directorLog.count) \(model.directorLog)")
        await pause(3)
        SmokeLog.mark("STEP t07-after-event")

        await model.examine(zoneId: "right_anatomical_snuffbox", source: .script)
        model.diagnosis = "Suspected scaphoid fracture"
        await model.submitDiagnosis()
        SmokeLog.mark("diagnosed score=\(model.feedback?.totalScore ?? -1)/\(model.feedback?.maxScore ?? -1)")
        let sid = model.session?.sessionId
        await pause(2)
        await model.stopSession()
        await dismissImmersiveSpace()
        await pause(2)

        studio.debriefSession = sid
        studio.tab = .debrief
        await pause(5)
        SmokeLog.mark("STEP t08-debrief")
        await pause(2)
        SmokeLog.mark("DONE")
    }
}
