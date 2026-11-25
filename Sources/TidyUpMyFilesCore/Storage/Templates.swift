import Foundation

/// Ready-made rules. Each starts in preview mode, like every new rule.
public enum Templates {
    public struct Template: Identifiable, Sendable {
        public var id: String
        public var title: String
        public var detail: String
        public var folderPath: String
        public var rule: Rule
    }

    public static var all: [Template] {
        catalog.map { template in
            var tagged = template
            tagged.rule.templateID = template.id
            return tagged
        }
    }

    /// A Downloads rule that sends one kind of file to its own folder.
    private static func sortByKind(_ id: String, _ title: String, _ kind: FileKind, to destination: String) -> Template {
        Template(id: id, title: title,
                 detail: "\(kind.title) files in Downloads → \(destination)",
                 folderPath: "~/Downloads",
                 rule: Rule(name: title, condition: .kind(kind),
                            actions: [.move(destination: destination, createFolders: true, onConflict: .rename)]))
    }

    /// In priority order: rules higher up win when several match, so duplicates go before anything is
    /// sorted by kind, and the dated archive only catches what nothing else recognised.
    private static var catalog: [Template] {
        [
            Template(id: "duplicates", title: "Duplicate downloads",
                     detail: "Exact copies of a file already in Downloads → Trash (the earliest copy stays)",
                     folderPath: "~/Downloads",
                     rule: Rule(name: "Duplicate downloads",
                                condition: .all([.duplicate(true), .isFolder(false)]),
                                actions: [.trash])),
            Template(id: "screenshots", title: "Screenshots",
                     detail: "Screenshots in \(ScreenshotLocation.folderPath) (where your Mac saves them) → ~/Pictures/Screenshots/year-month",
                     folderPath: ScreenshotLocation.folderPath,
                     rule: Rule(name: "Screenshots",
                                condition: .all([
                                    .any([.name(TextMatch(startsWith: "Screenshot")), .name(TextMatch(startsWith: "Screen Shot"))]),
                                    .kind(.image),
                                ]),
                                actions: [.move(destination: "~/Pictures/Screenshots/{added.year}-{added.month}",
                                                createFolders: true, onConflict: .rename)])),
            Template(id: "old-installers", title: "Old installers",
                     detail: ".dmg and .pkg in Downloads older than 7 days → Trash",
                     folderPath: "~/Downloads",
                     rule: Rule(name: "Old installers",
                                condition: .all([.fileExtension(["dmg", "pkg"]), .ageDays(NumberMatch(greaterThan: 7))]),
                                actions: [.trash])),
            Template(id: "images", title: "Images",
                     detail: "Images in Downloads → ~/Pictures/Downloads",
                     folderPath: "~/Downloads",
                     rule: Rule(name: "Images", condition: .kind(.image),
                                actions: [.move(destination: "~/Pictures/Downloads", createFolders: true, onConflict: .rename)])),
            Template(id: "pdf", title: "PDF files",
                     detail: "PDFs in Downloads → ~/Documents/PDF",
                     folderPath: "~/Downloads",
                     rule: Rule(name: "PDF files", condition: .kind(.pdf),
                                actions: [.move(destination: "~/Documents/PDF", createFolders: true, onConflict: .rename)])),
            sortByKind("documents", "Word & text documents", .document, to: "~/Documents/Docs"),
            sortByKind("spreadsheets", "Spreadsheets", .spreadsheet, to: "~/Documents/Spreadsheets"),
            sortByKind("presentations", "Presentations", .presentation, to: "~/Documents/Presentations"),
            sortByKind("videos", "Videos", .video, to: "~/Movies/Downloads"),
            sortByKind("audio", "Music & audio", .audio, to: "~/Music/Downloads"),
            sortByKind("code", "Code & data files", .code, to: "~/Documents/Code & Data"),
            sortByKind("ebooks", "E-books", .ebook, to: "~/Documents/Books"),
            sortByKind("fonts", "Fonts", .font, to: "~/Documents/Fonts"),
            Template(id: "archives", title: "Archives",
                     detail: ".zip, .tar.gz and .7z in Downloads → ~/Downloads/Archives",
                     folderPath: "~/Downloads",
                     rule: Rule(name: "Archives",
                                condition: .all([.fileExtension(["zip", "tar.gz", "tgz", "7z"]), .isFolder(false)]),
                                actions: [.move(destination: "~/Downloads/Archives", createFolders: true, onConflict: .rename)])),
            Template(id: "old-downloads", title: "Everything else, after 30 days",
                     detail: "Files nothing above recognises, older than 30 days → ~/Archive/Downloads/year-month",
                     folderPath: "~/Downloads",
                     rule: Rule(name: "Old downloads",
                                condition: .all([.isFolder(false), .ageDays(NumberMatch(greaterThan: 30))]),
                                actions: [.move(destination: "~/Archive/Downloads/{added.year}-{added.month}",
                                                createFolders: true, onConflict: .rename)])),
        ]
    }

    private static func folderIndex(for template: Template, in config: RulesConfig) -> Int? {
        folderIndex(path: template.folderPath, in: config)
    }

    private static func folderIndex(path folderPath: String, in config: RulesConfig) -> Int? {
        let path = PathTools.canonical(URL(fileURLWithPath: PathTools.expandTilde(folderPath)))
        return config.folders.firstIndex { PathTools.canonical($0.url) == path }
    }

