import Foundation
import Observation

/// What the patient avatar should do right now. Views observe `AppModel.reaction`
/// and react on `id` change: play `animation`, a pain sound if `painLevel >= 5`,
/// and speak `text` locally when `speakLocally` is true.
struct ReactionEvent: Identifiable, Equatable {
    let id = UUID()
    /// arm_withdrawal | flinch | none
    var animation: String
    var painLevel: Int
    var text: String
    /// Optional bundled clip name (Resources/Audio/<clip>.*), e.g. a zone id or scripted line id.
    var clip: String?
    /// False when the live voice agent will say the line itself.
    var speakLocally: Bool
}

enum NotebookTab: String, CaseIterable, Identifiable {
    case history = "History", examination = "Examination", investigations = "Investigations",
         assessment = "Assessment", conversation = "Transcript"
    var id: String { rawValue }

    /// Tab label for the kind of case: an ultrasound learner records scan findings and an impression.
    func title(ultrasound: Bool) -> String {
        guard ultrasound else { return rawValue }
        switch self {
        case .examination: return "Scan findings"
        case .assessment: return "Impression"
        default: return rawValue
        }
    }

    /// The Investigations tab does not apply to an ultrasound encounter.
    static func tabs(ultrasound: Bool) -> [NotebookTab] { allCases.filter { !ultrasound || $0 != .investigations } }
}

enum SessionPhase: Equatable {
    case idle, running, feedback
}

/// The last dictation, as the notebook's AI tidy left it. Kept so the learner can undo it.
struct NoteTidy: Equatable {
    enum Status: Equatable { case pending, tidied, kept(String) }
    var field: String
    var raw: String
    var text: String
    var status: Status
}

/// The debrief's AI comparison of the learner's notes with the conversation.
enum NotesReviewState: Equatable {
    case idle, loading
    case ready(NotesReview)
    case unavailable(String)
}

/// Why the patient conversation is paused. Both save ElevenLabs credits: a connected
/// conversation is billed per minute even while the microphone is muted.
enum VoicePause: String {
    case idle, notebook
}

/// What the learner picked on the dashboard. Nil fields mean "the case's default". With
/// `surprise` the case, mood and avatar are drawn at Start and stay hidden until then.
struct ScenarioSelection: Equatable {
    var caseId: String?
    var mood: String?
    var avatar: String?
    var surprise = false

    private static let keys = (caseId: "dashboard.caseId", mood: "dashboard.mood", avatar: "dashboard.avatar", surprise: "dashboard.surprise")

    /// Last dashboard choice, overridden by `-scenario`, `-mood`, `-avatar`. An unattended
    /// run (`-autoDemo`) ignores the stored choice so it is repeatable.
    static func initial() -> ScenarioSelection {
        let defaults = UserDefaults.standard
        var s = ScenarioSelection()
        if !SmokeLog.enabled {
            s.caseId = defaults.string(forKey: keys.caseId)
            s.mood = defaults.string(forKey: keys.mood)
            s.avatar = defaults.string(forKey: keys.avatar)
            s.surprise = defaults.bool(forKey: keys.surprise)
        }
        if let id = AppConfig.launchArgument("-scenario") { s.caseId = id; s.surprise = false }
        if let mood = AppConfig.launchArgument("-mood") { s.mood = mood }
        if let avatar = AppConfig.launchArgument("-avatar") { s.avatar = avatar }
        return s
    }

    func persist() {
        let defaults = UserDefaults.standard
        defaults.set(caseId, forKey: Self.keys.caseId)
        defaults.set(mood, forKey: Self.keys.mood)
        defaults.set(avatar, forKey: Self.keys.avatar)
        defaults.set(surprise, forKey: Self.keys.surprise)
    }
}

/// The only object views talk to. Orchestrates engine + voice + avatar reactions.
@MainActor
@Observable
final class AppModel {
    let engine: any ClinicalEngine
    let voice: any VoiceService
    /// The patient's body: standing, sitting, arm poses, recoil.
    let behavior = PatientBehaviorController()

    private(set) var phase: SessionPhase = .idle
    /// Whether the patient's immersive space is open (set by the space itself), so the control
    /// panel and the Studio window can both start and stop sessions.
    var immersiveOpen = false
    private(set) var session: SessionInfo?
    private(set) var transcript: [TranscriptTurn] = []
    private(set) var examinations: [ExaminationResult] = []
    private(set) var reaction: ReactionEvent?
    private(set) var feedback: Feedback?
    private(set) var lastError: String?
    /// Incremented by `recenter()`; the immersive view re-places the patient on change.
    private(set) var recenterToken = 0
    private(set) var isBusy = false
    var debugMode = false

    /// Cases the dashboard offers: bundled ones at once, the backend's list when it answers.
    private(set) var catalog: [CaseInfo] = []
    var selection = ScenarioSelection.initial() {
        didSet { if selection != oldValue { selection.persist() } }
    }
    /// Bundled avatar model for the encounter being started or running ("Patient", "Patient_female", ...).
    private(set) var activeAvatarModel = "Patient"
    /// Resolved at Start (random picks included) and consumed by `startSession`.
    @ObservationIgnored private var pending: (caseId: String, config: SessionConfig?)?

