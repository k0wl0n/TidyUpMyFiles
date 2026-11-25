import Foundation

/// Text test used by `name` and `source_url`. Every field that is set must hold.
public struct TextMatch: Equatable, Sendable {
    public var contains: String?
    public var startsWith: String?
    public var endsWith: String?
    public var equals: String?
    public var regex: String?
    /// Shell-style pattern such as `Invoice-*.pdf` (`*`, `?`, `[abc]`).
    public var glob: String?
    public var caseSensitive: Bool

    public init(contains: String? = nil, startsWith: String? = nil, endsWith: String? = nil,
                equals: String? = nil, regex: String? = nil, glob: String? = nil, caseSensitive: Bool = false) {
        self.contains = contains
        self.startsWith = startsWith
        self.endsWith = endsWith
        self.equals = equals
        self.regex = regex
        self.glob = glob
        self.caseSensitive = caseSensitive
    }

    public func matches(_ text: String) -> Bool {
        let subject = caseSensitive ? text : text.lowercased()
        func normalized(_ value: String) -> String { caseSensitive ? value : value.lowercased() }

        if let contains, !subject.contains(normalized(contains)) { return false }
        if let startsWith, !subject.hasPrefix(normalized(startsWith)) { return false }
        if let endsWith, !subject.hasSuffix(normalized(endsWith)) { return false }
        if let equals, subject != normalized(equals) { return false }
        if let regex {
            let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
            guard let expression = try? NSRegularExpression(pattern: regex, options: options) else { return false }
            let range = NSRange(text.startIndex..., in: text)
            if expression.firstMatch(in: text, range: range) == nil { return false }
        }
        if let glob {
            let flags = caseSensitive ? 0 : FNM_CASEFOLD
            if fnmatch(glob, text, flags) != 0 { return false }
        }
        return true
    }
}

/// Numeric comparison; every bound that is set must hold.
public struct NumberMatch: Equatable, Sendable {
    public var greaterThan: Double?
    public var atLeast: Double?
    public var lessThan: Double?
    public var atMost: Double?
    public var equalTo: Double?

    public init(greaterThan: Double? = nil, atLeast: Double? = nil, lessThan: Double? = nil,
                atMost: Double? = nil, equalTo: Double? = nil) {
        self.greaterThan = greaterThan
        self.atLeast = atLeast
        self.lessThan = lessThan
        self.atMost = atMost
        self.equalTo = equalTo
    }

    public func matches(_ value: Double) -> Bool {
        if let greaterThan, !(value > greaterThan) { return false }
        if let atLeast, !(value >= atLeast) { return false }
        if let lessThan, !(value < lessThan) { return false }
        if let atMost, !(value <= atMost) { return false }
        if let equalTo, value != equalTo { return false }
        return true
    }
}

/// Date test; `before`/`after` are `yyyy-MM-dd` (local time), the day counts are relative to now.
public struct DateMatch: Equatable, Sendable {
    public var before: String?
    public var after: String?
    public var olderThanDays: Double?
    public var newerThanDays: Double?

    public init(before: String? = nil, after: String? = nil, olderThanDays: Double? = nil, newerThanDays: Double? = nil) {
        self.before = before
        self.after = after
        self.olderThanDays = olderThanDays
        self.newerThanDays = newerThanDays
    }

    public func matches(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        if let before {
            guard let limit = DateMatch.parseDay(before), date < limit else { return false }
        }
        if let after {
            guard let limit = DateMatch.parseDay(after), date >= limit.addingTimeInterval(86_400) else { return false }
        }
        let ageDays = now.timeIntervalSince(date) / 86_400
        if let olderThanDays, !(ageDays > olderThanDays) { return false }
        if let newerThanDays, !(ageDays < newerThanDays) { return false }
        return true
    }

    static func parseDay(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }
}

public struct TagMatch: Equatable, Sendable {
    public var has: String?
    public var lacks: String?

    public init(has: String? = nil, lacks: String? = nil) {
        self.has = has
        self.lacks = lacks
    }

    public func matches(_ tags: [String]) -> Bool {
        let lowered = Set(tags.map { $0.lowercased() })
        if let has, !lowered.contains(has.lowercased()) { return false }
        if let lacks, lowered.contains(lacks.lowercased()) { return false }
        return true
    }
}

/// Finder color labels, numbered as Finder stores them.
public enum ColorLabel: Int, CaseIterable, Sendable, Codable {
    case none = 0, gray, green, purple, blue, yellow, red, orange

    public var name: String { String(describing: self) }

    public init?(name: String) {
        guard let match = ColorLabel.allCases.first(where: { $0.name == name.lowercased() }) else { return nil }
        self = match
    }
}

public indirect enum Condition: Equatable, Sendable {
    case all([Condition])
    case any([Condition])
    case not(Condition)
    case name(TextMatch)
    case fileExtension([String])
    case kind(FileKind)
    case size(NumberMatch)
    case created(DateMatch)
    case modified(DateMatch)
    case added(DateMatch)
    case ageDays(NumberMatch)
    case tag(TagMatch)
    case color(ColorLabel)
    case sourceURL(TextMatch)
    case isFolder(Bool)
    /// Same content as another item in the folder that arrived earlier.
    case duplicate(Bool)
    /// Text inside the file (plain text, PDF, Word, RTF…).
    case contents(TextMatch)
    /// When a photo was taken (EXIF), else when the file was created.
    case taken(DateMatch)
    /// When the file was last opened (Spotlight).
    case lastOpened(DateMatch)
    /// Zero-byte file or folder with nothing visible inside.
    case isEmpty(Bool)

    public var isGroup: Bool {
        switch self {
        case .all, .any, .not: return true
        default: return false
        }
    }
}
