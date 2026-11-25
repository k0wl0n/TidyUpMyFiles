import AppKit
import UniformTypeIdentifiers
import Foundation
import TidyUpMyFilesCore

/// The app's state. Everything the windows show comes from here; file work runs off the main thread.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var config: RulesConfig {
        didSet { if config != oldValue && !reloadingFromDisk { scheduleSave() } }
    }
    @Published var settings: AppSettings
    @Published var previews: [PreviewItem] = [] {
        didSet { if previews != oldValue { refreshPreviewDetails() } }
    }
    /// Predicted outcome of every waiting item (final path, name conflicts, new folders).
    @Published var previewDetails: [PreviewDetail] = []
    @Published var inspectingPreviews = false
    private var inspectTask: Task<Void, Never>?
    @Published var aiSuggestions: [AISuggestionItem] = []
    @Published var recent: [ActivityRecord] = []
    @Published var todayCount = 0
    @Published var busy = false
    /// Summary of the latest run that changed something, shown until dismissed.
    @Published var lastRun: RunReport?
    /// Set when a scan finds files: Preview shows a short guide for what to do next.
    @Published var scanFoundCount: Int?
    /// Lets other screens switch the main window to a section (e.g. "See what happened" → Activity).
    @Published var requestedSection: AppSection?
    /// The run the Activity screen should open and highlight.
    @Published var focusedRunID: Int64?
    /// What the current long task is (e.g. "Simulating 3 folders"); nil when idle.
    @Published var operationTitle: String?
    /// Live progress from the organizer, including the watcher's background work.
    @Published var work: WorkProgress?
    private var operationCancelled = false
    @Published var message: String? {
        didSet { messageActions = [] }
    }
    /// Buttons shown with the current message (set with `say(_:actions:)`).
    @Published var messageActions: [MessageAction] = []

    let organizer: Organizer?
    private var watchService: WatchService?
    private let rulesStore = RulesStore()
    private let settingsStore = SettingsStore()
    private var saveTask: Task<Void, Never>?
    /// When rules.yaml was last written or read by the app; a newer file was changed by someone else (CLI, an AI agent).
    private var rulesFileDate: Date?
    private var reloadingFromDisk = false
    private var rulesFileTimer: Timer?

    private init() {
        var loadProblem: String?
        var loaded: RulesConfig
        var needsSave = false
        let firstRun = !FileManager.default.fileExists(atPath: rulesStore.fileURL.path)
        do {
            loaded = try rulesStore.load()
            if firstRun {
                // Start with the recommended rules, in preview, so there is something useful right away.
                needsSave = Templates.installRecommended(into: &loaded) > 0
                loadProblem = "Recommended rules are set up in preview mode. Check Preview, then turn them on."
            } else {
                var notes: [String] = []
                let removed = loaded.removeDuplicates()
                if removed.rules + removed.folders > 0 {
                    notes.append("Cleaned up \(removed.rules) duplicate rule(s)" + (removed.folders > 0 ? " and \(removed.folders) repeated folder(s)." : "."))
                }
                if Templates.adoptLegacyRules(in: &loaded) > 0 { needsSave = true }
                let upgraded = Templates.upgradeUntouched(in: &loaded)
                if !upgraded.isEmpty {
                    notes.append("Updated \(upgraded.joined(separator: ", ")): leftovers are now archived by month.")
                }
                if !notes.isEmpty {
                    needsSave = true
                    loadProblem = notes.joined(separator: " ")
                }
            }
        } catch {
            loaded = RulesConfig()
            // Keep the unreadable file so a later save never loses it.
            let backup = rulesStore.fileURL.deletingLastPathComponent()
                .appendingPathComponent("rules.unreadable-\(Int(Date().timeIntervalSince1970)).yaml")
            try? FileManager.default.copyItem(at: rulesStore.fileURL, to: backup)
            loadProblem = "Could not read rules.yaml (\(error)). A copy was kept as \(backup.lastPathComponent)."
        }
        let loadedSettings = SettingsStore().load()
        config = loaded
        settings = loadedSettings
        do {
            let store = try ActivityStore(fileURL: AppPaths.databaseFile, logDirectory: AppPaths.logsDirectory)
            organizer = Organizer(config: loaded, settings: loadedSettings, store: store, trash: AppPaths.defaultTrash())
        } catch {
            organizer = nil
            loadProblem = "Activity log unavailable: \(error)"
        }
        message = loadProblem
        if let organizer {
            organizer.setProgressHandler { progress in
                Task { @MainActor in AppModel.shared.receive(progress) }
            }
            watchService = WatchService(organizer: organizer) { result in
                Task { @MainActor in AppModel.shared.absorbBackground(result) }
            }
        }
        refreshActivity()
        // Screenshot checks must not change anything on disk.
        if needsSave && LaunchOptions.screenshotPath == nil {
            saveConfigNow()
        }
        rulesFileDate = rulesFileModificationDate()
        if LaunchOptions.screenshotPath == nil {
            rulesFileTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                Task { @MainActor in AppModel.shared.reloadRulesIfChangedOutside() }
            }
        }
    }

    private func rulesFileModificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: rulesStore.fileURL.path))?[.modificationDate] as? Date
    }

    /// Picks up rules changed by the `tidyup` command or an AI agent, so the app never saves over them.
    private func reloadRulesIfChangedOutside() {
        guard saveTask == nil, let date = rulesFileModificationDate(), date != rulesFileDate else { return }
        rulesFileDate = date
        guard let loaded = try? rulesStore.load(), loaded != config else { return }
        reloadingFromDisk = true
        config = loaded
        reloadingFromDisk = false
        organizer?.config = loaded
        watchService?.restart()
        message = "Rules were changed outside the app (for example by the tidyup command or an AI agent) and have been reloaded."
    }

    var isWatching: Bool { !settings.paused && watchService != nil }

    func startWatching() {
        watchService?.restart()
    }

    // MARK: Saving

    private func scheduleSave() {
        organizer?.config = config
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.saveTask = nil
            self?.saveConfigNow()
        }
    }

    func saveConfigNow() {
        do {
            try rulesStore.save(config)
            rulesFileDate = rulesFileModificationDate()
            organizer?.config = config
            watchService?.restart()
        } catch {
            message = "Could not save rules: \(error)"
        }
    }

    func saveSettings() {
        organizer?.settings = settings
        do {
            try settingsStore.save(settings)
        } catch {
            message = "Could not save settings: \(error)"
        }
        watchService?.restart()
    }

    func replaceConfig(_ newConfig: RulesConfig) {
        config = newConfig
        saveConfigNow()
    }

    // MARK: Running

    func togglePause() {
        settings.paused.toggle()
        saveSettings()
    }

    func runNowAll() {
        guard let organizer else { return }
        let folders = config.folders.filter(\.enabled)
        perform("Tidying \(folders.count) folder(s)") { folders.map { organizer.runNow($0) } }
    }

    func runNow(_ folder: WatchedFolder) {
        guard let organizer else { return }
        perform("Tidying \(folder.path)") { [organizer.runNow(folder)] }
    }

    // MARK: Long tasks and progress

    /// Starts a long task unless one is already running. Returns false (and says why) when busy.
    private func beginOperation(_ title: String) -> Bool {
        guard !busy else {
            message = "Already busy: \(operationTitle ?? "working"). Wait for it to finish or press Cancel."
            return false
        }
        organizer?.resetCancel()
        operationCancelled = false
        busy = true
        operationTitle = title
        work = nil
        return true
    }

    private func endOperation() {
        busy = false
        operationTitle = nil
        work = nil
    }

    func cancelWork() {
        guard busy else { return }
        operationCancelled = true
        organizer?.cancel()
        operationTitle = "Stopping after the current item…"
    }

    fileprivate func receive(_ progress: WorkProgress) {
        if progress.kind == .checkingNewFiles && !busy {
            // The watcher's own work: show it while it runs, clear it when done.
            work = progress.finished ? nil : progress
            return
        }
        guard busy, !progress.finished else { return }
        work = progress
    }

    /// Shows what every folder's rules would do right now, without changing anything.
    func simulateAll() {
        guard let organizer else { return }
        let folders = config.folders.filter(\.enabled)
        guard !folders.isEmpty else {
            message = "No folders are being watched yet."
            return
        }
        guard beginOperation("Simulating \(folders.count) folder(s) — nothing will be moved") else { return }
        Task.detached {
            let items = folders.flatMap { organizer.simulate($0) }
            await MainActor.run {
                let model = AppModel.shared
                model.previews = items
                let cancelled = model.operationCancelled
                model.endOperation()
                model.lastRun = nil
                model.scanFoundCount = items.isEmpty ? nil : items.count
                if cancelled {
                    model.message = "Simulation stopped. \(items.count) item(s) found so far are in Preview."
                } else {
                    model.message = items.isEmpty ? "Nothing to tidy right now — everything is already in place." : nil
                }
            }
        }
    }

    /// Small, quiet simulation for the rule editor (no progress banner).
    func simulate(_ folder: WatchedFolder, rule: Rule? = nil) async -> [PreviewItem] {
        guard let organizer else { return [] }
        return await Task.detached { organizer.simulate(folder, onlyRule: rule, reportProgress: false) }.value
    }

    func approve(_ items: [PreviewItem]) {
        guard let organizer else { return }
        let approvedIDs = Set(items.map(\.id))
        guard !busy else {
            message = "Already busy: \(operationTitle ?? "working"). Wait for it to finish or press Cancel."
            return
        }
        previews.removeAll { approvedIDs.contains($0.id) }
        perform("Running \(items.count) approved item(s)") { [organizer.approve(items)] }
    }

    private func refreshPreviewDetails() {
        let items = previews
        inspectTask?.cancel()
        inspectingPreviews = true
        inspectTask = Task.detached(priority: .userInitiated) {
            let details = PreviewInspector.inspect(items)
            await MainActor.run {
                let model = AppModel.shared
                guard model.previews == items else { return }
                model.previewDetails = details
                model.inspectingPreviews = false
            }
        }
    }

    func discard(_ items: [PreviewItem]) {
        let ids = Set(items.map(\.id))
        previews.removeAll { ids.contains($0.id) }
    }

    private func perform(_ title: String, _ work: @escaping @Sendable () -> [ProcessResult]) {
        guard beginOperation(title) else { return }
        Task.detached {
            let results = work()
            await MainActor.run {
                let model = AppModel.shared
                for result in results { model.absorb(result) }
                let cancelled = model.operationCancelled
                model.endOperation()
                let waiting = results.flatMap(\.previews)
                if let report = RunReport(results: results, title: title, cancelled: cancelled) {
                    model.lastRun = report
                    if waiting.isEmpty {
                        model.message = nil
                    } else {
                        model.explainWaiting(waiting, lead: "")
                    }
                } else if cancelled {
                    model.message = "Stopped before anything was changed."
                } else if waiting.isEmpty {
                    model.message = "Already tidy — nothing new to sort. \(model.todayCount) file(s) were tidied today."
                } else {
                    model.explainWaiting(waiting, lead: "Already tidy — nothing new to sort automatically. ")
                }
            }
        }
    }

    /// Says why items are waiting (which preview-mode rules) and offers to review, run or turn those rules on.
    func explainWaiting(_ items: [PreviewItem], lead: String) {
        var names: [String] = []
        for item in items where !names.contains(item.ruleName) { names.append(item.ruleName) }
        let quoted = names.prefix(3).map { "“\($0)”" }.joined(separator: ", ") + (names.count > 3 ? " and \(names.count - 3) more" : "")
        let rules = items.map { MessageAction.RuleRef(folderPath: $0.folderPath, ruleName: $0.ruleName) }
        say(lead + "\(items.count) item(s) wait for your OK because \(quoted) \(names.count == 1 ? "is" : "are") in preview mode.",
            actions: [
                MessageAction(title: "Review", kind: .openPreview),
                MessageAction(title: "Run These \(items.count)", kind: .runWaiting(rules)),
                MessageAction(title: names.count == 1 ? "Always Run “\(names[0])”" : "Always Run These Rules", kind: .turnOnRules(rules)),
            ])
    }

    func say(_ text: String, actions: [MessageAction]) {
        message = text
        messageActions = actions
    }

    func handle(_ action: MessageAction) {
        switch action.kind {
        case .openPreview:
            requestedSection = .preview
            message = nil
        case .runWaiting(let rules):
            approve(previews.filter { item in rules.contains { $0.ruleName == item.ruleName && $0.folderPath == item.folderPath } })
        case .turnOnRules(let rules):
            var changed: [String] = []
            for folder in config.folders.indices {
                for index in config.folders[folder].rules.indices {
                    let rule = config.folders[folder].rules[index]
                    guard rule.mode == .preview,
                          rules.contains(where: { $0.ruleName == rule.name && $0.folderPath == config.folders[folder].path }) else { continue }
                    config.folders[folder].rules[index].mode = .live
                    changed.append(rule.name)
                }
            }
            let waiting = previews.filter { item in rules.contains { $0.ruleName == item.ruleName && $0.folderPath == item.folderPath } }
            say("\(changed.map { "“\($0)”" }.joined(separator: ", ")) now run automatically. "
                + (waiting.isEmpty ? "" : "The \(waiting.count) item(s) already waiting can run now."),
                actions: waiting.isEmpty ? [] : [MessageAction(title: "Run These \(waiting.count)", kind: .runWaiting(rules))])
        }
    }

    func absorb(_ result: ProcessResult) {
        let known = Set(previews.map(\.id))
        previews += result.previews.filter { !known.contains($0.id) }
        if !result.records.isEmpty { refreshActivity() }
    }

    /// Results of the watcher and scheduled checks: same report as a manual run, plus a notification.
    func absorbBackground(_ result: ProcessResult) {
        absorb(result)
        guard let report = RunReport(results: [result], title: "Tidied new files automatically", cancelled: false) else { return }
        lastRun = report
        if settings.notifyAfterBackgroundRuns {
            Notifier.post(report)
        }
    }

    func showRun(_ batchID: Int64?) {
        focusedRunID = batchID
        requestedSection = .activity
    }

    func undoRun(_ report: RunReport) {
        for batch in report.batchIDs { undoBatch(batch) }
        lastRun = nil
    }

    // MARK: Activity and undo

    func refreshActivity() {
        guard let store = organizer?.store else { return }
        recent = (try? store.records(ActivityQuery(limit: 8))) ?? []
        todayCount = (try? store.tidiedCount(since: Calendar.current.startOfDay(for: Date()))) ?? 0
    }

    func records(_ query: ActivityQuery) -> [ActivityRecord] {
        (try? organizer?.store.records(query)) ?? []
    }

    func undoLast() {
        guard let organizer else { return }
        do {
            let record = try organizer.undo.undoLast()
            message = "Undid: \(record.action) \(URL(fileURLWithPath: record.sourcePath).lastPathComponent)"
        } catch {
            message = String(describing: error)
        }
        refreshActivity()
    }

    func undo(_ record: ActivityRecord) {
        guard let organizer else { return }
        do {
            try organizer.undo.undo(record)
            message = "Undid: \(record.action) \(URL(fileURLWithPath: record.sourcePath).lastPathComponent)"
        } catch {
            message = String(describing: error)
        }
        refreshActivity()
    }

    func undoBatch(_ batchID: Int64) {
        guard let organizer else { return }
        do {
            let failures = try organizer.undo.undoBatch(batchID)
            message = failures.isEmpty ? "Undid the whole run."
                : "Undid the run; \(failures.count) step(s) could not be undone: \(failures.map { String(describing: $0.1) }.joined(separator: "; "))"
        } catch {
            message = String(describing: error)
        }
        refreshActivity()
    }

    // MARK: AI

    func requestAISuggestions(for folder: WatchedFolder) {
        guard settings.ai.enabled, let organizer else { return }
        let ai = settings.ai
        let key = KeychainStore.key(for: ai.provider)
        busy = true
        message = ai.provider.isLocal ? "Asking the local model…" : "Sending names and metadata to \(ai.provider.displayName)…"
        Task.detached {
            let provider = HTTPAIProvider(kind: ai.provider, endpoint: ai.endpoint, model: ai.model, apiKey: key)
            let sorter = AISorter(provider: provider, settings: ai)
            let outcome: Result<[AISuggestionItem], Error>
            do {
                outcome = .success(try await sorter.suggest(for: folder, items: organizer.candidates(in: folder)))
            } catch {
                outcome = .failure(error)
            }
            await MainActor.run {
                let model = AppModel.shared
                model.busy = false
                switch outcome {
                case .success(let items):
                    model.aiSuggestions = items
                    model.message = items.isEmpty ? "The model had no suggestions." : "\(items.count) suggestion(s) waiting for your OK."
                case .failure(let error):
                    model.message = String(describing: error)
                }
            }
        }
    }

    func approveAI(_ items: [AISuggestionItem]) {
        guard let organizer else { return }
        let ids = Set(items.map(\.id))
        aiSuggestions.removeAll { ids.contains($0.id) }
        perform("Running \(items.count) AI suggestion(s)") { [organizer.approve(items)] }
    }

    func makePermanentRule(_ item: AISuggestionItem) {
        guard let index = config.folders.firstIndex(where: { $0.path == item.folderPath }) else { return }
        config.folders[index].rules.append(AISorter.permanentRule(from: item))
        message = "Added rule “\(item.suggestion.category)” in preview mode."
    }

    // MARK: Smart Trash

    private var smartTrashTimer: Timer?

    func planSmartTrash() -> SmartTrashPlan? {
        do {
            return SmartTrash.plan(try SmartTrash().scan(), settings: settings.smartTrash)
        } catch {
            message = "Can't read the Trash. Give TidyUpMyFiles Full Disk Access in System Settings → Privacy & Security (\(error.localizedDescription))."
            return nil
        }
    }

    func emptySmartTrash(_ plan: SmartTrashPlan) {
        let result = SmartTrash().empty(plan)
        if let store = organizer?.store, let batch = try? store.beginBatch(trigger: "smart trash", folder: "~/.Trash") {
            for item in result.removed {
                _ = try? store.append(ActivityRecord(batchID: batch, ruleName: "Smart Trash", action: "empty_trash", status: .done,
                                                 sourcePath: item.url.path, message: ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)))
            }
            for (item, error) in result.failures {
                _ = try? store.append(ActivityRecord(batchID: batch, ruleName: "Smart Trash", action: "empty_trash", status: .failed,
                                                 sourcePath: item.url.path, message: String(describing: error)))
            }
        }
        message = "Smart Trash removed \(result.removed.count) item(s)" + (result.failures.isEmpty ? "." : ", \(result.failures.count) failed.")
        refreshActivity()
    }

    /// Hourly automatic run, only after the person confirmed the first summary.
    func startSmartTrashTimer() {
        smartTrashTimer?.invalidate()
        smartTrashTimer = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { _ in
            Task { @MainActor in AppModel.shared.runSmartTrashIfDue() }
        }
        runSmartTrashIfDue()
    }

    private func runSmartTrashIfDue() {
        let trash = settings.smartTrash
        guard trash.enabled, trash.confirmed, !settings.paused,
              let plan = try? SmartTrash.plan(SmartTrash().scan(), settings: trash), !plan.items.isEmpty else { return }
        emptySmartTrash(plan)
    }

    // MARK: Import and export

    func exportRules() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tidyup-rules.yaml"
        panel.allowedContentTypes = [.yaml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try RulesYAML.encode(config).write(to: url, atomically: true, encoding: .utf8)
            message = "Exported rules to \(PathTools.abbreviate(url.path))."
        } catch {
            message = "Export failed: \(error)"
        }
    }

    /// Adds the file's folders and rules, or replaces everything. Rules keep the mode written in the file.
    func importRules(replace: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.yaml, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try RulesYAML.decode(String(contentsOf: url, encoding: .utf8))
            if replace {
                config = imported
            } else {
                for folder in imported.folders {
                    if let index = config.folders.firstIndex(where: { PathTools.canonical($0.url) == PathTools.canonical(folder.url) }) {
                        config.folders[index].rules += folder.rules
                    } else {
                        config.folders.append(folder)
                    }
                }
            }
            saveConfigNow()
            message = "Imported \(imported.folders.reduce(0) { $0 + $1.rules.count }) rule(s)."
        } catch {
            message = "Import failed, nothing changed: \(error)"
        }
    }

    // MARK: Folders and templates

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard SafetyGuard().isAllowed(url) else {
            message = "TidyUpMyFiles never touches system folders, ~/Library, .git folders or app bundles."
            return
        }
        config.folders.append(WatchedFolder(path: PathTools.abbreviate(url.path)))
    }

    /// Adds a ready-made rule to `folderPath` (or the template's own folder).
    func install(_ template: Templates.Template, folderPath: String? = nil) {
        let place = PathTools.abbreviate(PathTools.expandTilde(folderPath ?? template.folderPath))
        if Templates.install(template, into: &config, folderPath: folderPath) {
            message = "Added “\(template.title)” to \(place) in preview mode. Turn on Live when the preview looks right."
        } else {
            message = "\(place) already has “\(template.title)”."
        }
    }

    func isInstalled(_ template: Templates.Template, folderPath: String) -> Bool {
        Templates.isInstalled(template, in: config, folderPath: folderPath)
    }

    /// Every watched folder that already has this ready-made rule.
    func folders(having template: Templates.Template) -> [WatchedFolder] {
        config.folders.filter { Templates.isInstalled(template, in: config, folderPath: $0.path) }
    }

    /// Asks for a folder (not yet watched is fine) and returns it, or nil when cancelled or not allowed.
    func pickFolderForRules() -> String? {
        guard let path = AppModel.chooseFolder(startingAt: "~") else { return nil }
        guard SafetyGuard().isAllowed(URL(fileURLWithPath: PathTools.expandTilde(path))) else {
            message = "TidyUpMyFiles never touches system folders, ~/Library, .git folders or app bundles."
            return nil
        }
        return PathTools.abbreviate(PathTools.expandTilde(path))
    }

    func installInPickedFolder(_ template: Templates.Template) {
        guard let path = pickFolderForRules() else { return }
        install(template, folderPath: path)
    }

    /// "Also use in…": a copy of the rule in another watched folder (same on/off and preview/live choice).
    func copyRule(_ rule: Rule, to folder: WatchedFolder) {
        guard let index = config.folders.firstIndex(where: { $0.id == folder.id }) else { return }
        if config.folders[index].rules.contains(where: { $0.isSameRule(as: rule) }) {
            message = "\(folder.path) already has “\(rule.name)”."
            return
        }
        var copy = rule
        copy.id = UUID()
        config.folders[index].rules.append(copy)
        message = "“\(rule.name)” now also works in \(folder.path)."
    }

    func isInstalled(_ template: Templates.Template) -> Bool {
        Templates.isInstalled(template, in: config)
    }

    var missingRecommendedCount: Int {
        Templates.all.filter { !Templates.isInstalled($0, in: config) }.count
    }

    var recommendedInPreviewCount: Int { Templates.recommendedInPreview(config) }

    func installRecommended() {
        let added = Templates.installRecommended(into: &config)
        message = added == 0 ? "All recommended rules are already set up."
            : "Added \(added) recommended rule(s) in preview mode."
    }

    /// Turns the recommended rules from preview into live tidying.
    func makeRecommendedLive() {
        let changed = Templates.makeRecommendedLive(in: &config)
        message = "Turned on \(changed) recommended rule(s). Every step is logged and can be undone."
    }

    static func chooseFolder(startingAt path: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: PathTools.expandTilde(path))
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return PathTools.abbreviate(url.path)
    }
}

/// A button offered with a message, e.g. "Run These 5".
struct MessageAction: Identifiable, Equatable {
    struct RuleRef: Equatable {
        let folderPath: String
        let ruleName: String
    }

    enum Kind: Equatable {
        case openPreview
        case runWaiting([RuleRef])
        case turnOnRules([RuleRef])
    }

    let id = UUID()
    let title: String
    let kind: Kind
}
