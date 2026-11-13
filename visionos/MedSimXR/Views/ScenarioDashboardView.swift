import SwiftUI

/// Look and wording of the options a case can allow. Unknown values still work: they get a
/// capitalised name and a neutral symbol, so a new case can list a mood the app has not met yet.
enum PatientOption {
    struct Info { let name: String, icon: String, detail: String }

    static func mood(_ id: String) -> Info {
        switch id {
        case "calm": Info(name: "Calm", icon: "leaf.fill", detail: "Relaxed and cooperative.")
        case "nervous": Info(name: "Nervous", icon: "exclamationmark.bubble.fill", detail: "Hesitant and worried. Needs reassurance.")
        case "angry": Info(name: "Angry", icon: "flame.fill", detail: "Annoyed about the wait. Short answers until acknowledged.")
        default: Info(name: id.replacingOccurrences(of: "_", with: " ").capitalized, icon: "person.fill", detail: "")
        }
    }

    static func avatar(_ id: String) -> Info {
        switch id {
        case "male": Info(name: "Male", icon: "figure.stand", detail: "A male patient.")
        case "female": Info(name: "Female", icon: "figure.stand.dress", detail: "A female patient.")
        default: Info(name: id.replacingOccurrences(of: "_", with: " ").capitalized, icon: "person.fill", detail: "")
        }
    }
}

/// Shown in the control panel while no session runs: pick a scenario, set up the patient, start.
/// Nothing here reveals a diagnosis; "Surprise me" keeps even the case hidden until Start.
struct ScenarioDashboardView<Footer: View>: View {
    @Environment(AppModel.self) private var model
    /// Scrolls the Customize section into view (automation).
    let focusCustomize: Bool
    let onStart: () -> Void
    @ViewBuilder let footer: Footer

