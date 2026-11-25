import XCTest
@testable import TidyUpMyFilesCore

final class SmartTrashTests: SandboxTestCase {
    private let now = Date(timeIntervalSince1970: 1_767_225_600)

    private func item(_ name: String, daysAgo: Double, size: Int64) -> TrashItem {
        TrashItem(url: URL(fileURLWithPath: "/t/\(name)"), trashedAt: now.addingTimeInterval(-daysAgo * 86_400), size: size)
    }

    func testAgeLimit() {
        var settings = SmartTrashSettings()
        settings.olderThanDays = 30
        let plan = SmartTrash.plan([item("old", daysAgo: 40, size: 1), item("new", daysAgo: 2, size: 1)], settings: settings, now: now)
        XCTAssertEqual(plan.items.map(\.url.lastPathComponent), ["old"])
    }

    func testSizeCapRemovesOldestFirst() {
        var settings = SmartTrashSettings()
        settings.olderThanDays = 365
        settings.maxSizeGB = 1
        let items = [item("a", daysAgo: 10, size: 600_000_000), item("b", daysAgo: 5, size: 600_000_000), item("c", daysAgo: 1, size: 300_000_000)]
        let plan = SmartTrash.plan(items, settings: settings, now: now)
        XCTAssertEqual(plan.items.map(\.url.lastPathComponent), ["a"])
        XCTAssertEqual(plan.totalBytes, 600_000_000)
    }

    func testEmptyOnlyRemovesItemsInsideTheTrashFolder() throws {
        let trashFolder = root.appendingPathComponent("FakeTrash")
        let inTrash = try makeFile("old.txt", in: trashFolder)
        let outside = try makeFile("keep.txt")
        let smartTrash = SmartTrash(trashFolder: trashFolder)

        let scanned = try smartTrash.scan()
        XCTAssertEqual(scanned.map(\.url.lastPathComponent), ["old.txt"])

        let plan = SmartTrashPlan(items: scanned + [TrashItem(url: outside, trashedAt: .distantPast, size: 1)])
        let result = smartTrash.empty(plan)
        XCTAssertEqual(result.removed.count, 1)
        XCTAssertFalse(exists(inTrash))
        XCTAssertTrue(exists(outside), "nothing outside the Trash folder is ever deleted")
    }
}
