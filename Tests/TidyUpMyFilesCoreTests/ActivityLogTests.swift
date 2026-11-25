import XCTest
@testable import TidyUpMyFilesCore

final class ActivityLogTests: SandboxTestCase {
    private var logs: URL { root.appendingPathComponent("Logs") }

    private func loggingStore() throws -> ActivityStore {
        try ActivityStore(fileURL: root.appendingPathComponent("logged.sqlite"), logDirectory: logs)
    }

    private func logText(_ store: ActivityStore) throws -> String {
        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil).first)
        XCTAssertTrue(file.lastPathComponent.hasPrefix("activity-") && file.pathExtension == "log")
        return try String(contentsOf: file, encoding: .utf8)
    }

    func testEverySuccessfulStepAndUndoIsWrittenToTheTextLog() throws {
        let store = try loggingStore()
        let file = try makeFile("report.pdf")
        let rule = Rule(name: "PDF files", mode: .live, condition: .kind(.pdf),
                        actions: [.move(destination: root.path + "/PDF", createFolders: true, onConflict: .rename)])
        let batch = try store.beginBatch(trigger: "run now", folder: inbox.path)
        let executor = ActionExecutor(store: store, trash: trash, opener: NoOpener())
        _ = executor.execute([rule], on: try FileFactsReader.read(file), batchID: batch)
        try UndoService(store: store, trash: trash).undoLast()

        let lines = try logText(store).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("DONE"))
        XCTAssertTrue(lines[0].contains("MOVE"))
        XCTAssertTrue(lines[0].contains("report.pdf → "))
        XCTAssertTrue(lines[0].contains("/PDF/report.pdf"))
        XCTAssertTrue(lines[0].contains("PDF files · run \(batch) (run now)"))
        XCTAssertTrue(lines[1].contains("UNDONE"))
        XCTAssertTrue(lines[1].hasSuffix("(undo)"))
    }

    func testSkippedStepsExplainWhy() throws {
        let store = try loggingStore()
        let batch = try store.beginBatch(trigger: "watch", folder: "/x")
        try store.append(ActivityRecord(batchID: batch, ruleName: "R", action: "move", status: .skipped,
                                        sourcePath: "/x/a.pdf", message: "a.pdf already exists"))
        XCTAssertTrue(try logText(store).contains("SKIPPED  MOVE         /x/a.pdf  (a.pdf already exists)"))
    }

    func testRunSummariesCountStepsPerRun() throws {
        let first = try store.beginBatch(trigger: "run now", folder: "/x")
        for name in ["a", "b"] {
            try store.append(ActivityRecord(batchID: first, ruleName: "R", action: "move", status: .done, sourcePath: "/x/\(name)"))
        }
        try store.append(ActivityRecord(batchID: first, ruleName: "R", action: "trash", status: .done, sourcePath: "/x/c"))
        try store.append(ActivityRecord(batchID: first, ruleName: "R", action: "move", status: .failed, sourcePath: "/x/d"))
        _ = try store.beginBatch(trigger: "watch", folder: "/x") // nothing happened in this one
        let second = try store.beginBatch(trigger: "watch", folder: "/y")
        try store.append(ActivityRecord(batchID: second, ruleName: "R", action: "rename", status: .skipped, sourcePath: "/y/e"))

        let runs = try store.runs()
        XCTAssertEqual(runs.map(\.id), [second, first], "newest first; empty runs are left out")
        XCTAssertEqual(runs[1].count(.done), 3)
        XCTAssertEqual(runs[1].count(.failed), 1)
        XCTAssertEqual(runs[1].actionCounts, ["move": 2, "trash": 1])
        XCTAssertTrue(runs[1].canUndo)
        XCTAssertFalse(runs[0].canUndo)
    }

    func testCSVQuotesAwkwardValues() {
        let record = ActivityRecord(batchID: 3, ruleName: "Bills, \"2026\"", action: "move", status: .done,
                                    sourcePath: "/x/a,b.pdf", targetPath: "/y/a,b.pdf")
        let csv = ActivityStore.csv([record]).split(separator: "\n").map(String.init)
        XCTAssertEqual(csv[0], "time,run,status,action,rule,from,to,message")
        XCTAssertTrue(csv[1].contains(",3,done,move,\"Bills, \"\"2026\"\"\",\"/x/a,b.pdf\",\"/y/a,b.pdf\","))
    }
}
