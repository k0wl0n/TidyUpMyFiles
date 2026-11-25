import Foundation
import SQLite3

public enum ActivityStatus: String, Codable, CaseIterable, Sendable {
    case done, skipped, failed, undone
}

/// What is needed to reverse one step.
public struct UndoInfo: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Move `currentPath` back to `originalPath` (move, rename, trash).
        case moveBack
        /// Send the copy at `currentPath` to the Trash.
        case trashCopy
        case restoreTags
        case restoreColor
    }

    public var kind: Kind
    public var originalPath: String
    public var currentPath: String
    public var previousTags: [String]?
    public var previousColor: Int?
    /// A file that `overwrite` displaced: it went to the Trash here and returns to `currentPath` on undo.
    public var displacedTrashPath: String?

    public init(kind: Kind, originalPath: String, currentPath: String, previousTags: [String]? = nil,
                previousColor: Int? = nil, displacedTrashPath: String? = nil) {
        self.kind = kind
        self.originalPath = originalPath
        self.currentPath = currentPath
        self.previousTags = previousTags
        self.previousColor = previousColor
        self.displacedTrashPath = displacedTrashPath
    }
}

public struct ActivityRecord: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var batchID: Int64
    public var timestamp: Date
    public var ruleName: String
    public var action: String
    public var status: ActivityStatus
    public var sourcePath: String
    public var targetPath: String?
    public var message: String
    public var undo: UndoInfo?

    public init(id: Int64 = 0, batchID: Int64, timestamp: Date = Date(), ruleName: String, action: String,
                status: ActivityStatus, sourcePath: String, targetPath: String? = nil, message: String = "", undo: UndoInfo? = nil) {
        self.id = id
        self.batchID = batchID
        self.timestamp = timestamp
        self.ruleName = ruleName
        self.action = action
        self.status = status
        self.sourcePath = sourcePath
        self.targetPath = targetPath
        self.message = message
        self.undo = undo
    }

    public var canUndo: Bool { status == .done && undo != nil }
}

public struct ActivityQuery: Sendable {
    public var search: String
    public var status: ActivityStatus?
    public var action: String?
    public var since: Date?
    public var limit: Int

    public init(search: String = "", status: ActivityStatus? = nil, action: String? = nil, since: Date? = nil, limit: Int = 500) {
        self.search = search
        self.status = status
        self.action = action
        self.since = since
        self.limit = limit
    }
}

public enum ActivityStoreError: Error, CustomStringConvertible {
    case sqlite(String)
    public var description: String {
        switch self {
        case .sqlite(let message): return "Activity database: \(message)"
        }
    }
}

/// Activity log and undo data in SQLite. All access is serialized through a lock.
public final class ActivityStore: @unchecked Sendable {
    private var database: OpaquePointer?
    private let lock = NSLock()
    private let logFile: ActivityLogFile?
    private var batchTriggers: [Int64: String] = [:]
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// With `logDirectory`, every step is also written to a readable monthly text log there.
    public init(fileURL: URL, logDirectory: URL? = nil) throws {
        logFile = logDirectory.map { ActivityLogFile(directory: $0) }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(fileURL.path, &database) == SQLITE_OK else {
            throw ActivityStoreError.sqlite("cannot open \(fileURL.path)")
        }
        try execute("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS batches (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                started_at REAL NOT NULL,
                trigger TEXT NOT NULL,
                folder TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS activities (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                batch_id INTEGER NOT NULL REFERENCES batches(id),
                timestamp REAL NOT NULL,
                rule_name TEXT NOT NULL,
                action TEXT NOT NULL,
                status TEXT NOT NULL,
                source_path TEXT NOT NULL,
                target_path TEXT,
                message TEXT NOT NULL DEFAULT '',
                undo_json TEXT
            );
            CREATE INDEX IF NOT EXISTS activities_timestamp ON activities(timestamp);
            CREATE INDEX IF NOT EXISTS activities_batch ON activities(batch_id);
            """)
    }

    deinit {
        sqlite3_close(database)
    }

    // MARK: Writing

    public func beginBatch(trigger: String, folder: String, at date: Date = Date()) throws -> Int64 {
        try locked {
            try run("INSERT INTO batches (started_at, trigger, folder) VALUES (?, ?, ?)",
                    [.real(date.timeIntervalSince1970), .text(trigger), .text(folder)])
            let id = sqlite3_last_insert_rowid(database)
            batchTriggers[id] = trigger
            return id
        }
    }

    @discardableResult
    public func append(_ record: ActivityRecord) throws -> ActivityRecord {
        try locked {
            let undoJSON = try record.undo.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
            try run("""
                INSERT INTO activities (batch_id, timestamp, rule_name, action, status, source_path, target_path, message, undo_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [.integer(record.batchID), .real(record.timestamp.timeIntervalSince1970), .text(record.ruleName),
                      .text(record.action), .text(record.status.rawValue), .text(record.sourcePath),
                      record.targetPath.map(Value.text) ?? .null, .text(record.message), undoJSON.map(Value.text) ?? .null])
            var stored = record
            stored.id = sqlite3_last_insert_rowid(database)
            logFile?.write(stored, trigger: batchTriggers[record.batchID])
            return stored
        }
    }

