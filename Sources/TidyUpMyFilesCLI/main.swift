import Foundation
import TidyUpMyFilesCore

let usage = """
    tidyup — tidy folders with the same rules.yaml as the TidyUpMyFiles app

    USAGE
      tidyup sim  [--rules FILE] [FOLDER]           Show what would happen. Changes nothing.
      tidyup run  [--rules FILE] [FOLDER] [--include-preview]
                                                   Act on live rules (and preview rules with the flag).
      tidyup undo [--batch ID]                      Undo the last action, or a whole run.
      tidyup log  [--search TEXT] [--limit N]       Show the activity log.
      tidyup validate [--rules FILE]                Check that a rules file can be read.
      tidyup templates [add] [--rules FILE]         List the ready-made rules, or add the missing ones (preview mode).
      tidyup mcp                                    Serve AI agents over the Model Context Protocol (stdio).

    FOLDER limits the command to one watched folder from the rules file.
    TIDYUP_HOME overrides the storage folder (default ~/Library/Application Support/TidyUpMyFiles).
    """

struct Arguments {
    var command: String
    var rulesFile: URL = AppPaths.rulesFile
    var folder: String?
    var includePreview = false
    var batch: Int64?
    var search = ""
    var limit = 50

    init(_ raw: [String]) throws {
        guard let first = raw.first else { throw CLIError.usage }
        command = first
        var rest = Array(raw.dropFirst())
        while !rest.isEmpty {
            let item = rest.removeFirst()
            func value() throws -> String {
                guard !rest.isEmpty else { throw CLIError.message("\(item) needs a value") }
                return rest.removeFirst()
            }
            switch item {
            case "--rules": rulesFile = URL(fileURLWithPath: PathTools.expandTilde(try value()))
            case "--include-preview": includePreview = true
            case "--batch": batch = Int64(try value())
            case "--search": search = try value()
            case "--limit": limit = Int(try value()) ?? 50
            case "-h", "--help": throw CLIError.usage
            default:
                guard !item.hasPrefix("-") else { throw CLIError.message("Unknown option \(item)") }
                folder = item
            }
        }
    }
}

enum CLIError: Error {
    case usage
    case message(String)
}

func folders(in config: RulesConfig, matching filter: String?) throws -> [WatchedFolder] {
    guard let filter else { return config.folders.filter(\.enabled) }
    let wanted = PathTools.canonical(URL(fileURLWithPath: PathTools.expandTilde(filter)))
    let found = config.folders.filter { PathTools.canonical($0.url) == wanted }
    guard !found.isEmpty else { throw CLIError.message("\(filter) is not a watched folder in the rules file") }
    return found
}

func printRecord(_ record: ActivityRecord) {
    let time = ISO8601DateFormatter().string(from: record.timestamp)
    let result = record.targetPath.map(PathTools.abbreviate) ?? record.message
    print("[\(record.batchID)] \(time) \(record.status.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)) "
          + "\(record.action) \(PathTools.abbreviate(record.sourcePath)) → \(result)  (\(record.ruleName))")
}

func runCLI() throws {
    let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
    switch arguments.command {
    case "mcp":
        // stdout carries the protocol only; anything else goes to stderr.
        var environment = MCPServer.Environment.standard()
        environment.rulesFile = arguments.rulesFile
        MCPServer(environment: environment).serve()

    case "templates":
        let store = RulesStore(fileURL: arguments.rulesFile)
        var config = try store.load()
        if arguments.folder == "add" {
            let added = Templates.installRecommended(into: &config)
            try store.save(config)
            print("Added \(added) ready-made rule(s) in preview mode to \(PathTools.abbreviate(arguments.rulesFile.path)).")
        } else {
            for template in Templates.all {
                let mark = Templates.isInstalled(template, in: config) ? "✓" : " "
                print("[\(mark)] \(template.id.padding(toLength: 15, withPad: " ", startingAt: 0)) \(template.detail)")
            }
        }

    case "validate":
        let config = try RulesStore(fileURL: arguments.rulesFile).load()
        print("OK: \(config.folders.count) folder(s), \(config.folders.reduce(0) { $0 + $1.rules.count }) rule(s)")

    case "sim", "run":
        let config = try RulesStore(fileURL: arguments.rulesFile).load()
        let store = try ActivityStore(fileURL: AppPaths.databaseFile, logDirectory: AppPaths.logsDirectory)
        let organizer = Organizer(config: config, settings: SettingsStore().load(), store: store, trash: AppPaths.defaultTrash())
        for folder in try folders(in: config, matching: arguments.folder) {
            print("== \(folder.path)")
            if arguments.command == "sim" {
                let previews = organizer.simulate(folder)
                if previews.isEmpty { print("   nothing to do") }
                for item in previews { print("   \(item.file.lastPathComponent): [\(item.ruleName)] \(item.summary)") }
            } else {
                let result = organizer.process(organizer.candidates(in: folder), in: folder, trigger: "cli",
                                               treatPreviewAsLive: arguments.includePreview)
                result.records.forEach(printRecord)
                for item in result.previews { print("   preview only: \(item.file.lastPathComponent): [\(item.ruleName)] \(item.summary)") }
                if result.records.isEmpty && result.previews.isEmpty { print("   nothing to do") }
                if let batch = result.batchID { print("   undo this run with: tidyup undo --batch \(batch)") }
            }
        }

    case "undo":
        let store = try ActivityStore(fileURL: AppPaths.databaseFile, logDirectory: AppPaths.logsDirectory)
        let undo = UndoService(store: store, trash: AppPaths.defaultTrash())
        if let batch = arguments.batch {
            let failures = try undo.undoBatch(batch)
            print(failures.isEmpty ? "Undid run \(batch)." : "Undid run \(batch); \(failures.count) step(s) failed:")
            for (record, error) in failures { print("   \(record.sourcePath): \(error)") }
        } else {
            let record = try undo.undoLast()
            print("Undid: \(record.action) \(PathTools.abbreviate(record.sourcePath))")
        }

    case "log":
        let store = try ActivityStore(fileURL: AppPaths.databaseFile, logDirectory: AppPaths.logsDirectory)
        try store.records(ActivityQuery(search: arguments.search, limit: arguments.limit)).reversed().forEach(printRecord)

    default:
        throw CLIError.usage
    }
}

do {
    try runCLI()
} catch CLIError.usage {
    print(usage)
    exit(64)
} catch CLIError.message(let text) {
    FileHandle.standardError.write(Data("tidyup: \(text)\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("tidyup: \(error)\n".utf8))
    exit(1)
}
