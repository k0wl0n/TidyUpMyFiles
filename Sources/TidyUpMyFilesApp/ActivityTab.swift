import AppKit
import TidyUpMyFilesCore
import SwiftUI
import UniformTypeIdentifiers

/// The history of everything the app did: grouped by run, or as a flat list of steps.
struct ActivityTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var view: ViewMode = .runs
    @State private var search = ""
    @State private var status: ActivityStatus?
    @State private var action: String?
    @State private var runs: [RunSummary] = []
    @State private var records: [ActivityRecord] = []
    @State private var expanded = Set<Int64>()
    @State private var runRecords: [Int64: [ActivityRecord]] = [:]
    @State private var selection: ActivityRecord.ID?
    @State private var openedNewest = false

    enum ViewMode: String, CaseIterable, Identifiable {
        case runs = "By run", steps = "All steps"
        var id: String { rawValue }
    }

    private static let actions = ["move", "copy", "rename", "archive", "add_tags", "remove_tags", "set_color", "trash", "open",
                                  "shell", "empty_trash"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            switch view {
            case .runs: runList
            case .steps: stepTable
            }
        }
        .onAppear {
            if ShotScene.is("activity-steps") { view = .steps }
            reload()
        }
        .onChange(of: model.recent) { _ in reload() }
        .onChange(of: search) { _ in reloadSteps() }
        .onChange(of: status) { _ in reloadSteps() }
        .onChange(of: action) { _ in reloadSteps() }
        .onChange(of: model.focusedRunID) { _ in focusRequestedRun() }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $view) {
                ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            .help("By run: what each tidy did. All steps: every single step, searchable.")
            if view == .steps {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                    TextField("Search files, folders, rules", text: $search)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Search activity")
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .overlay(Capsule().stroke(Theme.cardStroke))
                Picker("Status", selection: $status) {
                    Text("Any status").tag(ActivityStatus?.none)
                    ForEach(ActivityStatus.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(ActivityStatus?.some($0)) }
                }
                .fixedSize()
                Picker("Action", selection: $action) {
                    Text("Any action").tag(String?.none)
                    ForEach(ActivityTab.actions, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .fixedSize()
            }
            Spacer()
            Button {
                if let folder = model.organizer?.store.logDirectory {
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(folder)
                }
            } label: {
                Label("Log Files", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(GlassButtonStyle())
            .help("Open the folder with the readable monthly activity logs")
            Button { exportCSV() } label: { Label("Export CSV…", systemImage: "square.and.arrow.up") }
                .buttonStyle(GlassButtonStyle())
                .help("Save the history as a spreadsheet file")
        }
    }

    // MARK: Runs

    private var runList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if runs.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath").font(.system(size: 44)).foregroundStyle(Theme.accent)
                            Text("Nothing has happened yet").font(.system(.title3, design: .rounded).bold()).foregroundStyle(Theme.textPrimary)
                            Text("Every time files are tidied, the run shows up here with what happened to each file.")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                    ForEach(runs) { run in
                        RunCard(run: run,
                                isExpanded: expanded.contains(run.id),
                                isFocused: model.focusedRunID == run.id,
                                records: runRecords[run.id] ?? [],
                                toggle: { toggle(run.id) },
                                undo: {
                                    model.undoBatch(run.id)
                                    reload()
                                })
                            .id(run.id)
                    }
                }
                .padding(.bottom, 8)
            }
            .onAppear { scrollToFocus(proxy) }
            .onChange(of: model.focusedRunID) { _ in scrollToFocus(proxy) }
        }
    }

    private func scrollToFocus(_ proxy: ScrollViewProxy) {
        guard let id = model.focusedRunID else { return }
        withAnimation { proxy.scrollTo(id, anchor: .top) }
    }

    private func toggle(_ id: Int64) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
            loadRecords(for: id)
        }
    }

    private func loadRecords(for id: Int64) {
        runRecords[id] = ((try? model.organizer?.store.records(inBatch: id)) ?? []).reversed()
    }

    private func focusRequestedRun() {
        guard let id = model.focusedRunID else { return }
        view = .runs
        reload()
        expanded.insert(id)
        loadRecords(for: id)
    }

    // MARK: Steps

    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    private var selectedRecord: ActivityRecord? { records.first { $0.id == selection } }

    private var stepTable: some View {
        VStack(spacing: 10) {
            Table(records, selection: $selection) {
                TableColumn("Time") { record in Text(ActivityTab.timeFormat.string(from: record.timestamp)).monospacedDigit() }
                    .width(min: 120, ideal: 150)
                TableColumn("Status") { record in
                    Label(record.status.rawValue, systemImage: StatusStyle.icon(record.status))
                        .foregroundStyle(StatusStyle.color(record.status))
                }
                .width(min: 70, ideal: 90)
                TableColumn("Rule") { record in Text(record.ruleName) }
                    .width(min: 80, ideal: 120)
                TableColumn("Action") { record in Text(record.action) }
                    .width(min: 60, ideal: 80)
                TableColumn("From") { record in Text(PathTools.abbreviate(record.sourcePath)).lineLimit(1).truncationMode(.middle) }
                TableColumn("To / note") { record in
                    Text(record.targetPath.map(PathTools.abbreviate) ?? record.message).lineLimit(1).truncationMode(.middle)
                }
            }
            .clearScrollBackground()
            .glassCard(padding: 6, radius: 16)
            HStack {
                if let record = selectedRecord, !record.message.isEmpty {
                    Text(record.message).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
                Spacer()
                Button("Undo Selected") {
                    if let record = selectedRecord { model.undo(record) }
                    reload()
                }
                .buttonStyle(GlassButtonStyle())
                .disabled(!(selectedRecord?.canUndo ?? false))
                Button("Undo Last Action") {
                    model.undoLast()
                    reload()
                }
                .buttonStyle(GradientButtonStyle())
                .keyboardShortcut("z", modifiers: .command)
            }
        }
    }

    // MARK: Data

    private func reload() {
        runs = (try? model.organizer?.store.runs()) ?? []
        if !openedNewest, let newest = runs.first {
            // The latest run starts open, so "what just happened" is visible right away.
            openedNewest = true
            expanded.insert(newest.id)
        }
        for id in expanded { loadRecords(for: id) }
        reloadSteps()
    }

    private func reloadSteps() {
        records = model.records(ActivityQuery(search: search, status: status, action: action, limit: 2_000))
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TidyUpMyFiles activity.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let all = model.records(ActivityQuery(search: search, status: status, action: action, limit: 100_000))
        do {
            try ActivityStore.csv(all).write(to: url, atomically: true, encoding: .utf8)
            model.message = "Exported \(all.count) step(s) to \(url.lastPathComponent)."
        } catch {
            model.message = "Export failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Run card

private struct RunCard: View {
    let run: RunSummary
    let isExpanded: Bool
    let isFocused: Bool
    let records: [ActivityRecord]
    let toggle: () -> Void
    let undo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    GradientIcon(systemName: RunText.icon(run.trigger), gradient: RunText.gradient(run.trigger), size: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(RunText.title(run.trigger)).font(.system(.headline, design: .rounded)).foregroundStyle(Theme.textPrimary)
                        Text("\(PathTools.abbreviate(run.folder)) · \(run.startedAt.formatted(date: .abbreviated, time: .shortened)) · run \(run.id)")
                            .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(RunText.chips(run), id: \.text) { chip in
                            Badge(text: chip.text, color: chip.color)
                        }
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down").foregroundStyle(Theme.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(RunText.title(run.trigger)), \(RunText.chips(run).map(\.text).joined(separator: ", "))")
            .accessibilityHint(isExpanded ? "Hide files" : "Show what happened to each file")

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(records) { record in StepLine(record: record) }
                }
                HStack {
                    Text("Also in the log file for \(run.startedAt.formatted(.dateTime.month(.wide).year())).")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if run.canUndo {
                        Button("Undo This Run", action: undo).buttonStyle(GlassButtonStyle())
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(isFocused ? Theme.highlight.opacity(0.7) : Theme.cardStroke, lineWidth: isFocused ? 1.5 : 1))
    }
}

/// One step: status, file, action, and from → to (or why it didn't happen).
private struct StepLine: View {
    let record: ActivityRecord

    /// "MOVED" only when it really happened; otherwise "MOVE — SKIPPED", "MOVE — FAILED", "MOVE — UNDONE".
    static func tag(_ record: ActivityRecord) -> String {
        record.status == .done ? RunReport.pastTense(record.action).uppercased()
            : "\(record.action.uppercased()) — \(record.status.rawValue.uppercased())"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: StatusStyle.icon(record.status))
                .foregroundStyle(StatusStyle.color(record.status))
                .frame(width: 18)
                .accessibilityLabel(record.status.rawValue)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(URL(fileURLWithPath: record.sourcePath).lastPathComponent)
                        .font(.callout.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.middle)
                    Text(StepLine.tag(record))
                        .font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.textSecondary)
                    Text(record.ruleName).font(.caption2).foregroundStyle(Theme.info)
                    Spacer()
                    Text(record.timestamp.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                Text("from  " + PathTools.abbreviate(URL(fileURLWithPath: record.sourcePath).deletingLastPathComponent().path) + "/")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
                if let target = record.targetPath {
                    Text("to    " + PathTools.abbreviate(target))
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.info)
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if !record.message.isEmpty && record.status != .done {
                    Text(record.message).font(.caption).foregroundStyle(record.status == .failed ? Theme.danger : Theme.warning)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.rowFill))
        .accessibilityElement(children: .combine)
    }
}

