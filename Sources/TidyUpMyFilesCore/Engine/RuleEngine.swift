import Foundation

/// One action of a rule, resolved for a specific file but not yet run.
public struct PlannedStep: Equatable, Sendable {
    public var action: Action
    /// Where the file is when this step starts.
    public var source: URL
    /// Proposed new location for move, copy and rename (before name conflicts are resolved).
    public var target: URL?

    public init(action: Action, source: URL, target: URL?) {
        self.action = action
        self.source = source
        self.target = target
    }

    public var summary: String {
        let targetText = target.map { PathTools.abbreviate($0.path) } ?? ""
        switch action {
        case .move: return "Move to \(targetText)"
        case .copy: return "Copy to \(targetText)"
        case .rename: return "Rename to \(target?.lastPathComponent ?? "")"
        case .addTags(let tags): return "Add tags \(tags.joined(separator: ", "))"
        case .removeTags(let tags): return "Remove tags \(tags.joined(separator: ", "))"
        case .setColor(let label): return "Set color label \(label.name)"
        case .trash: return "Move to Trash"
        case .open: return "Open"
        case .shell: return "Run shell script"
        case .archive: return "Zip to \(targetText)"
        case .extract: return "Extract to \(targetText)"
        case .makeAlias: return "Make an alias in \(target.map { PathTools.abbreviate($0.deletingLastPathComponent().path) } ?? "")"
        case .runShortcut(let name): return "Run Shortcut \u{201C}\(name)\u{201D}"
        }
    }
}

public struct RuleMatch: Equatable, Sendable {
    public var rule: Rule
    public var steps: [PlannedStep]
}

/// Pure decision logic: which rules match a file and what they would do. No file system access.
public struct RuleEngine: Sendable {
    public var now: Date
    public var renderer: TokenRenderer

    public init(now: Date = Date(), timeZone: TimeZone = .current) {
        self.now = now
        self.renderer = TokenRenderer(now: now, timeZone: timeZone)
    }

    public func evaluate(_ condition: Condition, _ facts: FileFacts) -> Bool {
        switch condition {
        case .all(let list): return list.allSatisfy { evaluate($0, facts) }
        case .any(let list): return list.contains { evaluate($0, facts) }
        case .not(let inner): return !evaluate(inner, facts)
        case .name(let match): return match.matches(facts.fileName)
        case .fileExtension(let extensions):
            let name = facts.fileName.lowercased()
            return extensions.contains { ext in
                let cleaned = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                return !cleaned.isEmpty && name.hasSuffix("." + cleaned)
            }
        case .kind(let kind): return facts.kind == kind
        case .size(let match): return match.matches(Double(facts.size))
        case .created(let match): return match.matches(facts.created, now: now)
        case .modified(let match): return match.matches(facts.modified, now: now)
        case .added(let match): return match.matches(facts.added ?? facts.created, now: now)
        case .ageDays(let match):
            guard let reference = facts.ageReferenceDate else { return false }
            return match.matches(now.timeIntervalSince(reference) / 86_400)
        case .tag(let match): return match.matches(facts.tags)
        case .color(let label): return facts.colorLabel == label
        case .sourceURL(let match): return facts.sourceURLs.contains { match.matches($0) }
        case .isFolder(let expected): return facts.isDirectory == expected
        case .duplicate(let expected): return (facts.duplicateOf != nil) == expected
        case .contents(let match): return facts.textContent.map(match.matches) ?? false
        case .taken(let match): return match.matches(facts.taken ?? facts.created, now: now)
        case .lastOpened(let match): return match.matches(facts.lastOpened, now: now)
        case .isEmpty(let expected): return facts.isEmpty == expected
        }
    }

    /// Enabled rules that match, in order. Stops after the first match unless that rule says `continue_matching`.
    public func matchingRules(_ rules: [Rule], for facts: FileFacts) -> [Rule] {
        var matched: [Rule] = []
        for rule in rules where rule.enabled && evaluate(rule.condition, facts) {
            matched.append(rule)
            if !rule.continueMatching { break }
        }
        return matched
    }

