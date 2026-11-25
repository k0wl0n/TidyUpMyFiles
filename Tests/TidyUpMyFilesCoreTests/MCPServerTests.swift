import XCTest
@testable import TidyUpMyFilesCore

final class MCPServerTests: SandboxTestCase {
    private var rulesFile: URL { root.appendingPathComponent("rules.yaml") }

    private func server() -> MCPServer {
        MCPServer(environment: .init(rulesFile: rulesFile, databaseFile: root.appendingPathComponent("mcp.sqlite"),
                                     logsDirectory: nil, settings: AppSettings(), trash: trash))
    }

    private func request(_ server: MCPServer, _ method: String, _ params: [String: Any] = [:], id: Int = 1) throws -> [String: Any] {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
        let reply = try XCTUnwrap(server.handle(line))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
    }

    private func callText(_ server: MCPServer, _ tool: String, _ arguments: [String: Any] = [:]) throws -> (text: String, isError: Bool) {
        let reply = try request(server, "tools/call", ["name": tool, "arguments": arguments])
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        let content = try XCTUnwrap((result["content"] as? [[String: Any]])?.first)
        return (content["text"] as? String ?? "", result["isError"] as? Bool ?? false)
    }

    private func saveRules(mode: RuleMode) throws {
        let rule = Rule(name: "PDFs", mode: mode, condition: .kind(.pdf),
                        actions: [.move(destination: root.path + "/PDF", createFolders: true, onConflict: .rename)])
        try RulesStore(fileURL: rulesFile).save(RulesConfig(folders: [WatchedFolder(path: inbox.path, rules: [rule])]))
    }

    func testHandshakeAndToolList() throws {
        let mcp = server()
        let hello = try request(mcp, "initialize", ["protocolVersion": "2025-06-18", "capabilities": [:],
                                                    "clientInfo": ["name": "test", "version": "1"]])
        let result = try XCTUnwrap(hello["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-06-18")
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "tidyup")
        XCTAssertNil(mcp.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#), "notifications get no answer")

        let tools = try XCTUnwrap((try request(mcp, "tools/list")["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(Set(tools.compactMap { $0["name"] as? String }),
                       ["list_rules", "list_templates", "simulate", "run", "undo", "activity_log", "add_template", "set_rule_mode"])
        let run = try XCTUnwrap(tools.first { $0["name"] as? String == "run" })
        XCTAssertEqual((run["annotations"] as? [String: Any])?["destructiveHint"] as? Bool, true)
    }

    func testSimulateChangesNothingAndPreviewRulesWaitUntilLive() throws {
        let file = try makeFile("bill.pdf")
        try saveRules(mode: .preview)
        let mcp = server()

        let simulated = try callText(mcp, "simulate", ["folder": inbox.path])
        XCTAssertTrue(simulated.text.contains("bill.pdf"))
        XCTAssertTrue(exists(file))

        let previewRun = try callText(mcp, "run")
        XCTAssertTrue(previewRun.text.contains("preview only"))
        XCTAssertTrue(exists(file), "preview rules don't act")

        let switched = try callText(mcp, "set_rule_mode", ["folder": inbox.path, "rule": "pdfs", "mode": "live"])
        XCTAssertFalse(switched.isError)
        XCTAssertEqual(try RulesStore(fileURL: rulesFile).load().folders[0].rules[0].mode, .live, "saved to rules.yaml")

        let liveRun = try callText(mcp, "run", ["folder": inbox.path])
        XCTAssertFalse(exists(file), "a live rule really moves the file")
        XCTAssertTrue(exists(root.appendingPathComponent("PDF/bill.pdf")))
        XCTAssertTrue(liveRun.text.contains("run 1"))
        XCTAssertTrue(try callText(mcp, "activity_log").text.contains("bill.pdf"))

        let undone = try callText(mcp, "undo", ["batch": 1])
        XCTAssertEqual(undone.text, "Undid run 1.")
        XCTAssertTrue(exists(file), "undo puts it back")
    }

    func testAddTemplateAndRefusals() throws {
        let mcp = server()
        let added = try callText(mcp, "add_template", ["template_id": "pdf", "folder": inbox.path])
        XCTAssertFalse(added.isError)
        let rule = try XCTUnwrap(try RulesStore(fileURL: rulesFile).load().folders.first?.rules.first)
        XCTAssertEqual(rule.mode, .preview, "ready-made rules arrive in preview")
        XCTAssertTrue(try callText(mcp, "add_template", ["template_id": "pdf", "folder": inbox.path]).text.contains("already has"))
        XCTAssertTrue(try callText(mcp, "list_templates").text.contains("[in \(PathTools.abbreviate(inbox.path))]"))

        XCTAssertTrue(try callText(mcp, "add_template", ["template_id": "pdf", "folder": "/System/Library"]).isError)
        XCTAssertTrue(try callText(mcp, "add_template", ["template_id": "nope"]).isError)
        XCTAssertTrue(try callText(mcp, "simulate", ["folder": "/tmp/not-watched"]).isError)
    }

    func testProtocolErrors() throws {
        let mcp = server()
        XCTAssertEqual((try request(mcp, "no/such")["error"] as? [String: Any])?["code"] as? Int, -32601)
        XCTAssertEqual((try request(mcp, "tools/call", ["name": "format_disk"])["error"] as? [String: Any])?["code"] as? Int, -32602)
        let garbage = try XCTUnwrap(mcp.handle("not json"))
        XCTAssertTrue(garbage.contains("-32700"))
    }
}
