import SwiftUI
import RealityKit

struct ImmersivePatientView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("fingertipExam") private var fingertip = false
    @State private var avatar = PatientAvatar()
    @State private var placement = Placement()
    @State private var player = ReactionPlayer()
    @State private var lab = OrthoticsLab()

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
                panel.position = [-0.62, 1.34, 0.5] // above the tray
                panel.orientation = simd_quatf(angle: 0.35, axis: [0, 1, 0])
                avatar.root.addChild(panel)
            }
            SmokeLog.mark("immersive scene built zones=\(avatar.zoneEntities.count)")
        } attachments: {
            Attachment(id: "notebook") { NotebookView().environment(model) }
            Attachment(id: "fitting") { FittingPanel().environment(model) }
        }
        .gesture(
            SpatialTapGesture().targetedToAnyEntity().onEnded { value in
                let id = value.entity.name
                if lab.item(value.entity) != nil { // pick up a tray item
                    model.selectedTool = id
                    SmokeLog.mark("tap tool=\(id)")
                    return
                }
                guard model.zones.contains(where: { $0.id == id }) else { return }
                SmokeLog.mark("tap zone=\(id)")
                Task { await model.examine(zoneId: id) }
            }
        )
        .gesture(
            // Move a tray item through the room; letting go over the forearm snaps it on.
            DragGesture().targetedToAnyEntity()
                .onChanged { value in
                    guard let item = lab.item(value.entity), model.behavior.canExamine else { return }
                    model.selectedTool = item.name
                    lab.drag(item, to: value.convert(value.location3D, from: .local, to: avatar.root))
                }
                .onEnded { value in
                    if let item = lab.item(value.entity) { lab.dropped(item) }
                }
        )
        .onChange(of: model.session?.case.orthotics) { _, orthotics in lab.build(orthotics ?? Orthotics()) }
        .onChange(of: model.session?.sessionId) { lab.build(model.session?.case.orthotics ?? Orthotics()) }
        .onChange(of: model.selectedTool) { _, tool in lab.highlight(tool) }
        .onChange(of: model.labCommand) { _, command in if let command { lab.run(command) } }
        .onChange(of: model.fit) { _, fit in lab.sync(fit) }
        .onChange(of: model.measurements) { _, all in
            if let last = all.last { lab.measurement.setLabel(String(format: "%.1f cm", last.valueCm)) } else { lab.measurement.clear() }
        }
        .onChange(of: model.teachingMode) { _, on in
            lab.setTeaching(on && model.phase == .feedback ? model.feedback?.fitting.reference : nil, learner: model.fit)
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
        .onDisappear { avatar.stopIdle() }
    }
}
