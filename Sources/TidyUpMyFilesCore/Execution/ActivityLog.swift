import Foundation

/// One run (batch) of steps, summarised for the Activity screen and the run report.
public struct RunSummary: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var startedAt: Date
    public var trigger: String
    public var folder: String
    public var statusCounts: [ActivityStatus: Int] = [:]
    /// Steps carried out (including ones undone later), by action.
    public var actionCounts: [String: Int] = [:]

    public init(id: Int64, startedAt: Date, trigger: String, folder: String) {
        self.id = id
        self.startedAt = startedAt
        self.trigger = trigger
        self.folder = folder
    }

    public var total: Int { statusCounts.values.reduce(0, +) }
    public func count(_ status: ActivityStatus) -> Int { statusCounts[status] ?? 0 }
    public var canUndo: Bool { count(.done) > 0 }
}

/// Appends one readable line per step to a monthly file, e.g. `activity-2026-11.log`:
///
///     2026-11-24 13:05:12  DONE     MOVE         ~/Downloads/a.pdf → ~/Documents/PDF/a.pdf  · PDF files · run 12 (run now)
public final class ActivityLogFile: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()
    private let timeFormatter = ActivityLogFile.formatter("yyyy-MM-dd HH:mm:ss")
    private let monthFormatter = ActivityLogFile.formatter("yyyy-MM")

    public init(directory: URL) {
        self.directory = directory
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    public func fileURL(for date: Date = Date()) -> URL {
        directory.appendingPathComponent("activity-\(monthFormatter.string(from: date)).log")
    }

    public static func line(for record: ActivityRecord, trigger: String?, time: String) -> String {
        func pad(_ text: String, _ width: Int) -> String {
            text.count >= width ? text + " " : text.padding(toLength: width, withPad: " ", startingAt: 0)
        }
        let status = record.status.rawValue.uppercased()
        var line = "\(time)  \(pad(status, 8)) \(pad(record.action.uppercased(), 12)) \(PathTools.abbreviate(record.sourcePath))"
        if let target = record.targetPath { line += " → \(PathTools.abbreviate(target))" }
        if !record.message.isEmpty && record.status != .done { line += "  (\(record.message))" }
        line += "  · \(record.ruleName) · run \(record.batchID)"
        if let trigger, !trigger.isEmpty { line += " (\(trigger))" }
        return line
    }

    public func write(_ record: ActivityRecord, trigger: String?) {
        let now = Date()
        let text = ActivityLogFile.line(for: record, trigger: trigger, time: timeFormatter.string(from: now)) + "\n"
        lock.withLock {
            let url = fileURL(for: now)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try Data().write(to: url)
                }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(text.utf8))
            } catch {
                // The database stays the record of truth; a log file that can't be written is skipped.
            }
        }
    }
}

extension ActivityStore {
    /// Records as CSV (time, run, status, action, rule, from, to, message) for spreadsheets.
    public static func csv(_ records: [ActivityRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        func field(_ value: String) -> String {
            guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var lines = ["time,run,status,action,rule,from,to,message"]
        for record in records {
            let fields = [formatter.string(from: record.timestamp), String(record.batchID), record.status.rawValue, record.action,
                          record.ruleName, record.sourcePath, record.targetPath ?? "", record.message]
            lines.append(fields.map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
