import XCTest
@testable import TidyUpMyFilesCore

/// The user guide's "Preview → Live" steps, run for real on temporary folders.
final class LiveModeTests: SandboxTestCase {
    private func pdfRule(_ mode: RuleMode) -> Rule {
        Rule(name: "PDFs", mode: mode, condition: .kind(.pdf),
             actions: [.move(destination: root.path + "/PDF", createFolders: true, onConflict: .rename)])
    }

    private func organizer(_ folder: WatchedFolder) -> Organizer {
        Organizer(config: RulesConfig(folders: [folder]), settings: AppSettings(), store: store, trash: trash, opener: NoOpener())
    }

    func testPreviewRuleWaitsAndLiveRuleReallyMovesFiles() throws {
        let file = try makeFile("bill.pdf")
        let moved = root.appendingPathComponent("PDF/bill.pdf")

        let previewFolder = WatchedFolder(path: inbox.path, rules: [pdfRule(.preview)])
        let preview = organizer(previewFolder).runNow(previewFolder)
        XCTAssertEqual(preview.previews.count, 1, "a preview rule only lists the move")
        XCTAssertTrue(preview.records.isEmpty)
        XCTAssertTrue(exists(file), "nothing moves in preview")

        let liveFolder = WatchedFolder(path: inbox.path, rules: [pdfRule(.live)])
        let live = organizer(liveFolder).runNow(liveFolder)
        XCTAssertEqual(live.records.map(\.status), [.done])
        XCTAssertTrue(live.previews.isEmpty)
        XCTAssertFalse(exists(file), "live really moves the file")
        XCTAssertEqual(read(moved), "hello")
        XCTAssertEqual(try store.runs().first?.statusCounts[.done], 1, "the move is in Activity")

        try organizer(liveFolder).undo.undoLast()
        XCTAssertTrue(exists(file), "Undo puts it back")
        XCTAssertFalse(exists(moved))
    }

    func testTurnThemOnMakesReadyMadeRulesLive() {
        var config = RulesConfig()
        Templates.install(Templates.all.first { $0.id == "pdf" }!, into: &config, folderPath: inbox.path)
        XCTAssertEqual(config.folders.first?.rules.first?.mode, .preview, "ready-made rules start in preview")
        XCTAssertEqual(Templates.makeRecommendedLive(in: &config), 1)
        XCTAssertEqual(config.folders.first?.rules.first?.mode, .live)
    }
}
