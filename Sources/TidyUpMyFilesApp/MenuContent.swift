import TidyUpMyFilesCore
import SwiftUI

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AppLogo(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("TidyUpMyFiles").font(.system(.headline, design: .rounded))
                    HStack(spacing: 6) {
                        Circle().fill(model.settings.paused ? Color.orange : Color.green).frame(width: 7, height: 7)
                        Text(model.settings.paused ? "Paused" : "Watching \(model.config.folders.filter(\.enabled).count) folder(s)")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                Button { model.togglePause() } label: {
                    Image(systemName: model.settings.paused ? "play.fill" : "pause.fill")
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("p")
                .help(model.settings.paused ? "Resume watching your folders" : "Stop watching until you resume")
                .accessibilityLabel(model.settings.paused ? "Resume" : "Pause")
            }
            .accessibilityElement(children: .contain)

            if model.busy || model.work != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(WorkText.title(model)).font(.caption.bold()).lineLimit(1)
                        Spacer()
                        if model.busy { Button("Cancel") { model.cancelWork() }.buttonStyle(.plain).font(.caption).foregroundStyle(Theme.pink) }
                    }
                    Text(WorkText.detail(model.work)).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
                    if let work = model.work, work.total > 0 { ProgressView(value: work.fraction).tint(Theme.pink) }
                }
                .glassCard(padding: 10, radius: 12)
            }

            HStack(spacing: 10) {
                stat("\(model.todayCount)", "tidied today")
                stat("\(model.previews.count)", "in preview")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Recent activity").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                if model.recent.isEmpty {
                    Text("Nothing yet.").font(.callout).foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(model.recent.prefix(4)) { record in
                        ActivityLine(record: record)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(padding: 12, radius: 14)

            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(3)
            }

            Button {
                model.runNowAll()
            } label: {
                HStack {
                    if model.busy { ProgressView().controlSize(.small).tint(.white) }
                    Text("Tidy Now")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GradientButtonStyle())
            .keyboardShortcut("r")
            .help("Run your live rules on what's already in your folders (preview-mode rules only queue files)")
            .disabled(model.busy)

            HStack {
                Button("Undo Last") { model.undoLast() }.keyboardShortcut("z")
                    .help("Take back the most recent step")
                Spacer()
                Button("Open TidyUpMyFiles…") { SettingsWindowController.shared.show() }.keyboardShortcut(",")
                    .help("Open the main window to scan, review and change rules")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: 330)
        .background(AppBackdrop())
        .preferredColorScheme(.dark)
        .onAppear { model.refreshActivity() }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 12, radius: 14)
        .accessibilityElement(children: .combine)
    }
}

struct ActivityLine: View {
    let record: ActivityRecord

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: StatusStyle.icon(record.status))
                .foregroundStyle(StatusStyle.color(record.status))
                .accessibilityLabel(record.status.rawValue)
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: record.sourcePath).lastPathComponent).lineLimit(1)
                Text("\(record.action) · \(record.ruleName)").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.callout)
    }
}

enum StatusStyle {
    static func icon(_ status: ActivityStatus) -> String {
        switch status {
        case .done: return "checkmark.circle.fill"
        case .skipped: return "arrow.uturn.right.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .undone: return "arrow.uturn.backward.circle.fill"
        }
    }

    static func color(_ status: ActivityStatus) -> Color {
        switch status {
        case .done: return Color(red: 0.3, green: 0.9, blue: 0.6)
        case .skipped: return .gray
        case .failed: return Color(red: 1, green: 0.4, blue: 0.45)
        case .undone: return Theme.cyan
        }
    }
}