    /// The learner's notebook: free-text notes plus the diagnosis they formulate themselves.
    var notes = ClinicalNotes()
    var diagnosis = ""
    var notebookTab = NotebookTab.history
    private(set) var notebookOpen = false
    /// Tap-to-dictate for the notebook's notes.
    let dictation = NoteDictation()
    /// The last dictation and what the AI tidy made of it (one level of undo).
    private(set) var lastTidy: NoteTidy?
    private(set) var notesReview = NotesReviewState.idle

    /// Credit savers: the conversation pauses after `idleLimit` without speech, and after
    /// `notebookLimit` with the notebook open (it resumes when the notebook closes).
    private(set) var voicePause: VoicePause?
    /// The learner ended the conversation; nothing resumes it in this encounter.
    private(set) var consultationEnded = false
    /// Connected conversation time in this encounter, and the plan's balance when last read.
    private(set) var voiceSeconds: TimeInterval = 0
    private(set) var credits: VoiceCredits?
    static let idleLimit = AppConfig.seconds("-idleLimit") ?? 120
    static let notebookLimit = AppConfig.seconds("-notebookLimit") ?? 60
    static let resumeLine = "Yes, doctor?"
    @ObservationIgnored private var lastVoiceActivity = Date()
    @ObservationIgnored private var notebookOpenedAt: Date?
    @ObservationIgnored private var watchdog: Task<Void, Never>?

    /// Results the learner has received, latest order of each investigation.
    private(set) var investigationResults: [InvestigationResult] = []
    /// Result shown in the radiology viewer (takes the notebook's place while set).
    private(set) var viewing: InvestigationResult?
    var viewerZoom = 1.0

    /// Orthotics lab. `fit` is the support as the engine last recorded it; the scene renders it.
    private(set) var measurements: [MeasurementResult] = []
    private(set) var fit: OrthosisFit?
    private(set) var lastCheck: FittingCheckResult?
    var selectedTool: String?
    /// One-shot instruction for the 3D lab (scripted demo, panel fallback buttons).
    var labCommand: LabCommand?
    /// Ultrasound: gel on the belly, the probe's contact and what the machine shows. Everything comes
    /// from the engine's answers; the scene follows these values.
    private(set) var gelApplied = false
    private(set) var lastScan: ScanResult?
    /// Belly region the probe rests on; nil = in the holder or in the air (the monitor shows no contact).
    private(set) var probeRegion: String?
    /// Counts scans, so the probe can turn a quarter turn each time.
    private(set) var scanSerial = 0
    private(set) var scanLog: [ScanResult] = []
    /// Short reminder for the monitor's idle screen, e.g. after a tap with nothing in hand.
    var usHint: String?
    /// Spatial Clinical Replay; only available once feedback is showing.
    private(set) var teachingMode = false
    var replayStep = 0
    var showAnatomy = true
    /// Every examination that reached the engine, with how and where it happened.
    private(set) var examEvents: [ExamEvent] = []
    private var sessionStart = Date()
    @ObservationIgnored private var fitReactionTask: Task<Void, Never>?
    /// The complaint the patient last voiced about the fit, so it is not repeated.
    private var lastFitComplaint: String?
    /// Quiet time after the last adjustment before the patient speaks up unprompted.
    static let fitReactionDelay: TimeInterval = 1.3

    /// Replay steps: one per examination, then the support placement.
    var replayStepCount: Int { examEvents.count + 1 }
    var replayEvent: ExamEvent? { teachingMode && examEvents.indices.contains(replayStep) ? examEvents[replayStep] : nil }

    // MedSim Studio scenario (nil = the fixed default case). Everything below is setting,
    // companions and coaching; findings and scoring never come from here.
    var scenario: ScenarioRuntime? { session?.scenario }
    let director = DirectorLink()
    /// The last thing a companion said; the immersive scene speaks and shows it.
    private(set) var sceneLine: SceneLine?
    /// Latest coaching hint, when the scenario offers coaching.
    private(set) var hint: String?
    /// Instructor events applied in this session, newest last.
    private(set) var directorLog: [String] = []
    /// Why a selected scenario is not running, if it is not.
    private(set) var scenarioNotice: String?
    private(set) var debrief: ScenarioDebrief?
    /// Set by the immersive view after it rebuilt the room; reported back to the instructor.
    var stageStatus = "immersive scene not open"
    @ObservationIgnored private var companionTask: Task<Void, Never>?
    @ObservationIgnored private var coachTask: Task<Void, Never>?
    private var companionIndex = 0

    /// Seconds between accepted examination events (gaze+pinch or fingertip).
    static let examineCooldown: TimeInterval = 1.5
    private var lastExamineAt = Date.distantPast

    var zones: [ZoneInfo] { session?.case.zones ?? [] }
    var ultrasound: UltrasoundInfo? { session?.case.ultrasound }
    var isUltrasound: Bool { ultrasound != nil }
    var scriptedDialogue: [ScriptedLine] { session?.case.scriptedDialogue ?? [] }
    var engineModeLabel: String { engine.modeLabel }

