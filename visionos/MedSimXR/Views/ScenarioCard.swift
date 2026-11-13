import SwiftUI

/// Scenario selection before a session (launch code or the published list) and the
/// scenario's live state during one. With no code the app runs the fixed default case.
struct ScenarioCard: View {
    @Environment(AppModel.self) private var model
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
        .task { await load() }
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
            TextField("Launch code (empty: default case)", text: $code)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
            ForEach(published) { s in
                Button { code = s.code } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.subheadline)
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
}
