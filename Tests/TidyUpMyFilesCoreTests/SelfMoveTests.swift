import XCTest
@testable import TidyUpMyFilesCore

final class SelfMoveTests: SandboxTestCase {
    func testAFolderIsNeverMovedIntoItself() throws {
        let folder = inbox.appendingPathComponent("Archives")
        try makeFile("old.txt", in: folder)
        let rule = Rule(name: "Into itself", condition: .all([]),
                        actions: [.move(destination: folder.path, createFolders: true, onConflict: .rename)])
        let outcome = try run(rule, on: folder)
        XCTAssertEqual(outcome.records.map(\.status), [.skipped])
        XCTAssertEqual(outcome.records.first?.message, "A folder can't be moved, copied or packed into itself")
        XCTAssertTrue(exists(folder.appendingPathComponent("old.txt")), "nothing moved")
    }

    func testInsideUnderstandsPathsThatDoNotExistYet() {
        let temp = URL(fileURLWithPath: "/var/folders")
        XCTAssertTrue(PathTools.isInside(temp.appendingPathComponent("new/deeper"), folder: URL(fileURLWithPath: "/private/var/folders")))
        XCTAssertFalse(PathTools.isInside(URL(fileURLWithPath: "/tmp/Pack"), folder: URL(fileURLWithPath: "/tmp/Pack.zip")))
        XCTAssertFalse(PathTools.isInside(inbox, folder: inbox), "a folder is not inside itself")
    }

    func testAISuggestionsSkipFoldersAndTheirOwnLocation() async throws {
        let folder = inbox.appendingPathComponent("Design")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = try makeFile("logo.png")
        let reply = #"{"suggestions":[{"file":"Design","category":"Design","destination":"\#(folder.path)"},"# +
            #"{"file":"logo.png","category":"Here","destination":"\#(inbox.path)"}]}"#
        let provider = Provider(reply: reply)
        var settings = AISettings()
        settings.enabled = true
        settings.allowedFolders = [inbox.path]
        let items = try await AISorter(provider: provider, settings: settings)
            .suggest(for: WatchedFolder(path: inbox.path), items: [folder, file])
        XCTAssertTrue(items.isEmpty, "folders are never suggested and a file already in place is left alone")
        XCTAssertFalse(provider.seen.user.contains("\"Design\""), "only files are sent")
    }

    func testSystemErrorsReadPlainly() {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL))
        let error = NSError(domain: NSCocoaErrorDomain, code: 512,
                            userInfo: [NSUnderlyingErrorKey: underlying, NSLocalizedDescriptionKey: "“Docs” couldn’t be moved."])
        XCTAssertEqual(ExecutionError.plainWords(error), "“Docs” couldn’t be moved. (a folder can't go inside itself)")
    }
}

private struct Provider: AIProvider {
    let kind: AIProviderKind = .ollama
    let reply: String
    let seen = Seen()

    final class Seen: @unchecked Sendable {
        var user = ""
    }

    func complete(system: String, user: String) async throws -> String {
        seen.user = user
        return reply
    }
}
