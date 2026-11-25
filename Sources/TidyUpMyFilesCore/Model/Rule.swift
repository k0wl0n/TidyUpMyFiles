import Foundation

public enum RuleMode: String, Codable, CaseIterable, Sendable {
    /// Matches are only shown in the preview list until the person runs them.
    case preview
    /// Matches are acted on automatically.
    case live
}

public enum ConflictPolicy: String, Codable, CaseIterable, Sendable {
    /// Leave the item where it is.
    case skip
    /// The new item gets a number ("name 2.ext").
    case rename
    /// The existing file goes to the Trash first, then the new item takes its name (needs `allow_overwrite`).
    case overwrite
    /// The existing file gets a number ("name 2.ext") and the new item takes the name.
    case renameExisting = "rename_existing"
}

public enum Action: Equatable, Sendable {
    /// `destination` is a folder template; relative paths are resolved against the file's folder.
    case move(destination: String, createFolders: Bool, onConflict: ConflictPolicy)
    case copy(destination: String, createFolders: Bool, onConflict: ConflictPolicy)
    case rename(pattern: String, onConflict: ConflictPolicy)
    case addTags([String])
    case removeTags([String])
    case setColor(ColorLabel)
    case trash
    case open
    /// Runs only when shell scripts are allowed in General settings.
    case shell(script: String)
    /// Zips the item into `destination` (a folder template; empty means beside the file). The original stays.
    case archive(destination: String, onConflict: ConflictPolicy)
    /// Unpacks a .zip or .tar(.gz/.bz2/.xz) into a folder named after it inside `destination`
    /// (a folder template; empty means beside the archive). The archive stays.
    case extract(destination: String, onConflict: ConflictPolicy)
    /// Makes a Finder alias of the item in `destination`.
    case makeAlias(destination: String)
    /// Runs a Shortcut from the Shortcuts app with the item as input (only when allowed in Settings).
    case runShortcut(name: String)

    public var verb: String {
        switch self {
        case .move: return "move"
        case .copy: return "copy"
        case .rename: return "rename"
        case .addTags: return "add_tags"
        case .removeTags: return "remove_tags"
        case .setColor: return "set_color"
        case .trash: return "trash"
        case .open: return "open"
        case .shell: return "shell"
        case .archive: return "archive"
        case .extract: return "extract"
        case .makeAlias: return "alias"
        case .runShortcut: return "shortcut"
        }
    }

    public var conflictPolicy: ConflictPolicy? {
        switch self {
        case .move(_, _, let policy), .copy(_, _, let policy), .rename(_, let policy), .archive(_, let policy),
             .extract(_, let policy): return policy
        default: return nil
        }
    }
}

public struct Rule: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var mode: RuleMode
    public var continueMatching: Bool
    /// `on_conflict: overwrite` is honoured only when this is explicitly true.
    public var allowOverwrite: Bool
    public var condition: Condition
    public var actions: [Action]
    /// The ready-made template this rule came from, so it is never added twice.
    public var templateID: String?

    public init(id: UUID = UUID(), name: String, enabled: Bool = true, mode: RuleMode = .preview,
                continueMatching: Bool = false, allowOverwrite: Bool = false,
                condition: Condition, actions: [Action], templateID: String? = nil) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.mode = mode
        self.continueMatching = continueMatching
        self.allowOverwrite = allowOverwrite
        self.condition = condition
        self.actions = actions
        self.templateID = templateID
    }

    /// Same behaviour, ignoring the identity used by the editor.
    public func isSameRule(as other: Rule) -> Bool {
        var copy = other
        copy.id = id
        copy.templateID = templateID
        return copy == self
    }
}

public struct WatchedFolder: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var path: String
    public var enabled: Bool
    public var includeSubfolders: Bool
    /// Name patterns (`*.part`, `Keep*`) that this folder's rules never touch.
    public var exclude: [String]
    public var rules: [Rule]

    public init(id: UUID = UUID(), path: String, enabled: Bool = true, includeSubfolders: Bool = false,
                exclude: [String] = [], rules: [Rule] = []) {
        self.id = id
        self.path = path
        self.enabled = enabled
        self.includeSubfolders = includeSubfolders
        self.exclude = exclude
        self.rules = rules
    }

    public func isExcluded(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return exclude.contains { pattern in
            !pattern.isEmpty && fnmatch(pattern, name, FNM_CASEFOLD) == 0
        }
    }

    public var url: URL { URL(fileURLWithPath: PathTools.expandTilde(path)).standardizedFileURL }
}

public struct RulesConfig: Equatable, Sendable {
    public var version: Int
    public var folders: [WatchedFolder]

    public init(version: Int = 1, folders: [WatchedFolder] = []) {
        self.version = version
        self.folders = folders
    }

    /// Merges folders listed twice and drops rules that repeat an earlier one exactly.
    /// Returns how many rules and folders were removed.
    @discardableResult
    public mutating func removeDuplicates() -> (rules: Int, folders: Int) {
        var merged: [WatchedFolder] = []
        var removedFolders = 0
        for folder in folders {
            let path = PathTools.canonical(folder.url)
            if let index = merged.firstIndex(where: { PathTools.canonical($0.url) == path }) {
                merged[index].rules += folder.rules
                removedFolders += 1
            } else {
                merged.append(folder)
            }
        }
        var removedRules = 0
        for index in merged.indices {
            var kept: [Rule] = []
            for rule in merged[index].rules {
                let duplicate = kept.contains { existing in
                    existing.isSameRule(as: rule)
                        || (rule.templateID != nil && existing.templateID == rule.templateID)
                }
                if duplicate { removedRules += 1 } else { kept.append(rule) }
            }
            merged[index].rules = kept
        }
        folders = merged
        return (removedRules, removedFolders)
    }
}
