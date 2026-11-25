import Foundation

/// Runs the watcher for every enabled folder and re-checks folders periodically for age-based rules.
public final class WatchService: @unchecked Sendable {
    public typealias ChangeHandler = @Sendable (ProcessResult) -> Void

    private let organizer: Organizer
    private let onChange: ChangeHandler
    private let lock = NSLock()
    private var watcher: FolderWatcher?
    private var rescanTimer: DispatchSourceTimer?
    private let rescanQueue = DispatchQueue(label: "tidyup.rescan")

    public init(organizer: Organizer, onChange: @escaping ChangeHandler) {
        self.organizer = organizer
        self.onChange = onChange
    }

    public var isRunning: Bool { lock.withLock { watcher != nil } }

    /// Applies the current rules and settings: stops when paused, otherwise watches the enabled folders.
    public func restart() {
        stop()
        let settings = organizer.settings
        guard !settings.paused else { return }
        let roots = organizer.config.folders.filter(\.enabled).map {
            FolderWatcher.Root(url: $0.url, includeSubfolders: $0.includeSubfolders)
        }
        guard !roots.isEmpty else { return }

        let organizer = self.organizer
        let onChange = self.onChange
        let newWatcher = FolderWatcher(roots: roots, stableSeconds: settings.stableSeconds) { [weak self] root, items in
            guard let folder = organizer.folder(forRoot: root), folder.enabled else { return }
            let result = organizer.process(items, in: folder, trigger: "watch")
            self?.ignore(result.producedPaths)
            onChange(result)
        }
        newWatcher.start()

        let timer = DispatchSource.makeTimerSource(queue: rescanQueue)
        let interval = max(1, settings.rescanMinutes) * 60
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.rescanAll() }
        timer.resume()

        lock.withLock {
            watcher = newWatcher
            rescanTimer = timer
        }
    }

    public func stop() {
        let (oldWatcher, oldTimer) = lock.withLock { () -> (FolderWatcher?, DispatchSourceTimer?) in
            defer { watcher = nil; rescanTimer = nil }
            return (watcher, rescanTimer)
        }
        oldTimer?.cancel()
        oldWatcher?.stop()
    }

    public func ignore(_ paths: [URL]) {
        lock.withLock { watcher }?.ignore(paths)
    }

    /// Runs every enabled folder once (what "Run now" does for all folders).
    @discardableResult
    public func rescanAll() -> [ProcessResult] {
        guard !organizer.settings.paused else { return [] }
        return organizer.config.folders.filter(\.enabled).map { folder in
            let result = organizer.runNow(folder, trigger: "scheduled")
            ignore(result.producedPaths)
            onChange(result)
            return result
        }
    }
}
