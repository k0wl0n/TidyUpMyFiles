import Foundation

/// Moves files to the Trash and says where they ended up. Swappable so tests never touch the real Trash.
public protocol TrashProvider: Sendable {
    func trash(_ url: URL) throws -> URL
}

public struct SystemTrash: TrashProvider {
    public init() {}

    public func trash(_ url: URL) throws -> URL {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return (resulting as URL?) ?? url
    }
}

/// A Trash that is just a folder (demo mode): items are moved in with a free name and can be moved back.
public struct FolderTrash: TrashProvider {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func trash(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var destination = folder.appendingPathComponent(url.lastPathComponent)
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent(PathTools.numbered(url.lastPathComponent, counter))
            counter += 1
        }
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}

public protocol FileOpener: Sendable {
    func open(_ url: URL) throws
}

public struct SystemOpener: FileOpener {
    public init() {}

    public func open(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.path]
        try process.run()
    }
}

public struct ExecutionOutcome: Sendable {
    public var records: [ActivityRecord] = []
    /// Where the file is after all actions (nil when it went to the Trash).
    public var finalURL: URL?
    /// Every path TidyUpMyFiles created, so the watcher can ignore the events they cause.
    public var producedPaths: [URL] = []

    public var hadFailure: Bool { records.contains { $0.status == .failed } }
}

public enum ExecutionError: Error, CustomStringConvertible {
    case missingFolder(String)
    case shellFailed(Int32, String)
    case archiveFailed(String)
    case extractFailed(String)
    case shortcutFailed(Int32, String)

    public var description: String {
        switch self {
        case .archiveFailed(let output): return "Could not create the zip: \(output)"
        case .extractFailed(let output): return "Could not extract the archive: \(output)"
        case .shortcutFailed(let code, let output): return "The Shortcut stopped with code \(code): \(output)"
        case .missingFolder(let path): return "Folder \(path) does not exist and create_folders is off"
        case .shellFailed(let code, let output): return "Script exited with \(code): \(output)"
        }
    }
}

/// Runs the actions of matched rules on the real file system and logs each step with undo data.
public struct ActionExecutor: Sendable {
    public var engine: RuleEngine
    public var store: ActivityStore
    public var guardrail: SafetyGuard
    public var trash: any TrashProvider
    public var opener: any FileOpener
    public var allowShellScripts: Bool
    public var allowShortcuts: Bool

    public init(engine: RuleEngine = RuleEngine(), store: ActivityStore, guardrail: SafetyGuard = SafetyGuard(),
                trash: any TrashProvider = SystemTrash(), opener: any FileOpener = SystemOpener(),
                allowShellScripts: Bool = false, allowShortcuts: Bool = false) {
        self.engine = engine
        self.store = store
        self.guardrail = guardrail
        self.trash = trash
        self.opener = opener
        self.allowShellScripts = allowShellScripts
        self.allowShortcuts = allowShortcuts
    }

    private enum StepEnd { case next, stopRule, stopAll }

    private enum Resolution {
        case use(URL, displaced: URL?)
        case skip(String)
    }

    /// Runs each rule's actions in order. A failure or a trashed file stops everything that follows.
    public func execute(_ rules: [Rule], on facts: FileFacts, batchID: Int64) -> ExecutionOutcome {
        var outcome = ExecutionOutcome(finalURL: facts.url)
        var current = facts
        ruleLoop: for rule in rules {
            for action in rule.actions {
                let end = perform(action, rule: rule, current: &current, batchID: batchID, outcome: &outcome)
                switch end {
                case .next: continue
                case .stopRule: continue ruleLoop
                case .stopAll: break ruleLoop
                }
            }
        }
        if outcome.finalURL != nil { outcome.finalURL = current.url }
        return outcome
    }