    /// Rules added before rules remembered their template: same name, conditions and actions as a template
    /// in the template's folder get its id back, so "Turn Them On" and upgrades include them.
    /// The person's on/off and preview/live choices are kept. Returns how many were recognised.
    @discardableResult
    public static func adoptLegacyRules(in config: inout RulesConfig) -> Int {
        var adopted = 0
        for template in all {
            guard let folder = folderIndex(for: template, in: config) else { continue }
            for index in config.folders[folder].rules.indices {
                let rule = config.folders[folder].rules[index]
                guard rule.templateID == nil, rule.name == template.rule.name, rule.condition == template.rule.condition,
                      rule.actions == template.rule.actions || (previousVersions[template.id] ?? []).contains(rule.actions)
                else { continue }
                config.folders[folder].rules[index].templateID = template.id
                adopted += 1
            }
        }
        return adopted
    }

    /// True when the template's rule is already in its folder — or in `folderPath` when given
    /// (by template id, or an identical rule).
    public static func isInstalled(_ template: Template, in config: RulesConfig, folderPath: String? = nil) -> Bool {
        guard let index = folderIndex(path: folderPath ?? template.folderPath, in: config) else { return false }
        return config.folders[index].rules.contains { rule in
            rule.templateID == template.id || rule.isSameRule(as: template.rule)
        }
    }

    /// Adds a template's rule to its folder (creating the folder entry if needed), once.
    /// Rules keep the catalog's priority order. Returns false if it was already there.
    @discardableResult
    public static func install(_ template: Template, into config: inout RulesConfig, folderPath: String? = nil) -> Bool {
        let target = folderPath ?? template.folderPath
        guard !isInstalled(template, in: config, folderPath: target) else { return false }
        var rule = template.rule
        rule.id = UUID()
        let index: Int
        if let existing = folderIndex(path: target, in: config) {
            index = existing
        } else {
            config.folders.append(WatchedFolder(path: target))
            index = config.folders.count - 1
        }
        var rules = config.folders[index].rules
        // Keep ready-made rules in catalog order: insert before the first one that comes later.
        let order = catalog.map(\.id)
        let myPosition = order.firstIndex(of: template.id) ?? order.count
        let laterRule = rules.firstIndex { existing in
            guard let id = existing.templateID, let position = order.firstIndex(of: id) else { return false }
            return position > myPosition
        }
        if let laterRule {
            rules.insert(rule, at: laterRule)
        } else {
            rules.append(rule)
        }
        config.folders[index].rules = rules
        return true
    }

    /// Earlier versions of ready-made rules, by template id. A rule still exactly like one of these was never
    /// edited by the person, so it can safely take the current version.
    private static let previousVersions: [String: [[Action]]] = [
        "old-downloads": [[.move(destination: "~/Archive/Downloads/{added.year}", createFolders: true, onConflict: .rename)]],
    ]

    /// Brings untouched ready-made rules up to date (keeping their on/off and preview/live choice).
    /// Returns the titles of the rules that changed.
    @discardableResult
    public static func upgradeUntouched(in config: inout RulesConfig) -> [String] {
        var upgraded: [String] = []
        for folder in config.folders.indices {
            for index in config.folders[folder].rules.indices {
                let rule = config.folders[folder].rules[index]
                guard let id = rule.templateID, let old = previousVersions[id], old.contains(rule.actions),
                      let current = all.first(where: { $0.id == id }) else { continue }
                config.folders[folder].rules[index].actions = current.rule.actions
                config.folders[folder].rules[index].condition = current.rule.condition
                upgraded.append(current.title)
            }
        }
        return upgraded
    }

    /// Adds every recommended rule that isn't there yet. Returns how many were added.
    @discardableResult
    public static func installRecommended(into config: inout RulesConfig) -> Int {
        all.filter { install($0, into: &config) }.count
    }

    /// Recommended rules that exist but still only preview.
    public static func recommendedInPreview(_ config: RulesConfig) -> Int {
        config.folders.flatMap(\.rules).filter { $0.templateID != nil && $0.enabled && $0.mode == .preview }.count
    }

    /// Turns every enabled recommended rule live. Returns how many changed.
    @discardableResult
    public static func makeRecommendedLive(in config: inout RulesConfig) -> Int {
        var changed = 0
        for folder in config.folders.indices {
            for rule in config.folders[folder].rules.indices {
                let current = config.folders[folder].rules[rule]
                guard current.templateID != nil, current.enabled, current.mode == .preview else { continue }
                config.folders[folder].rules[rule].mode = .live
                changed += 1
            }
        }
        return changed
    }
}

/// Where macOS saves new screenshots: the "Save to" choice in the Screenshot app (⇧⌘5), stored by macOS
/// as `com.apple.screencapture location`. The Desktop when it was never changed.
public enum ScreenshotLocation {
    public static var folderPath: String {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["TIDYUP_SCREENSHOT_FOLDER"], !override.isEmpty { return override }
        let desktop = "~/Desktop"
        guard !PathTools.isDemoHome,
              let saved = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
              !saved.isEmpty else { return desktop }
        let url = URL(fileURLWithPath: (saved as NSString).expandingTildeInPath).standardizedFileURL
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else { return desktop }
        return PathTools.abbreviate(url.path)
    }
}
