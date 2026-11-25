import TidyUpMyFilesCore
import ServiceManagement
import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Watching") {
                Toggle("Pause all watching", isOn: Binding(get: { model.settings.paused }, set: { _ in model.togglePause() }))
                Stepper(value: settingBinding(\.stableSeconds), in: 1...30, step: 1) {
                    Text("Wait until a file stops changing for \(Int(model.settings.stableSeconds)) s")
                }
                Stepper(value: settingBinding(\.rescanMinutes), in: 1...240, step: 5) {
                    Text("Re-check folders every \(Int(model.settings.rescanMinutes)) min (for age-based rules)")
                }
                Text("Files ending in .crdownload, .download, .part, .tmp or .temp, hidden files, system folders, ~/Library, .git folders and apps are never touched.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch TidyUpMyFiles at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
            }
            Section("Shell scripts") {
                Toggle("Allow “Run shell script” actions", isOn: settingBinding(\.allowShellScripts))
                    .help("Rules can run a script on a file. Off unless you trust the script.")
                Toggle("Allow “Run a Shortcut” actions", isOn: settingBinding(\.allowShortcuts))
                    .help("Rules can run a Shortcut from the Shortcuts app with the file. Off unless you want it.")
                Label("Scripts run with your permissions and can't be undone. Leave this off unless you wrote the script.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            Section("Notifications") {
                Toggle("Notify me when files are tidied in the background", isOn: settingBinding(\.notifyAfterBackgroundRuns))
                Text("Shows what moved where. Needs TidyUpMyFiles to run from the app (not the command line).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Storage") {
                LabeledContent("Rules", value: PathTools.abbreviate(AppPaths.rulesFile.path))
                LabeledContent("Activity database", value: PathTools.abbreviate(AppPaths.databaseFile.path))
                LabeledContent("Readable log files", value: PathTools.abbreviate(AppPaths.logsDirectory.path))
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.rulesFile])
                }
            }
            Section("Import and export") {
                Text("Rules are plain YAML, so you can keep them in git or share them.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Export Rules…") { model.exportRules() }
                    Button("Import and Add…") { model.importRules(replace: false) }
                    Button("Import and Replace…") { model.importRules(replace: true) }
                }
            }
            Section("About") {
                Text("TidyUpMyFiles is free and open source (MIT). Every feature is included: no trial, no account, no telemetry.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .clearScrollBackground()
    }

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { model.settings[keyPath: keyPath] },
                set: {
                    model.settings[keyPath: keyPath] = $0
                    model.saveSettings()
                })
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled
        } catch {
            model.message = "Launch at login needs TidyUpMyFiles to run from TidyUpMyFiles.app in Applications: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
