import SwiftUI
import RealityKit

struct ImmersivePatientView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("fingertipExam") private var fingertip = false
    @State private var avatar = PatientAvatar()
    @State private var placement = Placement()
    @State private var player = ReactionPlayer()
    @State private var lab = OrthoticsLab()
    @State private var us = UltrasoundScene()
    @State private var stage = ScenarioStage()
    @State private var panels = MovablePanels()

    /// Everything the scene's own tap and drag handle: all but the panel grab bars, which
    /// ManipulationComponent moves.
    private static let scene: QueryPredicate<Entity> = {
        MovablePanels.GrabBar.registerComponent() // a query on an unregistered component traps
        return !.has(MovablePanels.GrabBar.self)
    }()

    var body: some View {
        RealityView { content, attachments in
            avatar.root.transform = Placement.fallback
            content.add(avatar.root)
            if let notebook = attachments.entity(for: "notebook") {
                // Beside the patient (the wearer's right), at chest height, turned to the wearer.
                us.notebook = panels.add(notebook, to: avatar.root, at: [0.42, 1.3, 0.5], yaw: -0.35)
            }
            if let viewer = attachments.entity(for: "viewer") {
                // Further out than the notebook and nearer the wearer, so both can be read side by side.
                panels.add(viewer, to: avatar.root, at: [1.0, 1.3, 0.75], yaw: -0.6)
            }
            avatar.rebuildZones(model.zones)
            avatar.startIdle()
            await avatar.loadOptionalVisuals(variant: model.activeAvatarModel)
            model.behavior.attach(animated: avatar.isAnimated, recumbent: avatar.isRecumbent) { await avatar.apply($0) }
            await avatar.apply(model.behavior.machine, snap: true)
            lab.install(on: avatar)
            us.install(on: avatar)
            us.onContact = { region in
                if let region { Task { await model.scan(regionId: region) } } else { model.probeLeftBelly() }
            }
            us.onGel = { Task { await model.applyGel() } }
            us.build(model.ultrasound)
            us.setEnabled(model.phase == .running)
            if us.arrange(recumbent: avatar.isRecumbent) { model.recenter() }
            if let monitor = attachments.entity(for: "usMonitor") {
                panels.add(monitor, to: us.monitorMount, scale: 1.3)
            }
            if let panel = attachments.entity(for: "usPanel") { panels.add(panel, to: us.panelMount) }
            lab.onMeasure = { id, value in Task { await model.measure(id, valueCm: value) } }
            lab.onPlace = { size, offset in Task { await model.placeOrthosis(size: size, offsetCm: offset) } }
            lab.build(model.session?.case.orthotics ?? Orthotics())
            // Above the tray, scaled to be readable from the examination position.
            if let panel = attachments.entity(for: "fitting") {
                panels.add(panel, to: avatar.root, at: [-0.62, 1.38, 0.5], yaw: 0.35, scale: 1.5)
            }
            // The debrief replay: same spot (the fitting panel is gone by then), movable on its own.
            if let panel = attachments.entity(for: "replay") {
                panels.add(panel, to: avatar.root, at: [-0.62, 1.38, 0.5], yaw: 0.35, scale: 1.5)
            }
            panels.markHomes()
            panels.updates = content.subscribe(to: SceneEvents.Update.self) { [panels] _ in panels.layout() }
            stage.install(on: avatar)
            stage.sync(model.scenario)
            stage.showInjury(model.visibleInjury)
            model.stageStatus = stage.status
            SmokeLog.mark("immersive scene built zones=\(avatar.zoneEntities.count)")
        } attachments: {
            Attachment(id: "notebook") { NotebookView().environment(model) }
            Attachment(id: "viewer") { NotebookView.ViewerPanel().environment(model) }
            Attachment(id: "usMonitor") { UltrasoundMonitorView().environment(model) }
            Attachment(id: "usPanel") { UltrasoundPanel().environment(model) }
            Attachment(id: "fitting") { FittingPanel().environment(model) }
            Attachment(id: "replay") { ReplayPanel().environment(model) }
        }
        .gesture(
            SpatialTapGesture().targetedToEntity(where: Self.scene).onEnded { value in
                let id = value.entity.name
                let world = value.convert(value.location3D, from: .local, to: .scene)
                if us.item(value.entity) != nil { // probe or gel bottle: pick up (on the belly: lift off)
                    if id == UltrasoundScene.probeName, model.probeRegion != nil { model.liftProbe(); return }
                    model.selectedTool = model.selectedTool == id ? nil : id
                    SmokeLog.mark("tap tool=\(id) selected=\(model.selectedTool ?? "none")")
                    return
                }
                if let region = us.region(value.entity) {
                    SmokeLog.mark("tap region=\(region)")
                    Task { await model.tapRegion(region) }
                    return
                }
                if lab.item(value.entity) != nil { // first pinch: select (again: deselect)
                    model.selectedTool = model.selectedTool == id ? nil : id
                    SmokeLog.mark("tap tool=\(id) selected=\(model.selectedTool ?? "none")")
                    return
                }
                let isZone = model.zones.contains { $0.id == id }
                if let tool = model.selectedTool, isZone || id == OrthoticsLab.forearmTargetName {
                    // second pinch, on the arm: use the selected item where the arm was pinched
                    guard model.behavior.canExamine else { return }
                    lab.place(tool, atWorld: world)
                    model.selectedTool = nil
                    return
                }
                guard isZone else { return }
                SmokeLog.mark("tap zone=\(id)")
                Task { await model.examine(zoneId: id, contact: value.entity.convert(position: world, from: nil), source: .touch) }
            }
        )
        .gesture(
            // Move a tray item through the room; letting go over the forearm snaps it on.
            DragGesture().targetedToEntity(where: Self.scene)
                .onChanged { value in
                    if let item = us.item(value.entity) { // probe or gel bottle follows the hand
                        guard model.phase == .running else { return }
                        if model.selectedTool != item.name { model.selectedTool = item.name }
                        us.drag(item, to: value.convert(value.location3D, from: .local, to: avatar.root))
                        return
                    }
                    guard let item = lab.item(value.entity), model.behavior.canExamine else { return }
                    if model.selectedTool != item.name { model.selectedTool = item.name }
                    lab.drag(item, to: value.convert(value.location3D, from: .local, to: avatar.root))
                }
                .onEnded { value in
                    if let item = us.item(value.entity) { us.dropped(item); model.selectedTool = nil; return }
                    if let item = lab.item(value.entity) { lab.dropped(item); model.selectedTool = nil }
                }
        )
        .onChange(of: model.session?.case.orthotics) { _, orthotics in
            lab.build(orthotics ?? Orthotics())
            lab.sync(model.fit) // equipment delivered mid-session: a support already on the arm stays there
        }
        .modifier(StageSync(stage: stage))
        .onChange(of: model.session?.sessionId) { lab.build(model.session?.case.orthotics ?? Orthotics()) }
        .modifier(UltrasoundSync(model: model, us: us))
        .onChange(of: model.activeAvatarModel) { _, variant in
            // Stop -> change -> Start, or a reset into another case: swap the body, keep the scene.
            Task {
                await avatar.loadOptionalVisuals(variant: variant)
                model.behavior.attach(animated: avatar.isAnimated, recumbent: avatar.isRecumbent) { await avatar.apply($0) }
                await avatar.apply(model.behavior.machine, snap: true)
                avatar.rebuildZones(model.zones)
                us.build(model.ultrasound)
                us.setEnabled(model.phase == .running)
                lab.avatarChanged(fit: model.fit)
            }
        }
        .onChange(of: model.selectedTool) { _, tool in lab.select(tool); us.select(tool) }
        .onChange(of: model.labCommand) { _, command in
            if let command { lab.run(command); model.selectedTool = nil }
        }
        .onChange(of: model.fit) { _, fit in lab.sync(fit) }
        .onChange(of: model.measurements) { _, all in
            if let last = all.last { lab.measurement.setLabel(String(format: "%.1f cm", last.valueCm)) } else { lab.measurement.clear() }
        }
        .onChange(of: [model.teachingMode ? 1 : 0, model.replayStep, model.showAnatomy ? 1 : 0]) {
            let on = model.teachingMode && model.phase == .feedback
            let supportStep = on && model.replayEvent == nil
            lab.setTeaching(anatomy: on && model.showAnatomy, reference: supportStep ? model.feedback?.fitting.reference : nil)
            lab.showReplay(on ? model.feedback?.replay ?? [] : [], events: model.examEvents, current: model.replayEvent)
            if on {
                SmokeLog.mark("replay step=\(model.replayStep + 1)/\(model.replayStepCount) "
                    + "zone=\(model.replayEvent?.zoneId ?? "support") anatomy=\(model.showAnatomy)")
            }
        }
        .task(id: model.recenterToken) {
            let t = await placement.transform()
            avatar.root.move(to: t, relativeTo: nil, duration: 0.4)
            panels.reset() // re-centring also brings moved panels back beside the patient
            SmokeLog.mark("placed at \(t.translation) tracked=\(t != Placement.fallback)")
        }
        .onChange(of: model.zones) { _, zones in
            avatar.rebuildZones(zones)
            SmokeLog.mark("zones rebuilt \(avatar.zoneEntities.map(\.name))")
        }
        .onChange(of: model.behavior.canExamine, initial: true) { _, can in avatar.zonesEnabled = can }
        .onChange(of: model.reaction?.id) {
            guard let r = model.reaction else { return }
            Task { await avatar.play(animation: r.animation) }
            Task { await avatar.flashZone(r.clip, painful: r.painLevel >= 5) }
            Task { await player.handle(r) }
        }
        .task(id: fingertip) {
            guard fingertip else { return }
            await FingertipExaminer().run(avatar: avatar, model: model)
        }
        .onDisappear { avatar.stopIdle(); stage.stop(); model.stageStatus = "immersive scene not open" }
    }
}

