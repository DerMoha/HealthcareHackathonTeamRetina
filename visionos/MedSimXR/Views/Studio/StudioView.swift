import SwiftUI

/// MedSim Studio inside the headset: the side tab bar holds the overview, the scenario library
/// (split into own and downloaded), the marketplace, debriefs and a pointer to the authoring
/// form. Launching a scenario here is the same as typing its code and pressing Start Session.
struct StudioView: View {
    static let windowId = "studio"

    @Environment(StudioState.self) private var studio

    var body: some View {
        @Bindable var studio = studio
        TabView(selection: $studio.tab) {
            ForEach(StudioState.Tab.allCases) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab) { page(tab) }
            }
        }
        .task { await studio.reload() }
        .onAppear { SmokeLog.mark("studio window shown tab=\(studio.tab.rawValue)") }
        .onDisappear { SmokeLog.mark("studio window closed") }
        .onChange(of: studio.tab) { _, _ in Task { await studio.reload() } }
    }

    @ViewBuilder private func page(_ tab: StudioState.Tab) -> some View {
        switch tab {
        case .overview: StudioOverview()
        case .mine: StudioLibrary(scope: .mine)
        case .downloaded: StudioLibrary(scope: .downloaded)
        case .marketplace: StudioMarketplace()
        case .debrief: StudioDebriefPage()
        case .create: StudioCreate()
        }
    }
}

// MARK: - Shared pieces

/// Launch a published scenario from anywhere in the Studio.
struct LaunchButton: View {
    let code: String
    var prominent = true
    @Environment(AppModel.self) private var model
    @Environment(StudioState.self) private var studio
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let button = Button {
            Task {
                await studio.launch(code: code, model: model, openSpace: openImmersiveSpace) {
                    dismissWindow(id: StudioView.windowId)
                }
            }
        } label: { Label("Launch", systemImage: "play.fill") }
        .disabled(studio.busy || model.phase != .idle)
        if prominent { button.buttonStyle(.borderedProminent).tint(.teal) } else { button.buttonStyle(.bordered) }
    }
}

struct ReviewBadge: View {
    let state: String
    var body: some View {
        Text(state.reviewStateLabel)
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.25), in: Capsule())
            .foregroundStyle(color)
    }
    private var color: Color {
        switch state {
        case "clinician_reviewed": .green
        case "experimental": .orange
        default: .secondary
        }
    }
}

/// Error and notice lines under a page title.
struct StudioMessages: View {
    @Environment(StudioState.self) private var studio
    var body: some View {
        if studio.messageTab != studio.tab {
            EmptyView()   // a message belongs to the page it came from
        } else if let e = studio.error {
            Label(e, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
        } else if let n = studio.notice {
            Label(n, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
        }
    }
}

struct StudioPage<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content
    @Environment(StudioState.self) private var studio

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(title).font(.largeTitle.bold())
                    Spacer()
                    if studio.loading || studio.busy { ProgressView() }
                    Button { Task { await studio.reload() } } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh")
                }
                if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
                StudioMessages()
                content
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StudioCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}

func studioDate(_ iso: String) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = f.date(from: iso) ?? { f.formatOptions = [.withInternetDateTime]; return f.date(from: iso) }()
    return date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? iso
}

// MARK: - Overview

struct StudioOverview: View {
    @Environment(StudioState.self) private var studio
    @Environment(AppModel.self) private var model

