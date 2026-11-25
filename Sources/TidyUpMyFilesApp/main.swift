import SwiftUI

struct TidyUpMyFilesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(model)
        } label: {
            Image(systemName: model.settings.paused ? "pause.circle" : "tray.and.arrow.down.fill")
                .accessibilityLabel(model.settings.paused ? "TidyUpMyFiles, paused" : "TidyUpMyFiles, watching")
        }
        .menuBarExtraStyle(.window)
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--export-icon"), index + 1 < CommandLine.arguments.count {
    // Used by scripts/build-app.sh to make AppIcon.icns from the same drawing the app uses.
    do {
        try IconArt.exportIconset(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Could not export the icon: \(error)\n".utf8))
        exit(1)
    }
}

TidyUpMyFilesApp.main()
