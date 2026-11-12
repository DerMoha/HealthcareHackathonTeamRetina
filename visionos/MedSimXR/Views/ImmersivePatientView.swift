import SwiftUI
import RealityKit

struct ImmersivePatientView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("fingertipExam") private var fingertip = false
    @State private var avatar = PatientAvatar()
    @State private var placement = Placement()
    @State private var player = ReactionPlayer()

    var body: some View {
        RealityView { content in
            avatar.root.transform = Placement.fallback
            content.add(avatar.root)
            avatar.rebuildZones(model.zones)
            avatar.startIdle()
            await avatar.loadOptionalVisuals()
            SmokeLog.mark("immersive scene built zones=\(avatar.zoneEntities.count)")
        }
        .gesture(
            SpatialTapGesture().targetedToAnyEntity().onEnded { value in
                let id = value.entity.name
                guard model.zones.contains(where: { $0.id == id }) else { return }
                SmokeLog.mark("tap zone=\(id)")
                Task { await model.examine(zoneId: id) }
            }
        )
        .task(id: model.recenterToken) {
            let t = await placement.transform()
            avatar.root.move(to: t, relativeTo: nil, duration: 0.4)
            SmokeLog.mark("placed at \(t.translation) tracked=\(t != Placement.fallback)")
        }
        .onChange(of: model.zones) { _, zones in
            avatar.rebuildZones(zones)
            SmokeLog.mark("zones rebuilt \(avatar.zoneEntities.map(\.name))")
        }
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