    var body: some View {
        StudioPage(title: "Overview") {
            HStack(alignment: .top, spacing: 16) {
                StudioCard {
                    Text("Last session").font(.headline)
                    if let s = studio.sessions.first {
                        Text(s.title).font(.title3.bold())
                        Text("\(s.code) · started \(studioDate(s.startedAt)) · \(s.submitted ? "diagnosis submitted" : "in progress")")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Open debrief") { studio.debriefSession = s.sessionId; studio.tab = .debrief }
                            .buttonStyle(.bordered)
                    } else {
                        Text("No scenario session yet. Launch one from My scenarios or the Marketplace.")
                            .foregroundStyle(.secondary)
                    }
                }
                StudioCard {
                    Text("Last scenario").font(.headline)
                    if let r = studio.library.first {
                        HStack { Text(r.title).font(.title3.bold()); ReviewBadge(state: r.reviewState) }
                        Text("v\(r.version) · \(r.environment) · \(r.difficulty) · \(r.isPublished ? "code \(r.code)" : "not published")")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            if r.isPublished { LaunchButton(code: r.code) }
                            Button("Open") { studio.open(r.scenarioId, downloaded: r.isDownloaded) }.buttonStyle(.bordered)
                        }
                    } else {
                        Text(studio.loaded ? "No scenarios yet." : "Loading…").foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 16) {
                stat(studio.mine.count, "My scenarios", .mine)
                stat(studio.downloaded.count, "Downloaded", .downloaded)
                stat(studio.market.count, "Published", .marketplace)
                stat(studio.sessions.filter { !$0.submitted }.count, "Sessions in progress", .debrief)
            }
            if model.phase != .idle {
                Label("A session is running. Stop it in the control panel to launch another scenario.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ n: Int, _ label: String, _ tab: StudioState.Tab) -> some View {
        Button { studio.tab = tab } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(n)").font(.largeTitle.bold())
                Text(label).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Library (My scenarios, Downloaded)

struct StudioLibrary: View {
    enum Scope { case mine, downloaded }
    let scope: Scope
    @Environment(StudioState.self) private var studio

    private var rows: [StudioScenarioRow] { scope == .mine ? studio.mine : studio.downloaded }

    var body: some View {
        @Bindable var studio = studio
        NavigationSplitView {
            List(rows, selection: $studio.selected) { r in
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.title).font(.headline)
                    HStack(spacing: 6) {
                        ReviewBadge(state: r.reviewState)
                        Text("v\(r.version) · \(r.isPublished ? r.code : "not published")").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(r.environment) · \(r.difficulty)").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .tag(r.scenarioId)
            }
            .overlay {
                if studio.loaded && rows.isEmpty {
                    ContentUnavailableView(scope == .mine ? "Nothing here yet" : "Nothing downloaded yet",
                        systemImage: scope == .mine ? "folder" : "arrow.down.circle",
                        description: Text(scope == .mine ? "Create a scenario in the web Studio, or duplicate one."
                                                         : "Download a copy from the Marketplace."))
                }
            }
            .navigationTitle(scope == .mine ? "My scenarios" : "Downloaded")
        } detail: {
            if let id = studio.selected, rows.contains(where: { $0.scenarioId == id }) {
                StudioScenarioDetailView(scenarioId: id).id(id)
            } else {
                ContentUnavailableView("Select a scenario", systemImage: "doc.text.magnifyingglass",
                    description: Text(scope == .mine ? "Scenarios created in the Studio or duplicated here."
                                                     : "Copies from the marketplace start as drafts and need their own review before use."))
            }
        }
    }
}

struct StudioScenarioDetailView: View {
    let scenarioId: String
    @Environment(StudioState.self) private var studio
    @State private var detail: StudioScenarioDetail?
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let d = detail { content(d) } else if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                } else { ProgressView() }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: studio.library) { await load() }
    }

    private func load() async {
        do { detail = try await StudioClient.scenario(scenarioId); loadError = nil }
        catch { loadError = error.localizedDescription }
    }

    @ViewBuilder private func content(_ d: StudioScenarioDetail) -> some View {
        let row = studio.library.first { $0.scenarioId == scenarioId }
        HStack(alignment: .firstTextBaseline) {
            Text(d.title).font(.title.bold())
            ReviewBadge(state: d.review.state)
        }
        StudioMessages()
        if let row, row.isPublished {
            HStack(spacing: 12) {
                Text(row.code).font(.system(.title, design: .monospaced).bold()).foregroundStyle(.teal)
                Text("published v\(row.publishedVersion ?? 0)\(row.publishedVersion == row.version ? "" : ", newer v\(row.version) not published")")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Not published. Publish to launch it; a draft becomes experimental, never clinician-reviewed.")
                .foregroundStyle(.secondary)
        }
        HStack {
            if let row, row.isPublished { LaunchButton(code: row.code) }
            if row?.publishedVersion != row?.version {
                Button(row?.isPublished == true ? "Publish latest version" : "Publish") {
                    Task { await studio.act("Published \"\(d.title)\".") { try await StudioClient.publish(scenarioId, true) } }
                }.buttonStyle(.bordered)
            }
            if row?.isPublished == true {
                Button("Unpublish") {
                    Task { await studio.act("Unpublished \"\(d.title)\".") { try await StudioClient.publish(scenarioId, false) } }
                }.buttonStyle(.bordered)
            }
            Button("Duplicate") {
                Task {
                    if let copy = await studio.act("Duplicated as a new draft in My scenarios.", { try await StudioClient.duplicate(scenarioId) }) {
                        studio.open(copy.scenarioId, downloaded: false)
                    }
                }
            }.buttonStyle(.bordered)
        }
        .disabled(studio.busy)
        if let origin = d.origin { Text(originText(origin)).font(.callout).foregroundStyle(.secondary) }
        if !d.narrative.description.isEmpty { Text(d.narrative.description) }

        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            fact("Setting", "\(d.environment.label). \(d.environment.brief)")
            fact("Crowd", "\(d.environment.crowd.label), \(d.environment.crowd.figures.count) people in the room, noise \(Int(d.environment.ambientLevel * 100))%")
            fact("Difficulty", "\(d.difficulty.label): \(d.difficulty.description)")
            fact("Bystander", d.companions.bystander.map { "\($0.name), \($0.roleLabel), \($0.mood)" } ?? "None")
            fact("Teammate", "\(d.companions.teammate.name), \(d.companions.teammate.roleLabel), "
                 + (d.companions.teammate.present ? "in the room from the start" : "not there at the start; the instructor can send them in"))
            fact("Seed", "\(d.seed)")
        }
        Text("Equipment").font(.headline)
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            ForEach(d.resources) { r in
                GridRow {
                    Image(systemName: r.available ? "checkmark.circle.fill" : r.deliverable ? "clock" : "xmark.circle")
                        .foregroundStyle(r.available ? .green : r.deliverable ? .orange : .secondary)
                    Text(r.label)
                    Text(r.available ? "in the room" : r.deliverable ? "instructor can deliver" : "not in this setting")
                        .foregroundStyle(.secondary)
                }
            }
        }
        Text("Learning objectives").font(.headline)
        ForEach(d.assessment.learningObjectives) { o in Label(o.label, systemImage: "target").font(.callout) }
        Text("Assessment").font(.headline)
        ForEach(d.assessment.dimensions) { dim in
            Text("\(dim.title): \(dim.achievableMax) of \(dim.maxScore) points earnable here")
                .font(.callout).foregroundStyle(dim.achievableMax < dim.maxScore ? .orange : .primary)
        }
        Text("Clinical facts come from the case file and cannot be changed by the scenario. Edit settings, review and export in the web Studio.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func fact(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v)
        }
    }

    private func originText(_ o: StudioOrigin) -> String {
        let version = o.version.map { " v\($0)" } ?? ""
        if o.downloadedFrom != nil {
            let claim = o.claimedReviewState.map { " The original is \($0.reviewStateLabel.lowercased()); this copy starts as a draft and needs its own review." } ?? ""
            return "Downloaded from the marketplace (\(o.code ?? "?"))\(version).\(claim)"
        }
        if let from = o.duplicatedFrom { return "Duplicated from \(from)\(version)." }
        let claim = o.claimedReviewState.map { " The file claimed \"\($0)\"; that claim was not accepted." } ?? ""
        return "Imported from a file\(version).\(claim)"
    }
}

// MARK: - Marketplace

struct StudioMarketplace: View {
    @Environment(StudioState.self) private var studio
    @State private var query = ""
    @State private var onlyReviewed = false

    private var shown: [StudioMarketItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return studio.market.filter { s in
            (!onlyReviewed || s.reviewState == "clinician_reviewed")
                && (q.isEmpty || [s.title, s.description, s.environment, s.difficulty, s.code].contains { $0.lowercased().contains(q) })
        }
    }

    var body: some View {
        StudioPage(title: "Marketplace",
                   subtitle: "Published scenarios on this server. Launch one now, or download a copy to adapt. A copy arrives as a draft; the original's review state does not carry over.") {
            HStack {
                TextField("Search title, setting, difficulty, code", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 420)
                Toggle("Clinician-reviewed only", isOn: $onlyReviewed).fixedSize()
            }
            if studio.loaded && shown.isEmpty {
                Text(studio.market.isEmpty ? "Nothing is published yet." : "Nothing matches.").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 16)], spacing: 16) {
                ForEach(shown) { s in card(s) }
            }
        }
    }

