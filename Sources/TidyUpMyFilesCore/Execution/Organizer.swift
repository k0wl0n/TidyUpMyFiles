import Foundation

/// "This file would be handled by this rule like this" — shown before anything happens.
public struct PreviewItem: Identifiable, Equatable, Sendable {
    public var folderPath: String
    public var file: URL
    public var ruleName: String
    public var steps: [PlannedStep]
    /// The rule permits replacing an existing file (needed to predict what a conflict will do).
    public var allowOverwrite: Bool = false

    public var id: String { file.path + "|" + ruleName }

    public var summary: String { steps.map(\.summary).joined(separator: ", then ") }
}

public struct ProcessResult: Sendable {
    public var batchID: Int64?
    public var records: [ActivityRecord] = []
    public var previews: [PreviewItem] = []
    public var producedPaths: [URL] = []

    public init() {}

    mutating func absorb(_ outcome: ExecutionOutcome) {
        records += outcome.records
        producedPaths += outcome.producedPaths
    }
}

/// What a long-running scan or run is doing, for the progress banner.
public struct WorkProgress: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// Looking at what would happen; nothing changes.
        case simulating
        /// Running rules on what is already in a folder.
        case tidying
        /// Handling items the watcher just saw arrive.
        case checkingNewFiles
        /// Running items approved in Preview or AI.
        case applying
    }

    public var kind: Kind
    public var folder: String
    public var done: Int
    public var total: Int
    public var item: String?
    public var finished: Bool

    public init(kind: Kind, folder: String, done: Int, total: Int, item: String? = nil, finished: Bool = false) {
        self.kind = kind
        self.folder = folder
        self.done = done
        self.total = total
        self.item = item
        self.finished = finished
    }

    public var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

public typealias ProgressHandler = @Sendable (WorkProgress) -> Void

/// Sends progress at most ten times a second, plus the start and the end.
private final class ProgressReporter {
    private let handler: ProgressHandler?
    private var lastSent = Date.distantPast

    init(_ handler: ProgressHandler?) { self.handler = handler }

    func report(_ progress: WorkProgress, force: Bool = false) {
        guard let handler, force || Date().timeIntervalSince(lastSent) >= 0.1 else { return }
        lastSent = Date()
        handler(progress)
    }
}

/// Ties rules, engine, executor and log together. Shared by the app, the watcher and the CLI.
public final class Organizer: @unchecked Sendable {
    private let lock = NSLock()
    private var currentConfig: RulesConfig
    private var currentSettings: AppSettings
    private var progressHandler: ProgressHandler?
    private var cancelRequested = false
    public let store: ActivityStore
    public let trash: any TrashProvider
    public let opener: any FileOpener
    public let guardrail: SafetyGuard

    public init(config: RulesConfig, settings: AppSettings, store: ActivityStore, trash: any TrashProvider = SystemTrash(),
                opener: any FileOpener = SystemOpener(), guardrail: SafetyGuard = SafetyGuard()) {
        self.currentConfig = config
        self.currentSettings = settings
        self.store = store
        self.trash = trash
        self.opener = opener
        self.guardrail = guardrail
    }

    public var config: RulesConfig {
        get { lock.withLock { currentConfig } }
        set { lock.withLock { currentConfig = newValue } }
    }

    public var settings: AppSettings {
        get { lock.withLock { currentSettings } }
        set { lock.withLock { currentSettings = newValue } }
    }

    public var undo: UndoService { UndoService(store: store, trash: trash) }

    /// Receives progress of scans and runs (from a background thread).
    public func setProgressHandler(_ handler: ProgressHandler?) {
        lock.withLock { progressHandler = handler }
    }

    /// Asks the running scan or run to stop after the current item. Steps already done stay logged and undoable.
    public func cancel() {
        lock.withLock { cancelRequested = true }
    }

    public func resetCancel() {
        lock.withLock { cancelRequested = false }
    }

    public var isCancelled: Bool { lock.withLock { cancelRequested } }

