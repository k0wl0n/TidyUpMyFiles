import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import TidyUpMyFilesCore

final class NewConditionTests: SandboxTestCase {
    private func organizer(_ rules: [Rule], exclude: [String] = []) -> (Organizer, WatchedFolder) {
        let folder = WatchedFolder(path: inbox.path, exclude: exclude, rules: rules)
        return (Organizer(config: RulesConfig(folders: [folder]), settings: AppSettings(), store: store, trash: trash,
                          opener: NoOpener()), folder)
    }

    private func matchedNames(_ rule: Rule, exclude: [String] = []) -> [String] {
        let (organizer, folder) = organizer([rule], exclude: exclude)
        return organizer.simulate(folder).map(\.file.lastPathComponent).sorted()
    }

    func testGlobNames() {
        let match = TextMatch(glob: "invoice-*.pdf")
        XCTAssertTrue(match.matches("Invoice-2026.PDF"))
        XCTAssertFalse(match.matches("my invoice-2026.pdf"))
        XCTAssertFalse(TextMatch(glob: "Invoice-*", caseSensitive: true).matches("invoice-1"))
    }

    func testDuplicatesKeepTheEarliestAsOriginal() throws {
        try makeFile("photo.jpg", contents: "same bytes")
        Thread.sleep(forTimeInterval: 1.1)
        try makeFile("photo copy.jpg", contents: "same bytes")
        try makeFile("other.jpg", contents: "different")
        try makeFile("empty-a.txt", contents: "")
        try makeFile("empty-b.txt", contents: "")
        let rule = Rule(name: "Dupes", condition: .duplicate(true), actions: [.trash])
        XCTAssertEqual(matchedNames(rule), ["photo copy.jpg"], "empty files are never called duplicates")
    }

    func testContentsOfTextAndRichText() throws {
        try makeFile("notes.txt", contents: "Please pay INVOICE 42 by Friday")
        try makeFile("other.txt", contents: "nothing here")
        let rich = NSAttributedString(string: "Contract for an invoice")
        let rtf = try rich.data(from: NSRange(location: 0, length: rich.length),
                                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        try rtf.write(to: inbox.appendingPathComponent("contract.rtf"))

        let rule = Rule(name: "Invoices", condition: .contents(TextMatch(contains: "invoice")), actions: [.trash])
        XCTAssertEqual(matchedNames(rule), ["contract.rtf", "notes.txt"])
    }

    func testPhotoTakenDateFromExif() throws {
        let url = inbox.appendingPathComponent("holiday.jpg")
        try writeJPEG(to: url, takenAt: "2019:07:14 10:30:00")
        let facts = try FileFactsReader.read(url)
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: try XCTUnwrap(facts.taken))
        XCTAssertEqual(components.year, 2019)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(TokenRenderer().render("Photos/{taken.year}", facts: facts), "Photos/2019")
        XCTAssertTrue(RuleEngine().evaluate(.taken(DateMatch(before: "2020-01-01")), facts))
    }

    func testEmptyFilesAndFolders() throws {
        try makeFile("blank.txt", contents: "")
        try makeFile("full.txt", contents: "x")
        try FileManager.default.createDirectory(at: inbox.appendingPathComponent("Empty Folder"), withIntermediateDirectories: true)
        try makeFile("inside.txt", in: inbox.appendingPathComponent("Full Folder"))
        let rule = Rule(name: "Empty", condition: .isEmpty(true), actions: [.trash])
        XCTAssertEqual(matchedNames(rule), ["Empty Folder", "blank.txt"])
    }

    func testExcludedNamesAreNeverTouched() throws {
        try makeFile("keep-me.pdf")
        try makeFile("report.pdf")
        let rule = Rule(name: "PDF", condition: .kind(.pdf), actions: [.trash])
        XCTAssertEqual(matchedNames(rule, exclude: ["keep*"]), ["report.pdf"])
    }

    func testArchiveCreatesZipAndUndoRemovesIt() throws {
        let file = try makeFile("big log.txt", contents: String(repeating: "log line\n", count: 500))
        let rule = Rule(name: "Zip", condition: .all([]), actions: [.archive(destination: "Zips", onConflict: .rename)])
        let outcome = try run(rule, on: file)
        let zip = inbox.appendingPathComponent("Zips/big log.txt.zip")
        XCTAssertEqual(outcome.records.map(\.status), [.done])
        XCTAssertTrue(exists(zip))
        XCTAssertTrue(exists(file), "the original stays")

        try undoer().undoLast()
        XCTAssertFalse(exists(zip))
    }

