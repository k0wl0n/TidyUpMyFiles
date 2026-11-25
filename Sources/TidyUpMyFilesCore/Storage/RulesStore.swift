import Foundation
import Yams

public enum AppPaths {
    /// `TIDYUP_HOME` overrides the storage folder (used by tests and the CLI's `--home`).
    public static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["TIDYUP_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: PathTools.expandTilde(override))
        }
        let base = PathTools.isDemoHome
            ? URL(fileURLWithPath: PathTools.homeDirectory).appendingPathComponent("Library/Application Support")
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TidyUpMyFiles")
    }

    /// The Trash to use: the real one, or `~/.Trash` inside the demo home.
    public static func defaultTrash() -> any TrashProvider {
        PathTools.isDemoHome ? FolderTrash(folder: URL(fileURLWithPath: PathTools.homeDirectory).appendingPathComponent(".Trash"))
            : SystemTrash()
    }

    public static var rulesFile: URL { supportDirectory.appendingPathComponent("rules.yaml") }
    public static var settingsFile: URL { supportDirectory.appendingPathComponent("settings.yaml") }
    public static var databaseFile: URL { supportDirectory.appendingPathComponent("activity.sqlite") }

    /// Plain-text activity logs: ~/Library/Logs/TidyUpMyFiles (where Console.app looks), or inside
    /// `TIDYUP_HOME` when that is set.
    public static var logsDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["TIDYUP_HOME"], !override.isEmpty {
            return supportDirectory.appendingPathComponent("Logs")
        }
        let library = PathTools.isDemoHome ? URL(fileURLWithPath: PathTools.homeDirectory).appendingPathComponent("Library")
            : FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return library.appendingPathComponent("Logs/TidyUpMyFiles")
    }
}

public enum RulesYAML {
    public static func decode(_ text: String) throws -> RulesConfig {
        try YAMLDecoder().decode(RulesConfig.self, from: text)
    }

    public static func encode(_ config: RulesConfig) throws -> String {
        let header = "# TidyUpMyFiles rules — edit in the app or by hand. Docs: README.md\n"
        return header + (try YAMLEncoder().encode(config))
    }
}

public struct RulesStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL = AppPaths.rulesFile) {
        self.fileURL = fileURL
    }

    /// A missing file means "no rules yet", not an error.
    public func load() throws -> RulesConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return RulesConfig() }
        return try RulesYAML.decode(String(contentsOf: fileURL, encoding: .utf8))
    }

    public func save(_ config: RulesConfig) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RulesYAML.encode(config).write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
