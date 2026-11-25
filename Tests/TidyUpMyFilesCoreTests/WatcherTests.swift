import XCTest
@testable import TidyUpMyFilesCore

final class WatcherTests: SandboxTestCase {
    private func organizer(rules: [Rule]) -> (Organizer, WatchedFolder) {
        let folder = WatchedFolder(path: inbox.path, rules: rules)
        let organizer = Organizer(config: RulesConfig(folders: [folder]), settings: AppSettings(), store: store,
                                  trash: trash, opener: NoOpener())
        return (organizer, folder)
    }

    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    func testNewScreenshotIsMovedWithinThreeSeconds() throws {
        let out = root.appendingPathComponent("Screenshots")
        let rule = Rule(name: "Screenshot", mode: .live, condition: .name(TextMatch(startsWith: "Screenshot")),
                        actions: [.move(destination: out.path, createFolders: true, onConflict: .rename)])
        let (organizer, _) = organizer(rules: [rule])
        let service = WatchService(organizer: organizer) { _ in }
        service.restart()
        defer { service.stop() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let started = Date()
        try makeFile("Screenshot 2026-11-24 at 10.00.00.png")
        XCTAssertTrue(waitUntil(5) { exists(out.appendingPathComponent("Screenshot 2026-11-24 at 10.00.00.png")) })
        XCTAssertLessThan(Date().timeIntervalSince(started), 3.0)
    }

    func testDownloadsInProgressAreLeftAlone() throws {
        let rule = Rule(name: "All", mode: .live, condition: .all([]),
                        actions: [.move(destination: root.path + "/Out", createFolders: true, onConflict: .rename)])
        let (organizer, _) = organizer(rules: [rule])
        let service = WatchService(organizer: organizer) { _ in }
        service.restart()
        defer { service.stop() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let chrome = try makeFile("movie.mp4.crdownload")
        let placeholder = try makeFile("archive.zip", contents: "")
        let partial = try makeFile("archive.zip.part")
        RunLoop.current.run(until: Date().addingTimeInterval(3.5))
        XCTAssertTrue(exists(chrome))
        XCTAssertTrue(exists(placeholder), "final name is untouched while its .part sibling exists")

        // Finishing the download: the .part replaces the placeholder.
        try FileManager.default.removeItem(at: placeholder)
        try FileManager.default.moveItem(at: partial, to: placeholder)
        XCTAssertTrue(waitUntil(5) { exists(root.appendingPathComponent("Out/archive.zip")) })
    }

    func testIgnoredNames() {
        for name in [".DS_Store", "a.tmp", "a.TEMP", "a.part", "a.crdownload", "a.download", "Thumbs.db"] {
            XCTAssertTrue(PartialFiles.shouldIgnore(URL(fileURLWithPath: "/x/\(name)")), name)
        }
        XCTAssertFalse(PartialFiles.shouldIgnore(URL(fileURLWithPath: "/x/report.pdf")))
    }

    func testGrowingFileWaitsUntilStable() throws {
        let rule = Rule(name: "All", mode: .live, condition: .all([]),
                        actions: [.move(destination: root.path + "/Out", createFolders: true, onConflict: .rename)])
        let (organizer, _) = organizer(rules: [rule])
        let service = WatchService(organizer: organizer) { _ in }
        service.restart()
        defer { service.stop() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let file = try makeFile("big.bin", contents: "x")
        let handle = try FileHandle(forWritingTo: file)
        for _ in 0..<6 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            handle.seekToEndOfFile()
            handle.write(Data(repeating: 1, count: 1_000))
            XCTAssertTrue(exists(file), "still being written")
        }
        try handle.close()
        XCTAssertTrue(waitUntil(5) { exists(root.appendingPathComponent("Out/big.bin")) })
    }

    func testPreviewRulesOnlyProducePreviews() throws {
        let rule = Rule(name: "PDF", mode: .preview, condition: .kind(.pdf),
                        actions: [.move(destination: "PDF", createFolders: true, onConflict: .rename)])
        let (organizer, folder) = organizer(rules: [rule])
        let file = try makeFile("a.pdf")

        let result = organizer.runNow(folder)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.previews.count, 1)
        XCTAssertTrue(result.previews[0].summary.hasSuffix("Inbox/PDF/a.pdf"))
        XCTAssertTrue(exists(file))

        let approved = organizer.approve(result.previews)
        XCTAssertEqual(approved.records.map(\.status), [.done])
        XCTAssertTrue(exists(inbox.appendingPathComponent("PDF/a.pdf")))
    }
}