enum RunText {
    static func title(_ trigger: String) -> String {
        switch trigger {
        case "watch": return "New files tidied automatically"
        case "scheduled": return "Scheduled check"
        case "run now": return "Tidy now"
        case "approved": return "Approved from Preview"
        case "ai": return "AI suggestions approved"
        case "cli": return "Command line run"
        case "smart trash": return "Smart Trash"
        default: return trigger.capitalized
        }
    }

    static func icon(_ trigger: String) -> String {
        switch trigger {
        case "watch": return "eye.fill"
        case "scheduled": return "clock.fill"
        case "approved": return "checkmark.seal.fill"
        case "ai": return "wand.and.stars"
        case "cli": return "terminal.fill"
        case "smart trash": return "trash.fill"
        default: return "sparkles"
        }
    }

    static func gradient(_ trigger: String) -> LinearGradient {
        switch trigger {
        case "watch", "scheduled": return Theme.cool
        case "approved": return AppSection.activity.gradient
        case "ai": return AppSection.ai.gradient
        case "smart trash": return AppSection.smartTrash.gradient
        default: return Theme.accent
        }
    }

    struct Chip {
        let text: String
        let color: Color
    }

    static func chips(_ run: RunSummary) -> [Chip] {
        var chips = run.actionCounts.sorted { $0.value > $1.value }.prefix(3)
            .map { Chip(text: "\($0.value) \(RunReport.pastTense($0.key))", color: Theme.info) }
        if run.count(.undone) > 0 { chips.append(Chip(text: "\(run.count(.undone)) undone", color: .gray)) }
        if run.count(.skipped) > 0 { chips.append(Chip(text: "\(run.count(.skipped)) skipped", color: Theme.warning)) }
        if run.count(.failed) > 0 { chips.append(Chip(text: "\(run.count(.failed)) failed", color: Theme.danger)) }
        return chips
    }
}

/// Shown after a run that changed something: what happened, with links to the details and Undo.
struct RunReportCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let report = model.lastRun {
            HStack(spacing: 14) {
                GradientIcon(systemName: report.failed > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                             gradient: report.failed > 0 ? AppSection.preview.gradient : AppSection.activity.gradient, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text((report.cancelled ? "Stopped — " : "Finished — ") + report.title)
                        .font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text(report.summary).font(.callout).foregroundStyle(Theme.info)
                    if !report.examples.isEmpty {
                        Text(report.examples.joined(separator: "   ") + (report.done.count > 3 ? "   …" : ""))
                            .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.tail)
                    }
                }
                Spacer()
                Button("See What Happened") { model.showRun(report.batchIDs.first) }
                    .buttonStyle(GradientButtonStyle(gradient: Theme.cool))
                if !report.done.isEmpty {
                    Button("Undo") { model.undoRun(report) }.buttonStyle(GlassButtonStyle())
                }
                Button { model.lastRun = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("Dismiss report")
            }
            .glassCard(padding: 12, radius: 14)
            .accessibilityElement(children: .contain)
        }
    }
}