    private func reporter(_ enabled: Bool) -> ProgressReporter {
        ProgressReporter(enabled ? lock.withLock { progressHandler } : nil)
    }

    private func executor(engine: RuleEngine) -> ActionExecutor {
        ActionExecutor(engine: engine, store: store, guardrail: guardrail, trash: trash, opener: opener,
                       allowShellScripts: settings.allowShellScripts, allowShortcuts: settings.allowShortcuts)
    }

    public func folder(forRoot root: URL) -> WatchedFolder? {
        let path = PathTools.canonical(root)
        return config.folders.first { PathTools.canonical($0.url) == path }
    }

    /// Items currently in a watched folder that rules may look at.
    public func candidates(in folder: WatchedFolder) -> [URL] {
        let fileManager = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = folder.includeSubfolders
            ? [.skipsHiddenFiles, .skipsPackageDescendants] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        guard guardrail.isAllowed(folder.url),
              let enumerator = fileManager.enumerator(at: folder.url, includingPropertiesForKeys: nil, options: options) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            if PartialFiles.shouldIgnore(url) || PartialFiles.hasPartialSibling(url) || folder.isExcluded(url)
                || !guardrail.isAllowed(url) { continue }
            urls.append(url)
        }
        return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Duplicate lookup for the folder, built only when a rule asks for duplicates.
    private func duplicateIndex(for needs: FactNeeds, in folder: WatchedFolder) -> DuplicateIndex? {
        needs.contains(.duplicates) ? DuplicateIndex(items: candidates(in: folder)) : nil
    }

    /// Reads a file's facts; slow ones (contents, duplicates, Spotlight, folder sizes) only when a rule needs them.
    private func facts(for url: URL, needs: FactNeeds, duplicates: DuplicateIndex?) -> FileFacts? {
        guard var facts = try? FileFactsReader.read(url, needs: needs) else { return nil }
        if needs.contains(.text) {
            facts.textContent = ContentReader.text(of: url)
        }
        facts.duplicateOf = duplicates?.originalFor(url)
        return facts
    }

    /// Acts on live rules and collects previews for preview-mode rules. All steps share one batch, so they undo together.
    public func process(_ urls: [URL], in folder: WatchedFolder, trigger: String, treatPreviewAsLive: Bool = false,
                        reportProgress: Bool = true) -> ProcessResult {
        let engine = RuleEngine()
        let rules = folder.rules
        let needs = FactNeeds.forRules(rules)
        let kind: WorkProgress.Kind = trigger == "watch" ? .checkingNewFiles : .tidying
        let progress = reporter(reportProgress)
        progress.report(WorkProgress(kind: kind, folder: folder.path, done: 0, total: urls.count), force: true)
        defer { progress.report(WorkProgress(kind: kind, folder: folder.path, done: urls.count, total: urls.count, finished: true), force: true) }
        let duplicates = duplicateIndex(for: needs, in: folder)
        var result = ProcessResult()
        for (index, url) in urls.enumerated() {
            if isCancelled { break }
            progress.report(WorkProgress(kind: kind, folder: folder.path, done: index, total: urls.count, item: url.lastPathComponent))
            guard FileManager.default.fileExists(atPath: url.path), guardrail.isAllowed(url), !folder.isExcluded(url),
                  !PartialFiles.shouldIgnore(url), let facts = facts(for: url, needs: needs, duplicates: duplicates) else { continue }
            let matched = engine.matchingRules(rules, for: facts)
            guard !matched.isEmpty else { continue }

            let live = treatPreviewAsLive ? matched : Array(matched.prefix { $0.mode == .live })
            var current: FileFacts? = facts
            if !live.isEmpty {
                if result.batchID == nil {
                    result.batchID = try? store.beginBatch(trigger: trigger, folder: folder.path)
                }
                let outcome = executor(engine: engine).execute(live, on: facts, batchID: result.batchID ?? 0)
                result.absorb(outcome)
                current = outcome.hadFailure ? nil : outcome.finalURL.flatMap { try? FileFactsReader.read($0, needs: needs) }
            }
            if let current {
                for rule in matched.dropFirst(live.count) {
                    result.previews.append(PreviewItem(folderPath: folder.path, file: current.url, ruleName: rule.name,
                                                       steps: engine.plan(rule, facts: current),
                                                       allowOverwrite: rule.allowOverwrite))
                }
            }
        }
        return result
    }

