import Foundation

/// Fills `{token}` placeholders in rename patterns and destination folders.
///
/// Tokens: `{name}` (without extension), `{ext}`, `{kind}`, `{counter}`,
/// `{date:FORMAT}` / `{created:FORMAT}` / `{modified:FORMAT}` / `{added:FORMAT}` / `{taken:FORMAT}` (Unicode date
/// patterns), and `{date|created|modified|added|taken}.{year|month|day}`. `taken` is a photo's EXIF date. `date` is the moment the rule runs.
/// Unknown tokens are left untouched so mistakes stay visible in the preview.
public struct TokenRenderer: Sendable {
    public var now: Date
    public var timeZone: TimeZone

    public init(now: Date = Date(), timeZone: TimeZone = .current) {
        self.now = now
        self.timeZone = timeZone
    }

    private static let dateSources: Set<String> = ["date", "now", "created", "modified", "added", "taken"]

    public static func usesCounter(_ template: String) -> Bool {
        template.contains("{counter}")
    }

    public func render(_ template: String, facts: FileFacts, counter: Int = 1) -> String {
        var output = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            if character == "{", let close = template[index...].firstIndex(of: "}") {
                let token = String(template[template.index(after: index)..<close])
                output += value(for: token, facts: facts, counter: counter) ?? "{\(token)}"
                index = template.index(after: close)
            } else {
                output.append(character)
                index = template.index(after: index)
            }
        }
        return output
    }

    private func value(for token: String, facts: FileFacts, counter: Int) -> String? {
        switch token {
        case "name": return facts.baseName
        case "ext": return facts.fileExtension
        case "kind": return facts.kind.rawValue
        case "counter": return String(counter)
        default: break
        }
        if let colon = token.firstIndex(of: ":") {
            let source = String(token[..<colon])
            let format = String(token[token.index(after: colon)...])
            guard TokenRenderer.dateSources.contains(source), !format.isEmpty else { return nil }
            guard let date = date(named: source, facts: facts) else { return "unknown" }
            return formatted(date, format)
        }
        let parts = token.split(separator: ".").map(String.init)
        if parts.count == 2, let date = date(named: parts[0], facts: facts) {
            switch parts[1] {
            case "year": return formatted(date, "yyyy")
            case "month": return formatted(date, "MM")
            case "day": return formatted(date, "dd")
            case "monthname": return formatted(date, "MMMM")
            default: return nil
            }
        }
        return nil
    }

    private func date(named name: String, facts: FileFacts) -> Date? {
        switch name {
        case "date", "now": return now
        case "created": return facts.created ?? facts.modified
        case "modified": return facts.modified
        case "taken": return facts.taken ?? facts.created ?? facts.modified
        case "added": return facts.added ?? facts.created ?? facts.modified
        default: return nil
        }
    }

    private func formatted(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
