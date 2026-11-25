import Foundation

/// A Model Context Protocol server over stdio (newline-delimited JSON-RPC 2.0), so AI agents can look at,
/// simulate, run and undo TidyUpMyFiles rules. It uses the same rules file, history and safety guard as the
/// app: nothing is deleted for good, every step is undoable, and only live rules act unless asked otherwise.
public final class MCPServer {
    public struct Environment {
        public var rulesFile: URL
        public var databaseFile: URL
        public var logsDirectory: URL?
        public var settings: AppSettings
        public var trash: any TrashProvider

        public init(rulesFile: URL, databaseFile: URL, logsDirectory: URL?, settings: AppSettings, trash: any TrashProvider) {
            self.rulesFile = rulesFile
            self.databaseFile = databaseFile
            self.logsDirectory = logsDirectory
            self.settings = settings
            self.trash = trash
        }

        public static func standard() -> Environment {
            Environment(rulesFile: AppPaths.rulesFile, databaseFile: AppPaths.databaseFile, logsDirectory: AppPaths.logsDirectory,
                        settings: SettingsStore().load(), trash: AppPaths.defaultTrash())
        }
    }

    public static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    static let serverVersion = "1.0.0"

    private let environment: Environment
    private var cachedStore: ActivityStore?

    public init(environment: Environment) {
        self.environment = environment
    }

    /// Reads requests from stdin until it closes and writes one response line per request.
    public func serve() {
        while let line = readLine(strippingNewline: true) {
            guard let response = handle(line) else { continue }
            FileHandle.standardOutput.write(Data((response + "\n").utf8))
        }
    }

    /// Handles one JSON-RPC message; returns the response line, or nil for notifications.
    public func handle(_ line: String) -> String? {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        let id = message["id"]
        guard let method = message["method"] as? String else {
            return id == nil ? nil : encode(errorResponse(id: id, code: -32600, message: "Invalid request"))
        }
        // Notifications (no id) never get an answer.
        guard let id else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            return encode(result(id: id, initializeResult(params)))
        case "ping":
            return encode(result(id: id, [String: Any]()))
        case "tools/list":
            return encode(result(id: id, ["tools": MCPServer.tools.map(\.json)]))
        case "tools/call":
            guard let name = params["name"] as? String else {
                return encode(errorResponse(id: id, code: -32602, message: "tools/call needs a tool name"))
            }
            guard MCPServer.tools.contains(where: { $0.name == name }) else {
                return encode(errorResponse(id: id, code: -32602, message: "Unknown tool: \(name)"))
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            return encode(result(id: id, callTool(name, arguments)))
        default:
            return encode(errorResponse(id: id, code: -32601, message: "Method not found: \(method)"))
        }
    }

    // MARK: Protocol

