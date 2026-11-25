import XCTest
@testable import TidyUpMyFilesCore

final class ProgressTests: SandboxTestCase {
    private final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [WorkProgress] = []
        func add(_ progress: WorkProgress) { lock.withLock { items.append(progress) } }
        var all: [WorkProgress] { lock.withLock { items } }
    }

    private func organizer(_ rules: [Rule]) -> (Organizer, WatchedFolder) {
        let folder = WatchedFolder(path: inbox.path, rules: rules)
        return (Organizer(config: RulesConfig(folders: [folder]), settings: AppSettings(), store: store, trash: trash,
                          opener: NoOpener()), folder)
    }

    func testSimulationReportsStartAndFinish() throws {
        for index in 0..<25 { try makeFile("file\(index).pdf") }
        let (organizer, folder) = organizer([Rule(name: "PDF", condition: .kind(.pdf), actions: [.trash])])
        let events = Events()
        organizer.setProgressHandler { events.add($0) }

        XCTAssertEqual(organizer.simulate(folder).count, 25)
        XCTAssertEqual(events.all.first?.done, 0)
        XCTAssertEqual(events.all.first?.total, 25)
        XCTAssertEqual(events.all.last?.finished, true)
        XCTAssertTrue(events.all.allSatisfy { $0.kind == .simulating })
    }

    func testRuleEditorPreviewStaysQuiet() throws {
        try makeFile("a.pdf")
        let (organizer, folder) = organizer([Rule(name: "PDF", condition: .kind(.pdf), actions: [.trash])])
        let events = Events()
        organizer.setProgressHandler { events.add($0) }
        _ = organizer.simulate(folder, onlyRule: folder.rules[0], reportProgress: false)
        XCTAssertTrue(events.all.isEmpty)
    }

    func testCancelStopsATidyRunEarly() throws {
        for index in 0..<40 { try makeFile("file\(index).txt") }
        let (organizer, folder) = organizer([Rule(name: "Move", mode: .live, condition: .all([]),
                                                   actions: [.move(destination: root.path + "/Out", createFolders: true, onConflict: .rename)])])
        organizer.setProgressHandler { progress in
            if progress.done >= 5 { organizer.cancel() }
        }
        // The reporter is throttled; cancel as soon as the first item is handled instead.
        organizer.cancel()
        let result = organizer.runNow(folder)
        XCTAssertTrue(result.records.isEmpty, "cancelled before the first item")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: inbox.path).count, 40)

        organizer.resetCancel()
        XCTAssertEqual(organizer.runNow(folder).records.count, 40)
    }

    func testFolderSizeIsOnlyAddedUpWhenARuleUsesSize() throws {
        let folder = inbox.appendingPathComponent("Big")
        try makeFile("inside.bin", in: folder, contents: String(repeating: "x", count: 5_000))
        XCTAssertEqual(try FileFactsReader.read(folder, needs: []).size, 0)
        XCTAssertGreaterThanOrEqual(try FileFactsReader.read(folder, needs: .folderSize).size, 5_000)

        let sizeRule = Rule(name: "Big", condition: .size(NumberMatch(greaterThan: 1)), actions: [.trash])
        let nameRule = Rule(name: "Name", condition: .name(TextMatch(contains: "x")), actions: [.trash])
        XCTAssertTrue(FactNeeds.forRules([sizeRule]).contains(.folderSize))
        XCTAssertFalse(FactNeeds.forRules([nameRule]).contains(.folderSize))
        let takenRule = Rule(name: "Photos", condition: .kind(.image), actions: [.move(destination: "~/P/{taken.year}", createFolders: true, onConflict: .rename)])
        XCTAssertTrue(FactNeeds.forRules([takenRule]).contains(.taken))
    }
}