    private func perform(_ action: Action, rule: Rule, current: inout FileFacts, batchID: Int64,
                         outcome: inout ExecutionOutcome) -> StepEnd {
        let source = current.url
        func log(_ status: ActivityStatus, target: URL? = nil, message: String = "", undo: UndoInfo? = nil) {
            let record = ActivityRecord(batchID: batchID, ruleName: rule.name, action: action.verb, status: status,
                                        sourcePath: source.path, targetPath: target?.path, message: message, undo: undo)
            outcome.records.append((try? store.append(record)) ?? record)
        }

        do {
            try guardrail.check(source)
            if let planned = engine.step(for: action, facts: current).target, PathTools.isInside(planned, folder: source) {
                log(.skipped, target: planned, message: "A folder can't be moved, copied or packed into itself")
                return .stopRule
            }
            switch action {
            case .move(_, let createFolders, let policy), .copy(_, let createFolders, let policy):
                guard let planned = engine.step(for: action, facts: current).target else { return .next }
                try guardrail.check(planned)
                let folder = planned.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: folder.path) {
                    guard createFolders else { throw ExecutionError.missingFolder(folder.path) }
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                }
                if isSameItem(planned, source) {
                    log(.skipped, target: planned, message: "Already in place")
                    return .next
                }
                switch try resolve(planned, policy: policy, rule: rule) {
                case .skip(let reason):
                    log(.skipped, target: planned, message: reason)
                    return .stopRule
                case .use(let target, let displaced):
                    if action.verb == "move" {
                        try FileManager.default.moveItem(at: source, to: target)
                        current.url = target
                        log(.done, target: target, undo: UndoInfo(kind: .moveBack, originalPath: source.path,
                                                                  currentPath: target.path, displacedTrashPath: displaced?.path))
                    } else {
                        try FileManager.default.copyItem(at: source, to: target)
                        log(.done, target: target, undo: UndoInfo(kind: .trashCopy, originalPath: source.path,
                                                                  currentPath: target.path, displacedTrashPath: displaced?.path))
                    }
                    outcome.producedPaths.append(target)
                }

            case .rename(let pattern, let policy):
                let resolution: Resolution
                if TokenRenderer.usesCounter(pattern) {
                    resolution = firstFreeCounterName(action, facts: current)
                } else {
                    guard let planned = engine.step(for: action, facts: current).target else { return .next }
                    if planned.lastPathComponent == source.lastPathComponent {
                        log(.skipped, target: planned, message: "Name already matches")
                        return .next
                    }
                    resolution = isSameItem(planned, source) ? .use(planned, displaced: nil)
                        : try resolve(planned, policy: policy, rule: rule)
                }
                switch resolution {
                case .skip(let reason):
                    log(.skipped, message: reason)
                    return .stopRule
                case .use(let target, let displaced):
                    try guardrail.check(target)
                    try FileManager.default.moveItem(at: source, to: target)
                    current.url = target
                    outcome.producedPaths.append(target)
                    log(.done, target: target, undo: UndoInfo(kind: .moveBack, originalPath: source.path,
                                                              currentPath: target.path, displacedTrashPath: displaced?.path))
                }

            case .addTags(let tags), .removeTags(let tags):
                let previous = FileTagging.tags(of: source)
                var updated = previous
                if action.verb == "add_tags" {
                    for tag in tags where !updated.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                        updated.append(tag)
                    }
                } else {
                    let removed = Set(tags.map { $0.lowercased() })
                    updated.removeAll { removed.contains($0.lowercased()) }
                }
                guard updated != previous else {
                    log(.skipped, message: "Tags already as wanted")
                    return .next
                }
                try FileTagging.setTags(updated, on: source)
                current.tags = updated
                log(.done, message: tags.joined(separator: ", "),
                    undo: UndoInfo(kind: .restoreTags, originalPath: source.path, currentPath: source.path, previousTags: previous))

            case .setColor(let label):
                let previous = FileTagging.colorLabel(of: source)
                guard previous != label else {
                    log(.skipped, message: "Color already \(label.name)")
                    return .next
                }
                try FileTagging.setColorLabel(label, on: source)
                current.colorLabel = label
                log(.done, message: label.name,
                    undo: UndoInfo(kind: .restoreColor, originalPath: source.path, currentPath: source.path, previousColor: previous.rawValue))

            case .trash:
                let trashed = try trash.trash(source)
                log(.done, target: trashed, undo: UndoInfo(kind: .moveBack, originalPath: source.path, currentPath: trashed.path))
                outcome.finalURL = nil
                return .stopAll

            case .open:
                try opener.open(source)
                log(.done)

            case .archive(_, let policy):
                guard let planned = engine.step(for: action, facts: current).target else { return .next }
                try guardrail.check(planned)
                try FileManager.default.createDirectory(at: planned.deletingLastPathComponent(), withIntermediateDirectories: true)
                switch try resolve(planned, policy: policy, rule: rule) {
                case .skip(let reason):
                    log(.skipped, target: planned, message: reason)
                    return .stopRule
                case .use(let target, let displaced):
                    try Archiver.zip(source, to: target)
                    outcome.producedPaths.append(target)
                    log(.done, target: target, undo: UndoInfo(kind: .trashCopy, originalPath: source.path,
                                                              currentPath: target.path, displacedTrashPath: displaced?.path))
                }

            case .extract(_, let policy):
                guard let planned = engine.step(for: action, facts: current).target else { return .next }
                guard Archiver.canExtract(source) else {
                    log(.skipped, message: "Only .zip and .tar archives can be extracted with what macOS has built in")
                    return .next
                }
                try guardrail.check(planned)
                try FileManager.default.createDirectory(at: planned.deletingLastPathComponent(), withIntermediateDirectories: true)
                switch try resolve(planned, policy: policy, rule: rule) {
                case .skip(let reason):
                    log(.skipped, target: planned, message: reason)
                    return .stopRule
                case .use(let target, let displaced):
                    try Archiver.extract(source, into: target)
                    outcome.producedPaths.append(target)
                    log(.done, target: target, undo: UndoInfo(kind: .trashCopy, originalPath: source.path,
                                                              currentPath: target.path, displacedTrashPath: displaced?.path))
                }

            case .makeAlias:
                guard let planned = engine.step(for: action, facts: current).target else { return .next }
                try guardrail.check(planned)
                try FileManager.default.createDirectory(at: planned.deletingLastPathComponent(), withIntermediateDirectories: true)
                switch try resolve(planned, policy: .rename, rule: rule) {
                case .skip(let reason):
                    log(.skipped, target: planned, message: reason)
                    return .stopRule
                case .use(let target, _):
                    let bookmark = try source.bookmarkData(options: .suitableForBookmarkFile,
                                                           includingResourceValuesForKeys: nil, relativeTo: nil)
                    try URL.writeBookmarkData(bookmark, to: target)
                    outcome.producedPaths.append(target)
                    log(.done, target: target, undo: UndoInfo(kind: .trashCopy, originalPath: source.path, currentPath: target.path))
                }

            case .runShortcut(let name):
                guard allowShortcuts else {
                    log(.skipped, message: "Running Shortcuts is turned off in Settings")
                    return .next
                }
                let output = try ShortcutRunner.run(name, file: source)
                log(.done, message: output.isEmpty ? "Shortcut \u{201C}\(name)\u{201D}" : output)

            case .shell(let script):
                guard allowShellScripts else {
                    log(.skipped, message: "Shell scripts are turned off in General settings")
                    return .next
                }
                let output = try ShellRunner.run(script, file: source)
                log(.done, message: output)
            }
        } catch {
            log(.failed, message: ExecutionError.plainWords(error))
            return .stopAll
        }
        return .next
    }

    private func resolve(_ target: URL, policy: ConflictPolicy, rule: Rule) throws -> Resolution {
        guard FileManager.default.fileExists(atPath: target.path) else { return .use(target, displaced: nil) }
        switch policy {
        case .skip:
            return .skip("\(target.lastPathComponent) already exists")
        case .rename:
            let folder = target.deletingLastPathComponent()
            for counter in 2...10_000 {
                let candidate = folder.appendingPathComponent(PathTools.numbered(target.lastPathComponent, counter))
                if !FileManager.default.fileExists(atPath: candidate.path) { return .use(candidate, displaced: nil) }
            }
            return .skip("No free name for \(target.lastPathComponent)")
        case .overwrite:
            guard rule.allowOverwrite else {
                return .skip("\(target.lastPathComponent) exists and overwriting is not confirmed in this rule")
            }
            try guardrail.check(target)
            let displaced = try trash.trash(target)
            return .use(target, displaced: displaced)
        case .renameExisting:
            // The file already there steps aside to "name 2.ext"; undo moves it back.
            try guardrail.check(target)
            let folder = target.deletingLastPathComponent()
            for counter in 2...10_000 {
                let aside = folder.appendingPathComponent(PathTools.numbered(target.lastPathComponent, counter))
                if !FileManager.default.fileExists(atPath: aside.path) {
                    try FileManager.default.moveItem(at: target, to: aside)
                    return .use(target, displaced: aside)
                }
            }
            return .skip("No free name to move the existing \(target.lastPathComponent) aside")
        }
    }

    private func firstFreeCounterName(_ action: Action, facts: FileFacts) -> Resolution {
        for counter in 1...10_000 {
            guard let candidate = engine.step(for: action, facts: facts, counter: counter).target else { break }
            if !FileManager.default.fileExists(atPath: candidate.path) || isSameItem(candidate, facts.url) {
                return .use(candidate, displaced: nil)
            }
        }
        return .skip("No free name for \(facts.fileName)")
    }

    /// True when both URLs point at the same file (also catches case-only renames on case-insensitive disks).
    private func isSameItem(_ first: URL, _ second: URL) -> Bool {
        if PathTools.canonical(first) == PathTools.canonical(second) { return true }
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let a = try? first.resourceValues(forKeys: key).fileResourceIdentifier,
              let b = try? second.resourceValues(forKeys: key).fileResourceIdentifier else { return false }
        return a.isEqual(b)
    }
}