    public func setStatus(_ status: ActivityStatus, for id: Int64, message: String? = nil) throws {
        try locked {
            if let message {
                try run("UPDATE activities SET status = ?, message = ? WHERE id = ?", [.text(status.rawValue), .text(message), .integer(id)])
            } else {
                try run("UPDATE activities SET status = ? WHERE id = ?", [.text(status.rawValue), .integer(id)])
            }
        }
        if status == .undone, let record = try? select("SELECT * FROM activities WHERE id = ?", [.integer(id)]).first {
            logFile?.write(record, trigger: "undo")
        }
    }

    public var logDirectory: URL? { logFile?.directory }

    /// One summary per run (newest first): when, what started it, and how many steps of each kind.
    public func runs(limit: Int = 200) throws -> [RunSummary] {
        try locked {
            let sql = "SELECT b.id, b.started_at, b.trigger, b.folder, a.status, a.action, COUNT(*) "
                + "FROM batches b JOIN activities a ON a.batch_id = b.id "
                + "WHERE b.id IN (SELECT DISTINCT batch_id FROM activities ORDER BY batch_id DESC LIMIT ?) "
                + "GROUP BY b.id, a.status, a.action ORDER BY b.id DESC"
            let statement = try prepare(sql, [.integer(Int64(limit))])
            defer { sqlite3_finalize(statement) }
            var order: [Int64] = []
            var runs: [Int64: RunSummary] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                if runs[id] == nil {
                    order.append(id)
                    runs[id] = RunSummary(id: id, startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                                          trigger: text(statement, 2) ?? "", folder: text(statement, 3) ?? "")
                }
                let status = ActivityStatus(rawValue: text(statement, 4) ?? "") ?? .failed
                let action = text(statement, 5) ?? ""
                let count = Int(sqlite3_column_int64(statement, 6))
                runs[id]?.statusCounts[status, default: 0] += count
                if status == .done || status == .undone { runs[id]?.actionCounts[action, default: 0] += count }
            }
            return order.compactMap { runs[$0] }
        }
    }

    // MARK: Reading

    public func records(_ query: ActivityQuery = ActivityQuery()) throws -> [ActivityRecord] {
        var clauses: [String] = []
        var values: [Value] = []
        if !query.search.isEmpty {
            clauses.append("(source_path LIKE ? OR IFNULL(target_path, '') LIKE ? OR rule_name LIKE ? OR message LIKE ?)")
            let pattern = "%\(query.search)%"
            values += Array(repeating: .text(pattern), count: 4)
        }
        if let status = query.status { clauses.append("status = ?"); values.append(.text(status.rawValue)) }
        if let action = query.action { clauses.append("action = ?"); values.append(.text(action)) }
        if let since = query.since { clauses.append("timestamp >= ?"); values.append(.real(since.timeIntervalSince1970)) }
        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        values.append(.integer(Int64(query.limit)))
        return try select("SELECT * FROM activities \(whereClause) ORDER BY id DESC LIMIT ?", values)
    }

    public func records(inBatch batchID: Int64) throws -> [ActivityRecord] {
        try select("SELECT * FROM activities WHERE batch_id = ? ORDER BY id DESC", [.integer(batchID)])
    }

    public func lastUndoable() throws -> ActivityRecord? {
        try select("SELECT * FROM activities WHERE status = 'done' AND undo_json IS NOT NULL ORDER BY id DESC LIMIT 1", []).first
    }

    /// The most recent batch that still has something to undo.
    public func lastUndoableBatch() throws -> Int64? {
        try lastUndoable()?.batchID
    }

    /// Files tidied (moved, copied, renamed or trashed) since the start of today.
    public func tidiedCount(since: Date) throws -> Int {
        try locked {
            let statement = try prepare("""
                SELECT COUNT(DISTINCT source_path) FROM activities
                WHERE status = 'done' AND action IN ('move', 'copy', 'rename', 'trash') AND timestamp >= ?
                """, [.real(since.timeIntervalSince1970)])
            defer { sqlite3_finalize(statement) }
            return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
        }
    }

    // MARK: SQLite plumbing

    private enum Value {
        case integer(Int64), real(Double), text(String), null
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func errorMessage() -> String {
        String(cString: sqlite3_errmsg(database))
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw ActivityStoreError.sqlite(errorMessage()) }
    }

    private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ActivityStoreError.sqlite(errorMessage())
        }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .integer(let number): sqlite3_bind_int64(statement, index, number)
            case .real(let number): sqlite3_bind_double(statement, index, number)
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, ActivityStore.transient)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private func run(_ sql: String, _ values: [Value]) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ActivityStoreError.sqlite(errorMessage()) }
    }

    private func select(_ sql: String, _ values: [Value]) throws -> [ActivityRecord] {
        try locked {
            let statement = try prepare(sql, values)
            defer { sqlite3_finalize(statement) }
            var rows: [ActivityRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                rows.append(row(statement))
            }
            return rows
        }
    }

    private func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    private func row(_ statement: OpaquePointer?) -> ActivityRecord {
        let undo = text(statement, 9).flatMap { try? JSONDecoder().decode(UndoInfo.self, from: Data($0.utf8)) }
        return ActivityRecord(
            id: sqlite3_column_int64(statement, 0),
            batchID: sqlite3_column_int64(statement, 1),
            timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
            ruleName: text(statement, 3) ?? "",
            action: text(statement, 4) ?? "",
            status: ActivityStatus(rawValue: text(statement, 5) ?? "") ?? .failed,
            sourcePath: text(statement, 6) ?? "",
            targetPath: text(statement, 7),
            message: text(statement, 8) ?? "",
            undo: undo
        )
    }
}
