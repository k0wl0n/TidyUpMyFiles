import XCTest
@testable import TidyUpMyFilesCore

final class MoreActionsTests: SandboxTestCase {
    func testRenameExistingMovesTheOldFileAsideAndUndoSwapsBack() throws {
        let incoming = try makeFile("report.pdf", contents: "new")
        let existing = try makeFile("report.pdf", in: root.appendingPathComponent("Out"), contents: "old")
        let rule = Rule(name: "PDF", condition: .kind(.pdf),
                        actions: [.move(destination: root.path + "/Out", createFolders: true, onConflict: .renameExisting)])
        _ = try run(rule, on: incoming)
        XCTAssertEqual(read(existing), "new", "the new file takes the name")
        XCTAssertEqual(read(root.appendingPathComponent("Out/report 2.pdf")), "old", "the old file steps aside")

        try undoer().undoLast()
        XCTAssertEqual(read(incoming), "new")
        XCTAssertEqual(read(existing), "old", "undo puts the old file back under its name")
        XCTAssertFalse(exists(root.appendingPathComponent("Out/report 2.pdf")))
    }

    func testPreviewPredictsTheExistingFileStepsAside() throws {
        try makeFile("a.pdf", in: root.appendingPathComponent("Out"))
        let file = try makeFile("a.pdf")
        let rule = Rule(name: "R", condition: .all([]),
                        actions: [.move(destination: root.path + "/Out", createFolders: true, onConflict: .renameExisting)])
        let item = PreviewItem(folderPath: inbox.path, file: file, ruleName: "R",
                               steps: RuleEngine().plan(rule, facts: try FileFactsReader.read(file)))
        let detail = PreviewInspector.inspect([item])[0]
        XCTAssertEqual(detail.steps[0].conflict, .movesExistingAside("a 2.pdf"))
        XCTAssertEqual(detail.finalLocation?.lastPathComponent, "a.pdf")
    }

    func testExtractZipIntoItsOwnFolderAndUndo() throws {
        let source = try makeFile("readme.txt", in: root.appendingPathComponent("Pack"), contents: "inside")
        let zip = inbox.appendingPathComponent("Pack.zip")
        try Archiver.zip(source.deletingLastPathComponent(), to: zip)
        let rule = Rule(name: "Unzip", condition: .kind(.archive), actions: [.extract(destination: "", onConflict: .rename)])
        let outcome = try run(rule, on: zip)
        XCTAssertEqual(outcome.records.map(\.status), [.done])
        XCTAssertEqual(read(inbox.appendingPathComponent("Pack/Pack/readme.txt")), "inside")
        XCTAssertTrue(exists(zip), "the archive stays")

        try undoer().undoLast()
        XCTAssertFalse(exists(inbox.appendingPathComponent("Pack")))
    }

    func testExtractTarGzAndSkipUnsupported() throws {
        let folder = root.appendingPathComponent("Data")
        try makeFile("a.csv", in: folder, contents: "1,2")
        let tarball = inbox.appendingPathComponent("data.tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-czf", tarball.path, "-C", folder.path, "a.csv"]
        try tar.run()
        tar.waitUntilExit()
        let rule = Rule(name: "Unpack", condition: .all([]), actions: [.extract(destination: "Unpacked", onConflict: .rename)])
        _ = try run(rule, on: tarball)
        XCTAssertEqual(read(inbox.appendingPathComponent("Unpacked/data/a.csv")), "1,2")

        let seven = try makeFile("old.7z", contents: "not really")
        let skipped = try run(rule, on: seven)
        XCTAssertEqual(skipped.records.map(\.status), [.skipped])
    }

    func testAliasPointsAtTheFile() throws {
        let file = try makeFile("plan.pdf")
        let rule = Rule(name: "Alias", condition: .all([]), actions: [.makeAlias(destination: root.path + "/Shortcuts")])
        _ = try run(rule, on: file)
        let alias = root.appendingPathComponent("Shortcuts/plan.pdf alias")
        XCTAssertTrue(exists(alias))
        let resolved = try URL(resolvingAliasFileAt: alias)
        XCTAssertEqual(PathTools.canonical(resolved), PathTools.canonical(file))
    }

    func testShortcutsAreOffUnlessAllowed() throws {
        let file = try makeFile("a.txt")
        let rule = Rule(name: "Shortcut", condition: .all([]), actions: [.runShortcut(name: "Does Not Exist")])
        XCTAssertEqual(try run(rule, on: file).records.map(\.status), [.skipped])
    }

    func testNewActionsRoundTripThroughYAML() throws {
        let rule = Rule(name: "All", condition: .all([]), actions: [
            .extract(destination: "", onConflict: .rename), .extract(destination: "~/Unpacked", onConflict: .skip),
            .makeAlias(destination: "~/Desktop/Links"), .runShortcut(name: "Resize Images"),
            .move(destination: "~/Out", createFolders: true, onConflict: .renameExisting),
        ])
        var decoded = try RulesYAML.decode(try RulesYAML.encode(RulesConfig(folders: [WatchedFolder(path: "~/x", rules: [rule])])))
        decoded.folders[0].rules[0].id = rule.id
        XCTAssertEqual(decoded.folders[0].rules[0], rule)
    }
}