public enum FileTagging {
    /// Reads from a fresh URL: URL objects cache resource values, which would hide changes.
    private static func uncached(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path)
    }

    public static func tags(of url: URL) -> [String] {
        (try? uncached(url).resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
    }

    public static func setTags(_ tags: [String], on url: URL) throws {
        try (uncached(url) as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
    }

    public static func colorLabel(of url: URL) -> ColorLabel {
        ColorLabel(rawValue: (try? uncached(url).resourceValues(forKeys: [.labelNumberKey]).labelNumber) ?? 0) ?? .none
    }

    public static func setColorLabel(_ label: ColorLabel, on url: URL) throws {
        try (uncached(url) as NSURL).setResourceValue(label.rawValue, forKey: .labelNumberKey)
    }
}

public enum ShellRunner {
    /// Runs `script` with zsh; the file path is in `$TIDYUP_FILE`. Gives up after `timeout` seconds.
    public static func run(_ script: String, file: URL, timeout: TimeInterval = 60) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        var environment = ProcessInfo.processInfo.environment
        environment["TIDYUP_FILE"] = file.path
        process.environment = environment
        process.currentDirectoryURL = file.deletingLastPathComponent()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else { throw ExecutionError.shellFailed(process.terminationStatus, output) }
        return String(output.prefix(500))
    }
}

