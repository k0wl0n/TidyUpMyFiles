import Foundation

/// What will happen when a step's destination name is already taken.
public enum PreviewConflict: Equatable, Sendable {
    case none
    /// Taken (on disk or by another waiting item): it will get this numbered name instead.
    case numbered(String)
    /// Taken and the rule says skip: the item stays where it is.
    case skipped
    /// Taken and the rule allows replacing: the existing file goes to the Trash first.
    case replaces
    /// Taken, the rule asks to replace but hasn't allowed it: the item stays where it is.
    case blocked
    /// Taken: the file already there is renamed to this, and the item takes the name.
    case movesExistingAside(String)

    public var stopsItem: Bool { self == .skipped || self == .blocked }
}

/// One action of a waiting item, with its predicted outcome.
public struct StepPreview: Identifiable, Equatable, Sendable {
    public var index: Int
    public var action: Action
    public var from: URL
    /// Where the rule asks for (before the name check).
    public var plannedTo: URL?
    /// Where it will really end up; nil when it is skipped or goes to the Trash.
    public var finalTo: URL?
    public var conflict: PreviewConflict
    public var createsFolder: Bool

    public var id: Int { index }
    public var verb: String { action.verb }
    public var movesItem: Bool { verb == "move" || verb == "rename" }
}

/// Everything the Preview screen shows about one waiting item.
public struct PreviewDetail: Identifiable, Equatable, Sendable {
    public var item: PreviewItem
    public var size: Int64?
    public var kind: FileKind
    public var added: Date?
    public var modified: Date?
    public var steps: [StepPreview]

    public var id: String { item.id }

    /// The step that decides where the item goes (move, copy, rename, zip or Trash).
    public var mainStep: StepPreview? {
        steps.first { ["move", "copy", "archive", "extract", "alias", "trash"].contains($0.verb) } ?? steps.first { $0.verb == "rename" } ?? steps.first
    }

    public var goesToTrash: Bool { steps.contains { $0.verb == "trash" } }

    /// Where the item itself will be afterwards; nil when it goes to the Trash or a step is skipped.
    public var finalLocation: URL? {
        if goesToTrash || steps.contains(where: { $0.conflict.stopsItem }) { return nil }
        return steps.last(where: \.movesItem)?.finalTo ?? item.file
    }

    public var nameChanges: Bool {
        guard let final = finalLocation else { return false }
        return final.lastPathComponent != item.file.lastPathComponent
    }

    public var hasConflict: Bool { steps.contains { $0.conflict != .none } }
    public var createsFolder: Bool { steps.contains { $0.createsFolder } }
    public var isBlocked: Bool { steps.contains { $0.conflict.stopsItem } }

    /// The folder the main step sends the item to, for grouping.
    public var destinationFolder: URL? {
        guard let step = mainStep, step.verb != "trash" else { return nil }
        return (step.finalTo ?? step.plannedTo)?.deletingLastPathComponent()
    }
}

/// Predicts the outcome of waiting items in order, as running them all would: earlier items claim names
/// that later items then can't use. Reads the disk but changes nothing.
public enum PreviewInspector {
    public static func inspect(_ items: [PreviewItem]) -> [PreviewDetail] {
        var claimed = Set<String>()
        var claimedFolders = Set<String>()
        return items.map { inspect($0, claimed: &claimed, claimedFolders: &claimedFolders) }
    }

    private static func key(_ url: URL) -> String {
        PathTools.canonical(url).lowercased()
    }

    private static func inspect(_ item: PreviewItem, claimed: inout Set<String>, claimedFolders: inout Set<String>) -> PreviewDetail {
        let values = try? item.file.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .addedToDirectoryDateKey,
                                                             .contentModificationDateKey])
        var current = item.file
        var steps: [StepPreview] = []
        var stopped = false
        for (index, step) in item.steps.enumerated() where !stopped {
            var preview = StepPreview(index: index, action: step.action, from: current, plannedTo: nil, finalTo: nil,
                                      conflict: .none, createsFolder: false)
            switch step.action {
            case .move, .copy, .rename, .archive, .extract, .makeAlias:
                guard let target = step.target else { break }
                let folder = target.deletingLastPathComponent()
                let name: String
                switch step.action {
                case .rename: name = target.lastPathComponent
                case .archive: name = current.lastPathComponent + ".zip"
                case .extract: name = PathTools.archiveBaseName(current.lastPathComponent)
                case .makeAlias: name = current.lastPathComponent + " alias"
                default: name = current.lastPathComponent
                }
                let planned = folder.appendingPathComponent(name)
                preview.plannedTo = planned
                preview.createsFolder = !FileManager.default.fileExists(atPath: folder.path) && !claimedFolders.contains(key(folder))
                let taken = (FileManager.default.fileExists(atPath: planned.path) && key(planned) != key(current))
                    || claimed.contains(key(planned))
                var final: URL? = planned
                if taken {
                    switch step.action.conflictPolicy ?? .rename {
                    case .rename:
                        final = freeName(for: planned, claimed: claimed)
                        preview.conflict = .numbered(final?.lastPathComponent ?? name)
                    case .skip:
                        final = nil
                        preview.conflict = .skipped
                    case .overwrite:
                        if item.allowOverwrite {
                            preview.conflict = .replaces
                        } else {
                            final = nil
                            preview.conflict = .blocked
                        }
                    case .renameExisting:
                        if let aside = freeName(for: planned, claimed: claimed) {
                            claimed.insert(key(aside))
                            preview.conflict = .movesExistingAside(aside.lastPathComponent)
                        }
                    }
                }
                preview.finalTo = final
                if let final {
                    claimed.insert(key(final))
                    claimedFolders.insert(key(folder))
                    if preview.movesItem { current = final }
                } else {
                    stopped = true
                }
            case .trash:
                stopped = true
            default:
                break
            }
            steps.append(preview)
        }
        return PreviewDetail(item: item,
                             size: (values?.isDirectory ?? false) ? nil : values?.fileSize.map(Int64.init),
                             kind: FileKind.classify(fileName: item.file.lastPathComponent, isDirectory: values?.isDirectory ?? false),
                             added: values?.addedToDirectoryDate, modified: values?.contentModificationDate, steps: steps)
    }

    private static func freeName(for url: URL, claimed: Set<String>) -> URL? {
        let folder = url.deletingLastPathComponent()
        for counter in 2...10_000 {
            let candidate = folder.appendingPathComponent(PathTools.numbered(url.lastPathComponent, counter))
            if !FileManager.default.fileExists(atPath: candidate.path) && !claimed.contains(key(candidate)) { return candidate }
        }
        return nil
    }
}
