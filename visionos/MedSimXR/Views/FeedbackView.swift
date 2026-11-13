import SwiftUI

struct FeedbackView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let f = model.feedback {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero(f)
                    if !f.replay.isEmpty {
                        Button { model.startReplay() } label: {
                            Label("Open Spatial Clinical Replay", systemImage: "clock.arrow.circlepath").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.indigo)
                    }
                    Text(f.summary).font(.callout)
                    if let s = model.scenario, let d = model.debrief { scenarioDebrief(s, d) }

                    section("Categories") {
                        ForEach(f.categories) { CategoryCard(category: $0) }
                    }
                    management(f.management)
                    scored(f.fitting.title, f.fitting.score, f.fitting.maxScore, f.fitting.criteria, [
                        ("measurement", "Measurement"), ("fitting", "Size, position and tension"),
                        ("safety", "Circulation, sensation and comfort checks"),
                    ])
                    if let explanation = f.fitting.explanation {
                        Text(explanation).font(.callout)
                        Text("Educational fitting exercise, not a validated sizing method.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    list("Investigations requested", f.investigations, "rays", .teal)
                    list("Strengths", f.strengths, "checkmark.circle.fill", .green)
                    list("Missed", f.missed, "exclamationmark.circle.fill", .orange)
                    list("Relevant findings", f.relevantFindings, "stethoscope", .teal)
                    documentation(f.documentation)
                    list("Next steps", f.nextSteps, "arrow.right.circle.fill", .blue)

                    Button { Task { await model.reset() } } label: {
                        Label("Try Again", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.teal).disabled(model.isBusy)

                    Text(f.disclaimer).font(.caption).foregroundStyle(.secondary)
                }
                .padding(4)
            }
        }
    }

    /// How to read the score: what this scenario offered and what the instructor changed.
    private func scenarioDebrief(_ s: ScenarioRuntime, _ d: ScenarioDebrief) -> some View {
        section("Scenario: \(s.title)") {
            Text(s.reviewLabel).font(.caption).foregroundStyle(s.reviewState == "clinician_reviewed" ? .green : .orange)
            ForEach(d.interpretation, id: \.self) { Text($0).font(.callout) }
            ForEach(d.timeline.filter { $0.type == "intervention" || $0.type == "hint" }, id: \.seq) { step in
                Label(step.label, systemImage: step.type == "hint" ? "lightbulb" : "person.wave.2")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private static let areas = [
        ("investigation", "Investigation choices"), ("interpretation", "Interpretation of results"),
        ("management", "Management decisions"), ("safety", "Safety after inconclusive imaging"),
    ]

    /// Separate dimension: shown with its own score, never added to the 100 points.
    private func management(_ m: ManagementAssessment) -> some View {
        scored(m.title, m.score, m.maxScore, m.criteria, Self.areas)
    }

    @ViewBuilder
    private func scored(_ title: String, _ score: Int, _ maxScore: Int, _ criteria: [CriterionResult],
                        _ areas: [(String, String)]) -> some View {
        if !criteria.isEmpty {
            section("\(title) · \(score)/\(maxScore)") {
                Text("Scored separately from the 100 points above.").font(.caption).foregroundStyle(.secondary)
                ForEach(areas, id: \.0) { area, title in
                    Text(title).font(.subheadline.bold())
                    ForEach(criteria.filter { $0.area == area }) { c in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(c.label) · \(c.points)/\(c.maxPoints)").font(.callout.weight(.medium))
                                Text(c.comment).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: c.met ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(c.met ? .green : .red)
                        }
                    }
                }
            }
        }
    }

    /// Notebook versus session record: written and done, done but not written, written but never done.
    @ViewBuilder
    private func documentation(_ items: [DocumentationItem]) -> some View {
        if !items.isEmpty {
            section("Your notes vs. what happened") {
                ForEach(items) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label).font(.callout.weight(.medium))
                            Text(item.comment).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        switch item.status {
                        case "documented": Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case "unsupported": Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        default: Image(systemName: "pencil.slash").foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private func hero(_ f: Feedback) -> some View {
        let frac = f.maxScore > 0 ? Double(f.totalScore) / Double(f.maxScore) : 0
        let a = f.diagnosticAssessment
        return HStack(spacing: 20) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 12)
                Circle().trim(from: 0, to: frac)
                    .stroke(scoreColor(frac), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(f.totalScore)").font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("of \(f.maxScore)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 130, height: 130)

            VStack(alignment: .leading, spacing: 6) {
                Text(a.verdict.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.headline)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(verdictColor(a.verdict).opacity(0.25), in: Capsule())
                    .foregroundStyle(verdictColor(a.verdict))
                Text(a.explanation).font(.callout)
                if let d = f.diagnosisSubmitted {
                    Text("Your answer: \(d)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func scoreColor(_ f: Double) -> Color { f >= 0.75 ? .green : f >= 0.5 ? .orange : .red }
    private func verdictColor(_ v: String) -> Color {
        switch v { case "correct": .green; case "partial": .orange; case "incorrect": .red; default: .secondary }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    @ViewBuilder
    private func list(_ title: String, _ items: [String], _ icon: String, _ color: Color) -> some View {
        if !items.isEmpty {
            section(title) {
                ForEach(items, id: \.self) { item in
                    Label { Text(item).font(.callout) } icon: { Image(systemName: icon).foregroundStyle(color) }
                }
            }
        }
    }
}

private struct CategoryCard: View {
    let category: CategoryResult
    @State private var open = false

    var body: some View {
        let frac = category.maxScore > 0 ? Double(category.score) / Double(category.maxScore) : 0
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation { open.toggle() } } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(category.title).font(.subheadline.bold())
                        Spacer()
                        Text("\(category.score)/\(category.maxScore)").font(.subheadline.monospacedDigit())
                        Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption)
                    }
                    ProgressView(value: frac).tint(frac >= 0.75 ? .green : frac >= 0.5 ? .orange : .red)
                }
            }
            .buttonStyle(.plain)

            if open {
                ForEach(category.criteria) { c in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: c.met ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(c.met ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(c.label).font(.callout.weight(.medium))
                                if c.method == "keyword" {
                                    Text("heuristic").font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(.orange.opacity(0.25), in: Capsule())
                                }
                                Spacer()
                                Text("\(c.points)/\(c.maxPoints)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Text(c.comment).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
