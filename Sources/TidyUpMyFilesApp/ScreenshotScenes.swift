import AppKit
import SwiftUI
import TidyUpMyFilesCore

/// States that normally need a click, staged for `--screenshot` only (documentation pictures and checks).
/// Chosen with `TIDYUP_SHOT_SCENE`; ignored when the app runs normally.
@MainActor
enum ShotScene {
    static var current: String? {
        guard LaunchOptions.screenshotPath != nil else { return nil }
        return ProcessInfo.processInfo.environment["TIDYUP_SHOT_SCENE"]
    }

    static func `is`(_ name: String) -> Bool { current == name }

    /// Prepares model state before the window draws.
    static func prepare(_ model: AppModel) {
        switch current {
        case "report": stageReport(model)
        case "ai-suggestions": stageAISuggestions(model)
        case "tidy-explained": stageTidyExplained(model)
        default: break
        }
    }

    /// The menu bar popup, drawn into a window so it can be photographed.
    static func menuView(_ model: AppModel) -> some View {
        MenuContent().environmentObject(model)
    }

    /// The message after pressing Tidy when everything left is waiting on preview-mode rules (read-only simulation).
    private static func stageTidyExplained(_ model: AppModel) {
        guard let organizer = model.organizer else { return }
        let items = model.config.folders.filter(\.enabled).flatMap { organizer.simulate($0, reportProgress: false) }
        model.previews = items
        model.explainWaiting(items, lead: "Already tidy — nothing new to sort automatically. ")
    }

    /// The report card for the most recent run in the activity log.
    private static func stageReport(_ model: AppModel) {
        guard let store = model.organizer?.store, let run = try? store.runs(limit: 1).first,
              let records = try? store.records(inBatch: run.id) else { return }
        model.lastRun = RunReport(records: records.reversed(), batchIDs: [run.id], title: RunText.title(run.trigger))
    }

    /// Example AI suggestions for the demo Downloads folder, made locally (no model or network involved).
    private static func stageAISuggestions(_ model: AppModel) {
        guard let folder = model.config.folders.first(where: { $0.path.hasSuffix("Downloads") }) else { return }
        let canned = [
            AISuggestion(file: "kroscek transaksi Mei.xlsx", category: "Finance", destination: "~/Documents/Finance/2026",
                         newName: "2026-05 Transaction check.xlsx"),
            AISuggestion(file: "Laba Rugi 2026 Revised.xlsx", category: "Finance", destination: "~/Documents/Finance/2026",
                         newName: "2026 Profit and loss (revised).xlsx"),
            AISuggestion(file: "Infra Engineer CV.pdf", category: "Career", destination: "~/Documents/Career", newName: nil),
            AISuggestion(file: "Competency Matrix.docx", category: "Career", destination: "~/Documents/Career", newName: nil),
            AISuggestion(file: "podcast ep 12.mp3", category: "Podcasts", destination: "~/Music/Podcasts", newName: nil),
        ]
        let facts = canned.compactMap { try? FileFactsReader.read(folder.url.appendingPathComponent($0.file), needs: []) }
        model.aiSuggestions = AISorter(provider: OfflineProvider(), settings: model.settings.ai)
            .items(from: canned, facts: facts, folder: folder)
    }

    private struct OfflineProvider: AIProvider {
        let kind: AIProviderKind = .ollama
        func complete(system: String, user: String) async throws -> String { "{\"suggestions\":[]}" }
    }
}

extension RunReport {
    /// A report rebuilt from logged steps (used to show the latest run).
    init?(records: [ActivityRecord], batchIDs: [Int64], title: String) {
        var result = ProcessResult()
        result.batchID = batchIDs.first
        result.records = records
        self.init(results: [result], title: title, cancelled: false)
    }
}
