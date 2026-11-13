import SwiftUI
import RealityKit

struct ImmersivePatientView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("fingertipExam") private var fingertip = false
    @State private var avatar = PatientAvatar()
    @State private var placement = Placement()
    @State private var player = ReactionPlayer()
    @State private var lab = OrthoticsLab()
    @State private var stage = ScenarioStage()

    var body: some View {
        RealityView { content, attachments in
            avatar.root.transform = Placement.fallback
            content.add(avatar.root)
            if let notebook = attachments.entity(for: "notebook") {
                // Beside the patient (the wearer's right), at chest height, turned to the wearer.
                notebook.position = [0.42, 1.3, 0.5]
                notebook.orientation = simd_quatf(angle: -0.35, axis: [0, 1, 0])
                avatar.root.addChild(notebook)
            }
            avatar.rebuildZones(model.zones)
            avatar.startIdle()
            await avatar.loadOptionalVisuals()
            model.behavior.attach(animated: avatar.isAnimated) { await avatar.apply($0) }
            await avatar.apply(model.behavior.machine, snap: true)
            lab.install(on: avatar)
            lab.onMeasure = { id, value in Task { await model.measure(id, valueCm: value) } }
            lab.onPlace = { size, offset in Task { await model.placeOrthosis(size: size, offsetCm: offset) } }
            lab.build(model.session?.case.orthotics ?? Orthotics())
            if let panel = attachments.entity(for: "fitting") {
                panel.position = [-0.62, 1.38, 0.5] // above the tray
                panel.scale = [1.5, 1.5, 1.5] // readable from the examination position
                panel.orientation = simd_quatf(angle: 0.35, axis: [0, 1, 0])
                avatar.root.addChild(panel)
            }
            stage.install(on: avatar)
            stage.sync(model.scenario)
            model.stageStatus = stage.status
            SmokeLog.mark("immersive scene built zones=\(avatar.zoneEntities.count)")
        } attachments: {
            Attachment(id: "notebook") { NotebookView().environment(model) }
            Attachment(id: "fitting") {
                VStack { FittingPanel(); ReplayPanel() }.environment(model)
            }
        }
        .gesture(
            SpatialTapGesture().targetedToAnyEntity().onEnded { value in
                let id = value.entity.name
                let world = value.convert(value.location3D, from: .local, to: .scene)
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
            DragGesture().targetedToAnyEntity()
                .onChanged { value in
                    guard let item = lab.item(value.entity), model.behavior.canExamine else { return }
                    if model.selectedTool != item.name { model.selectedTool = item.name }
                    lab.drag(item, to: value.convert(value.location3D, from: .local, to: avatar.root))
                }
                .onEnded { value in
                    if let item = lab.item(value.entity) { lab.dropped(item); model.selectedTool = nil }
                }
        )
        .onChange(of: model.session?.case.orthotics) { _, orthotics in
            lab.build(orthotics ?? Orthotics())
            lab.sync(model.fit) // equipment delivered mid-session: a support already on the arm stays there
        }
        .modifier(StageSync(stage: stage))
        .onChange(of: model.session?.sessionId) { lab.build(model.session?.case.orthotics ?? Orthotics()) }
        .onChange(of: model.selectedTool) { _, tool in lab.select(tool) }
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
    }
}
