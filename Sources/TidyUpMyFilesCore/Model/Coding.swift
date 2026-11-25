import Foundation

// Codable shapes that keep rules.yaml short and readable: each condition and action is a
// one-key mapping (`- kind: image`, `- move: ~/Pictures`).

struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private func corrupted(_ decoder: Decoder, _ message: String) -> DecodingError {
    DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: message))
}

/// Writes whole numbers as integers so YAML shows `7`, not `7.0`.
private func encodeNumber(_ value: Double, to container: inout KeyedEncodingContainer<DynamicKey>, key: String) throws {
    if value.rounded() == value, abs(value) < 9e15 {
        try container.encode(Int64(value), forKey: DynamicKey(key))
    } else {
        try container.encode(value, forKey: DynamicKey(key))
    }
}

/// Accepts plain numbers and sizes such as "10 MB" or "1.5GB" (1 KB = 1000 bytes, like Finder).
public enum SizeParser {
    public static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        let units: [(String, Double)] = [("tb", 1e12), ("gb", 1e9), ("mb", 1e6), ("kb", 1e3), ("b", 1)]
        for (suffix, multiplier) in units where trimmed.hasSuffix(suffix) {
            let number = trimmed.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
            return Double(number).map { $0 * multiplier }
        }
        return Double(trimmed)
    }
}

extension TextMatch: Codable {
    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(String.self) {
            self.init(contains: single)
            return
        }
        let container = try decoder.container(keyedBy: DynamicKey.self)
        self.init(
            contains: try container.decodeIfPresent(String.self, forKey: DynamicKey("contains")),
            startsWith: try container.decodeIfPresent(String.self, forKey: DynamicKey("starts_with")),
            endsWith: try container.decodeIfPresent(String.self, forKey: DynamicKey("ends_with")),
            equals: try container.decodeIfPresent(String.self, forKey: DynamicKey("equals")),
            regex: try container.decodeIfPresent(String.self, forKey: DynamicKey("regex")),
            glob: try container.decodeIfPresent(String.self, forKey: DynamicKey("glob")),
            caseSensitive: try container.decodeIfPresent(Bool.self, forKey: DynamicKey("case_sensitive")) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encodeIfPresent(contains, forKey: DynamicKey("contains"))
        try container.encodeIfPresent(startsWith, forKey: DynamicKey("starts_with"))
        try container.encodeIfPresent(endsWith, forKey: DynamicKey("ends_with"))
        try container.encodeIfPresent(equals, forKey: DynamicKey("equals"))
        try container.encodeIfPresent(regex, forKey: DynamicKey("regex"))
        try container.encodeIfPresent(glob, forKey: DynamicKey("glob"))
        if caseSensitive { try container.encode(true, forKey: DynamicKey("case_sensitive")) }
    }
}

extension NumberMatch: Codable {
    private static let keys = ["gt", "gte", "lt", "lte", "eq"]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        func value(_ key: String) throws -> Double? {
            let codingKey = DynamicKey(key)
            guard container.contains(codingKey) else { return nil }
            if let number = try? container.decode(Double.self, forKey: codingKey) { return number }
            let text = try container.decode(String.self, forKey: codingKey)
            guard let parsed = SizeParser.parse(text) else { throw corrupted(decoder, "Not a number: \(text)") }
            return parsed
        }
        self.init(greaterThan: try value("gt"), atLeast: try value("gte"), lessThan: try value("lt"),
                  atMost: try value("lte"), equalTo: try value("eq"))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        let values = [greaterThan, atLeast, lessThan, atMost, equalTo]
        for (key, value) in zip(NumberMatch.keys, values) {
            if let value { try encodeNumber(value, to: &container, key: key) }
        }
    }
}