    private func initializeResult(_ params: [String: Any]) -> [String: Any] {
        let asked = params["protocolVersion"] as? String ?? ""
        let version = MCPServer.supportedProtocolVersions.contains(asked) ? asked : MCPServer.supportedProtocolVersions[0]
        return [
            "protocolVersion": version,
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "tidyup", "title": "TidyUpMyFiles", "version": MCPServer.serverVersion],
            "instructions": """
                TidyUpMyFiles tidies folders on this Mac with rules. Use simulate before run: simulate changes nothing. \
                run only acts on rules in live mode unless include_preview is true. Nothing is ever deleted for good \
                (removed files go to the Trash) and every run can be taken back with undo. New rules start in preview mode.
                """,
        ]
    }

    private func result(id: Any, _ value: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": value]
    }

    private func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Tools

    struct Tool {
        var name: String
        var title: String
        var description: String
        var properties: [String: [String: Any]] = [:]
        var required: [String] = []
        var readOnly: Bool
        var destructive = false
        var idempotent = false

        var json: [String: Any] {
            [
                "name": name,
                "title": title,
                "description": description,
                "inputSchema": ["type": "object", "properties": properties, "required": required] as [String: Any],
                "annotations": ["title": title, "readOnlyHint": readOnly, "destructiveHint": destructive,
                                "idempotentHint": idempotent, "openWorldHint": false],
            ]
        }
    }

    private static var folderProperty: [String: Any] {
        ["type": "string", "description": "A watched folder such as ~/Downloads. Leave out for every watched folder."]
    }

    static var tools: [Tool] { [
        Tool(name: "list_rules", title: "List rules",
             description: "Every watched folder with its rules, in the order they are checked, and whether each rule is on and in preview or live mode.",
             readOnly: true, idempotent: true),
        Tool(name: "list_templates", title: "List ready-made rules",
             description: "The ready-made rules (by id) and the folders that already use each one.",
             readOnly: true, idempotent: true),
        Tool(name: "simulate", title: "Simulate",
             description: "What every enabled rule would do to the files already in the folder. Changes nothing.",
             properties: ["folder": folderProperty], readOnly: true, idempotent: true),
        Tool(name: "run", title: "Tidy now",
             description: "Tidy the folder now with the live rules (moves, renames, Trash). Preview-mode rules are only listed unless include_preview is true. Every step is logged and can be undone.",
             properties: ["folder": folderProperty,
                          "include_preview": ["type": "boolean", "description": "Also act on rules that are still in preview mode."]],
             readOnly: false, destructive: true),
        Tool(name: "undo", title: "Undo",
             description: "Take back the last step, or a whole run when batch is given (the run number shown by run or activity_log).",
             properties: ["batch": ["type": "integer", "description": "The run number to undo completely."]],
             readOnly: false),
        Tool(name: "activity_log", title: "Activity log",
             description: "What TidyUpMyFiles did recently, newest last: each file's from → to, or why it was skipped or failed.",
             properties: ["search": ["type": "string", "description": "Only steps whose file, folder or rule contains this text."],
                          "limit": ["type": "integer", "description": "How many steps (default 50, at most 500)."]],
             readOnly: true, idempotent: true),
        Tool(name: "add_template", title: "Add a ready-made rule",
             description: "Add a ready-made rule (an id from list_templates) to a folder, in preview mode. Without folder it goes to the folder it is made for.",
             properties: ["template_id": ["type": "string", "description": "The ready-made rule's id, e.g. pdf or screenshots."],
                          "folder": ["type": "string", "description": "The folder to add it to, e.g. ~/Desktop."]],
             required: ["template_id"], readOnly: false, idempotent: true),
        Tool(name: "set_rule_mode", title: "Switch a rule between preview and live",
             description: "Turn a rule live (it then tidies new files by itself) or back to preview (it only lists what it would do).",
             properties: ["folder": ["type": "string", "description": "The watched folder the rule belongs to."],
                          "rule": ["type": "string", "description": "The rule's name, as list_rules shows it."],
                          "mode": ["type": "string", "enum": ["preview", "live"]]],
             required: ["folder", "rule", "mode"], readOnly: false, idempotent: true),
    ] }

    private func callTool(_ name: String, _ arguments: [String: Any]) -> [String: Any] {
        do {
            let text: String
            switch name {
            case "list_rules": text = try listRules()
            case "list_templates": text = try listTemplates()
            case "simulate": text = try simulate(folder: arguments["folder"] as? String)
            case "run": text = try run(folder: arguments["folder"] as? String, includePreview: arguments["include_preview"] as? Bool ?? false)
            case "undo": text = try undo(batch: (arguments["batch"] as? NSNumber)?.int64Value)
            case "activity_log":
                text = try activityLog(search: arguments["search"] as? String ?? "", limit: (arguments["limit"] as? NSNumber)?.intValue ?? 50)
            case "add_template": text = try addTemplate(id: arguments["template_id"] as? String ?? "", folder: arguments["folder"] as? String)
            default:
                text = try setRuleMode(folder: arguments["folder"] as? String ?? "", rule: arguments["rule"] as? String ?? "",
                                       mode: arguments["mode"] as? String ?? "")
            }
            return ["content": [["type": "text", "text": text]], "isError": false]
        } catch {
            return ["content": [["type": "text", "text": MCPServer.plain(error)]], "isError": true]
        }
    }

    struct ToolError: Error, CustomStringConvertible {
        var description: String
    }

    static func plain(_ error: Error) -> String {
        if let error = error as? ToolError { return error.description }
        return ExecutionError.plainWords(error)
    }

    private var rulesStore: RulesStore { RulesStore(fileURL: environment.rulesFile) }

    private func activityStore() throws -> ActivityStore {
        if let cachedStore { return cachedStore }
        let store = try ActivityStore(fileURL: environment.databaseFile, logDirectory: environment.logsDirectory)
        cachedStore = store
        return store
    }

    private func organizer(_ config: RulesConfig) throws -> Organizer {
        Organizer(config: config, settings: environment.settings, store: try activityStore(), trash: environment.trash)
    }

    private func folders(in config: RulesConfig, matching filter: String?) throws -> [WatchedFolder] {
        guard let filter, !filter.isEmpty else { return config.folders.filter(\.enabled) }
        let found = config.folders.filter { MCPServer.samePath($0.path, filter) }
        guard !found.isEmpty else {
            throw ToolError(description: "\(filter) is not a watched folder. Watched: "
                            + config.folders.map(\.path).joined(separator: ", "))
        }
        return found
    }

    private static func samePath(_ left: String, _ right: String) -> Bool {
        PathTools.canonical(URL(fileURLWithPath: PathTools.expandTilde(left)))
            == PathTools.canonical(URL(fileURLWithPath: PathTools.expandTilde(right)))
    }

    private func listRules() throws -> String {
        let config = try rulesStore.load()
        guard !config.folders.isEmpty else { return "No watched folders yet. Add a ready-made rule with add_template." }
        return config.folders.map { folder in
            let header = "\(folder.path)\(folder.enabled ? "" : " (not watched)")"
            let rules = folder.rules.enumerated().map { index, rule in
                "  \(index + 1). \(rule.name) — \(rule.enabled ? "on" : "off"), \(rule.mode == .live ? "live" : "preview")"
            }
            return ([header] + (rules.isEmpty ? ["  (no rules)"] : rules)).joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func listTemplates() throws -> String {
        let config = try rulesStore.load()
        return Templates.all.map { template in
            let used = config.folders.filter { Templates.isInstalled(template, in: config, folderPath: $0.path) }.map(\.path)
            return "\(template.id): \(template.title) — \(template.detail)"
                + (used.isEmpty ? "" : " [in \(used.joined(separator: ", "))]")
        }.joined(separator: "\n")
    }

    private func simulate(folder: String?) throws -> String {
        let config = try rulesStore.load()
        let organizer = try organizer(config)
        return try folders(in: config, matching: folder).map { watched in
            let previews = organizer.simulate(watched, reportProgress: false)
            let lines = previews.map { "  \($0.file.lastPathComponent): [\($0.ruleName)] \($0.summary)" }
            return (["\(watched.path) — \(previews.count) item(s), nothing changed"] + (lines.isEmpty ? ["  nothing to do"] : lines))
                .joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func run(folder: String?, includePreview: Bool) throws -> String {
        let config = try rulesStore.load()
        let organizer = try organizer(config)
        return try folders(in: config, matching: folder).map { watched in
            let result = organizer.process(organizer.candidates(in: watched), in: watched, trigger: "mcp",
                                           treatPreviewAsLive: includePreview, reportProgress: false)
            var lines = ["\(watched.path)"]
            lines += result.records.map { "  " + MCPServer.describe($0) }
            lines += result.previews.map { "  preview only (not done): \($0.file.lastPathComponent): [\($0.ruleName)] \($0.summary)" }
            if result.records.isEmpty && result.previews.isEmpty { lines.append("  nothing to do") }
            if let batch = result.batchID { lines.append("  run \(batch) — undo it with undo(batch: \(batch))") }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func undo(batch: Int64?) throws -> String {
        let undo = UndoService(store: try activityStore(), trash: environment.trash)
        if let batch {
            let failures = try undo.undoBatch(batch)
            return ([failures.isEmpty ? "Undid run \(batch)." : "Undid run \(batch); \(failures.count) step(s) could not be undone:"]
                    + failures.map { "  \(PathTools.abbreviate($0.0.sourcePath)): \(MCPServer.plain($0.1))" }).joined(separator: "\n")
        }
        let record = try undo.undoLast()
        return "Undid: \(record.action) \(PathTools.abbreviate(record.sourcePath))"
    }

    private func activityLog(search: String, limit: Int) throws -> String {
        let records = try activityStore().records(ActivityQuery(search: search, limit: min(max(limit, 1), 500)))
        guard !records.isEmpty else { return "No activity yet." }
        return records.reversed().map(MCPServer.describe).joined(separator: "\n")
    }

    private func addTemplate(id: String, folder: String?) throws -> String {
        guard let template = Templates.all.first(where: { $0.id == id }) else {
            throw ToolError(description: "Unknown ready-made rule \"\(id)\". Known: " + Templates.all.map(\.id).joined(separator: ", "))
        }
        if let folder, !SafetyGuard().isAllowed(URL(fileURLWithPath: PathTools.expandTilde(folder))) {
            throw ToolError(description: "\(folder) is off-limits: system folders, ~/Library, .git folders and apps are never touched.")
        }
        var config = try rulesStore.load()
        let place = PathTools.abbreviate(PathTools.expandTilde(folder ?? template.folderPath))
        guard Templates.install(template, into: &config, folderPath: folder.map { PathTools.abbreviate(PathTools.expandTilde($0)) }) else {
            return "\(place) already has \"\(template.title)\"."
        }
        try rulesStore.save(config)
        return "Added \"\(template.title)\" to \(place) in preview mode. Check it with simulate, then turn it on with set_rule_mode."
    }

    private func setRuleMode(folder: String, rule: String, mode: String) throws -> String {
        guard let newMode = RuleMode(rawValue: mode) else { throw ToolError(description: "mode must be preview or live") }
        var config = try rulesStore.load()
        guard let f = config.folders.firstIndex(where: { MCPServer.samePath($0.path, folder) }) else {
            throw ToolError(description: "\(folder) is not a watched folder.")
        }
        guard let r = config.folders[f].rules.firstIndex(where: { $0.name.caseInsensitiveCompare(rule) == .orderedSame }) else {
            throw ToolError(description: "\(config.folders[f].path) has no rule named \"\(rule)\". Rules: "
                            + config.folders[f].rules.map(\.name).joined(separator: ", "))
        }
        config.folders[f].rules[r].mode = newMode
        try rulesStore.save(config)
        let name = config.folders[f].rules[r].name
        return newMode == .live
            ? "\"\(name)\" in \(config.folders[f].path) is now live: it tidies new files by itself. Every step can be undone."
            : "\"\(name)\" in \(config.folders[f].path) is back in preview: it only lists what it would do."
    }

    static func describe(_ record: ActivityRecord) -> String {
        let outcome = record.targetPath.map { "→ \(PathTools.abbreviate($0))" } ?? record.message
        return "[run \(record.batchID)] \(record.status.rawValue) \(record.action) \(PathTools.abbreviate(record.sourcePath)) \(outcome) (\(record.ruleName))"
    }
}