    init(engine: any ClinicalEngine, voice: any VoiceService) {
        self.engine = engine
        self.voice = voice
        self.catalog = Self.ordered(engine.bundledCases)
        normalizeSelection()
        voice.onTranscript = { [weak self] turn in self?.record(turn) }
        voice.onAction = { [weak self] raw in self?.performPatientAction(raw) ?? "failure: unavailable" }
        voice.onOrder = { [weak self] raw in await self?.orderInvestigation(raw) ?? "failure: unavailable" }
        director.onEvent = { [weak self] event in await self?.apply(event) ?? (false, "the app has no session") }
    }

    // MARK: Session

    /// The default case first, the others in the order the engine lists them.
    private static func ordered(_ cases: [CaseInfo]) -> [CaseInfo] {
        cases.filter { $0.caseId == AppConfig.defaultCaseId } + cases.filter { $0.caseId != AppConfig.defaultCaseId }
    }

    /// The chosen case, else the default case, else the first one.
    var selectedCase: CaseInfo? {
        catalog.first { $0.caseId == selection.caseId } ?? catalog.first { $0.caseId == AppConfig.defaultCaseId } ?? catalog.first
    }

    func loadCatalog() async {
        if catalog.isEmpty { catalog = Self.ordered(engine.bundledCases) }
        if let all = try? await engine.caseCatalog(), !all.isEmpty { catalog = Self.ordered(all) }
        normalizeSelection()
        SmokeLog.mark("catalog cases=\(catalog.map(\.caseId))")
    }

    /// Keeps the selection inside what the catalog offers (a stored case may be gone, a mood
    /// may not exist in the newly chosen case).
    func normalizeSelection() {
        guard !catalog.isEmpty else { return }
        var next = selection
        let chosen = selectedCase
        next.caseId = chosen?.caseId
        let cat = chosen?.catalog ?? CaseCatalog()
        if let mood = next.mood, !cat.allowedMoods.contains(mood) { next.mood = nil }
        if let avatar = next.avatar, !cat.allowedAvatars.contains(avatar) { next.avatar = nil }
        if next != selection { selection = next }
    }

    /// Settles case, mood and avatar for the coming encounter and the avatar model the scene
    /// must load. Called before the immersive space opens; `startSession` uses the result.
    @discardableResult
    func prepareStart() -> (caseId: String, config: SessionConfig?) {
        if let pending { return pending }
        var chosen = selectedCase
        var config: SessionConfig?
        if selection.surprise, let random = catalog.randomElement() {
            chosen = random
            config = random.catalog.map { $0.randomConfig() }
        } else if let cat = chosen?.catalog {
            config = (try? cat.resolve(mood: selection.mood, avatar: selection.avatar)) ?? (try? cat.resolve(nil))
        }
        let plan = (caseId: chosen?.caseId ?? AppConfig.defaultCaseId, config: config)
        activeAvatarModel = avatarModel(chosen?.catalog, config?.avatar)
        pending = plan
        return plan
    }

    private func avatarModel(_ catalog: CaseCatalog?, _ avatar: String?) -> String {
        let cat = catalog ?? CaseCatalog()
        return cat.avatarModelName(for: avatar ?? cat.defaultAvatar)
    }

    func startSession() async {
        scenarioNotice = nil
        var scenarioCase = false
        if let code = AppConfig.scenarioCode {
            // A wrong code must be an error, not a quiet fall back to the default case.
            switch await ScenarioClient.lookup(code) {
            case .found: scenarioCase = true
            case .unknown:
                pending = nil
                lastError = "No published scenario with code \(code). Check the code in MedSim Studio, or clear it to run the default case."
                SmokeLog.mark("scenario code=\(code) unknown, session not started")
                return
            case .unreachable:
                scenarioNotice = "Scenario \(code) needs the backend, which is not reachable. Running the selected case offline."
            }
        }
        let plan = prepareStart()
        pending = nil
        // A scenario brings its own case; the dashboard's mood and avatar may not exist there.
        let config = scenarioCase ? nil : plan.config
        await run {
            let info = try await self.engine.startSession(caseId: plan.caseId, config: config)
            self.apply(info)
            SmokeLog.mark("session config case=\(info.case.caseId) mood=\(info.config?.mood ?? "none") "
                + "avatar=\(info.config?.avatar ?? "none") model=\(self.activeAvatarModel)")
            Task { await self.startVoice(info) }
        }
    }

    private func startVoice(_ info: SessionInfo) async {
        lastVoiceActivity = Date()
        await voice.start(caseContext: info.case.voiceContext, voiceId: info.config.flatMap { AppConfig.voiceId(for: $0.avatar) },
                          resumeLine: nil)
        await refreshCredits()
    }

    func stopSession() async {
        watchdog?.cancel()
        await voice.stop()
        endScenario()
        phase = .idle
    }

    func reset() async {
        await voice.stop()
        await run {
            let info = try await self.engine.reset()
            self.apply(info)
            Task { await self.startVoice(info) }
        }
    }

    func recenter() { recenterToken += 1 }