    private let customizeId = "customize"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    scenarioGrid
                    customizeSection.id(customizeId)
                    if let err = model.lastError {
                        Label(err, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
                    }
                    footer
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .onChange(of: focusCustomize) { _, focus in
                if focus { withAnimation(.smooth) { proxy.scrollTo(customizeId, anchor: .top) } }
            }
        }
        .safeAreaInset(edge: .bottom) { startBar }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "cross.case.fill")
                .font(.title)
                .foregroundStyle(.teal)
                .frame(width: 52, height: 52)
                .background(.teal.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("MedSim XR").font(.title.bold())
                Text("Choose a patient encounter and set up how the patient comes across.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isBusy { ProgressView() }
        }
    }

    // MARK: Scenarios

    private var scenarioGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Scenario", icon: "rectangle.stack.fill")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14, alignment: .top)], spacing: 14) {
                ForEach(model.catalog, id: \.caseId) { item in
                    ScenarioCard(item: item, selected: !model.selection.surprise && model.selectedCase?.caseId == item.caseId) {
                        select(item)
                    }
                }
            }
            SurpriseCard(selected: model.selection.surprise) {
                model.selection.surprise = true
            }
        }
    }

    private func select(_ item: CaseInfo) {
        var next = model.selection
        next.surprise = false
        next.caseId = item.caseId
        model.selection = next
        model.normalizeSelection()
    }

    // MARK: Customize

    @ViewBuilder
    private var customizeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Customize", icon: "slider.horizontal.3")
            if model.selection.surprise {
                HStack(spacing: 12) {
                    Image(systemName: "questionmark.circle.fill").font(.title2).foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Random scenario").font(.headline)
                        Text("The case, the patient's mood and appearance are drawn when you press Start.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            } else {
                let catalog = model.selectedCase?.catalog ?? CaseCatalog()
                optionGroup(title: "Mood", icon: "theatermasks.fill", ids: catalog.allowedMoods,
                            current: model.selection.mood ?? catalog.defaultMood, info: PatientOption.mood) {
                    model.selection.mood = $0
                }
                optionGroup(title: "Patient", icon: "person.fill", ids: catalog.allowedAvatars,
                            current: model.selection.avatar ?? catalog.defaultAvatar, info: PatientOption.avatar) {
                    model.selection.avatar = $0
                }
            }
        }
    }

    /// Tiles to choose from. A case that allows a single value shows it locked instead.
    @ViewBuilder
    private func optionGroup(title: String, icon: String, ids: [String], current: String,
                             info: @escaping (String) -> PatientOption.Info, pick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if ids.count > 1 {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(ids, id: \.self) { id in
                        OptionTile(info: info(id), selected: id == current) { pick(id) }
                    }
                }
            } else if let only = ids.first {
                HStack(spacing: 10) {
                    Image(systemName: info(only).icon).frame(width: 28)
                    Text(info(only).name).font(.headline)
                    Spacer()
                    Label("Fixed for this scenario", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .opacity(0.85)
            }
        }
    }

    // MARK: Start

    private var startBar: some View {
        VStack(spacing: 6) {
            Button(action: onStart) {
                Label(model.selection.surprise ? "Start Random Scenario" : "Start Session", systemImage: "play.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .controlSize(.large)
            .disabled(model.isBusy || model.catalog.isEmpty)
            if let line = startSummary {
                Text(line).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    /// What Start will launch; for a random pick only that it is random.
    private var startSummary: String? {
        if model.selection.surprise { return "Case, mood and patient stay hidden until the session starts." }
        guard let item = model.selectedCase else { return nil }
        let cat = item.catalog ?? CaseCatalog()
        let mood = PatientOption.mood(model.selection.mood ?? cat.defaultMood).name
        let avatar = PatientOption.avatar(model.selection.avatar ?? cat.defaultAvatar).name
        return "\(item.title) · \(mood) · \(avatar)"
    }

    private func sectionTitle(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.title3.weight(.semibold))
    }
}

// MARK: - Cards

private struct ScenarioCard: View {
    let item: CaseInfo
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: item.catalog?.icon ?? "stethoscope")
                        .font(.title2)
                        .foregroundStyle(.teal)
                        .frame(width: 46, height: 46)
                        .background(.teal.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    Spacer()
                    SelectionMark(selected: selected)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.headline).multilineTextAlignment(.leading)
                    if let setting = item.catalog?.setting {
                        Text(setting).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let summary = item.catalog?.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                FlowLayout(spacing: 6) {
                    ForEach(item.catalog?.skills ?? [], id: \.self) { skill in
                        Text(skill)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
            .modifier(CardChrome(selected: selected))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SurpriseCard: View {
    let selected: Bool
    let action: () -> Void

    /// A slim banner under the case cards: the random pick needs no skills list.
    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .frame(width: 46, height: 46)
                    .background(.purple.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Surprise me").font(.headline)
                    Text("A random case with a random mood and patient. You will not know which until you start.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                SelectionMark(selected: selected)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardChrome(selected: selected))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct OptionTile: View {
    let info: PatientOption.Info
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: info.icon).font(.title3).foregroundStyle(selected ? .teal : .secondary)
                    Spacer()
                    SelectionMark(selected: selected)
                }
                Text(info.name).font(.headline)
                if !info.detail.isEmpty {
                    Text(info.detail)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: info.detail.count > 30 ? 92 : 72, alignment: .topLeading)
            .modifier(CardChrome(selected: selected, radius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SelectionMark: View {
    let selected: Bool
    var body: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(selected ? Color.teal : Color.secondary.opacity(0.5))
    }
}

/// Glass card with a teal outline when selected and a hover highlight.
private struct CardChrome: ViewModifier {
    let selected: Bool
    var radius: CGFloat = 20

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        content
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(selected ? Color.teal : Color.white.opacity(0.08), lineWidth: selected ? 3 : 1))
            .contentShape(.interaction, shape)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.highlight)
    }
}

/// Wraps its children onto new lines, like text.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), origins)
    }
}