public enum Archiver {
    /// Zips a file or folder the way Finder's "Compress" does (keeps the top folder and macOS metadata).
    public static func zip(_ source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, destination.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw ExecutionError.archiveFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

extension Archiver {
    /// .zip and .tar (plain, .gz, .bz2, .xz) can be unpacked with tools every Mac has; .7z and .rar can't.
    public static func canExtract(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return PathTools.extractableExtensions.contains { name.hasSuffix($0) }
    }

    /// Unpacks into `folder` (created here), so the archive's contents never spill into the folder around it.
    public static func extract(_ archive: URL, into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let isZip = archive.pathExtension.lowercased() == "zip"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: isZip ? "/usr/bin/ditto" : "/usr/bin/tar")
        process.arguments = isZip ? ["-x", "-k", archive.path, folder.path] : ["-xf", archive.path, "-C", folder.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw ExecutionError.extractFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

public enum ShortcutRunner {
    /// Runs a Shortcut from the Shortcuts app with the file as input. Gives up after `timeout` seconds.
    public static func run(_ name: String, file: URL, timeout: TimeInterval = 120) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name, "--input-path", file.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else { throw ExecutionError.shortcutFailed(process.terminationStatus, output) }
        return String(output.prefix(500))
    }
}

extension ExecutionError {
    /// A short, readable reason for the activity log instead of a raw system error dump.
    public static func plainWords(_ error: Error) -> String {
        let system = error as NSError
        guard system.domain == NSCocoaErrorDomain || system.domain == NSPOSIXErrorDomain else { return String(describing: error) }
        var text = system.localizedDescription
        let posix = (system.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap { $0.domain == NSPOSIXErrorDomain ? $0.code : nil }
            ?? (system.domain == NSPOSIXErrorDomain ? system.code : nil)
        switch posix.map(Int32.init) {
        case EINVAL?: text += " (a folder can't go inside itself)"
        case EACCES?, EPERM?: text += " (macOS didn't allow it — check permissions or Full Disk Access)"
        case ENOSPC?: text += " (the disk is full)"
        case ENOENT?: text += " (it's no longer there)"
        default: break
        }
        return text
    }
}
