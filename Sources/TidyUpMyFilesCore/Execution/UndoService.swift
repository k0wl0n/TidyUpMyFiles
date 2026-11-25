import Foundation

public enum UndoError: Error, CustomStringConvertible {
    case nothingToUndo
    case fileMissing(String)

    public var description: String {
        switch self {
        case .nothingToUndo: return "Nothing to undo"
        case .fileMissing(let path): return "The file is no longer at \(PathTools.abbreviate(path))"
        }
    }
}

/// Reverses logged steps: moves and renames go back, trashed files come out of the Trash,
/// copies go to the Trash, tags and colors are restored. Never overwrites: a taken name gets a number.
public struct UndoService: Sendable {
    public var store: ActivityStore
    public var trash: any TrashProvider

    public init(store: ActivityStore, trash: any TrashProvider = SystemTrash()) {
        self.store = store
        self.trash = trash
    }

    public func undo(_ record: ActivityRecord) throws {
        guard record.canUndo, let info = record.undo else { throw UndoError.nothingToUndo }
        let fileManager = FileManager.default
        let current = URL(fileURLWithPath: info.currentPath)
        let original = URL(fileURLWithPath: info.originalPath)

        switch info.kind {
        case .moveBack:
            guard fileManager.fileExists(atPath: current.path) else { throw UndoError.fileMissing(current.path) }
            try fileManager.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            let destination = freeLocation(for: original)
            try fileManager.moveItem(at: current, to: destination)
            try restoreDisplaced(info)
            try store.setStatus(.undone, for: record.id,
                                message: destination == original ? nil : "Restored as \(destination.lastPathComponent)")
        case .trashCopy:
            if fileManager.fileExists(atPath: current.path) {
                _ = try trash.trash(current)
            }
            try restoreDisplaced(info)
            try store.setStatus(.undone, for: record.id)
        case .restoreTags:
            guard fileManager.fileExists(atPath: current.path) else { throw UndoError.fileMissing(current.path) }
            try FileTagging.setTags(info.previousTags ?? [], on: current)
            try store.setStatus(.undone, for: record.id)
        case .restoreColor:
            guard fileManager.fileExists(atPath: current.path) else { throw UndoError.fileMissing(current.path) }
            try FileTagging.setColorLabel(ColorLabel(rawValue: info.previousColor ?? 0) ?? .none, on: current)
            try store.setStatus(.undone, for: record.id)
        }
    }

    @discardableResult
    public func undoLast() throws -> ActivityRecord {
        guard let record = try store.lastUndoable() else { throw UndoError.nothingToUndo }
        try undo(record)
        return record
    }

    /// Undoes every step of a batch, newest first. Returns the steps that could not be undone.
    @discardableResult
    public func undoBatch(_ batchID: Int64) throws -> [(ActivityRecord, Error)] {
        var failures: [(ActivityRecord, Error)] = []
        for record in try store.records(inBatch: batchID) where record.canUndo {
            do {
                try undo(record)
            } catch {
                failures.append((record, error))
            }
        }
        return failures
    }

    /// A file that `overwrite` pushed to the Trash comes back to where it was.
    private func restoreDisplaced(_ info: UndoInfo) throws {
        guard let displacedPath = info.displacedTrashPath else { return }
        let displaced = URL(fileURLWithPath: displacedPath)
        guard FileManager.default.fileExists(atPath: displaced.path) else { return }
        let home = freeLocation(for: URL(fileURLWithPath: info.currentPath))
        try FileManager.default.moveItem(at: displaced, to: home)
    }

    private func freeLocation(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let folder = url.deletingLastPathComponent()
        for counter in 2...10_000 {
            let candidate = folder.appendingPathComponent(PathTools.numbered(url.lastPathComponent, counter))
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }
}
