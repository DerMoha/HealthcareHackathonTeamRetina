import SwiftUI
import Observation

/// State of the in-headset Studio window, shared with the control panel so either can open
/// it on a given page. Everything comes from the backend; nothing is cached across launches.
@MainActor
@Observable
final class StudioState {
    enum Tab: String, CaseIterable, Identifiable {
        case overview, mine, downloaded, marketplace, debrief, create
        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview: "Overview"
            case .mine: "My scenarios"
            case .downloaded: "Downloaded"
            case .marketplace: "Marketplace"
            case .debrief: "Debrief"
            case .create: "Create"
            }
        }
        var icon: String {
            switch self {
            case .overview: "house"
            case .mine: "folder"
            case .downloaded: "arrow.down.circle"
            case .marketplace: "storefront"
            case .debrief: "list.clipboard"
            case .create: "square.and.pencil"
            }
        }
    }

    var tab: Tab = .overview
    /// Scenario open in My scenarios / Downloaded.
    var selected: String?
    /// Session the Debrief page shows; nil = the newest one.
    var debriefSession: String?

    private(set) var library: [StudioScenarioRow] = []
    private(set) var market: [StudioMarketItem] = []
    private(set) var sessions: [StudioSession] = []
    private(set) var loaded = false
    private(set) var loading = false
    private(set) var busy = false
    // Setting a message ties it to the current page; clearing one (as every reload does) must not
    // move an older message onto this page.
    var error: String? { didSet { if error != nil { messageTab = tab } } }
    var notice: String? { didSet { if notice != nil { messageTab = tab } } }
    /// The page the current error or notice belongs to.
    private(set) var messageTab: Tab = .overview

    var mine: [StudioScenarioRow] { library.filter { !$0.isDownloaded } }
    var downloaded: [StudioScenarioRow] { library.filter(\.isDownloaded) }

    func reload() async {
        loading = true
        defer { loading = false; loaded = true }
        do {
            async let l = StudioClient.library(), m = StudioClient.published(), s = StudioClient.sessions()
            (library, market, sessions) = try await (l, m, s)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Runs a library change, then reloads. Returns the scenario it produced, if any.
    @discardableResult
    func act(_ done: String, _ work: () async throws -> StudioScenarioDetail) async -> StudioScenarioDetail? {
        busy = true
        defer { busy = false }
        do {
            let d = try await work()
            notice = done
            error = nil
            await reload()
            return d
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func download(_ item: StudioMarketItem) async {
        if let d = await act("Downloaded \"\(item.title)\" as a draft.", { try await StudioClient.download(item.code) }) {
            open(d.scenarioId, downloaded: true)
        }
    }

    func open(_ scenarioId: String, downloaded: Bool) {
        selected = scenarioId
        tab = downloaded ? .downloaded : .mine
        messageTab = tab   // the message that led here comes along
    }

    /// Starts a session on a published scenario: the same path as typing the code in the
    /// control panel and pressing Start Session. Closes the Studio so the patient has the room.
    func launch(code: String, model: AppModel, openSpace: OpenImmersiveSpaceAction, closeStudio: () -> Void) async {
        guard model.phase == .idle else {
            error = "A session is running. Stop it in the control panel before launching another scenario."
            return
        }
        busy = true
        defer { busy = false }
        UserDefaults.standard.set(code, forKey: AppConfig.scenarioCodeKey)
        if !model.immersiveOpen { _ = await openSpace(id: "patient") }
        await model.startSession()
        SmokeLog.mark("studio launch code=\(code) phase=\(model.phase) scenario=\(model.scenario?.code ?? "none") error=\(model.lastError ?? "none")")
        if model.phase == .running {
            error = nil
            closeStudio()
        } else {
            error = model.lastError ?? "The session did not start."
        }
    }
}