extension DateMatch: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        self.init(
            before: try container.decodeIfPresent(String.self, forKey: DynamicKey("before")),
            after: try container.decodeIfPresent(String.self, forKey: DynamicKey("after")),
            olderThanDays: try container.decodeIfPresent(Double.self, forKey: DynamicKey("older_than_days")),
            newerThanDays: try container.decodeIfPresent(Double.self, forKey: DynamicKey("newer_than_days"))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encodeIfPresent(before, forKey: DynamicKey("before"))
        try container.encodeIfPresent(after, forKey: DynamicKey("after"))
        if let olderThanDays { try encodeNumber(olderThanDays, to: &container, key: "older_than_days") }
        if let newerThanDays { try encodeNumber(newerThanDays, to: &container, key: "newer_than_days") }
    }
}

extension TagMatch: Codable {
    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(String.self) {
            self.init(has: single)
            return
        }
        let container = try decoder.container(keyedBy: DynamicKey.self)
        self.init(has: try container.decodeIfPresent(String.self, forKey: DynamicKey("has")),
                  lacks: try container.decodeIfPresent(String.self, forKey: DynamicKey("lacks")))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encodeIfPresent(has, forKey: DynamicKey("has"))
        try container.encodeIfPresent(lacks, forKey: DynamicKey("lacks"))
    }
}

private func decodeColor(_ container: KeyedDecodingContainer<DynamicKey>, key: DynamicKey, decoder: Decoder) throws -> ColorLabel {
    if let number = try? container.decode(Int.self, forKey: key), let label = ColorLabel(rawValue: number) {
        return label
    }
    let name = try container.decode(String.self, forKey: key)
    guard let label = ColorLabel(name: name) else { throw corrupted(decoder, "Unknown color: \(name)") }
    return label
}

extension Condition: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw corrupted(decoder, "Each condition needs exactly one key (all, any, not, name, kind, ...)")
        }
        switch key.stringValue {
        case "all": self = .all(try container.decode([Condition].self, forKey: key))
        case "any": self = .any(try container.decode([Condition].self, forKey: key))
        case "not": self = .not(try container.decode(Condition.self, forKey: key))
        case "name": self = .name(try container.decode(TextMatch.self, forKey: key))
        case "extension":
            if let list = try? container.decode([String].self, forKey: key) {
                self = .fileExtension(list)
            } else {
                self = .fileExtension([try container.decode(String.self, forKey: key)])
            }
        case "kind": self = .kind(try container.decode(FileKind.self, forKey: key))
        case "size": self = .size(try container.decode(NumberMatch.self, forKey: key))
        case "created": self = .created(try container.decode(DateMatch.self, forKey: key))
        case "modified": self = .modified(try container.decode(DateMatch.self, forKey: key))
        case "added": self = .added(try container.decode(DateMatch.self, forKey: key))
        case "age_days": self = .ageDays(try container.decode(NumberMatch.self, forKey: key))
        case "tag": self = .tag(try container.decode(TagMatch.self, forKey: key))
        case "color": self = .color(try decodeColor(container, key: key, decoder: decoder))
        case "source_url": self = .sourceURL(try container.decode(TextMatch.self, forKey: key))
        case "is_folder": self = .isFolder(try container.decode(Bool.self, forKey: key))
        case "duplicate": self = .duplicate(try container.decode(Bool.self, forKey: key))
        case "contents": self = .contents(try container.decode(TextMatch.self, forKey: key))
        case "taken": self = .taken(try container.decode(DateMatch.self, forKey: key))
        case "last_opened": self = .lastOpened(try container.decode(DateMatch.self, forKey: key))
        case "empty": self = .isEmpty(try container.decode(Bool.self, forKey: key))
        default: throw corrupted(decoder, "Unknown condition: \(key.stringValue)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        switch self {
        case .all(let list): try container.encode(list, forKey: DynamicKey("all"))
        case .any(let list): try container.encode(list, forKey: DynamicKey("any"))
        case .not(let inner): try container.encode(inner, forKey: DynamicKey("not"))
        case .name(let match): try container.encode(match, forKey: DynamicKey("name"))
        case .fileExtension(let list): try container.encode(list, forKey: DynamicKey("extension"))
        case .kind(let kind): try container.encode(kind, forKey: DynamicKey("kind"))
        case .size(let match): try container.encode(match, forKey: DynamicKey("size"))
        case .created(let match): try container.encode(match, forKey: DynamicKey("created"))
        case .modified(let match): try container.encode(match, forKey: DynamicKey("modified"))
        case .added(let match): try container.encode(match, forKey: DynamicKey("added"))
        case .ageDays(let match): try container.encode(match, forKey: DynamicKey("age_days"))
        case .tag(let match): try container.encode(match, forKey: DynamicKey("tag"))
        case .color(let label): try container.encode(label.name, forKey: DynamicKey("color"))
        case .sourceURL(let match): try container.encode(match, forKey: DynamicKey("source_url"))
        case .isFolder(let flag): try container.encode(flag, forKey: DynamicKey("is_folder"))
        case .duplicate(let flag): try container.encode(flag, forKey: DynamicKey("duplicate"))
        case .contents(let match): try container.encode(match, forKey: DynamicKey("contents"))
        case .taken(let match): try container.encode(match, forKey: DynamicKey("taken"))
        case .lastOpened(let match): try container.encode(match, forKey: DynamicKey("last_opened"))
        case .isEmpty(let flag): try container.encode(flag, forKey: DynamicKey("empty"))
        }
    }
}