    public func matches(_ rules: [Rule], for facts: FileFacts) -> [RuleMatch] {
        var current = facts
        var result: [RuleMatch] = []
        for rule in matchingRules(rules, for: facts) {
            let steps = plan(rule, facts: current)
            result.append(RuleMatch(rule: rule, steps: steps))
            if let last = steps.last(where: { $0.action.verb == "move" || $0.action.verb == "rename" }), let target = last.target {
                current.url = target
            }
            if steps.contains(where: { $0.action == .trash }) { break }
        }
        return result
    }

    /// Resolves one action for a file. `counter` fills `{counter}` in rename patterns.
    public func step(for action: Action, facts: FileFacts, counter: Int = 1) -> PlannedStep {
        var step = PlannedStep(action: action, source: facts.url, target: nil)
        switch action {
        case .move(let destination, _, _), .copy(let destination, _, _):
            let folder = PathTools.resolveFolder(renderer.render(destination, facts: facts, counter: counter),
                                                 relativeTo: facts.url.deletingLastPathComponent())
            step.target = folder.appendingPathComponent(facts.fileName)
        case .rename(let pattern, _):
            let newName = PathTools.sanitizeFileName(renderer.render(pattern, facts: facts, counter: counter))
            step.target = facts.url.deletingLastPathComponent().appendingPathComponent(newName)
        case .archive(let destination, _):
            let folder = PathTools.resolveFolder(renderer.render(destination, facts: facts, counter: counter),
                                                 relativeTo: facts.url.deletingLastPathComponent())
            step.target = folder.appendingPathComponent(facts.fileName + ".zip")
        case .extract(let destination, _):
            let folder = PathTools.resolveFolder(renderer.render(destination, facts: facts, counter: counter),
                                                 relativeTo: facts.url.deletingLastPathComponent())
            step.target = folder.appendingPathComponent(PathTools.archiveBaseName(facts.fileName))
        case .makeAlias(let destination):
            let folder = PathTools.resolveFolder(renderer.render(destination, facts: facts, counter: counter),
                                                 relativeTo: facts.url.deletingLastPathComponent())
            step.target = folder.appendingPathComponent(facts.fileName + " alias")
        default:
            break
        }
        return step
    }

    public func plan(_ rule: Rule, facts: FileFacts) -> [PlannedStep] {
        var current = facts
        var steps: [PlannedStep] = []
        for action in rule.actions {
            let step = step(for: action, facts: current)
            switch action {
            case .move, .rename:
                if let target = step.target { current.url = target }
            case .copy, .archive, .extract, .makeAlias, .runShortcut:
                break
            case .addTags(let tags):
                current.tags = Array(Set(current.tags).union(tags)).sorted()
            case .removeTags(let tags):
                let removed = Set(tags.map { $0.lowercased() })
                current.tags.removeAll { removed.contains($0.lowercased()) }
            case .setColor(let label):
                current.colorLabel = label
            case .trash, .open, .shell:
                break
            }
            steps.append(step)
            if action == .trash { break }
        }
        return steps
    }
}

extension PathTools {
    public static func abbreviate(_ path: String) -> String {
        var path = path
        // macOS shows /tmp and /var; /private/... is the same place.
        for alias in ["/private/tmp", "/private/var"] where path == alias || path.hasPrefix(alias + "/") {
            path.removeFirst("/private".count)
        }
        let home = homeDirectory
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

extension PathTools {
    /// Archive extensions `extract` understands, longest first.
    public static let extractableExtensions = [".tar.gz", ".tar.bz2", ".tar.xz", ".tgz", ".tbz", ".txz", ".tar", ".zip"]

    /// "project-backup.tar.gz" → "project-backup" (the folder an archive is unpacked into).
    public static func archiveBaseName(_ fileName: String) -> String {
        let lower = fileName.lowercased()
        for ext in extractableExtensions where lower.hasSuffix(ext) && lower.count > ext.count {
            return String(fileName.dropLast(ext.count))
        }
        return (fileName as NSString).deletingPathExtension
    }
}
