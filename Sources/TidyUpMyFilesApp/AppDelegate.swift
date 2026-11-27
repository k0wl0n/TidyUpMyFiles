import AppKit
import SwiftUI

enum LaunchOptions {
    /// `--screenshot <file.png>`: open Settings without taking focus, draw, save a picture, quit.
    static let screenshotPath: String? = {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--screenshot"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The packaged app also has AppIcon.icns; this covers running the program file directly.
        NSApp.applicationIconImage = IconArt.image()
        if let path = LaunchOptions.screenshotPath {
            // A check must never take focus or add a Dock icon.
            NSApp.setActivationPolicy(.accessory)
            // Checks must never act on real files, so the watcher stays off here.
            ShotScene.prepare(AppModel.shared)
            if ShotScene.is("menu") {
                SettingsWindowController.shared.showMenuPreview()
            } else {
                SettingsWindowController.shared.show(activate: false)
            }
            var delay = 2.0
            if ProcessInfo.processInfo.environment["TIDYUP_START_SECTION"] == "preview" || ShotScene.is("overview-results") {
                // A simulation only reads files, so it is safe in check mode; give it time to finish.
                AppModel.shared.simulateAll()
                delay = 6.0
            }
            if let override = ProcessInfo.processInfo.environment["TIDYUP_SHOT_DELAY"].flatMap(Double.init) {
                delay = override
            }
            ScreenshotTaker.capture(after: delay, to: path)
        } else {
            if let running = SingleInstance.otherCopy() {
                // TidyUpMyFiles is already running: show its window instead of starting a second watcher.
                SingleInstance.askRunningCopyToShowWindow()
                running.activate(options: [])
                NSApp.terminate(nil)
                return
            }
            SingleInstance.listenForShowRequests()
            // A Dock icon plus the window at launch, so TidyUpMyFiles is always findable even when the
            // menu bar icon is hidden (for example behind the notch).
            NSApp.setActivationPolicy(.regular)
            Notifier.setUp()
            AppModel.shared.startWatching()
            AppModel.shared.startSmartTrashTimer()
            SettingsWindowController.shared.show(activate: true)
        }
    }

    /// Opening TidyUpMyFiles again (Dock, Finder, Spotlight, `open`) brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show(activate: true)
        return true
    }

    /// Closing the window keeps TidyUpMyFiles tidying in the background.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(activate: Bool = true) {
        let window = self.window ?? makeWindow()
        self.window = window
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    var contentView: NSView? { window?.contentView }

    /// Screenshot scene "menu": the menu bar popup in a small window of its own.
    func showMenuPreview() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 330, height: 560),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = ShotAppearance.forced
        let hosting = NSHostingView(rootView: ShotScene.menuView(AppModel.shared))
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.center()
        window.orderFrontRegardless()
        self.window = window
    }
    var isVisible: Bool { window?.isVisible ?? false }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "TidyUpMyFiles"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = ShotAppearance.forced
        window.backgroundColor = NSColor(Theme.background)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 940, height: 600)
        window.contentView = NSHostingView(rootView: SettingsView().environmentObject(AppModel.shared))
        window.center()
        window.setFrameAutosaveName("TidyUpMyFilesSettings")
        window.delegate = self
        return window
    }

}

@MainActor
enum ScreenshotTaker {
    static func capture(after seconds: Double, to path: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            var status: Int32 = 1
            if let view = SettingsWindowController.shared.contentView, let png = snapshot(of: view) {
                let url = URL(fileURLWithPath: path)
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                status = (try? png.write(to: url)) != nil ? 0 : 1
            }
            exit(status)
        }
    }

    /// Draws the view over the window background colour: cached view drawing leaves the background transparent.
    private static func snapshot(of view: NSView) -> Data? {
        let bounds = view.bounds
        guard let content = view.bitmapImageRepForCachingDisplay(in: bounds),
              let canvas = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: content)
        guard let context = NSGraphicsContext(bitmapImageRep: canvas) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
        content.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        return canvas.representation(using: .png, properties: [:])
    }
}

/// Keeps one TidyUpMyFiles running: a second launch asks the first to show its window, then quits.
@MainActor
enum SingleInstance {
    private static let showWindow = Notification.Name("io.github.tidyupmyfiles.TidyUpMyFiles.showWindow")

    static func otherCopy() -> NSRunningApplication? {
        let me = NSRunningApplication.current
        let candidates: [NSRunningApplication]
        if let bundleID = Bundle.main.bundleIdentifier {
            candidates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        } else {
            candidates = NSWorkspace.shared.runningApplications.filter {
                $0.executableURL?.resolvingSymlinksInPath() == me.executableURL?.resolvingSymlinksInPath()
            }
        }
        return candidates.first { $0.processIdentifier != me.processIdentifier && !$0.isTerminated }
    }

    static func askRunningCopyToShowWindow() {
        DistributedNotificationCenter.default().postNotificationName(showWindow, object: nil, userInfo: nil, deliverImmediately: true)
    }

    static func listenForShowRequests() {
        DistributedNotificationCenter.default().addObserver(forName: showWindow, object: nil, queue: .main) { _ in
            Task { @MainActor in SettingsWindowController.shared.show(activate: true) }
        }
    }
}

/// Follows the system's light or dark mode; `TIDYUP_APPEARANCE=light|dark` forces one (for screenshots).
enum ShotAppearance {
    static var forced: NSAppearance? {
        switch ProcessInfo.processInfo.environment["TIDYUP_APPEARANCE"] {
        case "light": return NSAppearance(named: .aqua)
        case "dark": return NSAppearance(named: .darkAqua)
        default: return nil
        }
    }
}
