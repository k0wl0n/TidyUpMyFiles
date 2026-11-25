import Foundation
import Yams

public struct SmartTrashSettings: Equatable, Sendable {
    public var enabled = false
    public var olderThanDays: Double = 30
    /// When set, the oldest items also go once the Trash is bigger than this.
    public var maxSizeGB: Double?
    /// The person has seen the first summary and agreed to automatic emptying.
    public var confirmed = false

    public init() {}
}

public enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case ollama, openai, anthropic, gemini

    public var displayName: String {
        switch self {
        case .ollama: return "Ollama (local)"
        case .openai: return "OpenAI-compatible"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        }
    }

    public var isLocal: Bool { self == .ollama }

    public var defaultEndpoint: String {
        switch self {
        case .ollama: return "http://localhost:11434"
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com"
        case .gemini: return "https://generativelanguage.googleapis.com"
        }
    }

    public var defaultModel: String {
        switch self {
        case .ollama: return "llama3.2"
        case .openai: return "gpt-4o-mini"
        case .anthropic: return "claude-haiku-5-5"
        case .gemini: return "gemini-2.5-flash"
        }
    }
}

public struct AISettings: Equatable, Sendable {
    public var enabled = false
    public var provider: AIProviderKind = .ollama
    public var endpoint = AIProviderKind.ollama.defaultEndpoint
    public var model = AIProviderKind.ollama.defaultModel
    /// Only these folders may be analysed.
    public var allowedFolders: [String] = []
    /// Folders whose file contents (first few KB of text) may be sent; otherwise only names and metadata.
    public var readContentsFolders: [String] = []

    public init() {}
}

public struct AppSettings: Equatable, Sendable {
    public var paused = false
    public var allowShellScripts = false
    /// "Run Shortcut" actions only run when this is on.
    public var allowShortcuts = false
    public var stableSeconds: Double = 2
    /// Folders are re-checked this often so age-based rules fire without a file event.
    public var rescanMinutes: Double = 15
    /// A macOS notification after the watcher or a scheduled check tidies something.
    public var notifyAfterBackgroundRuns = true
    public var smartTrash = SmartTrashSettings()
    public var ai = AISettings()

    public init() {}
}

extension SmartTrashSettings: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        self.init()
        enabled = try c.decodeIfPresent(Bool.self, forKey: DynamicKey("enabled")) ?? enabled
        olderThanDays = try c.decodeIfPresent(Double.self, forKey: DynamicKey("older_than_days")) ?? olderThanDays
        maxSizeGB = try c.decodeIfPresent(Double.self, forKey: DynamicKey("max_size_gb"))
        confirmed = try c.decodeIfPresent(Bool.self, forKey: DynamicKey("confirmed")) ?? confirmed
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        try c.encode(enabled, forKey: DynamicKey("enabled"))
        try c.encode(olderThanDays, forKey: DynamicKey("older_than_days"))
        try c.encodeIfPresent(maxSizeGB, forKey: DynamicKey("max_size_gb"))
        try c.encode(confirmed, forKey: DynamicKey("confirmed"))
    }
}

extension AISettings: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        self.init()
        enabled = try c.decodeIfPresent(Bool.self, forKey: DynamicKey("enabled")) ?? enabled
        provider = try c.decodeIfPresent(AIProviderKind.self, forKey: DynamicKey("provider")) ?? provider
        endpoint = try c.decodeIfPresent(String.self, forKey: DynamicKey("endpoint")) ?? provider.defaultEndpoint
        model = try c.decodeIfPresent(String.self, forKey: DynamicKey("model")) ?? provider.defaultModel
        allowedFolders = try c.decodeIfPresent([String].self, forKey: DynamicKey("allowed_folders")) ?? []
        readContentsFolders = try c.decodeIfPresent([String].self, forKey: DynamicKey("read_contents_folders")) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        try c.encode(enabled, forKey: DynamicKey("enabled"))
        try c.encode(provider, forKey: DynamicKey("provider"))
        try c.encode(endpoint, forKey: DynamicKey("endpoint"))
        try c.encode(model, forKey: DynamicKey("model"))
        try c.encode(allowedFolders, forKey: DynamicKey("allowed_folders"))
        try c.encode(readContentsFolders, forKey: DynamicKey("read_contents_folders"))
    }
}

extension AppSettings: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        self.init()
        paused = try c.decodeIfPresent(Bool.self, forKey: DynamicKey("paused")) ?? paused
        allowShellScripts = try c.decodeIfPresent(Bool.self, forKey: DynamicKey("allow_shell_scripts")) ?? allowShellScripts
        allowShortcuts = try c.decodeIfPresent(Bool.self, forKey: DynamicKey("allow_shortcuts")) ?? allowShortcuts
        stableSeconds = try c.decodeIfPresent(Double.self, forKey: DynamicKey("stable_seconds")) ?? stableSeconds
        rescanMinutes = try c.decodeIfPresent(Double.self, forKey: DynamicKey("rescan_minutes")) ?? rescanMinutes
        notifyAfterBackgroundRuns = try c.decodeIfPresent(Bool.self, forKey: DynamicKey("notify_after_background_runs")) ?? notifyAfterBackgroundRuns
        smartTrash = try c.decodeIfPresent(SmartTrashSettings.self, forKey: DynamicKey("smart_trash")) ?? smartTrash
        ai = try c.decodeIfPresent(AISettings.self, forKey: DynamicKey("ai")) ?? ai
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        try c.encode(paused, forKey: DynamicKey("paused"))
        try c.encode(allowShellScripts, forKey: DynamicKey("allow_shell_scripts"))
        try c.encode(allowShortcuts, forKey: DynamicKey("allow_shortcuts"))
        try c.encode(stableSeconds, forKey: DynamicKey("stable_seconds"))
        try c.encode(rescanMinutes, forKey: DynamicKey("rescan_minutes"))
        try c.encode(notifyAfterBackgroundRuns, forKey: DynamicKey("notify_after_background_runs"))
        try c.encode(smartTrash, forKey: DynamicKey("smart_trash"))
        try c.encode(ai, forKey: DynamicKey("ai"))
    }
}

/// Non-secret settings. API keys live in the Keychain, never here.
public struct SettingsStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL = AppPaths.settingsFile) {
        self.fileURL = fileURL
    }

    public func load() -> AppSettings {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8),
              let settings = try? YAMLDecoder().decode(AppSettings.self, from: text) else { return AppSettings() }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try YAMLEncoder().encode(settings).write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
