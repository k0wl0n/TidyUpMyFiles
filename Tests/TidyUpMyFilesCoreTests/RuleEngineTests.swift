import XCTest
@testable import TidyUpMyFilesCore

final class RuleEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00 UTC
    private var engine: RuleEngine { RuleEngine(now: now, timeZone: TimeZone(identifier: "UTC")!) }

    private func facts(_ name: String, size: Int64 = 1_000, addedDaysAgo: Double = 0, isDirectory: Bool = false,
                       tags: [String] = [], color: ColorLabel = .none, sources: [String] = []) -> FileFacts {
        let added = now.addingTimeInterval(-addedDaysAgo * 86_400)
        return FileFacts(url: URL(fileURLWithPath: "/tmp/inbox/\(name)"), isDirectory: isDirectory, size: size,
                         created: added, modified: added, added: added, tags: tags, colorLabel: color, sourceURLs: sources)
    }

    func testNameMatchesAreCaseInsensitiveByDefault() {
        let file = facts("Screenshot 2026-01-01 at 10.00.png")
        XCTAssertTrue(engine.evaluate(.name(TextMatch(startsWith: "screenshot")), file))
        XCTAssertTrue(engine.evaluate(.name(TextMatch(contains: "AT 10")), file))
        XCTAssertTrue(engine.evaluate(.name(TextMatch(endsWith: ".PNG")), file))
        XCTAssertFalse(engine.evaluate(.name(TextMatch(startsWith: "screenshot", caseSensitive: true)), file))
        XCTAssertTrue(engine.evaluate(.name(TextMatch(regex: #"^screenshot \d{4}"#)), file))
        XCTAssertFalse(engine.evaluate(.name(TextMatch(regex: "[")), file), "invalid regex never matches")
    }

    func testExtensionHandlesCompoundAndDots() {
        XCTAssertTrue(engine.evaluate(.fileExtension(["tar.gz"]), facts("backup.tar.gz")))
        XCTAssertTrue(engine.evaluate(.fileExtension([".DMG", "pkg"]), facts("Setup.dmg")))
        XCTAssertFalse(engine.evaluate(.fileExtension(["dmg"]), facts("notdmg")))
    }

    func testKinds() {
        XCTAssertEqual(facts("a.HEIC").kind, .image)
        XCTAssertEqual(facts("a.pdf").kind, .pdf)
        XCTAssertEqual(facts("a.tar.gz").kind, .archive)
        XCTAssertEqual(facts("a.pkg").kind, .installer)
        XCTAssertEqual(facts("a.docx").kind, .document)
        XCTAssertEqual(facts("budget.xlsx").kind, .spreadsheet)
        XCTAssertEqual(facts("deck.key").kind, .presentation)
        XCTAssertEqual(facts("data.json").kind, .code)
        XCTAssertEqual(facts("novel.epub").kind, .ebook)
        XCTAssertEqual(facts("Inter.otf").kind, .font)
        XCTAssertEqual(facts("a.mov").kind, .video)
        XCTAssertEqual(facts("a.flac").kind, .audio)
        XCTAssertEqual(facts("Stuff", isDirectory: true).kind, .folder)
        XCTAssertEqual(facts("unknown.xyz").kind, .other)
    }

    func testSizeAgeAndDates() {
        let big = facts("movie.mov", size: 50_000_000, addedDaysAgo: 10)
        XCTAssertTrue(engine.evaluate(.size(NumberMatch(greaterThan: 10_000_000)), big))
        XCTAssertFalse(engine.evaluate(.size(NumberMatch(lessThan: 10_000_000)), big))
        XCTAssertTrue(engine.evaluate(.ageDays(NumberMatch(greaterThan: 7)), big))
        XCTAssertFalse(engine.evaluate(.ageDays(NumberMatch(greaterThan: 30)), big))
        XCTAssertTrue(engine.evaluate(.added(DateMatch(olderThanDays: 7)), big))
        XCTAssertTrue(engine.evaluate(.created(DateMatch(before: "2025-12-31")), big))
        XCTAssertFalse(engine.evaluate(.modified(DateMatch(after: "2025-12-31")), big))
        XCTAssertTrue(engine.evaluate(.modified(DateMatch(newerThanDays: 11)), big))
    }

    func testTagsColorSourceAndFolder() {
        let file = facts("x.zip", isDirectory: false, tags: ["Work"], color: .red, sources: ["https://github.com/a/b.zip"])
        XCTAssertTrue(engine.evaluate(.tag(TagMatch(has: "work")), file))
        XCTAssertFalse(engine.evaluate(.tag(TagMatch(lacks: "Work")), file))
        XCTAssertTrue(engine.evaluate(.color(.red), file))
        XCTAssertTrue(engine.evaluate(.sourceURL(TextMatch(contains: "github.com")), file))
        XCTAssertFalse(engine.evaluate(.isFolder(true), file))
    }

    func testNestedAndOrNot() {
        // (image OR pdf) AND NOT name contains "keep"
        let condition = Condition.all([
            .any([.kind(.image), .kind(.pdf)]),
            .not(.name(TextMatch(contains: "keep"))),
        ])
        XCTAssertTrue(engine.evaluate(condition, facts("photo.jpg")))
        XCTAssertTrue(engine.evaluate(condition, facts("report.pdf")))
        XCTAssertFalse(engine.evaluate(condition, facts("keep-photo.jpg")))
        XCTAssertFalse(engine.evaluate(condition, facts("song.mp3")))
        XCTAssertTrue(engine.evaluate(.all([]), facts("anything")), "empty AND matches everything")
        XCTAssertFalse(engine.evaluate(.any([]), facts("anything")), "empty OR matches nothing")
    }

    func testFirstMatchStopsUnlessContinueMatching() {
        let tagRule = Rule(name: "Tag", continueMatching: true, condition: .kind(.image), actions: [.addTags(["Seen"])])
        let imageRule = Rule(name: "Images", condition: .kind(.image), actions: [.move(destination: "~/Pictures", createFolders: true, onConflict: .rename)])
        let laterRule = Rule(name: "Later", condition: .kind(.image), actions: [.trash])
        let disabled = Rule(name: "Off", enabled: false, condition: .kind(.image), actions: [.trash])

        let matched = engine.matchingRules([disabled, tagRule, imageRule, laterRule], for: self.facts("a.png"))
        XCTAssertEqual(matched.map(\.name), ["Tag", "Images"])
    }

    func testPlanResolvesRelativeFoldersAndChainsActions() {
        let rule = Rule(name: "Chain", condition: .kind(.pdf), actions: [
            .rename(pattern: "{added:yyyy-MM-dd} {name}.{ext}", onConflict: .rename),
            .move(destination: "PDF/{added.year}", createFolders: true, onConflict: .rename),
        ])
        let steps = engine.plan(rule, facts: facts("invoice.pdf", addedDaysAgo: 1))
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].target?.path, "/tmp/inbox/2025-12-31 invoice.pdf")
        XCTAssertEqual(steps[1].source.path, "/tmp/inbox/2025-12-31 invoice.pdf")
        XCTAssertEqual(steps[1].target?.path, "/tmp/inbox/PDF/2025/2025-12-31 invoice.pdf")
    }

    func testPlanStopsAfterTrash() {
        let rule = Rule(name: "Bin", condition: .all([]), actions: [.trash, .open])
        XCTAssertEqual(engine.plan(rule, facts: facts("old.dmg")).map(\.action), [.trash])
    }
}

final class TokenRendererTests: XCTestCase {
    private let renderer = TokenRenderer(now: Date(timeIntervalSince1970: 1_767_225_600), timeZone: TimeZone(identifier: "UTC")!)

    private let file = FileFacts(url: URL(fileURLWithPath: "/tmp/Report Final.pdf"),
                                 created: Date(timeIntervalSince1970: 1_700_000_000), // 2023-11-14
                                 modified: Date(timeIntervalSince1970: 1_710_000_000), // 2024-03-09
                                 added: Date(timeIntervalSince1970: 1_720_000_000)) // 2024-07-03

    func testBasicTokens() {
        XCTAssertEqual(renderer.render("{name}.{ext}", facts: file), "Report Final.pdf")
        XCTAssertEqual(renderer.render("{kind}/{name}", facts: file), "pdf/Report Final")
        XCTAssertEqual(renderer.render("{name} {counter}", facts: file, counter: 3), "Report Final 3")
    }

    func testDateTokens() {
        XCTAssertEqual(renderer.render("{date:yyyy-MM-dd}", facts: file), "2026-01-01")
        XCTAssertEqual(renderer.render("{created:yyyy}", facts: file), "2023")
        XCTAssertEqual(renderer.render("{modified:MM}", facts: file), "03")
        XCTAssertEqual(renderer.render("~/Pictures/Screenshots/{added.year}-{added.month}", facts: file),
                       "~/Pictures/Screenshots/2024-07")
        XCTAssertEqual(renderer.render("{added.day}", facts: file), "03")
    }

    func testUnknownTokensStayVisible() {
        XCTAssertEqual(renderer.render("{nope} {added.century} {foo:bar}", facts: file), "{nope} {added.century} {foo:bar}")
        XCTAssertEqual(renderer.render("{unclosed", facts: file), "{unclosed")
    }

    func testAddedFallsBackToCreated() {
        var noAdded = file
        noAdded.added = nil
        XCTAssertEqual(renderer.render("{added.year}", facts: noAdded), "2023")
    }

    func testSanitizeAndNumbering() {
        XCTAssertEqual(PathTools.sanitizeFileName("a/b:c. "), "a-b-c")
        XCTAssertEqual(PathTools.sanitizeFileName(""), "untitled")
        XCTAssertEqual(PathTools.numbered("photo.jpg", 2), "photo 2.jpg")
        XCTAssertEqual(PathTools.numbered("README", 3), "README 3")
    }
}

final class SafetyGuardTests: XCTestCase {
    func testRefusesProtectedPlaces() {
        let guardrail = SafetyGuard(homeDirectory: "/Users/someone")
        XCTAssertFalse(guardrail.isAllowed(URL(fileURLWithPath: "/System/Library/x")))
        XCTAssertFalse(guardrail.isAllowed(URL(fileURLWithPath: "/Users/someone/Library/Preferences/x.plist")))
        XCTAssertFalse(guardrail.isAllowed(URL(fileURLWithPath: "/Users/someone/code/.git/config")))
        XCTAssertFalse(guardrail.isAllowed(URL(fileURLWithPath: "/Users/someone/Downloads/Tool.app")))
        XCTAssertFalse(guardrail.isAllowed(URL(fileURLWithPath: "/Users/someone/Downloads/Tool.app/Contents/Info.plist")))
        XCTAssertTrue(guardrail.isAllowed(URL(fileURLWithPath: "/Users/someone/Downloads/report.pdf")))
        XCTAssertTrue(guardrail.isAllowed(URL(fileURLWithPath: "/Users/someone/LibraryBooks/a.pdf")))
    }
}

final class RulesYAMLTests: XCTestCase {
    func testRoundTripKeepsEverything() throws {
        let rule = Rule(name: "Everything", enabled: false, mode: .live, continueMatching: true, allowOverwrite: true,
                        condition: .all([
                            .any([.name(TextMatch(startsWith: "Screen", regex: "\\d")), .fileExtension(["png", "tar.gz"])]),
                            .not(.kind(.video)),
                            .size(NumberMatch(greaterThan: 1_000, lessThan: 2.5e9)),
                            .added(DateMatch(olderThanDays: 7)),
                            .created(DateMatch(before: "2025-01-01")),
                            .modified(DateMatch(after: "2024-01-01")),
                            .ageDays(NumberMatch(atLeast: 30)),
                            .tag(TagMatch(has: "Work", lacks: "Keep")),
                            .color(.orange),
                            .sourceURL(TextMatch(contains: "github")),
                            .isFolder(false),
                        ]),
                        actions: [
                            .rename(pattern: "{date:yyyy-MM-dd} {name}.{ext}", onConflict: .skip),
                            .move(destination: "~/Archive/{added.year}", createFolders: false, onConflict: .overwrite),
                            .copy(destination: "/tmp/backup", createFolders: true, onConflict: .rename),
                            .addTags(["Sorted"]), .removeTags(["Inbox"]), .setColor(.green),
                            .open, .shell(script: "echo \"$TIDYUP_FILE\""), .trash,
                        ])
        let config = RulesConfig(folders: [WatchedFolder(path: "~/Downloads", includeSubfolders: true, rules: [rule])])
        let text = try RulesYAML.encode(config)
        let decoded = try RulesYAML.decode(text)

        XCTAssertEqual(decoded.folders.count, 1)
        XCTAssertEqual(decoded.folders[0].path, "~/Downloads")
        XCTAssertTrue(decoded.folders[0].includeSubfolders)
        var decodedRule = decoded.folders[0].rules[0]
        decodedRule.id = rule.id
        XCTAssertEqual(decodedRule, rule)
    }

    func testReadsHandWrittenShorthand() throws {
        let yaml = """
        version: 1
        folders:
          - path: ~/Desktop
            rules:
              - name: Screenshots
                when:
                  all:
                    - name: { starts_with: "Screenshot" }
                    - kind: image
                    - size: { lt: "20 MB" }
                    - tag: Work
                do:
                  - move: "~/Pictures/Screenshots/{added.year}-{added.month}"
                  - set_color: 4
        """
        let config = try RulesYAML.decode(yaml)
        let rule = try XCTUnwrap(config.folders.first?.rules.first)
        XCTAssertEqual(rule.mode, .preview, "rules default to preview")
        XCTAssertTrue(rule.enabled)
        XCTAssertEqual(rule.condition, .all([
            .name(TextMatch(startsWith: "Screenshot")), .kind(.image),
            .size(NumberMatch(lessThan: 20_000_000)), .tag(TagMatch(has: "Work")),
        ]))
        XCTAssertEqual(rule.actions, [
            .move(destination: "~/Pictures/Screenshots/{added.year}-{added.month}", createFolders: true, onConflict: .rename),
            .setColor(.blue),
        ])
    }

    func testRejectsUnknownKeys() {
        let yaml = """
        folders:
          - path: /tmp
            rules:
              - name: Bad
                when: { colour: red }
                do: [ { trash: true } ]
        """
        XCTAssertThrowsError(try RulesYAML.decode(yaml))
    }
}
