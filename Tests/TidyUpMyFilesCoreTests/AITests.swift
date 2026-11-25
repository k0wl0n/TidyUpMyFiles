import XCTest
@testable import TidyUpMyFilesCore

private struct ScriptedProvider: AIProvider {
    let kind: AIProviderKind = .ollama
    let reply: String
    let seen = Captured()

    final class Captured: @unchecked Sendable {
        var user = ""
    }

    func complete(system: String, user: String) async throws -> String {
        seen.user = user
        return reply
    }
}

private struct RecordingTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        (Data(#"{"content":[{"type":"text","text":"{\"suggestions\":[]}"}]}"#.utf8), 200)
    }
}

final class AITests: SandboxTestCase {
    private func settings(allow: Bool, contents: Bool = false) -> AISettings {
        var settings = AISettings()
        settings.enabled = true
        settings.allowedFolders = allow ? [inbox.path] : []
        settings.readContentsFolders = contents ? [inbox.path] : []
        return settings
    }

    func testOnlyNamesAndMetadataAreSentByDefault() async throws {
        let file = try makeFile("notes.txt", contents: "secret diary")
        let provider = ScriptedProvider(reply: #"{"suggestions":[{"file":"notes.txt","category":"Notes","destination":"~/Documents/Notes"}]}"#)
        let folder = WatchedFolder(path: inbox.path)

        let items = try await AISorter(provider: provider, settings: settings(allow: true)).suggest(for: folder, items: [file])
        XCTAssertFalse(provider.seen.user.contains("secret diary"))
        XCTAssertTrue(provider.seen.user.contains("notes.txt"))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].rule.mode, .preview)
        XCTAssertTrue(exists(file), "suggesting changes nothing")

        _ = try await AISorter(provider: provider, settings: settings(allow: true, contents: true)).suggest(for: folder, items: [file])
        XCTAssertTrue(provider.seen.user.contains("secret diary"), "contents only when the folder opted in")
    }

    func testFoldersOutsideTheAllowlistAreNeverSent() async throws {
        let file = try makeFile("a.pdf")
        let provider = ScriptedProvider(reply: #"{"suggestions":[]}"#)
        let items = try await AISorter(provider: provider, settings: settings(allow: false))
            .suggest(for: WatchedFolder(path: inbox.path), items: [file])
        XCTAssertTrue(items.isEmpty)
        XCTAssertEqual(provider.seen.user, "", "nothing was sent")
    }

    func testUnsafeDestinationsAreDroppedAndRulesCanBeMadePermanent() throws {
        let facts = [try FileFactsReader.read(try makeFile("invoice.pdf")), try FileFactsReader.read(try makeFile("x.txt"))]
        let suggestions = try AISorter.parse("""
            Sure! {"suggestions":[
              {"file":"invoice.pdf","category":"Invoices","destination":"~/Documents/Invoices","new_name":"2026 invoice.pdf"},
              {"file":"x.txt","category":"Bad","destination":"~/Library/Hidden"}
            ]}
            """)
        let sorter = AISorter(provider: ScriptedProvider(reply: ""), settings: settings(allow: true))
        let items = sorter.items(from: suggestions, facts: facts, folder: WatchedFolder(path: inbox.path))
        XCTAssertEqual(items.map(\.suggestion.category), ["Invoices"])
        XCTAssertEqual(items[0].steps.map(\.action.verb), ["rename", "move"])

        let rule = AISorter.permanentRule(from: items[0])
        XCTAssertEqual(rule.condition, .fileExtension(["pdf"]))
        XCTAssertEqual(rule.mode, .preview)
    }

    func testApprovedSuggestionRunsAndCanBeUndone() throws {
        let file = try makeFile("invoice.pdf")
        let facts = [try FileFactsReader.read(file)]
        let folder = WatchedFolder(path: inbox.path)
        let sorter = AISorter(provider: ScriptedProvider(reply: ""), settings: settings(allow: true))
        let items = sorter.items(from: [AISuggestion(file: "invoice.pdf", category: "Bills", destination: "Bills", newName: nil)],
                                 facts: facts, folder: folder)
        let organizer = Organizer(config: RulesConfig(folders: [folder]), settings: AppSettings(), store: store, trash: trash, opener: NoOpener())
        let result = organizer.approve(items)
        XCTAssertEqual(result.records.map(\.status), [.done])
        XCTAssertTrue(exists(inbox.appendingPathComponent("Bills/invoice.pdf")))
        try organizer.undo.undoLast()
        XCTAssertTrue(exists(file))
    }

    func testProviderRequestsAndReplies() async throws {
        let anthropic = HTTPAIProvider(kind: .anthropic, endpoint: "https://api.anthropic.com", model: "m", apiKey: "k",
                                       transport: RecordingTransport())
        let request = try anthropic.makeRequest(system: "s", user: "u")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "k")
        let reply = try await anthropic.complete(system: "s", user: "u")
        XCTAssertEqual(reply, #"{"suggestions":[]}"#)

        let ollama = try HTTPAIProvider(kind: .ollama, endpoint: "http://localhost:11434/", model: "m", apiKey: nil)
            .makeRequest(system: "s", user: "u")
        XCTAssertEqual(ollama.url?.absoluteString, "http://localhost:11434/api/chat")
        XCTAssertThrowsError(try HTTPAIProvider(kind: .gemini, endpoint: "https://x", model: "m", apiKey: nil).makeRequest(system: "", user: ""))
    }
}
