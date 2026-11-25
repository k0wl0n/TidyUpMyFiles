import AppKit
import TidyUpMyFilesCore
import UserNotifications

/// What a finished run did, in words: shown as a card, in a notification, and linked to Activity.
struct RunReport: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let finishedAt = Date()
    let cancelled: Bool
    let batchIDs: [Int64]
    let done: [ActivityRecord]
    let skipped: Int
    let failed: Int

    /// Nil when nothing was carried out, skipped or failed (nothing worth reporting).
    init?(results: [ProcessResult], title: String, cancelled: Bool) {
        let records = results.flatMap(\.records)
        guard !records.isEmpty else { return nil }
        self.title = title
        self.cancelled = cancelled
        batchIDs = results.compactMap(\.batchID)
        done = records.filter { $0.status == .done }
        skipped = records.filter { $0.status == .skipped }.count
        failed = records.filter { $0.status == .failed }.count
    }

    /// "12 moved · 1 to Trash · 2 renamed"
    var summary: String {
        var counts: [String: Int] = [:]
        for record in done { counts[record.action, default: 0] += 1 }
        var parts = ["move", "copy", "rename", "archive", "extract", "alias", "trash", "add_tags", "remove_tags", "set_color",
                     "open", "shortcut", "shell"]
            .compactMap { action -> String? in
                guard let count = counts[action] else { return nil }
                return "\(count) \(RunReport.pastTense(action))"
            }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.isEmpty ? "Nothing changed" : parts.joined(separator: " · ")
    }

    /// The first few moves, as "a.pdf → ~/Documents/PDF".
    var examples: [String] {
        done.prefix(3).map { record in
            let name = URL(fileURLWithPath: record.sourcePath).lastPathComponent
            guard let target = record.targetPath else { return "\(name) → \(RunReport.pastTense(record.action))" }
            return "\(name) → \(PathTools.abbreviate(URL(fileURLWithPath: target).deletingLastPathComponent().path))"
        }
    }

    static func pastTense(_ action: String) -> String {
        switch action {
        case "move": return "moved"
        case "copy": return "copied"
        case "rename": return "renamed"
        case "archive": return "zipped"
        case "extract": return "extracted"
        case "alias": return "aliased"
        case "shortcut": return "Shortcuts run"
        case "trash": return "to Trash"
        case "add_tags", "remove_tags": return "tagged"
        case "set_color": return "labelled"
        case "open": return "opened"
        case "shell": return "scripts run"
        case "empty_trash": return "removed from Trash"
        default: return action
        }
    }
}

/// macOS notifications for background runs, with Undo and Show buttons. Only when running as the app bundle.
@MainActor
enum Notifier {
    static let category = "TIDY_RUN"
    static let undoAction = "UNDO"
    static let showAction = "SHOW"
    private static var authorized: Bool?
    private static let handler = NotificationHandler()

    /// Registers the buttons and who answers them. Call once at launch.
    static func setUp() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = handler
        let undo = UNNotificationAction(identifier: undoAction, title: "Undo", options: [])
        let show = UNNotificationAction(identifier: showAction, title: "Show", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: category, actions: [undo, show], intentIdentifiers: [])])
    }

    static func post(_ report: RunReport) {
        guard Bundle.main.bundleIdentifier != nil, !report.done.isEmpty else { return }
        let title = "TidyUpMyFiles: \(report.summary)"
        let body = report.examples.joined(separator: "\n") + (report.done.count > 3 ? "\n…and \(report.done.count - 3) more" : "")
        let identifier = report.id.uuidString
        let batches = report.batchIDs
        switch authorized {
        case true?:
            deliver(title: title, body: body, identifier: identifier, batches: batches)
        case nil:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
                Task { @MainActor in
                    authorized = granted
                    if granted { deliver(title: title, body: body, identifier: identifier, batches: batches) }
                }
            }
        case false?:
            break
        }
    }

    private static func deliver(title: String, body: String, identifier: String, batches: [Int64]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.userInfo = ["batches": batches.map { NSNumber(value: $0) }]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    /// The person pressed a notification or one of its buttons.
    static func respond(action: String, batches: [Int64]) {
        let model = AppModel.shared
        if action == undoAction {
            for batch in batches { model.undoBatch(batch) }
            if model.lastRun?.batchIDs == batches { model.lastRun = nil }
        } else {
            SettingsWindowController.shared.show(activate: true)
            model.showRun(batches.first)
        }
    }
}

/// Receives notification clicks (on any thread) and hands them to the main actor.
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let batches = (response.notification.request.content.userInfo["batches"] as? [NSNumber])?.map(\.int64Value) ?? []
        let action = response.actionIdentifier
        Task { @MainActor in Notifier.respond(action: action, batches: batches) }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