    /// What every enabled rule (live or preview) would do to the folder's current items. Changes nothing.
    /// The rule editor's live preview passes `onlyRule` and no progress; Simulate All reports progress.
    public func simulate(_ folder: WatchedFolder, onlyRule: Rule? = nil, reportProgress: Bool = true) -> [PreviewItem] {
        let engine = RuleEngine()
        let rules = onlyRule.map { rule in [Rule](arrayLiteral: { var r = rule; r.enabled = true; return r }()) } ?? folder.rules
        let needs = FactNeeds.forRules(rules)
        let items = candidates(in: folder)
        let progress = reporter(reportProgress)
        progress.report(WorkProgress(kind: .simulating, folder: folder.path, done: 0, total: items.count), force: true)
        defer {
            progress.report(WorkProgress(kind: .simulating, folder: folder.path, done: items.count, total: items.count, finished: true),
                            force: true)
        }
        let duplicates = duplicateIndex(for: needs, in: folder)
        var previews: [PreviewItem] = []
        for (index, url) in items.enumerated() {
            if reportProgress && isCancelled { break }
            progress.report(WorkProgress(kind: .simulating, folder: folder.path, done: index, total: items.count, item: url.lastPathComponent))
            guard let facts = facts(for: url, needs: needs, duplicates: duplicates) else { continue }
            for match in engine.matches(rules, for: facts) {
                previews.append(PreviewItem(folderPath: folder.path, file: url, ruleName: match.rule.name, steps: match.steps,
                                            allowOverwrite: match.rule.allowOverwrite))
            }
        }
        return previews
    }

    /// "Run now": handles everything already in the folder as one batch.
    public func runNow(_ folder: WatchedFolder, trigger: String = "run now") -> ProcessResult {
        process(candidates(in: folder), in: folder, trigger: trigger)
    }

    /// Runs previewed items the person approved, as one batch.
    public func approve(_ items: [PreviewItem]) -> ProcessResult {
        var result = ProcessResult()
        let engine = RuleEngine()
        let progress = reporter(true)
        defer {
            progress.report(WorkProgress(kind: .applying, folder: "", done: items.count, total: items.count, finished: true), force: true)
        }
        for (index, item) in items.enumerated() {
            if isCancelled { break }
            progress.report(WorkProgress(kind: .applying, folder: item.folderPath, done: index, total: items.count,
                                         item: item.file.lastPathComponent), force: index == 0)
            guard let folder = config.folders.first(where: { $0.path == item.folderPath }),
                  let rule = folder.rules.first(where: { $0.name == item.ruleName }),
                  let facts = try? FileFactsReader.read(item.file, needs: FactNeeds.forRules([rule])) else { continue }
            if result.batchID == nil {
                result.batchID = try? store.beginBatch(trigger: "approved", folder: folder.path)
            }
            result.absorb(executor(engine: engine).execute([rule], on: facts, batchID: result.batchID ?? 0))
        }
        return result
    }

    /// Runs AI suggestions the person approved, as one batch.
    public func approve(_ items: [AISuggestionItem]) -> ProcessResult {
        var result = ProcessResult()
        let engine = RuleEngine()
        for item in items {
            guard let facts = try? FileFactsReader.read(item.file) else { continue }
            if result.batchID == nil {
                result.batchID = try? store.beginBatch(trigger: "ai", folder: item.folderPath)
            }
            result.absorb(executor(engine: engine).execute([item.rule], on: facts, batchID: result.batchID ?? 0))
        }
        return result
    }
}
