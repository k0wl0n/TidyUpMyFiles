import CoreServices
import Foundation

/// Names that mean "still downloading or being written".
public enum PartialFiles {
    public static let extensions: Set<String> = ["crdownload", "download", "part", "partial", "tmp", "temp", "opdownload", "!qb"]
    /// System clutter that is never a user's file.
    public static let junkNames: Set<String> = ["Icon\r", "Thumbs.db", "desktop.ini"]

    public static func isPartial(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    /// Firefox and others create the final name early and keep the data in a sibling `.part` file.
    public static func hasPartialSibling(_ url: URL) -> Bool {
        extensions.contains { FileManager.default.fileExists(atPath: url.path + "." + $0) }
    }

    public static func shouldIgnore(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix(".") || junkNames.contains(name) || isPartial(url)
    }
}

/// Watches folders with FSEvents and reports items once they have stopped changing.
///
/// An item is ready when no event arrived for it and its size stayed the same for `stableSeconds`.
public final class FolderWatcher: @unchecked Sendable {
    public struct Root: Sendable {
        public var url: URL
        public var includeSubfolders: Bool

        public init(url: URL, includeSubfolders: Bool) {
            self.url = url
            self.includeSubfolders = includeSubfolders
        }
    }

    public typealias ReadyHandler = @Sendable (_ root: URL, _ items: [URL]) -> Void

    private struct Pending {
        var root: URL
        var size: Int64
        var lastChange: Date
    }

    private let queue = DispatchQueue(label: "tidyup.watcher")
    private let roots: [Root]
    private let latency: TimeInterval
    private let stableSeconds: TimeInterval
    private let onReady: ReadyHandler
    private var stream: FSEventStreamRef?
    private var pending: [String: Pending] = [:]
    private var ignoredUntil: [String: Date] = [:]
    private var checkTimer: DispatchSourceTimer?

    public init(roots: [Root], latency: TimeInterval = 0.2, stableSeconds: TimeInterval = 2.0, onReady: @escaping ReadyHandler) {
        self.roots = roots.map { Root(url: URL(fileURLWithPath: PathTools.canonical($0.url)), includeSubfolders: $0.includeSubfolders) }
        self.latency = latency
        self.stableSeconds = stableSeconds
        self.onReady = onReady
    }

    deinit {
        stopStream()
    }

    public func start() {
        queue.sync { startStream() }
    }

    public func stop() {
        queue.sync {
            stopStream()
            pending.removeAll()
        }
    }

    /// Paths TidyUpMyFiles itself just created; their events are ignored for a few seconds to avoid loops.
    public func ignore(_ urls: [URL], for seconds: TimeInterval = 10) {
        let until = Date().addingTimeInterval(seconds)
        queue.async {
            for url in urls { self.ignoredUntil[PathTools.canonical(url)] = until }
        }
    }

    // MARK: FSEvents

    private func startStream() {
        guard stream == nil, !roots.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = unsafeBitCast(paths, to: NSArray.self)
            let changed = (0..<count).compactMap { array[$0] as? String }
            watcher.received(changed)
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(nil, callback, &context, roots.map(\.url.path) as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return }
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    private func stopStream() {
        checkTimer?.cancel()
        checkTimer = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Called on `queue` by FSEvents.
    private func received(_ paths: [String]) {
        let now = Date()
        ignoredUntil = ignoredUntil.filter { $0.value > now }
        for rawPath in paths {
            let url = URL(fileURLWithPath: rawPath)
            guard let root = root(for: url), !PartialFiles.shouldIgnore(url) else { continue }
            let path = PathTools.canonical(url)
            if ignoredUntil[path] != nil { continue }
            guard FileManager.default.fileExists(atPath: path) else {
                pending[path] = nil
                continue
            }
            pending[path] = Pending(root: root, size: FolderWatcher.size(of: path), lastChange: now)
        }
        scheduleChecks()
    }

    /// The watched root an event belongs to, or nil when it is deeper than the root allows.
    private func root(for url: URL) -> URL? {
        let path = PathTools.canonical(url)
        for root in roots {
            let rootPath = root.url.path
            guard path.hasPrefix(rootPath + "/") else { continue }
            let relative = path.dropFirst(rootPath.count + 1)
            if root.includeSubfolders {
                // Nested items count too, unless a folder on the way is hidden.
                return relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) ? nil : root.url
            }
            return relative.contains("/") ? nil : root.url
        }
        return nil
    }

    private func scheduleChecks() {
        guard checkTimer == nil, !pending.isEmpty else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in self?.checkPending() }
        timer.resume()
        checkTimer = timer
    }

    private func checkPending() {
        let now = Date()
        var ready: [URL: [URL]] = [:]
        for (path, item) in pending {
            guard FileManager.default.fileExists(atPath: path) else {
                pending[path] = nil
                continue
            }
            let size = FolderWatcher.size(of: path)
            if size != item.size {
                pending[path]?.size = size
                pending[path]?.lastChange = now
                continue
            }
            guard now.timeIntervalSince(item.lastChange) >= stableSeconds else { continue }
            pending[path] = nil
            let url = URL(fileURLWithPath: path)
            if PartialFiles.hasPartialSibling(url) { continue }
            ready[item.root, default: []].append(url)
        }
        if pending.isEmpty {
            checkTimer?.cancel()
            checkTimer = nil
        }
        for (root, items) in ready {
            onReady(root, items.sorted { $0.path < $1.path })
        }
    }

    private static func size(of path: String) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