extension Action: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        let createFolders = try container.decodeIfPresent(Bool.self, forKey: DynamicKey("create_folders")) ?? true
        let onConflict = try container.decodeIfPresent(ConflictPolicy.self, forKey: DynamicKey("on_conflict")) ?? .rename
        let verbs = ["move", "copy", "rename", "add_tags", "remove_tags", "set_color", "trash", "open", "shell", "archive",
                     "extract", "alias", "shortcut"]
        let present = verbs.filter { container.contains(DynamicKey($0)) }
        guard present.count == 1, let verb = present.first else {
            throw corrupted(decoder, "Each action needs exactly one of: \(verbs.joined(separator: ", "))")
        }
        let key = DynamicKey(verb)
        func tagList() throws -> [String] {
            if let list = try? container.decode([String].self, forKey: key) { return list }
            return [try container.decode(String.self, forKey: key)]
        }
        switch verb {
        case "move": self = .move(destination: try container.decode(String.self, forKey: key), createFolders: createFolders, onConflict: onConflict)
        case "copy": self = .copy(destination: try container.decode(String.self, forKey: key), createFolders: createFolders, onConflict: onConflict)
        case "rename": self = .rename(pattern: try container.decode(String.self, forKey: key), onConflict: onConflict)
        case "add_tags": self = .addTags(try tagList())
        case "remove_tags": self = .removeTags(try tagList())
        case "set_color": self = .setColor(try decodeColor(container, key: key, decoder: decoder))
        case "trash": self = .trash
        case "open": self = .open
        case "archive", "extract":
            // `archive: true` / `extract: true` work beside the file; a string names the folder.
            let destination: String
            if (try? container.decode(Bool.self, forKey: key)) != nil {
                destination = ""
            } else {
                destination = try container.decode(String.self, forKey: key)
            }
            self = verb == "archive" ? .archive(destination: destination, onConflict: onConflict)
                : .extract(destination: destination, onConflict: onConflict)
        case "alias": self = .makeAlias(destination: try container.decode(String.self, forKey: key))
        case "shortcut": self = .runShortcut(name: try container.decode(String.self, forKey: key))
        default: self = .shell(script: try container.decode(String.self, forKey: key))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        switch self {
        case .move(let destination, let createFolders, let onConflict),
             .copy(let destination, let createFolders, let onConflict):
            try container.encode(destination, forKey: DynamicKey(verb))
            if !createFolders { try container.encode(false, forKey: DynamicKey("create_folders")) }
            try container.encode(onConflict, forKey: DynamicKey("on_conflict"))
        case .rename(let pattern, let onConflict):
            try container.encode(pattern, forKey: DynamicKey("rename"))
            try container.encode(onConflict, forKey: DynamicKey("on_conflict"))
        case .addTags(let tags), .removeTags(let tags):
            try container.encode(tags, forKey: DynamicKey(verb))
        case .setColor(let label): try container.encode(label.name, forKey: DynamicKey("set_color"))
        case .trash: try container.encode(true, forKey: DynamicKey("trash"))
        case .open: try container.encode(true, forKey: DynamicKey("open"))
        case .shell(let script): try container.encode(script, forKey: DynamicKey("shell"))
        case .archive(let destination, let onConflict), .extract(let destination, let onConflict):
            if destination.isEmpty {
                try container.encode(true, forKey: DynamicKey(verb))
            } else {
                try container.encode(destination, forKey: DynamicKey(verb))
            }
            try container.encode(onConflict, forKey: DynamicKey("on_conflict"))
        case .makeAlias(let destination): try container.encode(destination, forKey: DynamicKey("alias"))
        case .runShortcut(let name): try container.encode(name, forKey: DynamicKey("shortcut"))
        }
    }
}

