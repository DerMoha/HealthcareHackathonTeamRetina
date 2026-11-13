import SwiftUI

/// Compact floating panel above the orthotics tray: measured values, adjustments for the
/// support on the arm, and the explicit comfort / circulation checks. Placement itself is
/// done by dragging tray items onto the arm; the buttons here are the gaze-and-pinch fallback.
struct FittingPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.phase == .running, let orthotics = model.session?.case.orthotics, !orthotics.sizes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Orthotics tray", systemImage: "ruler").font(.headline)
                if !model.behavior.canExamine {
                    Text("Available once the patient is seated.").font(.caption).foregroundStyle(.secondary)
                } else {
                    tools(orthotics)
                    if let fit = model.fit { adjust(fit, orthotics) }
                    checks
                }
            }
            .padding(18)
            .frame(width: 380, alignment: .leading)
            .glassBackgroundEffect()
        }
    }

    @ViewBuilder
    private func tools(_ orthotics: Orthotics) -> some View {
        ForEach(model.measurements) { m in
            HStack {
                Text(m.label).font(.callout)
                Spacer()
                Text(String(format: "%.1f cm", m.valueCm)).font(.callout.monospacedDigit().bold())
            }
        }
        if model.selectedTool == OrthoticsLab.tapeName {
            Text("Drag the tape to the arm, or:").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Measure wrist") { model.labCommand = LabCommand(item: OrthoticsLab.tapeName, axialCm: 1, radialCm: 3) }
                Button("Measure forearm") { model.labCommand = LabCommand(item: OrthoticsLab.tapeName, axialCm: 14, radialCm: 3) }
            }
        } else if model.selectedTool != nil, model.fit == nil {
            Text("Drag the support onto the patient's arm.").font(.caption).foregroundStyle(.secondary)
        } else if model.measurements.isEmpty, model.fit == nil {
            Text("Pinch an item on the tray to pick it up, then drag it to the patient's arm.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func adjust(_ fit: OrthosisFit, _ orthotics: Orthotics) -> some View {
        let label = orthotics.sizes.first { $0.id == fit.size }?.label ?? fit.size
        return VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("\(label) support on the arm · straps \(fit.tightness)").font(.callout.bold())
            HStack {
                Button { Task { await model.adjustFit { $0.offsetCm -= 1 } } } label: { Label("To hand", systemImage: "arrow.down") }
                Button { Task { await model.adjustFit { $0.offsetCm += 1 } } } label: { Label("To elbow", systemImage: "arrow.up") }
                Button { Task { await model.adjustFit { $0.orientation = $0.orientation == "thumb_radial" ? "thumb_ulnar" : "thumb_radial" } } }
                    label: { Label("Turn", systemImage: "arrow.triangle.2.circlepath") }
            }
            HStack {
                Button("Loosen") { Task { await model.stepTightness(-1) } }.disabled(fit.tightness == orthotics.tightness.first)
                Button("Tighten") { Task { await model.stepTightness(1) } }.disabled(fit.tightness == orthotics.tightness.last)
                Button("Take off", role: .destructive) { Task { await model.setFit(nil) } }
            }
        }
        .buttonStyle(.bordered).controlSize(.small)
    }

    private var checks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Button { Task { await model.fittingCheck("comfort") } } label: { Label("Ask how it feels", systemImage: "bubble.left") }
                Button { Task { await model.fittingCheck("neurovascular") } } label: { Label("Check fingers", systemImage: "hand.raised") }
            }
            .buttonStyle(.bordered).controlSize(.small)
            if let check = model.lastCheck {
                if let finding = check.finding {
                    Text("Circulation, sensation, movement: \(finding)").font(.caption)
                }
                Text("\u{201C}\(check.patientResponse)\u{201D}").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
