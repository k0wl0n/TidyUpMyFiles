import XCTest
@testable import TidyUpMyFilesCore

/// Template tests expect macOS's default screenshot folder, whatever this Mac is set to.
private func pinScreenshotFolder() { setenv("TIDYUP_SCREENSHOT_FOLDER", "~/Desktop", 1) }

final class TemplateTests: XCTestCase {
    override func setUp() { pinScreenshotFolder() }

    private var screenshots: Templates.Template { Templates.all.first { $0.id == "screenshots" }! }

    func testAddingATemplateTwiceAddsItOnce() {
        var config = RulesConfig()
        XCTAssertTrue(Templates.install(screenshots, into: &config))
        XCTAssertFalse(Templates.install(screenshots, into: &config))
        XCTAssertFalse(Templates.install(screenshots, into: &config))
        XCTAssertEqual(config.folders.flatMap(\.rules).count, 1)
        XCTAssertTrue(Templates.isInstalled(screenshots, in: config))
    }

    func testOlderCopiesWithoutTemplateIDStillCount() {
        var rule = screenshots.rule
        rule.templateID = nil
        var config = RulesConfig(folders: [WatchedFolder(path: "~/Desktop", rules: [rule])])
        XCTAssertTrue(Templates.isInstalled(screenshots, in: config))
        XCTAssertFalse(Templates.install(screenshots, into: &config))
    }

    func testRecommendedSetInstallsEverythingOnceWithCatchAllLast() {
        var config = RulesConfig()
        XCTAssertEqual(Templates.installRecommended(into: &config), Templates.all.count)
        XCTAssertEqual(Templates.installRecommended(into: &config), 0)
        let downloads = config.folders.first { $0.path == "~/Downloads" }!
        XCTAssertEqual(downloads.rules.last?.templateID, "old-downloads")
        XCTAssertTrue(config.folders.flatMap(\.rules).allSatisfy { $0.mode == .preview })

        XCTAssertEqual(Templates.recommendedInPreview(config), Templates.all.count)
        XCTAssertEqual(Templates.makeRecommendedLive(in: &config), Templates.all.count)
        XCTAssertEqual(Templates.recommendedInPreview(config), 0)
    }

    func testDuplicateRulesAndFoldersAreCleanedUp() {
        var copy = screenshots.rule
        copy.templateID = nil
        let custom = Rule(name: "Mine", condition: .kind(.pdf), actions: [.trash])
        var config = RulesConfig(folders: [
            WatchedFolder(path: "~/Desktop", rules: [screenshots.rule, screenshots.rule, copy, custom]),
            WatchedFolder(path: "~/Desktop", rules: [screenshots.rule, custom]),
        ])
        let removed = config.removeDuplicates()
        XCTAssertEqual(removed.folders, 1)
        XCTAssertEqual(removed.rules, 4)
        XCTAssertEqual(config.folders.count, 1)
        XCTAssertEqual(config.folders[0].rules.map(\.name), ["Screenshots", "Mine"])
    }

    func testTemplateIDSurvivesYAML() throws {
        var config = RulesConfig()
        Templates.install(screenshots, into: &config)
        let decoded = try RulesYAML.decode(try RulesYAML.encode(config))
        XCTAssertEqual(decoded.folders.first?.rules.first?.templateID, "screenshots")
    }
}

/// The recommended Downloads rules applied to a sandbox folder: each kind of file goes somewhere meaningful,
/// and only unrecognised old files reach the dated archive.
final class RecommendedRoutingTests: SandboxTestCase {
    override func setUpWithError() throws {
        pinScreenshotFolder()
        try super.setUpWithError()
    }

    func testEachKindHasItsOwnHome() throws {
        var config = RulesConfig()
        Templates.installRecommended(into: &config)
        let downloads = try XCTUnwrap(config.folders.first { $0.path == "~/Downloads" })
        XCTAssertEqual(downloads.rules.first?.templateID, "duplicates", "duplicates are handled before sorting")
        XCTAssertEqual(downloads.rules.last?.templateID, "old-downloads", "the archive only catches leftovers")

        for name in ["budget.xlsx", "letter.docx", "deck.pptx", "config.json", "clip.mp4", "song.mp3", "novel.epub",
                     "Inter.otf", "photo.jpg", "manual.pdf", "mystery.xyz"] {
            try makeFile(name, contents: "content of \(name)")
        }
        let folder = WatchedFolder(path: inbox.path, rules: downloads.rules)
        let organizer = Organizer(config: RulesConfig(folders: [folder]), settings: AppSettings(), store: store,
                                  trash: trash, opener: NoOpener())
        let previews = organizer.simulate(folder)
        func destination(_ name: String) -> String? {
            previews.first { $0.file.lastPathComponent == name }?.steps.last?.target?.deletingLastPathComponent().path
        }
        let home = NSHomeDirectory()
        XCTAssertEqual(destination("budget.xlsx"), home + "/Documents/Spreadsheets")
        XCTAssertEqual(destination("letter.docx"), home + "/Documents/Docs")
        XCTAssertEqual(destination("deck.pptx"), home + "/Documents/Presentations")
        XCTAssertEqual(destination("config.json"), home + "/Documents/Code & Data")
        XCTAssertEqual(destination("clip.mp4"), home + "/Movies/Downloads")
        XCTAssertEqual(destination("song.mp3"), home + "/Music/Downloads")
        XCTAssertEqual(destination("novel.epub"), home + "/Documents/Books")
        XCTAssertEqual(destination("Inter.otf"), home + "/Documents/Fonts")
        XCTAssertEqual(destination("photo.jpg"), home + "/Pictures/Downloads")
        XCTAssertEqual(destination("manual.pdf"), home + "/Documents/PDF")
        XCTAssertNil(destination("mystery.xyz"), "new unknown files wait until they are 30 days old")
    }

