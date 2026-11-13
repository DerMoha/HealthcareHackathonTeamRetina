import SwiftUI

/// Compact floating panel above the equipment tray. Placement happens in the room: pinch an
/// item, then pinch the forearm (or drag it there). The panel shows what is selected, the
/// measured values, adjustments for the support on the arm, and the two recorded checks.
struct FittingPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.phase == .running, let orthotics = model.session?.case.orthotics, !orthotics.sizes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !model.behavior.canExamine {
                    Label("Equipment: once the patient is seated", systemImage: "ruler").font(.callout)
                } else {
                    selection(orthotics)
                    if !model.measurements.isEmpty {
                        Text(model.measurements.map { "\($0.kind == "circumference" ? "Wrist" : "Forearm") \(String(format: "%.1f", $0.valueCm)) cm" }
                            .joined(separator: "  ·  "))
                            .font(.callout.monospacedDigit().bold())
                    }
                    if let fit = model.fit { adjust(fit, orthotics) }
                    checks
                }
            }
            .padding(16)
            .frame(width: 340, alignment: .leading)
            .glassBackgroundEffect()
        }
    }

    @ViewBuilder
    private func selection(_ orthotics: Orthotics) -> some View {
        if let tool = model.selectedTool {
            let name = tool == OrthoticsLab.tapeName ? "Tape"
                : (orthotics.sizes.first { OrthoticsLab.orthosisPrefix + $0.id == tool }?.label ?? "") + " support"
            HStack {
                Label("\(name) selected", systemImage: "hand.point.up.left.fill").font(.callout.bold()).foregroundStyle(.teal)
                Spacer()
                Button("Cancel") { model.selectedTool = nil }.controlSize(.small)
            }
            Text("Pinch the patient's right forearm to use it there.").font(.caption).foregroundStyle(.secondary)
        } else if model.fit == nil {
            Label("Pinch an item on the tray", systemImage: "ruler").font(.callout).foregroundStyle(.secondary)
        }
    }

    private func adjust(_ fit: OrthosisFit, _ orthotics: Orthotics) -> some View {
        let label = orthotics.sizes.first { $0.id == fit.size }?.label ?? fit.size
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(label) support on · straps \(fit.tightness)").font(.callout.bold())
            HStack {
                Button { Task { await model.adjustFit { $0.offsetCm -= 1 } } } label: { Image(systemName: "arrow.down") }
                    .accessibilityLabel("Move toward the hand")
                Button { Task { await model.adjustFit { $0.offsetCm += 1 } } } label: { Image(systemName: "arrow.up") }
                    .accessibilityLabel("Move toward the elbow")
                Button { Task { await model.adjustFit { $0.orientation = $0.orientation == "thumb_radial" ? "thumb_ulnar" : "thumb_radial" } } }
                    label: { Image(systemName: "arrow.triangle.2.circlepath") }.accessibilityLabel("Turn the support around")
                Button("Loosen") { Task { await model.stepTightness(-1) } }.disabled(fit.tightness == orthotics.tightness.first)
                Button("Tighten") { Task { await model.stepTightness(1) } }.disabled(fit.tightness == orthotics.tightness.last)
            }
            Button("Take off", role: .destructive) { Task { await model.setFit(nil) } }
        }
        .buttonStyle(.bordered).controlSize(.small)
    }

    private var checks: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { Task { await model.fittingCheck("comfort") } } label: { Label("Ask how it feels", systemImage: "bubble.left") }
                Button { Task { await model.fittingCheck("neurovascular") } } label: { Label("Check fingers", systemImage: "hand.raised") }
            }
            .buttonStyle(.bordered).controlSize(.small)
            if let check = model.lastCheck {
                Text(check.finding ?? "\u{201C}\(check.patientResponse)\u{201D}").font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
    }
}

/// Spatial Clinical Replay: steps through what was actually examined, in order, then the
/// support placement. Shown instead of the fitting panel, only after submission.
struct ReplayPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.teachingMode, model.phase == .feedback, let feedback = model.feedback {
            @Bindable var model = model
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Spatial Clinical Replay", systemImage: "clock.arrow.circlepath").font(.headline)
                    Spacer()
                    Button { model.exitReplay() } label: { Label("Exit", systemImage: "xmark") }
                        .buttonStyle(.borderedProminent).tint(.red)
                }
                Text("Step \(model.replayStep + 1) of \(model.replayStepCount)").font(.caption).foregroundStyle(.secondary)
                if let event = model.replayEvent {
                    step(event, feedback.replay.first { $0.zoneId == event.zoneId })
                } else {
                    support(feedback.fitting)
                }
                HStack {
                    Button { model.replayStep -= 1 } label: { Label("Back", systemImage: "chevron.left") }
                        .disabled(model.replayStep == 0)
                    Button { model.replayStep += 1 } label: { Label("Next", systemImage: "chevron.right") }
                        .disabled(model.replayStep >= model.replayStepCount - 1)
                    Spacer()
                    Toggle("Anatomy", isOn: $model.showAnatomy).toggleStyle(.button)
                }
                .buttonStyle(.bordered).controlSize(.small)
                let missed = feedback.replay.filter { !$0.examined }
                if !missed.isEmpty {
                    Divider()
                    Text("Not examined").font(.caption.bold()).foregroundStyle(.orange)
                    ForEach(missed) { zone in
                        Text("\(zone.label)\(zone.important ? " (key area)" : ""): \(zone.explanation)").font(.caption)
                    }
                }
                Text("Schematic anatomy for illustration only; not anatomically validated. Markers show recorded examination areas, not hand paths.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 400, alignment: .leading)
            .glassBackgroundEffect()
        }
    }

    private func step(_ event: ExamEvent, _ zone: ReplayZone?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(zone?.label ?? event.zoneId).font(.callout.bold())
            Text("\(String(format: "%d:%02d", Int(event.time) / 60, Int(event.time) % 60)) · \(event.action) · "
                + "\(event.finding.replacingOccurrences(of: "_", with: " ")), pain \(event.painLevel)/10")
                .font(.caption.monospacedDigit())
            Text("Patient \(event.pose.replacingOccurrences(of: "_", with: " ")) · recorded by \(event.source.rawValue)"
                + (event.contact == nil ? " · no contact point" : ""))
                .font(.caption).foregroundStyle(.secondary)
            if let zone { Text(zone.explanation).font(.callout) }
        }
    }

    private func support(_ fitting: FittingAssessment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Wrist support").font(.callout.bold())
            if let fit = fitting.finalFit {
                Text("Yours: \(fit.size), \(String(format: "%g", fit.offsetCm)) cm above the wrist joint, straps \(fit.tightness), "
                    + "thumb opening \(fit.orientation == "thumb_radial" ? "on the thumb side" : "on the little-finger side")").font(.caption)
            } else {
                Text("Yours: no support left on the arm").font(.caption)
            }
            if let ref = fitting.reference {
                Text("Reference (green): \(ref.size), \(ref.offsetCm.map { String(format: "%g", $0) }.joined(separator: "–")) cm, "
                    + "straps \(ref.tightness), thumb opening on the thumb side").font(.caption).foregroundStyle(.green)
            }
            if let explanation = fitting.explanation { Text(explanation).font(.callout) }
        }
    }
}
