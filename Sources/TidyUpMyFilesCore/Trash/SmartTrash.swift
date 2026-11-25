import Foundation

public struct TrashItem: Identifiable, Equatable, Sendable {
    public var url: URL
    /// When it went to the Trash (the date it was added to the Trash folder).
    public var trashedAt: Date
    public var size: Int64

    public init(url: URL, trashedAt: Date, size: Int64) {
        self.url = url
        self.trashedAt = trashedAt
        self.size = size
    }

    public var id: String { url.path }
}

public struct SmartTrashPlan: Equatable, Sendable {
    public var items: [TrashItem]
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// Empties old items from the Trash. This is the one place TidyUpMyFiles deletes for good, so it is off by default
/// and the app shows a summary that has to be confirmed before it runs on its own.
public struct SmartTrash: Sendable {
    public var trashFolder: URL

    public init(trashFolder: URL = URL(fileURLWithPath: PathTools.homeDirectory).appendingPathComponent(".Trash")) {
        self.trashFolder = trashFolder
    }

    /// Reading ~/.Trash needs Full Disk Access on recent macOS; the error says so.
    public func scan() throws -> [TrashItem] {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey, .isDirectoryKey, .totalFileAllocatedSizeKey]
        let contents = try FileManager.default.contentsOfDirectory(at: trashFolder, includingPropertiesForKeys: keys,
                                                                   options: [.skipsHiddenFiles])
        return contents.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let date = values?.addedToDirectoryDate ?? values?.contentModificationDate ?? Date()
            let size = (values?.isDirectory ?? false) ? SmartTrash.folderSize(url) : Int64(values?.totalFileAllocatedSize ?? 0)
            return TrashItem(url: url, trashedAt: date, size: size)
        }
    }

    /// Items older than the limit go; then, if a size cap is set, the oldest remaining items go until the Trash fits.
    public static func plan(_ items: [TrashItem], settings: SmartTrashSettings, now: Date = Date()) -> SmartTrashPlan {
        let cutoff = now.addingTimeInterval(-settings.olderThanDays * 86_400)
        var remove = items.filter { $0.trashedAt < cutoff }
        if let maxSizeGB = settings.maxSizeGB {
            let limit = Int64(maxSizeGB * 1e9)
            let removedIDs = Set(remove.map(\.id))
            var kept = items.filter { !removedIDs.contains($0.id) }.sorted { $0.trashedAt < $1.trashedAt }
            var keptBytes = kept.reduce(0) { $0 + $1.size }
            while keptBytes > limit, !kept.isEmpty {
                let oldest = kept.removeFirst()
                keptBytes -= oldest.size
                remove.append(oldest)
            }
        }
        return SmartTrashPlan(items: remove.sorted { $0.trashedAt < $1.trashedAt })
    }

    /// Deletes the planned items, but only ones that really sit directly in this Trash folder.
    public func empty(_ plan: SmartTrashPlan) -> (removed: [TrashItem], failures: [(TrashItem, Error)]) {
        let trashPath = PathTools.canonical(trashFolder)
        var removed: [TrashItem] = []
        var failures: [(TrashItem, Error)] = []
        for item in plan.items {
            guard PathTools.canonical(item.url.deletingLastPathComponent()) == trashPath else { continue }
            do {
                try FileManager.default.removeItem(at: item.url)
                removed.append(item)
            } catch {
                failures.append((item, error))
            }
        }
        return (removed, failures)
    }

    private static func folderSize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            total += Int64((try? child.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}