extension Rule: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        self.init(
            name: try container.decode(String.self, forKey: DynamicKey("name")),
            enabled: try container.decodeIfPresent(Bool.self, forKey: DynamicKey("enabled")) ?? true,
            mode: try container.decodeIfPresent(RuleMode.self, forKey: DynamicKey("mode")) ?? .preview,
            continueMatching: try container.decodeIfPresent(Bool.self, forKey: DynamicKey("continue_matching")) ?? false,
            allowOverwrite: try container.decodeIfPresent(Bool.self, forKey: DynamicKey("allow_overwrite")) ?? false,
            condition: try container.decode(Condition.self, forKey: DynamicKey("when")),
            actions: try container.decode([Action].self, forKey: DynamicKey("do")),
            templateID: try container.decodeIfPresent(String.self, forKey: DynamicKey("template"))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encode(name, forKey: DynamicKey("name"))
        try container.encode(enabled, forKey: DynamicKey("enabled"))
        try container.encode(mode, forKey: DynamicKey("mode"))
        if continueMatching { try container.encode(true, forKey: DynamicKey("continue_matching")) }
        if allowOverwrite { try container.encode(true, forKey: DynamicKey("allow_overwrite")) }
        try container.encode(condition, forKey: DynamicKey("when"))
        try container.encode(actions, forKey: DynamicKey("do"))
        try container.encodeIfPresent(templateID, forKey: DynamicKey("template"))
    }
}

extension WatchedFolder: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        self.init(
            path: try container.decode(String.self, forKey: DynamicKey("path")),
            enabled: try container.decodeIfPresent(Bool.self, forKey: DynamicKey("enabled")) ?? true,
            includeSubfolders: try container.decodeIfPresent(Bool.self, forKey: DynamicKey("subfolders")) ?? false,
            exclude: try container.decodeIfPresent([String].self, forKey: DynamicKey("exclude")) ?? [],
            rules: try container.decodeIfPresent([Rule].self, forKey: DynamicKey("rules")) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encode(path, forKey: DynamicKey("path"))
        try container.encode(enabled, forKey: DynamicKey("enabled"))
        if includeSubfolders { try container.encode(true, forKey: DynamicKey("subfolders")) }
        if !exclude.isEmpty { try container.encode(exclude, forKey: DynamicKey("exclude")) }
        try container.encode(rules, forKey: DynamicKey("rules"))
    }
}

extension RulesConfig: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        self.init(version: try container.decodeIfPresent(Int.self, forKey: DynamicKey("version")) ?? 1,
                  folders: try container.decodeIfPresent([WatchedFolder].self, forKey: DynamicKey("folders")) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encode(version, forKey: DynamicKey("version"))
        try container.encode(folders, forKey: DynamicKey("folders"))
    }
}