    func testNewKeysRoundTripThroughYAML() throws {
        let rule = Rule(name: "All new", condition: .all([
            .duplicate(true), .contents(TextMatch(regex: "inv\\d+")), .taken(DateMatch(olderThanDays: 365)),
            .lastOpened(DateMatch(olderThanDays: 90)), .isEmpty(false), .name(TextMatch(glob: "*.jpg")),
        ]), actions: [.archive(destination: "", onConflict: .skip), .archive(destination: "Zips", onConflict: .rename)])
        let config = RulesConfig(folders: [WatchedFolder(path: "~/Downloads", exclude: ["*.part", "Keep*"], rules: [rule])])
        var decoded = try RulesYAML.decode(try RulesYAML.encode(config))
        decoded.folders[0].rules[0].id = rule.id
        XCTAssertEqual(decoded.folders[0].rules[0], rule)
        XCTAssertEqual(decoded.folders[0].exclude, ["*.part", "Keep*"])
    }

    private func writeJPEG(to url: URL, takenAt: String) throws {
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let properties = [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: takenAt]] as CFDictionary
        CGImageDestinationAddImage(destination, context.makeImage()!, properties)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}

final class PreviewInspectorTests: SandboxTestCase {
    private func item(_ file: URL, _ actions: [Action], allowOverwrite: Bool = false) throws -> PreviewItem {
        let rule = Rule(name: "R", allowOverwrite: allowOverwrite, condition: .all([]), actions: actions)
        let facts = try FileFactsReader.read(file)
        return PreviewItem(folderPath: inbox.path, file: file, ruleName: "R", steps: RuleEngine().plan(rule, facts: facts),
                           allowOverwrite: allowOverwrite)
    }

    private func moveTo(_ folder: String, _ policy: ConflictPolicy = .rename) -> Action {
        .move(destination: root.path + "/" + folder, createFolders: true, onConflict: policy)
    }

    func testPlainMoveIntoNewFolder() throws {
        let detail = PreviewInspector.inspect([try item(try makeFile("a.pdf"), [moveTo("PDF")])])[0]
        XCTAssertEqual(detail.finalLocation?.path, root.appendingPathComponent("PDF/a.pdf").path)
        XCTAssertTrue(detail.createsFolder)
        XCTAssertFalse(detail.hasConflict)
    }

    func testNameTakenOnDiskAndWithinTheBatch() throws {
        try makeFile("a.pdf", in: root.appendingPathComponent("PDF"), contents: "already there")
        let first = try item(try makeFile("a.pdf"), [moveTo("PDF")])
        let second = try item(try makeFile("a.pdf", in: inbox.appendingPathComponent("Sub")), [moveTo("PDF")])
        let details = PreviewInspector.inspect([first, second])
        XCTAssertEqual(details[0].steps[0].conflict, .numbered("a 2.pdf"))
        XCTAssertEqual(details[1].steps[0].conflict, .numbered("a 3.pdf"), "the earlier waiting item already claims a 2.pdf")
        XCTAssertFalse(details[0].createsFolder)
    }

    func testSkipAndBlockedOverwriteStayPut() throws {
        try makeFile("a.pdf", in: root.appendingPathComponent("PDF"))
        let skip = PreviewInspector.inspect([try item(try makeFile("a.pdf"), [moveTo("PDF", .skip)])])[0]
        XCTAssertEqual(skip.steps[0].conflict, .skipped)
        XCTAssertNil(skip.finalLocation)

        let blocked = PreviewInspector.inspect([try item(try makeFile("a.pdf"), [moveTo("PDF", .overwrite)])])[0]
        XCTAssertEqual(blocked.steps[0].conflict, .blocked)
        let replaces = PreviewInspector.inspect([try item(try makeFile("a.pdf"), [moveTo("PDF", .overwrite)], allowOverwrite: true)])[0]
        XCTAssertEqual(replaces.steps[0].conflict, .replaces)
    }

    func testRenameThenMoveAndTrash() throws {
        let file = try makeFile("scan.pdf")
        let chain = PreviewInspector.inspect([try item(file, [.rename(pattern: "Invoice.{ext}", onConflict: .rename), moveTo("Bills")])])[0]
        XCTAssertEqual(chain.finalLocation?.path, root.appendingPathComponent("Bills/Invoice.pdf").path)
        XCTAssertTrue(chain.nameChanges)
        XCTAssertEqual(chain.destinationFolder?.path, root.appendingPathComponent("Bills").path)

        let trashed = PreviewInspector.inspect([try item(file, [.trash])])[0]
        XCTAssertTrue(trashed.goesToTrash)
        XCTAssertNil(trashed.finalLocation)
    }
}
