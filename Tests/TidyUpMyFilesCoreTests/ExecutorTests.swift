import XCTest
@testable import TidyUpMyFilesCore

/// Moves "trashed" files into the sandbox, so tests never touch the real Trash.
struct SandboxTrash: TrashProvider {
    let folder: URL

    func trash(_ url: URL) throws -> URL {
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

struct NoOpener: FileOpener {
    func open(_ url: URL) throws {}
}

/// A throwaway folder per test with an inbox, a fake Trash and its own activity database.
class SandboxTestCase: XCTestCase {
    var root: URL!
    var inbox: URL!
    var store: ActivityStore!
    var trash: SandboxTrash!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TidyUpMyFilesTests-\(UUID().uuidString)").resolvingSymlinksInPath()
        inbox = root.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        store = try ActivityStore(fileURL: root.appendingPathComponent("activity.sqlite"))
        trash = SandboxTrash(folder: root.appendingPathComponent("Trash"))
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func makeFile(_ name: String, in folder: URL? = nil, contents: String = "hello") throws -> URL {
        let url = (folder ?? inbox).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func executor(shell: Bool = false) -> ActionExecutor {
        ActionExecutor(store: store, guardrail: SafetyGuard(), trash: trash, opener: NoOpener(), allowShellScripts: shell)
    }

    func undoer() -> UndoService { UndoService(store: store, trash: trash) }

    func run(_ rule: Rule, on url: URL) throws -> ExecutionOutcome {
        let batch = try store.beginBatch(trigger: "test", folder: url.deletingLastPathComponent().path)
        return executor().execute([rule], on: try FileFactsReader.read(url), batchID: batch)
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
}

final class ActionExecutorTests: SandboxTestCase {
    func testMoveCreatesFoldersFromTokensAndUndoMovesBack() throws {
        let file = try makeFile("photo.jpg")
        let year = Calendar.current.component(.year, from: Date())
        let rule = Rule(name: "Images", mode: .live, condition: .kind(.image),
                        actions: [.move(destination: root.path + "/Pictures/{added.year}", createFolders: true, onConflict: .rename)])

        let outcome = try run(rule, on: file)
        let moved = root.appendingPathComponent("Pictures/\(year)/photo.jpg")
        XCTAssertTrue(exists(moved))
        XCTAssertFalse(exists(file))
        XCTAssertEqual(outcome.finalURL?.path, moved.path)

        try undoer().undoLast()
        XCTAssertTrue(exists(file))
        XCTAssertFalse(exists(moved))
        XCTAssertEqual(try store.records().first?.status, .undone)
    }

    func testMoveWithoutCreateFoldersFails() throws {
        let file = try makeFile("a.pdf")
        let rule = Rule(name: "PDF", condition: .kind(.pdf),
                        actions: [.move(destination: root.path + "/Missing", createFolders: false, onConflict: .rename)])
        let outcome = try run(rule, on: file)
        XCTAssertTrue(outcome.hadFailure)
        XCTAssertTrue(exists(file))
    }

    func testConflictSkipLeavesBothFiles() throws {
        let file = try makeFile("a.pdf", contents: "new")
        let existing = try makeFile("a.pdf", in: root.appendingPathComponent("Out"), contents: "old")
        let rule = Rule(name: "PDF", condition: .kind(.pdf),
                        actions: [.move(destination: root.path + "/Out", createFolders: true, onConflict: .skip)])
        let outcome = try run(rule, on: file)
        XCTAssertEqual(outcome.records.map(\.status), [.skipped])
        XCTAssertEqual(read(file), "new")
        XCTAssertEqual(read(existing), "old")
    }

    func testConflictRenameAddsNumber() throws {
        let file = try makeFile("a.pdf", contents: "new")
        try makeFile("a.pdf", in: root.appendingPathComponent("Out"), contents: "old")
        try makeFile("a 2.pdf", in: root.appendingPathComponent("Out"), contents: "older")
        let rule = Rule(name: "PDF", condition: .kind(.pdf),
                        actions: [.move(destination: root.path + "/Out", createFolders: true, onConflict: .rename)])
        _ = try run(rule, on: file)
        XCTAssertEqual(read(root.appendingPathComponent("Out/a 3.pdf")), "new")
    }

    func testOverwriteNeedsExplicitConfirmation() throws {
        let file = try makeFile("a.pdf", contents: "new")
        let existing = try makeFile("a.pdf", in: root.appendingPathComponent("Out"), contents: "old")
        var rule = Rule(name: "PDF", condition: .kind(.pdf),
                        actions: [.move(destination: root.path + "/Out", createFolders: true, onConflict: .overwrite)])

        _ = try run(rule, on: file)
        XCTAssertEqual(read(existing), "old", "overwrite without allow_overwrite must not replace")
        XCTAssertTrue(exists(file))

        rule.allowOverwrite = true
        _ = try run(rule, on: file)
        XCTAssertEqual(read(existing), "new")
        XCTAssertEqual(read(trash.folder.appendingPathComponent("a.pdf")), "old", "replaced file goes to the Trash, never deleted")

        try undoer().undoLast()
        XCTAssertEqual(read(file), "new")
        XCTAssertEqual(read(existing), "old", "undo brings the replaced file back")
    }

    func testRenameWithCounterToken() throws {
        let file = try makeFile("scan.pdf")
        try makeFile("Invoice 1.pdf")
        let rule = Rule(name: "Rename", condition: .kind(.pdf),
                        actions: [.rename(pattern: "Invoice {counter}.{ext}", onConflict: .rename)])
        _ = try run(rule, on: file)
        XCTAssertTrue(exists(inbox.appendingPathComponent("Invoice 2.pdf")))
        XCTAssertFalse(exists(file))
    }

    func testTrashAndRestore() throws {
        let file = try makeFile("old.dmg")
        let rule = Rule(name: "Installers", condition: .kind(.installer), actions: [.trash, .open])
        let outcome = try run(rule, on: file)
        XCTAssertNil(outcome.finalURL)
        XCTAssertEqual(outcome.records.map(\.action), ["trash"], "nothing runs after trash")
        XCTAssertFalse(exists(file))

        try undoer().undoLast()
        XCTAssertTrue(exists(file))
    }

    func testCopyUndoSendsCopyToTrash() throws {
        let file = try makeFile("notes.txt")
        let rule = Rule(name: "Backup", condition: .kind(.document),
                        actions: [.copy(destination: root.path + "/Backup", createFolders: true, onConflict: .rename)])
        _ = try run(rule, on: file)
        let copy = root.appendingPathComponent("Backup/notes.txt")
        XCTAssertTrue(exists(copy))
        XCTAssertTrue(exists(file))

        try undoer().undoLast()
        XCTAssertFalse(exists(copy))
        XCTAssertTrue(exists(file))
    }

    func testTagsColorAndUndo() throws {
        let file = try makeFile("a.txt")
        try FileTagging.setTags(["Inbox"], on: file)
        let rule = Rule(name: "Tags", condition: .all([]),
                        actions: [.addTags(["Done"]), .removeTags(["inbox"]), .setColor(.green)])
        _ = try run(rule, on: file)
        XCTAssertTrue(FileTagging.tags(of: file).contains("Done"))
        XCTAssertFalse(FileTagging.tags(of: file).contains("Inbox"))
        XCTAssertEqual(FileTagging.colorLabel(of: file), .green)

        let batch = try XCTUnwrap(store.lastUndoableBatch())
        XCTAssertTrue(try undoer().undoBatch(batch).isEmpty)
        XCTAssertEqual(FileTagging.tags(of: file), ["Inbox"])
        XCTAssertEqual(FileTagging.colorLabel(of: file), ColorLabel.none)
    }

    func testBatchUndoReversesAChain() throws {
        let file = try makeFile("report.pdf")
        let rule = Rule(name: "Chain", condition: .kind(.pdf), actions: [
            .rename(pattern: "Final {name}.{ext}", onConflict: .rename),
            .move(destination: "Sorted", createFolders: true, onConflict: .rename),
        ])
        _ = try run(rule, on: file)
        XCTAssertTrue(exists(inbox.appendingPathComponent("Sorted/Final report.pdf")))

        let batch = try XCTUnwrap(store.lastUndoableBatch())
        XCTAssertTrue(try undoer().undoBatch(batch).isEmpty)
        XCTAssertTrue(exists(file))
        XCTAssertNil(try store.lastUndoable())
    }

    func testRefusesProtectedLocations() throws {
        let file = try makeFile("config", in: inbox.appendingPathComponent(".git"))
        let rule = Rule(name: "Bad", condition: .all([]), actions: [.trash])
        let outcome = try run(rule, on: file)
        XCTAssertTrue(outcome.hadFailure)
        XCTAssertTrue(exists(file))

        let normal = try makeFile("x.txt")
        let intoApp = Rule(name: "Bad", condition: .all([]),
                           actions: [.move(destination: root.path + "/Tool.app/Contents", createFolders: true, onConflict: .rename)])
        XCTAssertTrue(try run(intoApp, on: normal).hadFailure)
        XCTAssertTrue(exists(normal))
    }

    func testShellIsOffByDefaultAndRunsWhenAllowed() throws {
        let file = try makeFile("a.txt")
        let marker = root.appendingPathComponent("ran.txt")
        let rule = Rule(name: "Script", condition: .all([]), actions: [.shell(script: "echo \"$TIDYUP_FILE\" > '\(marker.path)'")])

        let off = try run(rule, on: file)
        XCTAssertEqual(off.records.map(\.status), [.skipped])
        XCTAssertFalse(exists(marker))

        let batch = try store.beginBatch(trigger: "test", folder: inbox.path)
        _ = executor(shell: true).execute([rule], on: try FileFactsReader.read(file), batchID: batch)
        XCTAssertEqual(read(marker)?.trimmingCharacters(in: .whitespacesAndNewlines), file.path)
    }
}

final class ActivityStoreTests: SandboxTestCase {
    func testSearchFilterAndCount() throws {
        let batch = try store.beginBatch(trigger: "test", folder: "/x")
        try store.append(ActivityRecord(batchID: batch, ruleName: "Images", action: "move", status: .done, sourcePath: "/x/cat.jpg", targetPath: "/y/cat.jpg"))
        try store.append(ActivityRecord(batchID: batch, ruleName: "PDF", action: "move", status: .skipped, sourcePath: "/x/a.pdf"))
        try store.append(ActivityRecord(batchID: batch, ruleName: "Old", action: "trash", status: .done, sourcePath: "/x/b.dmg",
                                        timestamp: Date().addingTimeInterval(-3 * 86_400)))

        XCTAssertEqual(try store.records(ActivityQuery(search: "cat")).map(\.ruleName), ["Images"])
        XCTAssertEqual(try store.records(ActivityQuery(status: .skipped)).count, 1)
        XCTAssertEqual(try store.records(ActivityQuery(action: "trash")).count, 1)
        XCTAssertEqual(try store.tidiedCount(since: Calendar.current.startOfDay(for: Date())), 1)
    }
}

private extension ActivityRecord {
    init(batchID: Int64, ruleName: String, action: String, status: ActivityStatus, sourcePath: String, timestamp: Date) {
        self.init(batchID: batchID, timestamp: timestamp, ruleName: ruleName, action: action, status: status, sourcePath: sourcePath)
    }
}