    private func card(_ s: StudioMarketItem) -> some View {
        let copy = studio.library.first { $0.origin?.downloadedFrom == s.scenarioId }
        return StudioCard {
            HStack(alignment: .firstTextBaseline) {
                Text(s.title).font(.title3.bold())
                Spacer()
                ReviewBadge(state: s.reviewState)
            }
            Text(s.description).font(.callout).lineLimit(4)
            Text("\(s.environment) · \(s.crowdedness) · \(s.difficulty) · v\(s.version)").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(s.code).font(.system(.title2, design: .monospaced).bold()).foregroundStyle(.teal)
                Spacer()
                LaunchButton(code: s.code)
                if let copy {
                    Button("Open your copy") { studio.open(copy.scenarioId, downloaded: true) }.buttonStyle(.bordered)
                } else {
                    Button("Download a copy") { Task { await studio.download(s) } }.buttonStyle(.bordered).disabled(studio.busy)
                }
            }
        }
    }
}

// MARK: - Debrief

struct StudioDebriefPage: View {
    @Environment(StudioState.self) private var studio
    @State private var debrief: StudioDebrief?
    @State private var loadError: String?

    private var sessionId: String? { studio.debriefSession ?? studio.sessions.first?.sessionId }

    var body: some View {
        @Bindable var studio = studio
        StudioPage(title: "Debrief") {
            if studio.sessions.count > 1 {
                Picker("Session", selection: Binding(get: { sessionId ?? "" }, set: { studio.debriefSession = $0 })) {
                    ForEach(studio.sessions) { s in Text("\(s.title), \(studioDate(s.startedAt))").tag(s.sessionId) }
                }
                .fixedSize()
            }
            if let d = debrief, d.sessionId == sessionId { content(d) }
            else if let loadError { Label(loadError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            else if sessionId == nil { Text("No scenario session yet.").foregroundStyle(.secondary) }
            else { ProgressView() }
        }
        .task(id: sessionId) { await load() }
    }

    private func load() async {
        guard let sessionId else { return }
        do {
            let d = try await StudioClient.debrief(sessionId)
            debrief = d; loadError = nil
            SmokeLog.mark("studio debrief shown code=\(d.scenario.code) interventions=\(d.interventions.count) "
                + "acknowledged=\(d.interventions.filter(\.acknowledged).count) score=\(d.scores.map { "\($0.core.score)/\($0.core.maxScore)" } ?? "none") "
                + "resources=\(d.resources.count)")
        } catch { loadError = error.localizedDescription }
    }

    @ViewBuilder private func content(_ d: StudioDebrief) -> some View {
        StudioCard {
            HStack { Text(d.scenario.title).font(.title2.bold()); ReviewBadge(state: d.scenario.reviewState) }
            Text("\(d.scenario.code) · \(d.scenario.environment) · \(d.scenario.crowdedness) · \(d.scenario.difficulty)")
                .foregroundStyle(.secondary)
            if let dx = d.diagnosisSubmitted { Text("Diagnosis submitted: \(dx)") } else { Text("No diagnosis submitted yet.").foregroundStyle(.secondary) }
        }
        if let s = d.scores {
            HStack(spacing: 16) {
                score("Core case", s.core)
                if let m = s.management { score("Investigation and management", m) }
                if let f = s.fitting { score("Measurement and fitting", f) }
            }
        }
        if !d.interpretation.isEmpty {
            Text("How to read the score").font(.headline)
            ForEach(d.interpretation, id: \.self) { Label($0, systemImage: "info.circle").font(.callout) }
        }
        Text("Instructor interventions").font(.headline)
        if d.interventions.isEmpty { Text("None.").foregroundStyle(.secondary) }
        ForEach(d.interventions) { i in
            VStack(alignment: .leading, spacing: 2) {
                Label("\(i.label) · \(studioDate(i.at))", systemImage: i.acknowledged ? "checkmark.circle.fill" : "clock")
                    .foregroundStyle(i.acknowledged ? .primary : .secondary)
                if let line = i.line { Text("\(line.speaker): “\(line.text)”").font(.caption).foregroundStyle(.secondary) }
            }
        }
        Text("Resources").font(.headline)
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            ForEach(d.resources) { r in
                GridRow {
                    Text(r.label)
                    Text(r.availableAtStart ? "at the start" : r.deliveredAtSeq != nil ? "delivered" : "not available").foregroundStyle(.secondary)
                    Text(r.used ? "used" : "").foregroundStyle(.teal)
                }
            }
        }
        Text("What the student did").font(.headline)
        ForEach(d.timeline) { step in
            Label(step.label, systemImage: step.type == "intervention" ? "person.wave.2" : step.type == "hint" ? "lightbulb" : "stethoscope")
                .font(.callout)
        }
    }

    private func score(_ title: String, _ s: StudioDebrief.Score) -> some View {
        StudioCard {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text("\(s.score) / \(s.maxScore)").font(.title.bold())
            if let a = s.achievableMax, a < s.maxScore { Text("\(a) earnable in this scenario").font(.caption).foregroundStyle(.orange) }
        }
    }
}

// MARK: - Create

struct StudioCreate: View {
    var body: some View {
        StudioPage(title: "Create a scenario") {
            StudioCard {
                Text("Use the scenario generator in the web Studio").font(.headline)
                Text("Authoring is a six-step form with free text, which is quicker at a keyboard. Open this address on a laptop or iPad on the same network:")
                Text(AppConfig.backendURL.appendingPathComponent("app/").absoluteString)
                    .font(.system(.title2, design: .monospaced).bold()).foregroundStyle(.teal)
                    .textSelection(.enabled)
                Text("Scenarios you save there appear under My scenarios here. Publish them here or there, then launch.")
                    .foregroundStyle(.secondary)
            }
            StudioCard {
                Text("Quick variant without a keyboard").font(.headline)
                Text("Open a scenario in My scenarios or Downloaded and choose Duplicate. The copy is a draft you can publish and launch, or adjust later in the web Studio.")
                    .foregroundStyle(.secondary)
            }
            StudioCard {
                Text("Live Director").font(.headline)
                Text("The instructor steers a running session from the web Studio (Sessions › Live director). It is kept off the headset so the student does not see what is coming.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