    func testNewRulesSlotIntoPriorityOrderForExistingSetups() {
        var config = RulesConfig()
        for id in ["images", "old-downloads"] {
            Templates.install(Templates.all.first { $0.id == id }!, into: &config)
        }
        Templates.installRecommended(into: &config)
        let ids = config.folders.first { $0.path == "~/Downloads" }!.rules.compactMap(\.templateID)
        let expected = Templates.all.filter { $0.folderPath == "~/Downloads" }.map(\.id)
        XCTAssertEqual(ids, expected)
    }
}

final class TemplateUpgradeTests: XCTestCase {
    override func setUp() { pinScreenshotFolder() }

    func testUntouchedOldDownloadsRuleIsUpgradedButEditedOnesAreNot() {
        let oldActions: [Action] = [.move(destination: "~/Archive/Downloads/{added.year}", createFolders: true, onConflict: .rename)]
        var untouched = Rule(name: "Old downloads", mode: .live,
                             condition: .all([.isFolder(false), .ageDays(NumberMatch(greaterThan: 30))]),
                             actions: oldActions, templateID: "old-downloads")
        var edited = untouched
        edited.actions = [.move(destination: "~/Somewhere/Mine", createFolders: true, onConflict: .rename)]
        untouched.id = UUID()
        var config = RulesConfig(folders: [WatchedFolder(path: "~/Downloads", rules: [untouched]),
                                           WatchedFolder(path: "~/Desktop", rules: [edited])])
        XCTAssertEqual(Templates.upgradeUntouched(in: &config).count, 1)
        XCTAssertEqual(config.folders[0].rules[0].actions,
                       [.move(destination: "~/Archive/Downloads/{added.year}-{added.month}", createFolders: true, onConflict: .rename)])
        XCTAssertEqual(config.folders[0].rules[0].mode, .live, "keeps the person's live/preview choice")
        XCTAssertEqual(config.folders[1].rules[0].actions, edited.actions, "edited rules are left alone")
        XCTAssertTrue(Templates.upgradeUntouched(in: &config).isEmpty, "runs once")
    }
}

final class LegacyTemplateTests: XCTestCase {
    override func setUp() { pinScreenshotFolder() }

    func testRulesFromBeforeTemplateIDsAreRecognisedAndTurnedOn() {
        let installers = Templates.all.first { $0.id == "old-installers" }!
        var legacy = installers.rule
        legacy.templateID = nil
        legacy.id = UUID()
        var custom = Rule(name: "Old installers", condition: .kind(.installer), actions: [.trash]) // same name, different rule
        custom.id = UUID()
        var config = RulesConfig(folders: [WatchedFolder(path: "~/Downloads", rules: [legacy]),
                                           WatchedFolder(path: "~/Elsewhere", rules: [custom])])

        XCTAssertEqual(Templates.recommendedInPreview(config), 0, "before: invisible to Turn Them On")
        XCTAssertEqual(Templates.adoptLegacyRules(in: &config), 1)
        XCTAssertEqual(config.folders[0].rules[0].templateID, "old-installers")
        XCTAssertNil(config.folders[1].rules[0].templateID, "a look-alike elsewhere is left alone")
        XCTAssertEqual(Templates.recommendedInPreview(config), 1)
        XCTAssertEqual(Templates.makeRecommendedLive(in: &config), 1)
        XCTAssertEqual(config.folders[0].rules[0].mode, .live)
    }
}

final class ScreenshotLocationTests: XCTestCase {
    override func tearDown() { setenv("TIDYUP_SCREENSHOT_FOLDER", "~/Desktop", 1) }

    func testScreenshotTemplateFollowsWhereTheMacSavesScreenshots() {
        setenv("TIDYUP_SCREENSHOT_FOLDER", "~/Documents", 1)
        let template = Templates.all.first { $0.id == "screenshots" }!
        XCTAssertEqual(template.folderPath, "~/Documents")

        // Someone who added it for the Desktop earlier is offered it again for the real location.
        var config = RulesConfig(folders: [WatchedFolder(path: "~/Desktop", rules: [template.rule]), WatchedFolder(path: "~/Documents")])
        XCTAssertFalse(Templates.isInstalled(template, in: config))
        XCTAssertTrue(Templates.install(template, into: &config))
        XCTAssertEqual(config.folders.first { $0.path == "~/Documents" }?.rules.first?.templateID, "screenshots")
    }
}

final class TemplateTargetFolderTests: XCTestCase {
    func testTemplatesCanBeAddedToAnyFolderOncePerFolder() {
        let images = Templates.all.first { $0.id == "images" }!
        var config = RulesConfig(folders: [WatchedFolder(path: "~/Documents")])
        XCTAssertTrue(Templates.install(images, into: &config))                        // its own folder (~/Downloads)
        XCTAssertFalse(Templates.isInstalled(images, in: config, folderPath: "~/Documents"))
        XCTAssertTrue(Templates.install(images, into: &config, folderPath: "~/Documents"))
        XCTAssertFalse(Templates.install(images, into: &config, folderPath: "~/Documents"), "once per folder")
        XCTAssertEqual(config.folders.first { $0.path == "~/Documents" }?.rules.map(\.name), ["Images"])
    }
}
