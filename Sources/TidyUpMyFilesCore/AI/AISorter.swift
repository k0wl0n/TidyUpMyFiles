import Foundation

/// What the model is told about one file. Contents are included only for folders the person opted in.
public struct AIFileInput: Codable, Equatable, Sendable {
    public var name: String
    public var `extension`: String
    public var kind: String
    public var sizeBytes: Int64
    public var created: String?
    public var modified: String?
    public var added: String?
    public var downloadedFrom: String?
    public var contentExcerpt: String?
}

public struct AISuggestion: Codable, Equatable, Sendable {
    public var file: String
    public var category: String
    public var destination: String?
    public var newName: String?

    public init(file: String, category: String, destination: String?, newName: String?) {
        self.file = file
        self.category = category
        self.destination = destination
        self.newName = newName
    }

    enum CodingKeys: String, CodingKey {
        case file, category, destination
        case newName = "new_name"
    }
}

/// A suggestion tied to a real file, ready for the preview screen.
public struct AISuggestionItem: Identifiable, Equatable, Sendable {
    public var suggestion: AISuggestion
    public var file: URL
    public var folderPath: String
    /// A one-off rule that performs the suggestion; it runs only after the person approves.
    public var rule: Rule
    public var steps: [PlannedStep]

    public var id: String { file.path }
    public var summary: String { steps.map(\.summary).joined(separator: ", then ") }
}

public struct AISorter: Sendable {
    public var provider: any AIProvider
    public var settings: AISettings
    public var guardrail: SafetyGuard

    public init(provider: any AIProvider, settings: AISettings, guardrail: SafetyGuard = SafetyGuard()) {
        self.provider = provider
        self.settings = settings
        self.guardrail = guardrail
    }

    static let systemPrompt = """
        You help tidy a Mac's folders. For each file, suggest a short category, a destination folder \
        (an absolute path or one starting with ~/) and optionally a clearer file name that keeps the extension. \
        Reply with JSON only: {"suggestions":[{"file":"<exact name>","category":"...","destination":"~/...","new_name":"..."}]}. \
        Leave out files you are unsure about. Never suggest paths inside ~/Library, system folders or app bundles.
        """

    private static let textExtensions: Set<String> = ["txt", "md", "csv", "json", "xml", "html", "yaml", "yml", "log", "rtf", "tex"]

    public func isAllowed(_ folder: WatchedFolder) -> Bool {
        let path = PathTools.canonical(folder.url)
        return settings.allowedFolders.contains { PathTools.canonical(URL(fileURLWithPath: PathTools.expandTilde($0))) == path }
    }

    private func mayReadContents(_ folder: WatchedFolder) -> Bool {
        let path = PathTools.canonical(folder.url)
        return settings.readContentsFolders.contains { PathTools.canonical(URL(fileURLWithPath: PathTools.expandTilde($0))) == path }
    }

    public func inputs(for facts: [FileFacts], in folder: WatchedFolder) -> [AIFileInput] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let includeContents = mayReadContents(folder)
        return facts.map { file in
            var excerpt: String?
            if includeContents, !file.isDirectory, AISorter.textExtensions.contains(file.fileExtension.lowercased()),
               let handle = try? FileHandle(forReadingFrom: file.url) {
                excerpt = String(decoding: handle.readData(ofLength: 2_000), as: UTF8.self)
                try? handle.close()
            }
            return AIFileInput(name: file.fileName, extension: file.fileExtension, kind: file.kind.rawValue, sizeBytes: file.size,
                               created: file.created.map(formatter.string), modified: file.modified.map(formatter.string),
                               added: file.added.map(formatter.string), downloadedFrom: file.sourceURLs.first,
                               contentExcerpt: excerpt)
        }
    }

    public static func parse(_ reply: String) throws -> [AISuggestion] {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}") else { throw AIError.unexpectedReply(reply) }
        struct Envelope: Decodable { var suggestions: [AISuggestion] }
        do {
            return try JSONDecoder().decode(Envelope.self, from: Data(reply[start...end].utf8)).suggestions
        } catch {
            throw AIError.unexpectedReply(reply)
        }
    }

    /// Asks the model about up to `limit` items in an allowed folder. Nothing is changed here.
    public func suggest(for folder: WatchedFolder, items: [URL], limit: Int = 40) async throws -> [AISuggestionItem] {
        guard isAllowed(folder) else { return [] }
        // Files only: moving whole folders (often your own project or destination folders) is never suggested.
        let facts = items.compactMap { try? FileFactsReader.read($0, needs: []) }.filter { !$0.isDirectory }.prefix(limit).map { $0 }
        guard !facts.isEmpty else { return [] }
        let payload = try JSONEncoder().encode(["files": inputs(for: facts, in: folder)])
        let reply = try await provider.complete(system: AISorter.systemPrompt, user: String(decoding: payload, as: UTF8.self))
        return self.items(from: try AISorter.parse(reply), facts: facts, folder: folder)
    }

    public func items(from suggestions: [AISuggestion], facts: [FileFacts], folder: WatchedFolder) -> [AISuggestionItem] {
        let engine = RuleEngine()
        var result: [AISuggestionItem] = []
        for suggestion in suggestions {
            guard let file = facts.first(where: { $0.fileName == suggestion.file }), !file.isDirectory else { continue }
            var actions: [Action] = []
            if let newName = suggestion.newName?.trimmingCharacters(in: .whitespaces), !newName.isEmpty, newName != file.fileName {
                actions.append(.rename(pattern: PathTools.sanitizeFileName(newName), onConflict: .rename))
            }
            if let destination = suggestion.destination?.trimmingCharacters(in: .whitespaces), !destination.isEmpty {
                let resolved = PathTools.resolveFolder(destination, relativeTo: folder.url)
                guard guardrail.isAllowed(resolved), !PathTools.isInside(resolved, folder: file.url),
                      PathTools.canonical(resolved) != PathTools.canonical(file.url) else { continue }
                // Already where the AI suggests: nothing to move.
                if PathTools.canonical(resolved) == PathTools.canonical(file.url.deletingLastPathComponent()) && actions.isEmpty { continue }
                actions.append(.move(destination: destination, createFolders: true, onConflict: .rename))
            }
            guard !actions.isEmpty else { continue }
            let rule = Rule(name: "AI: \(suggestion.category)", mode: .preview,
                            condition: .name(TextMatch(equals: file.fileName)), actions: actions)
            result.append(AISuggestionItem(suggestion: suggestion, file: file.url, folderPath: folder.path, rule: rule,
                                           steps: engine.plan(rule, facts: file)))
        }
        return result
    }

    /// Turns a suggestion into a lasting rule: same extension goes to the same place. Starts in preview mode.
    public static func permanentRule(from item: AISuggestionItem) -> Rule {
        let ext = item.file.pathExtension
        let condition: Condition = ext.isEmpty ? .name(TextMatch(equals: item.file.lastPathComponent)) : .fileExtension([ext])
        let moves = item.rule.actions.filter { $0.verb == "move" }
        return Rule(name: item.suggestion.category, mode: .preview, condition: condition,
                    actions: moves.isEmpty ? item.rule.actions : moves)
    }
}
