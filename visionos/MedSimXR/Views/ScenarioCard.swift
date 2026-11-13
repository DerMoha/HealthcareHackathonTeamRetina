import SwiftUI

/// Scenario selection before a session (launch code or the published list) and the
/// scenario's live state during one. With no code the app runs the fixed default case.
struct ScenarioCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(StudioState.self) private var studio
    @AppStorage(AppConfig.scenarioCodeKey) private var code = ""
    @State private var published: [ScenarioSummary] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let s = model.scenario, model.phase != .idle { running(s) } else { picker }
            if let notice = model.scenarioNotice {
                Label(notice, systemImage: "wifi.slash").font(.footnote).foregroundStyle(.orange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .task { await load(); await scenarioDemo(); await studioDemo() }
    }

    private func load() async {
        published = await ScenarioClient.published()
        loaded = true
    }

    private var picker: some View {
        Group {
            HStack {
                Text("Scenario").font(.subheadline.bold())
                Spacer()
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }
            Button { studio.tab = .overview; openWindow(id: StudioView.windowId) } label: {
                Label("Open MedSim Studio", systemImage: "square.grid.2x2").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            TextField("Launch code (empty: default case)", text: $code)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
            ForEach(published) { s in
                Button { code = s.code } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.subheadline)
                        JourneyTag(stages: s.stages)
                        Text("\(s.code) · \(s.environment) · \(s.difficulty) · \(s.reviewState.replacingOccurrences(of: "_", with: " "))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered).tint(code.uppercased() == s.code ? .teal : nil)
            }
            if loaded && published.isEmpty {
                Text("No published scenarios reachable. The fixed default case works offline.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !code.isEmpty { Button("Use the default case") { code = "" }.font(.caption) }
        }
        .disabled(model.phase != .idle)
    }

    private func running(_ s: ScenarioRuntime) -> some View {
        Group {
            Text(s.title).font(.subheadline.bold())
            Text(s.reviewLabel).font(.caption).foregroundStyle(s.reviewState == "clinician_reviewed" ? .green : .orange)
            row("mappin.and.ellipse", "\(s.environmentLabel) · \(s.difficulty.capitalized)")
            row("speaker.wave.2", "Room noise \(Int(s.noiseLevel * 100))%")
            if let b = s.bystander { row("person", "\(b.name), \(b.roleLabel): \(b.mood)") }
            if s.teammate.present { row("cross.case", "\(s.teammate.name), \(s.teammate.roleLabel), is here to help") }
            row("shippingbox", s.equipment.filter(\.available).map(\.label).joined(separator: ", "))
            let missing = s.equipment.filter { !$0.available }.map(\.label)
            if !missing.isEmpty { row("xmark.circle", "Not here: " + missing.joined(separator: ", ")) }
            row("antenna.radiowaves.left.and.right", model.director.connected ? "Instructor connected" : "Instructor link down, retrying")
            ForEach(Array(model.directorLog.suffix(3).enumerated()), id: \.offset) { _, label in
                row("person.wave.2", label)
            }
            if s.hintPolicy != "off" {
                Divider()
                if let hint = model.hint { Label(hint, systemImage: "lightbulb.fill").font(.callout).foregroundStyle(.yellow) }
                Button("Ask for a hint") { Task { await model.requestHint() } }.buttonStyle(.bordered)
            }
        }
    }

    private func row(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.caption).foregroundStyle(.secondary)
    }

    /// Scripted scenario run for visionos/scripts/scenario_smoke_test.sh (launch argument
    /// `-scenarioDemo`, with `-MEDSIM_SCENARIO_CODE <code>`). The script plays the instructor:
    /// it sends director events while this waits at the "await-director" steps.
    /// `-eventsA N` / `-eventsB N`: how many events to wait for before and after the link drop.
    private func scenarioDemo() async {
        guard SmokeLog.scenarioDemo, !SmokeLog.studioDemo else { return }
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
        openWindow(id: StudioView.windowId)
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
        await studio.launch(code: walkIn, model: model, openSpace: openImmersiveSpace) { dismissWindow(id: StudioView.windowId) }
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
        openWindow(id: StudioView.windowId)
        await pause(5)
        SmokeLog.mark("STEP t08-debrief")
        await pause(2)
        SmokeLog.mark("DONE")
    }
}

/// "Multi-stage journey · 3 places" and the places in order, or "Single encounter · 1 place".
struct JourneyTag: View {
    let stages: [String]?

    var body: some View {
        if let stages, !stages.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Label("Multi-stage journey · \(stages.count) places", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.orange.opacity(0.22), in: Capsule())
                Text(stages.joined(separator: " → ")).font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            Label("Single encounter · 1 place", systemImage: "person.fill")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.teal.opacity(0.22), in: Capsule())
        }
    }
}
