import SwiftUI

/// Compact floating panel above the equipment tray. Placement happens in the room: pinch an
/// item, then pinch the forearm (or drag it there). The panel shows what is selected, the
/// measured values, adjustments for the support on the arm, and the two recorded checks.
struct FittingPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.phase == .running, !SmokeLog.pitch || Pitch.shared.showFitting, let orthotics = model.session?.case.orthotics, !orthotics.sizes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                header
                if !model.behavior.canExamine {
                    Label("Equipment: once the patient is seated", systemImage: "ruler").font(.callout).foregroundStyle(.secondary)
                } else {
                    selection(orthotics)
                    measurements(orthotics)
                    sizes(orthotics)
                    if let fit = model.fit { adjust(fit, orthotics) }
                    checks
                }
            }
            .padding(22)
            .frame(width: 470, alignment: .leading)
            .glassBackgroundEffect(in: .rect(cornerRadius: 32))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fingers.spread.fill")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(LinearGradient(colors: [.teal, .teal.opacity(0.6)], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 12))
            Text("Wrist support fitting").font(.title3.weight(.bold))
            Spacer()
            if model.fit != nil {
                Text("ON THE ARM").font(.callout.weight(.heavy)).tracking(1).foregroundStyle(.teal)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(.teal.opacity(0.18), in: .capsule)
            }
        }
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.callout.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func selection(_ orthotics: Orthotics) -> some View {
        if let tool = model.selectedTool {
            let name = tool == OrthoticsLab.tapeName ? "Tape"
                : (orthotics.sizes.first { OrthoticsLab.orthosisPrefix + $0.id == tool }?.label ?? "") + " support"
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "hand.point.up.left.fill").foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(name) selected").font(.callout.bold())
                    Text("Pinch the patient's right forearm to use it there.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { model.selectedTool = nil }.controlSize(.small)
            }
            .padding(12)
            .background(.teal.opacity(0.14), in: .rect(cornerRadius: 14))
        } else if model.fit == nil {
            Label("Pinch an item on the tray", systemImage: "ruler").font(.callout).foregroundStyle(.secondary)
        }
    }

    private func measurements(_ orthotics: Orthotics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            section("MEASUREMENTS")
            HStack(spacing: 10) {
                ForEach(orthotics.measurements) { info in
                    let value = model.measurements.first { $0.measurementId == info.id }?.valueCm
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.kind == "circumference" ? "Wrist" : "Forearm").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(value.map { String(format: "%.1f", $0) } ?? "–")
                                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                            Text("cm").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.07), in: .rect(cornerRadius: 14))
                }
            }
        }
    }

    /// The tray's sizes; pinching one selects it, like pinching it on the tray.
    private func sizes(_ orthotics: Orthotics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            section("SIZE")
            HStack(spacing: 8) {
                ForEach(orthotics.sizes) { size in
                    let on = model.fit?.size == size.id
                    Button { model.selectedTool = OrthoticsLab.orthosisPrefix + size.id } label: {
                        VStack(spacing: 2) {
                            Text(size.label).font(.title3.weight(.semibold))
                            Text(size.wristCm.map { String(format: "%g", $0) }.joined(separator: "–") + " cm")
                                .font(.callout.monospacedDigit()).foregroundStyle(on ? .black.opacity(0.75) : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 12))
                    .tint(on ? .teal : nil)
                    .foregroundStyle(on ? .black : .primary)
                }
            }
        }
    }

    private func adjust(_ fit: OrthosisFit, _ orthotics: Orthotics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            section("STRAPS")
            HStack(spacing: 8) {
                Button { Task { await model.stepTightness(-1) } } label: { Image(systemName: "minus") }
                    .accessibilityLabel("Loosen").disabled(fit.tightness == orthotics.tightness.first)
                HStack(spacing: 4) {
                    ForEach(orthotics.tightness, id: \.self) { level in
                        Text(level.capitalized).font(.callout.weight(.bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(level == fit.tightness ? AnyShapeStyle(.teal) : AnyShapeStyle(.white.opacity(0.06)), in: .capsule)
                            .foregroundStyle(level == fit.tightness ? .black : .secondary)
                    }
                }
                Button { Task { await model.stepTightness(1) } } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Tighten").disabled(fit.tightness == orthotics.tightness.last)
            }
            section("POSITION")
            HStack(spacing: 8) {
                Button { Task { await model.adjustFit { $0.offsetCm -= 1 } } } label: { Label("Hand", systemImage: "arrow.down") }
                    .accessibilityLabel("Move toward the hand")
                Button { Task { await model.adjustFit { $0.offsetCm += 1 } } } label: { Label("Elbow", systemImage: "arrow.up") }
                    .accessibilityLabel("Move toward the elbow")
                Button { Task { await model.adjustFit { $0.orientation = $0.orientation == "thumb_radial" ? "thumb_ulnar" : "thumb_radial" } } }
                    label: { Image(systemName: "arrow.triangle.2.circlepath") }.accessibilityLabel("Turn the support around")
                Spacer(minLength: 0)
                Button(role: .destructive) { Task { await model.setFit(nil) } } label: { Label("Take off", systemImage: "xmark").foregroundStyle(Color(red: 1, green: 0.5, blue: 0.5)) }
            }
        }
        .buttonStyle(.bordered).controlSize(.regular)
    }

    private var checks: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("CHECKS")
            HStack(spacing: 8) {
                Button { Task { await model.fittingCheck("comfort") } } label: {
                    Label("Ask how it feels", systemImage: "bubble.left.fill").frame(maxWidth: .infinity)
                }
                Button { Task { await model.fittingCheck("neurovascular") } } label: {
                    Label("Check fingers", systemImage: "hand.raised.fill").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered).controlSize(.regular)
            if let check = model.lastCheck, !SmokeLog.pitch { // pitch: the conversation card carries the answer
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: check.check == "comfort" ? "quote.opening" : "waveform.path.ecg")
                        .foregroundStyle(check.comfortable ? .teal : .orange)
                    Text(check.finding ?? check.patientResponse).font(.callout).lineLimit(3)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
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