/// Keeps the scenario stage in step with the model. Its own modifier so the view's
/// modifier chain stays short enough for the type checker.
private struct StageSync: ViewModifier {
    @Environment(AppModel.self) private var model
    let stage: ScenarioStage

    func body(content: Content) -> some View {
        content
            .onChange(of: model.scenario) { _, scenario in
                stage.sync(scenario)
                model.stageStatus = stage.status
                SmokeLog.mark("stage \(stage.status)")
            }
            .onChange(of: model.sceneLine) { _, line in if let line { stage.say(line) } }
            .onChange(of: model.phase) { _, phase in if phase != .running { stage.stop() } }
            .onChange(of: model.currentStage, initial: true) { showJourney() }
            .onChange(of: model.session?.sessionId) { showJourney(); stage.showInjury(model.visibleInjury) }
            .onChange(of: model.visibleInjury) { _, injury in stage.showInjury(injury) }
    }

    private func showJourney() {
        stage.showJourney(model.currentStage, team: model.teamPresent, position: model.stageIndex,
                          count: model.journey?.stages.count ?? 0)
        stage.showInjury(model.visibleInjury) // showJourney(nil) clears it; a journey keeps it
    }
}


/// Keeps the ultrasound corner in step with the model: case, session, phase, probe contact, gel.
private struct UltrasoundSync: ViewModifier {
    let model: AppModel
    let us: UltrasoundScene

    func body(content: Content) -> some View {
        content
            .onChange(of: model.session?.sessionId) {
                us.build(model.ultrasound)
                us.setEnabled(model.phase == .running)
            }
            .onChange(of: model.phase) { us.setEnabled(model.phase == .running) }
            .onChange(of: model.probeRegion) { us.sync(region: model.probeRegion, scans: model.scanSerial) }
            .onChange(of: model.scanSerial) { us.sync(region: model.probeRegion, scans: model.scanSerial) }
            .onChange(of: model.gelApplied) { _, applied in us.showGel(applied) }
    }
}