    /// Opening the notebook is note-taking mode: the patient's microphone is muted so that
    /// dictated notes are not heard as speech to the patient.
    func setNotebookOpen(_ open: Bool) {
        if open != notebookOpen { notebookOpenedAt = open ? Date() : nil }
        notebookOpen = open
        if !open {
            viewing = nil
            // Stops recording before the patient's microphone opens again; the transcript still lands.
            Task { await dictation.stop() }
            if voicePause == .notebook { Task { await resumeVoice() } }
        }
        Task { await voice.setMicMuted(open && phase == .running) }
    }

    // MARK: Credit savers

    /// Runs while an encounter is running: counts connected time and pauses an idle conversation.
    private func startWatchdog() {
        watchdog?.cancel()
        voiceSeconds = 0
        lastVoiceActivity = Date()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled, self.phase == .running else { return }
                await self.tick()
            }
        }
    }

    private func tick() async {
        guard voice.status == .connected else { return }
        voiceSeconds += 1
        let now = Date()
        if voice.isAgentSpeaking || dictation.state != .idle { lastVoiceActivity = now }
        if notebookOpen, let opened = notebookOpenedAt, now.timeIntervalSince(opened) >= Self.notebookLimit {
            await pauseVoice(.notebook)
        } else if !notebookOpen, now.timeIntervalSince(lastVoiceActivity) >= Self.idleLimit {
            await pauseVoice(.idle)
        }
    }

    func pauseVoice(_ reason: VoicePause) async {
        guard phase == .running, voicePause == nil, voice.status == .connected else { return }
        voicePause = reason
        await voice.stop()
        SmokeLog.mark("voice paused reason=\(reason.rawValue) voiceSeconds=\(Int(voiceSeconds)) turns=\(transcript.count)")
        await refreshCredits()
    }

    /// Continues a paused conversation in a new ElevenLabs conversation that is told what was said.
    func resumeVoice() async {
        guard phase == .running, voicePause != nil, !consultationEnded, let info = session else { return }
        let reason = voicePause
        voicePause = nil
        lastVoiceActivity = Date()
        await voice.start(caseContext: resumeContext(info), voiceId: info.config.flatMap { AppConfig.voiceId(for: $0.avatar) },
                          resumeLine: Self.resumeLine)
        if notebookOpen { await voice.setMicMuted(true) }
        SmokeLog.mark("voice resumed after=\(reason?.rawValue ?? "?") voice=\(voice.status.label) turns=\(transcript.count)")
    }

    /// The case facts plus the conversation so far, so a resumed agent does not start over.
    func resumeContext(_ info: SessionInfo) -> String {
        let lines = transcript.suffix(30).map { "\($0.role == .learner ? "Student" : "You"): \($0.text)" }
        guard !lines.isEmpty else { return info.case.voiceContext }
        return info.case.voiceContext + "\n\nCONVERSATION SO FAR (the consultation was briefly paused; continue it, "
            + "do not greet again and do not repeat what you already said):\n" + lines.joined(separator: "\n")
    }

    func refreshCredits() async {
        if let c = await NotesClient.credits() {
            credits = c
            SmokeLog.mark("credits remaining=\(c.creditsRemaining)/\(c.creditsLimit) tier=\(c.tier)")
        }
    }

    // MARK: Dictation

    /// Text of a note by the id the notebook uses for it.
    func noteText(_ id: String) -> String {
        switch id {
        case "history": notes.history
        case "examination": notes.examination
        case "assessment": notes.assessment
        case "interpretation": notes.interpretation
        case "management": notes.management
        case "followUp": notes.followUp
        case "diagnosis": diagnosis
        default: ""
        }
    }

    func setNoteText(_ id: String, _ text: String) {
        switch id {
        case "history": notes.history = text
        case "examination": notes.examination = text
        case "assessment": notes.assessment = text
        case "interpretation": notes.interpretation = text
        case "management": notes.management = text
        case "followUp": notes.followUp = text
        case "diagnosis": diagnosis = text
        default: break
        }
    }

    /// A finished dictation: the words go into the note at once, then the AI tidy replaces them
    /// if the learner has not changed them meanwhile. The diagnosis line is never tidied.
    func dictated(_ words: String, into id: String) async {
        let raw = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, phase == .running else { return }
        let existing = noteText(id)
        if id == "diagnosis" {
            let space = existing.last.map { $0.isWhitespace ? "" : " " } ?? ""
            setNoteText(id, existing + space + raw)
            return
        }
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        setNoteText(id, trimmed.isEmpty ? raw : trimmed + "\n" + raw)
        let entry = NoteTidy(field: id, raw: raw, text: raw, status: .pending)
        lastTidy = entry
        let result = await NotesClient.tidy(raw, field: id)
        guard lastTidy == entry else { return } // a newer dictation or a reset took over
        guard let result, result.source == "ai", result.text != raw else {
            lastTidy?.status = .kept(result?.note ?? "AI tidy unavailable: kept your words as dictated.")
            SmokeLog.mark("tidy note=\(id) source=\(result?.source ?? "none") note=\"\(result?.note ?? "unreachable")\"")
            return
        }
        let current = noteText(id)
        guard let range = current.range(of: raw, options: .backwards) else {
            lastTidy?.status = .kept("You edited the note, so the AI tidy was not applied.")
            return
        }
        setNoteText(id, current.replacingCharacters(in: range, with: result.text))
        lastTidy = NoteTidy(field: id, raw: raw, text: result.text, status: .tidied)
        SmokeLog.mark("tidy note=\(id) source=ai raw=\"\(raw)\" tidy=\"\(result.text.replacingOccurrences(of: "\n", with: " | "))\"")
    }

    /// Puts the learner's own words back in place of the AI tidy.
    func undoTidy() {
        guard let t = lastTidy, t.status == .tidied else { return }
        let current = noteText(t.field)
        if let range = current.range(of: t.text, options: .backwards) {
            setNoteText(t.field, current.replacingCharacters(in: range, with: t.raw))
        }
        lastTidy = nil
        SmokeLog.mark("tidy undone note=\(t.field)")
    }

    /// Body movement requested by the voice agent's client tool or a debug button. Never an
    /// examination and never a transcript turn, so it cannot earn points.
    @discardableResult
    func performPatientAction(_ raw: String) -> String {
        guard phase == .running else { return "failure: no session is running" }
        let result = behavior.perform(raw).text
        SmokeLog.mark("action \(raw) -> \(result) exams=\(examinations.count) turns=\(transcript.count)")
        return result
    }

    // MARK: Investigations

    /// Requested from the notebook or by the voice agent's client tool. `raw` must be one of
    /// the case's investigation ids; the result comes from the clinical engine only. The
    /// returned text goes back to the voice agent and deliberately leaves the result out.
    @discardableResult
    func orderInvestigation(_ raw: String) async -> String {
        guard phase == .running, let offered = session?.case.investigations else { return "failure: no session is running" }
        guard let info = offered.first(where: { $0.id == raw }) else {
            return "failure: Unknown investigation. Allowed: \(offered.map(\.id).joined(separator: ", "))."
        }
        do {
            let result = try await engine.orderInvestigation(raw)
            investigationResults.removeAll { $0.investigationId == result.investigationId }
            investigationResults.append(result)
            show(result)
            lastError = nil
            SmokeLog.mark("investigation \(raw) impression=\"\(result.impression)\" image=\(result.image ?? "none") "
                + "imageFound=\(result.image.map { RadiologyImage.url($0) != nil } ?? false) engine=\(engineModeLabel) "
                + "results=\(investigationResults.count) exams=\(examinations.count) turns=\(transcript.count)")
            return "success: \(info.label) requested. The result is shown to the student on screen. "
                + "You do not know the result. Do not describe or guess it."
        } catch {
            lastError = error.localizedDescription
            return "failure: The request could not be sent."
        }
    }

    /// Opens the radiology viewer. It does not mute the microphone: only the notes pages do.
    func show(_ result: InvestigationResult) {
        viewerZoom = 1
        viewing = result
        notebookOpen = true
    }

    /// "Back to notebook": lands on the Investigations tab, in note-taking mode.
    func closeViewer() {
        viewing = nil
        notebookTab = .investigations
        setNotebookOpen(true)
    }

    // MARK: Measurement and orthosis fitting

    func measure(_ id: String, valueCm: Double?) async {
        guard phase == .running, behavior.canExamine else { return }
        do {
            let result = try await engine.recordMeasurement(id, valueCm: valueCm)
            measurements.removeAll { $0.measurementId == id }
            measurements.append(result)
            lastError = nil
            SmokeLog.mark("measure \(id) value=\(result.valueCm) source=\(result.source) engine=\(engineModeLabel)")
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// A support was dropped on the forearm (`offsetCm` nil = taken off). A newly placed
    /// support starts in the tray orientation with its straps at the loosest setting.
    func placeOrthosis(size: String, offsetCm: Double?) async {
        guard let offsetCm else { return await setFit(nil) }
        var next = fit ?? OrthosisFit(size: size, orientation: "thumb_radial", offsetCm: offsetCm,
                                      tightness: session?.case.orthotics.tightness.first ?? "loose")
        if next.size != size { next.tightness = session?.case.orthotics.tightness.first ?? "loose" }
        next.size = size
        next.offsetCm = offsetCm
        await setFit(next)
    }

    func adjustFit(_ change: (inout OrthosisFit) -> Void) async {
        guard var next = fit else { return }
        change(&next)
        await setFit(next)
    }

    func stepTightness(_ step: Int) async {
        let levels = session?.case.orthotics.tightness ?? []
        guard let current = fit, let i = levels.firstIndex(of: current.tightness), levels.indices.contains(i + step) else { return }
        await adjustFit { $0.tightness = levels[i + step] }
    }

    /// Every change goes to the engine first; the scene shows only what was recorded.
    func setFit(_ next: OrthosisFit?) async {
        guard phase == .running, behavior.canExamine else { return }
        do {
            let ack = try await engine.recordFit(next)
            fit = next
            lastError = nil
            SmokeLog.mark("fit \(next.map { "size=\($0.size) offset=\($0.offsetCm) orientation=\($0.orientation) tightness=\($0.tightness)" } ?? "removed") "
                + "attempt=\(ack.attempt) engine=\(engineModeLabel) exams=\(examinations.count)")
            await voice.sendContext(ack.voiceNote)
            scheduleFitReaction(next == nil ? nil : ack)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Explicit, recorded check: "comfort" or "neurovascular". The engine supplies the
    /// finding and what the patient says; the voice agent only speaks it.
    func fittingCheck(_ kind: String) async {
        guard phase == .running, behavior.canExamine else { return }
        do {
            let result = try await engine.fittingCheck(kind)
            lastCheck = result
            if kind == "comfort" { // asked: the answer replaces any pending unprompted remark
                fitReactionTask?.cancel()
                lastFitComplaint = result.comfortable ? nil : result.patientResponse
            }
            await patientSays(result.patientResponse, voiceContext: result.voiceContext, animation: result.animation)
            lastError = nil
            SmokeLog.mark("check \(kind) phase=\(result.phase) comfortable=\(result.comfortable) "
                + "response=\"\(result.patientResponse)\" engine=\(engineModeLabel) turns=\(transcript.count)")
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The patient speaks a line the engine supplied: through the live agent when connected,
    /// otherwise locally. A flinch goes through the behaviour controller.
    private func patientSays(_ text: String, voiceContext: String, animation: String, clip: String? = nil) async {
        let live = voice.status == .connected
        reaction = ReactionEvent(animation: animation, painLevel: 0, text: text, clip: clip, speakLocally: !live)
        if animation != "none" { behavior.pain(withdrawArm: false) }
        if live { await voice.sendExaminationEvent(voiceContext) }
        else { record(TranscriptTurn(role: .patient, text: text)) }
    }

    /// An uncomfortable fit makes the patient speak up without being asked: once, after the
    /// adjustments have stopped, and not again for the same complaint.
    private func scheduleFitReaction(_ ack: FitAck?) {
        fitReactionTask?.cancel()
        guard let ack, !ack.comfortable else { lastFitComplaint = nil; return }
        guard ack.patientResponse != lastFitComplaint else { return }
        fitReactionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.fitReactionDelay * 1_000_000_000))
            guard let self, !Task.isCancelled, self.phase == .running else { return }
            self.lastFitComplaint = ack.patientResponse
            SmokeLog.mark("fit reaction unprompted response=\"\(ack.patientResponse)\"")
            await self.patientSays(ack.patientResponse, voiceContext: ack.voiceContext, animation: ack.animation)
        }
    }

    // MARK: Ultrasound

    /// Gel on the belly. Recorded by the engine; the patient reacts to the cold.
    func applyGel() async {
        guard phase == .running, isUltrasound else { return }
        selectedTool = nil
        do {
            let result = try await engine.applyGel()
            gelApplied = true
            usHint = nil
            lastError = nil
            SmokeLog.mark("gel applied repeat=\(result.repeatCount) response=\"\(result.patientResponse)\" engine=\(engineModeLabel) "
                + "exams=\(examinations.count) turns=\(transcript.count)")
            await patientSays(result.patientResponse, voiceContext: result.voiceContext, animation: "none", clip: "us_gel")
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The probe touches a belly region (drag, pinch or button). The engine decides what the image is;
    /// scanning again at the same region cycles through the views available there.
    func scan(regionId: String) async {
        guard phase == .running, isUltrasound else { return }
        selectedTool = nil
        do {
            let result = try await engine.scan(regionId: regionId, gelApplied: gelApplied)
            lastScan = result
            probeRegion = regionId
            scanSerial += 1
            scanLog.append(result)
            usHint = nil
            lastError = nil
            SmokeLog.mark("scan region=\(regionId) view=\(result.viewId ?? "none") quality=\(result.quality) image=\(result.image ?? "none") "
                + "imageFound=\(result.image.map { UltrasoundImage.url($0) != nil } ?? false) measurements=\(result.measurements.map(\.text)) "
                + "repeat=\(result.repeatCount) gel=\(result.gelApplied) engine=\(engineModeLabel) exams=\(examinations.count) turns=\(transcript.count)")
            // The patient reacts the first time something shows (and to the dry probe), not to every cycle.
            if !result.patientResponse.isEmpty, result.repeatCount == 1 {
                await patientSays(result.patientResponse, voiceContext: result.voiceContext, animation: "none",
                                  clip: result.viewId.map { "us_view_\($0)" } ?? "us_no_gel")
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Same region again: the next view there.
    func rotateProbe() async {
        if let region = probeRegion { await scan(regionId: region) }
    }

    /// The probe leaves the belly: the monitor shows no contact.
    func liftProbe() {
        guard probeRegion != nil || selectedTool != nil else { return }
        probeRegion = nil
        selectedTool = nil
        SmokeLog.mark("probe lifted")
    }

    /// The probe was dragged off the belly (scene side of `liftProbe`: keeps the selection alone).
    func probeLeftBelly() {
        guard probeRegion != nil else { return }
        probeRegion = nil
        SmokeLog.mark("probe left the belly")
    }

    /// Pinch on a belly region: use what is in hand there.
    func tapRegion(_ id: String) async {
        guard phase == .running, isUltrasound else { return }
        if selectedTool == UltrasoundScene.gelName {
            await applyGel()
        } else if selectedTool == UltrasoundScene.probeName || probeRegion != nil {
            await scan(regionId: id)
        } else {
            usHint = "Pick up the probe first: pinch it on the trolley."
            SmokeLog.mark("tap region=\(id) with nothing in hand")
        }
    }

    // MARK: Spatial Clinical Replay

    /// Only after submission: the teaching content it shows would give the diagnosis away.
    func startReplay() {
        guard phase == .feedback, feedback?.replay.isEmpty == false else { return }
        replayStep = 0
        teachingMode = true
        setNotebookOpen(false)
        SmokeLog.mark("replay started steps=\(replayStepCount) events=\(examEvents.map { "\($0.zoneId):\($0.source)" })")
    }

    func exitReplay() {
        teachingMode = false
        setNotebookOpen(true)
    }

    // MARK: Examination

    /// Entry point for gaze+pinch, fingertip contact and debug buttons. Nothing else creates
    /// an examination: not speech, not tool calls, not notes. `contact` is the touched point
    /// in the zone's own space, when there was one.
    func examine(zoneId: String, contact: SIMD3<Float>? = nil, source: ExamSource = .button) async {
        guard phase == .running, behavior.canExamine else { return }
        let now = Date()
        guard now.timeIntervalSince(lastExamineAt) >= Self.examineCooldown else { return }
        lastExamineAt = now
        do {
            let result = try await engine.examine(zoneId: zoneId, action: "palpation")
            examinations.append(result)
            examEvents.append(ExamEvent(id: examEvents.count, zoneId: zoneId, action: result.action, finding: result.finding,
                                        painLevel: result.painLevel, time: Date().timeIntervalSince(sessionStart),
                                        pose: behavior.state.rawValue, contact: contact, source: source))
            if result.animation != "none" { behavior.pain(withdrawArm: result.animation == "arm_withdrawal") }
            let live = voice.status == .connected
            reaction = ReactionEvent(
                animation: result.animation,
                painLevel: result.painLevel,
                text: result.patientResponse,
                clip: result.bodyPart,
                speakLocally: !live
            )
            if live {
                await voice.sendExaminationEvent(result.voiceContext)
            } else {
                // Offline voice: the scripted reply still belongs in the transcript.
                record(TranscriptTurn(role: .patient, text: result.patientResponse))
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Scripted dialogue (fallback when live voice is unavailable)

    func askScripted(_ line: ScriptedLine) {
        guard phase == .running else { return }
        record(TranscriptTurn(role: .learner, text: line.learner))
        record(TranscriptTurn(role: .patient, text: line.patient))
        reaction = ReactionEvent(animation: "none", painLevel: 0, text: line.patient, clip: line.id, speakLocally: true)
    }

    // MARK: Consultation

    /// Ends the conversation with the patient for good (saves credits). The session keeps
    /// running: examinations and notes still work, the patient then speaks locally.
    func endConsultation() async {
        guard phase == .running, !consultationEnded else { return }
        consultationEnded = true
        voicePause = nil
        await voice.stop()
        SmokeLog.mark("consultation ended voiceSeconds=\(Int(voiceSeconds)) turns=\(transcript.count)")
        await refreshCredits()
    }

    // MARK: Diagnosis / feedback

    func submitDiagnosis() async {
        let diagnosis = diagnosis.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !diagnosis.isEmpty, session != nil else { return }
        await run {
            self.feedback = try await self.engine.diagnose(diagnosis, notes: self.notes)
            self.phase = .feedback
            self.watchdog?.cancel()
            self.voicePause = nil
            await self.voice.stop()
            self.loadNotesReview()
            self.companionTask?.cancel()
            self.coachTask?.cancel()
            if self.scenario != nil, let id = self.session?.sessionId {
                self.debrief = await ScenarioClient.debrief(sessionId: id)
            }
        }
    }

    /// After submission: the AI compares the notes with the conversation (debrief only, not scored).
    func loadNotesReview() {
        guard phase == .feedback, let caseId = session?.case.caseId else { return }
        notesReview = .loading
        let (notes, diagnosis, turns) = (self.notes, self.diagnosis, transcript)
        Task { [weak self] in
            let review = await NotesClient.review(caseId: caseId, diagnosis: diagnosis, notes: notes, transcript: turns)
            guard let self, self.phase == .feedback, self.notesReview == .loading else { return }
            if let review, review.source == "ai" {
                self.notesReview = .ready(review)
            } else {
                self.notesReview = .unavailable(review?.note ?? "The AI comparison needs the backend, which is not reachable.")
            }
            SmokeLog.mark("notes review source=\(review?.source ?? "unreachable") captured=\(review?.captured.count ?? 0) "
                + "missed=\(review?.missed.count ?? 0) inaccurate=\(review?.inaccurate.count ?? 0)")
        }
    }

    func loadFeedback() async {
        guard session != nil else { return }
        await run { self.feedback = try await self.engine.feedback() }
    }

    // MARK: Private

    private func apply(_ info: SessionInfo) {
        session = info
        activeAvatarModel = avatarModel(info.case.catalog, info.config?.avatar)
        transcript = []
        examinations = []
        feedback = nil
        reaction = nil
        dictation.cancel()
        dictation.resetCounters()
        lastTidy = nil
        notesReview = .idle
        voicePause = nil
        consultationEnded = false
        notebookOpenedAt = nil
        notes = ClinicalNotes()
        diagnosis = ""
        notebookTab = .history
        notebookOpen = false
        investigationResults = []
        viewing = nil
        measurements = []
        fit = nil
        lastCheck = nil
        selectedTool = nil
        gelApplied = false
        lastScan = nil
        probeRegion = nil
        scanSerial = 0
        scanLog = []
        usHint = nil
        teachingMode = false
        replayStep = 0
        examEvents = []
        sessionStart = Date()
        fitReactionTask?.cancel()
        lastFitComplaint = nil
        lastExamineAt = .distantPast
        behavior.reset()
        phase = .running
        startWatchdog()
        startScenario()
    }

    // MARK: Scenario runtime

    private func endScenario() {
        companionTask?.cancel()
        coachTask?.cancel()
        director.disconnect()
    }

    /// Called for every new encounter. With no scenario this only clears the scenario state.
    private func startScenario() {
        endScenario()
        sceneLine = nil; hint = nil; directorLog = []; debrief = nil; companionIndex = 0
        guard let s = scenario, let id = session?.sessionId else {
            if AppConfig.scenarioCode != nil, scenarioNotice == nil {
                scenarioNotice = "The backend did not answer, so the scenario was not loaded. Running the fixed default case offline."
            }
            return
        }
        scenarioNotice = nil
        director.connect(sessionId: id)
        SmokeLog.mark("scenario code=\(s.code) v\(s.version) title=\"\(s.title)\" review=\(s.reviewState) env=\(s.environmentId) "
            + "difficulty=\(s.difficulty) hints=\(s.hintPolicy) noise=\(String(format: "%.2f", s.noiseLevel)) "
            + "bystander=\(s.bystander?.mood ?? "none") helper=\(s.teammate.present) crowd=\(s.crowdFigures.count) "
            + "sizes=\(session?.case.orthotics.sizes.map(\.id) ?? []) tape=\(session?.case.orthotics.measurements.isEmpty == false) "
            + "investigations=\(session?.case.investigations.map(\.id) ?? []) engine=\(engineModeLabel)")
        companionTask = Task { [weak self] in
            // The bystander speaks up on their own: once early, then at the scenario's interval.
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            while !Task.isCancelled, let self, self.phase == .running, let b = self.scenario?.bystander {
                let lines = b.lines[b.mood] ?? []
                guard self.companionIndex < lines.count else { return }
                self.sceneLine = SceneLine(speaker: b.name, text: lines[self.companionIndex])
                self.companionIndex += 1
                try? await Task.sleep(nanoseconds: UInt64(b.interjectEveryS * 1_000_000_000))
            }
        }
        coachTask = Task { [weak self] in
            // Guided scenarios: hints arrive without asking, as the encounter goes on.
            while !Task.isCancelled, let self, self.phase == .running {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                if !Task.isCancelled, self.phase == .running, self.scenario?.hintPolicy == "auto" { await self.requestHint() }
            }
        }
    }

    /// The next coaching hint from the backend, which records it for the debrief.
    func requestHint() async {
        guard phase == .running, let s = scenario, s.hintPolicy != "off", let id = session?.sessionId else { return }
        let text = await ScenarioClient.hint(sessionId: id)
        if let text { hint = text }
        SmokeLog.mark("hint policy=\(s.hintPolicy) text=\"\(text ?? "none")\"")
    }

    /// An instructor event from the Live Director. The message carries the scenario and the
    /// case as they are after the event; examinations, results and the transcript are not
    /// touched, so nothing the student already found changes.
    private func apply(_ event: DirectorEventMessage) async -> (applied: Bool, detail: String) {
        guard phase == .running, var info = session, info.scenario != nil else {
            return (false, "no scenario session is running in the app")
        }
        info.scenario = event.scenario
        info.case.investigations = event.case.investigations
        info.case.orthotics = event.case.orthotics
        info.case.learnerBrief = event.case.learnerBrief
        session = info
        directorLog.append(event.label)
        if let line = event.line {
            sceneLine = SceneLine(speaker: line.speaker, text: line.text)
            if event.kind == "bystander_anxious" { companionIndex = 1 } // the first anxious line was just said
        }
        if let context = event.voiceContext { await voice.sendContext(context) }
        if event.kind == "enable_coaching", event.scenario.hintPolicy == "auto" { await requestHint() }
        try? await Task.sleep(nanoseconds: 400_000_000) // let the immersive view rebuild the room first
        let detail = "\(stageStatus) sizes=\(info.case.orthotics.sizes.map(\.id)) hints=\(event.scenario.hintPolicy)"
        SmokeLog.mark("director applied seq=\(event.seq) kind=\(event.kind) event=\(event.eventId) \(detail) "
            + "exams=\(examinations.count) turns=\(transcript.count)")
        return (true, detail)
    }

    private func record(_ turn: TranscriptTurn) {
        guard phase == .running else { return }
        lastVoiceActivity = Date()
        transcript.append(turn)
        Task { await engine.recordInteraction(turn) }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await work()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
