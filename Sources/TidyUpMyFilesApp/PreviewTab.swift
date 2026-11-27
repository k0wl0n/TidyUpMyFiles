import AppKit
import TidyUpMyFilesCore
import SwiftUI

/// Waiting items, shown as "from → to" journeys with every predicted outcome made explicit.
struct PreviewTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var selected = Set<String>()
    @State private var focusedID: String?
    @State private var search = ""
    @State private var grouping: Grouping = .destination
    @State private var filter: Filter = .all
    /// Folded groups, per grouping ("Destination|~/Pictures/Downloads").
    @State private var collapsed = Set<String>()
    /// Groupings whose groups were already folded once for a big list.
    @State private var autoFolded = Set<Grouping>()

    enum Grouping: String, CaseIterable, Identifiable {
        case destination = "Destination", rule = "Rule", source = "Current folder", none = "No grouping"
        var id: String { rawValue }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", moves = "Moves", renames = "Renamed", trash = "To Trash", newFolders = "New folders", attention = "Needs attention"
        var id: String { rawValue }
    }

    private var details: [PreviewDetail] { model.previewDetails }

    private var visible: [PreviewDetail] {
        details.filter { detail in
            let matchesSearch = search.isEmpty
                || detail.item.file.lastPathComponent.localizedCaseInsensitiveContains(search)
                || detail.item.ruleName.localizedCaseInsensitiveContains(search)
                || (detail.finalLocation?.path.localizedCaseInsensitiveContains(search) ?? false)
            guard matchesSearch else { return false }
            switch filter {
            case .all: return true
            case .moves: return detail.mainStep?.verb == "move"
            case .renames: return detail.nameChanges
            case .trash: return detail.goesToTrash
            case .newFolders: return detail.createsFolder
            case .attention: return detail.hasConflict
            }
        }
    }

    private var focused: PreviewDetail? {
        details.first { $0.id == focusedID } ?? visible.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let found = model.scanFoundCount, !model.previews.isEmpty {
                scanGuide(found)
            }
            if model.previews.isEmpty && model.busy {
                scanningState
            } else if model.previews.isEmpty {
                emptyState
            } else {
                summary
                toolbar
                HStack(alignment: .top, spacing: 14) {
                    list
                    if let focused { PreviewDetailPanel(detail: focused, discard: discard, run: run).frame(width: 340) }
                }
                bottomBar
            }
        }
    }

    // MARK: Summary

    private var summary: some View {
        let moves = details.filter { $0.mainStep?.verb == "move" }.count
        let renames = details.filter(\.nameChanges).count
        let trash = details.filter(\.goesToTrash).count
        let folders = Set(details.flatMap { $0.steps.filter(\.createsFolder).compactMap { $0.plannedTo?.deletingLastPathComponent().path } }).count
        let attention = details.filter(\.hasConflict).count
        return HStack(spacing: 10) {
            SummaryChip(value: "\(details.count)", label: "items waiting",
                        icon: "doc.on.doc.fill", gradient: Theme.accent, active: filter == .all) { filter = .all }
            SummaryChip(value: "\(moves)", label: "to move", icon: "arrow.right", gradient: Theme.cool, active: filter == .moves) { filter = .moves }
            SummaryChip(value: "\(renames)", label: "renamed", icon: "character.cursor.ibeam",
                        gradient: AppSection.ai.gradient, active: filter == .renames) { filter = .renames }
            SummaryChip(value: "\(trash)", label: "to Trash", icon: "trash.fill", gradient: AppSection.smartTrash.gradient,
                        active: filter == .trash) { filter = .trash }
            SummaryChip(value: "\(folders)", label: "new folders", icon: "folder.badge.plus", gradient: AppSection.activity.gradient,
                        active: filter == .newFolders) { filter = .newFolders }
            SummaryChip(value: "\(attention)", label: "need attention", icon: "exclamationmark.triangle.fill",
                        gradient: AppSection.preview.gradient, active: filter == .attention) { filter = .attention }
            if model.inspectingPreviews { ProgressView().controlSize(.small) }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                TextField("Search file, rule or destination", text: $search)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search waiting items")
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .overlay(Capsule().stroke(Theme.cardStroke))
            Picker("Group by", selection: $grouping) {
                ForEach(Grouping.allCases) { Text($0.rawValue).tag($0) }
            }
            .fixedSize()
            .help("Group the list by where files go, by rule, or by the folder they're in now")
            Spacer()
            Button(allCollapsed ? "Expand All" : "Collapse All") {
                let keys = groups.map(collapseKey)
                if allCollapsed { collapsed.subtract(keys) } else { collapsed.formUnion(keys) }
            }
            .buttonStyle(GlassButtonStyle())
            .disabled(grouping == .none)
            .help("Fold or unfold every group")
            Button(allVisibleSelected ? "Select None" : "Select All (\(visible.count))") {
                if allVisibleSelected { selected.subtract(visible.map(\.id)) } else { selected.formUnion(visible.map(\.id)) }
            }
            .buttonStyle(GlassButtonStyle())
        }
    }

    private func collapseKey(_ group: Group) -> String { "\(grouping.rawValue)|\(group.id)" }

    private func isCollapsed(_ group: Group) -> Bool { collapsed.contains(collapseKey(group)) }

    private var allCollapsed: Bool { !groups.isEmpty && groups.allSatisfy(isCollapsed) }

    private func toggleCollapse(_ group: Group) {
        let key = collapseKey(group)
        if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
    }

    /// Big lists open folded: first a short list of destinations with counts, then unfold what you want to check.
    private func foldBigListOnce() {
        guard grouping != .none, !details.isEmpty, details.count > 30 || ShotScene.is("preview-folded"),
              !autoFolded.contains(grouping) else { return }
        autoFolded.insert(grouping)
        collapsed.formUnion(groups.map(collapseKey))
    }

    private var allVisibleSelected: Bool {
        !visible.isEmpty && visible.allSatisfy { selected.contains($0.id) }
    }

    // MARK: List

    private struct Group: Identifiable {
        var id: String
        var title: String
        var icon: String
        var note: String?
        var items: [PreviewDetail]
    }

    private var groups: [Group] {
        let items = visible
        func make(_ key: (PreviewDetail) -> (String, String, String)) -> [Group] {
            var order: [String] = []
            var buckets: [String: (String, String, [PreviewDetail])] = [:]
            for item in items {
                let (id, title, icon) = key(item)
                if buckets[id] == nil { order.append(id); buckets[id] = (title, icon, []) }
                buckets[id]?.2.append(item)
            }
            return order.map { id in
                let (title, icon, members) = buckets[id]!
                let createsFolder = members.contains(where: \.createsFolder)
                return Group(id: id, title: title, icon: icon, note: createsFolder ? "New folder" : nil, items: members)
            }
        }
        switch grouping {
        case .destination:
            return make { detail in
                if detail.goesToTrash { return ("trash", "Trash", "trash.fill") }
                guard let folder = detail.destinationFolder else { return ("stay", "Stays where it is", "pin.fill") }
                return (folder.path, PathTools.abbreviate(folder.path), "folder.fill")
            }
        case .rule:
            return make { ($0.item.ruleName, $0.item.ruleName, "slider.horizontal.3") }
        case .source:
            return make { detail in
                let folder = detail.item.file.deletingLastPathComponent().path
                return (folder, PathTools.abbreviate(folder), "folder")
            }
        case .none:
            return [Group(id: "all", title: "All waiting items", icon: "tray.full.fill", note: nil, items: items)]
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                ForEach(groups) { group in
                    Section {
                        ForEach(isCollapsed(group) ? [] : group.items) { detail in
                            PreviewRow(detail: detail,
                                       isSelected: selected.contains(detail.id),
                                       isFocused: focused?.id == detail.id,
                                       toggle: { toggle(detail.id) })
                                .onTapGesture { focusedID = detail.id }
                        }
                    } header: {
                        groupHeader(group)
                    }
                }
                if visible.isEmpty {
                    Text("Nothing matches this filter.").foregroundStyle(Theme.textSecondary).padding()
                }
            }
            .padding(10)
        }
        .onAppear {
            // Screenshot scene "preview-attention": only the items that need a decision.
            if ShotScene.is("preview-attention") { filter = .attention }
            foldBigListOnce()
        }
        .onChange(of: grouping) { _ in foldBigListOnce() }
        .onChange(of: details.count) { count in
            // A new simulation with a big result folds again; an empty list resets that.
            if count == 0 { autoFolded.removeAll() } else { foldBigListOnce() }
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.cardStroke))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func groupHeader(_ group: Group) -> some View {
        let bytes = group.items.compactMap(\.size).reduce(0, +)
        let allSelected = group.items.allSatisfy { selected.contains($0.id) }
        let folded = isCollapsed(group)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    if allSelected { selected.subtract(group.items.map(\.id)) } else { selected.formUnion(group.items.map(\.id)) }
                } label: {
                    Image(systemName: allSelected ? "checkmark.square.fill" : "square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(allSelected ? Theme.highlight : Theme.textSecondary)
                .accessibilityLabel(allSelected ? "Deselect group" : "Select group")
                Button { toggleCollapse(group) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .rotationEffect(.degrees(folded ? 0 : 90))
                            .foregroundStyle(Theme.textSecondary)
                        Image(systemName: group.icon).foregroundStyle(Theme.info).accessibilityHidden(true)
                        Text(group.title).font(.system(.headline, design: .rounded)).foregroundStyle(Theme.textPrimary)
                            .lineLimit(1).truncationMode(.middle)
                        if let note = group.note { Badge(text: note, color: Theme.done) }
                        Spacer()
                        Text("\(group.items.count) item(s) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group.title), \(group.items.count) items")
                .accessibilityHint(folded ? "Show the items" : "Hide the items")
            }
            if folded {
                Text(foldedPreview(group))
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
                    .padding(.leading, 56)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.rowFill)
        )
        .animation(.easeInOut(duration: 0.15), value: folded)
    }

    /// "a.png, b.svg, c.png … and 259 more" for a folded group.
    private func foldedPreview(_ group: Group) -> String {
        let names = group.items.prefix(3).map(\.item.file.lastPathComponent).joined(separator: ", ")
        return group.items.count > 3 ? "\(names) … and \(group.items.count - 3) more" : names
    }

    private var bottomBar: some View {
        HStack {
            Button("Simulate All Folders") { model.simulateAll() }
                .buttonStyle(GlassButtonStyle())
                .disabled(model.busy)
                .help("Look at every watched folder again and list what would happen. Nothing moves.")
            Text(selected.isEmpty
                 ? "\(details.count) items · \(ByteCountFormatter.string(fromByteCount: details.compactMap(\.size).reduce(0, +), countStyle: .file)). Tap one for details."
                 : "\(selected.count) of \(details.count) selected")
                .font(.callout).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("Discard Selected") { discard(selectedItems) }
                .buttonStyle(GlassButtonStyle())
                .help("Remove the ticked items from this list without changing any file")
                .disabled(selected.isEmpty)
            Button("Run Selected (\(selected.count))") { run(selectedItems) }
                .buttonStyle(GradientButtonStyle(gradient: Theme.cool))
                .help("Do what's shown for the ticked items only. Every step can be undone.")
                .disabled(selected.isEmpty)
            Button("Run All (\(details.count))") { run(details.map(\.item)) }
                .buttonStyle(GradientButtonStyle())
                .help("Do what's shown for every item in the list. Every step can be undone.")
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Shown after a scan: what was found and what to do next.
    private func scanGuide(_ found: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            GradientIcon(systemName: "magnifyingglass", gradient: Theme.cool, size: 34)
            VStack(alignment: .leading, spacing: 6) {
                Text("Scan finished — \(found) file(s) found. Nothing has moved yet.")
                    .font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(Theme.textPrimary)
                HStack(spacing: 18) {
                    Label("Check each file's FROM → TO", systemImage: "1.circle.fill")
                    Label("Tick the ones you want (or none)", systemImage: "2.circle.fill")
                    Label("Press Run Selected or Run All", systemImage: "3.circle.fill")
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Got it") { model.scanFoundCount = nil }
                .buttonStyle(GlassButtonStyle())
                .help("Hide this guide")
        }
        .glassCard(padding: 12, radius: 14)
    }

    private var scanningState: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Scanning your folders…").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
            Text("Nothing is moved while simulating. Results appear here when the scan finishes; the banner above shows how far it is.")
                .foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(Theme.accent)
            Text("Nothing is waiting").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
            Text("Rules in preview mode and simulations show here, with exactly where each file would go, before anything moves.")
                .foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 460)
            Button("Simulate All Folders") { model.simulateAll() }
                .buttonStyle(GradientButtonStyle())
                .disabled(model.busy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private var selectedItems: [PreviewItem] {
        details.filter { selected.contains($0.id) }.map(\.item)
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func discard(_ items: [PreviewItem]) {
        model.discard(items)
        selected.subtract(items.map(\.id))
    }

    private func run(_ items: [PreviewItem]) {
        model.approve(items)
        selected.subtract(items.map(\.id))
    }
}

// MARK: - Row

private struct PreviewRow: View {
    let detail: PreviewDetail
    let isSelected: Bool
    let isFocused: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square").font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isSelected ? Theme.highlight : Theme.textSecondary)
            .padding(.top, 8)
            .accessibilityLabel(isSelected ? "Deselect \(detail.item.file.lastPathComponent)" : "Select \(detail.item.file.lastPathComponent)")

            FileIconView(url: detail.item.file, size: 38)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(detail.item.file.lastPathComponent)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                    Badge(text: detail.item.ruleName, color: Theme.info)
                    Spacer(minLength: 4)
                    Text(PreviewText.meta(detail)).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                JourneyLine(detail: detail)
                if !PreviewText.warnings(detail).isEmpty {
                    HStack(spacing: 6) {
                        ForEach(PreviewText.warnings(detail), id: \.text) { warning in
                            Badge(text: warning.text, color: warning.color, icon: warning.icon)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isFocused ? Theme.rowFillActive : Theme.rowFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(isFocused ? Theme.highlight.opacity(0.7) : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Two lines: where the item is now, and exactly where it will be (folder + final name).
private struct JourneyLine: View {
    let detail: PreviewDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                StepLabel(text: "FROM", gradient: nil)
                PathText(folder: detail.item.file.deletingLastPathComponent(), name: nil, highlight: false)
            }
            HStack(spacing: 8) {
                StepLabel(text: PreviewText.verbTitle(detail.mainStep?.verb ?? "move"),
                          gradient: PreviewText.verbGradient(detail.mainStep?.verb ?? "move"))
                if detail.goesToTrash {
                    Label("Trash — can be restored with Undo", systemImage: "trash")
                        .font(.callout).foregroundStyle(Theme.danger)
                } else if let final = detail.finalLocation {
                    PathText(folder: final.deletingLastPathComponent(),
                             name: detail.nameChanges || detail.mainStep?.verb == "archive" ? final.lastPathComponent : nil,
                             highlight: true)
                } else {
                    Label("Stays where it is — see the warning", systemImage: "pin.fill")
                        .font(.callout).foregroundStyle(PreviewText.orange)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// A fixed-width tag in front of a path line, so FROM and the action line up.
private struct StepLabel: View {
    let text: String
    let gradient: LinearGradient?

    var body: some View {
        HStack(spacing: 3) {
            Text(text).font(.system(size: 10, weight: .heavy))
            if gradient != nil { Image(systemName: "arrow.right").font(.system(size: 9, weight: .heavy)) }
        }
        .foregroundStyle(gradient == nil ? Theme.textSecondary : .white)
        .frame(width: 78, height: 20)
        .background(Capsule().fill(gradient.map(AnyShapeStyle.init) ?? AnyShapeStyle(Color.primary.opacity(0.05))))
        .accessibilityLabel(text.lowercased())
    }
}

/// `~/Documents/PDF/` in grey and the file name in bold; long paths are shortened in the middle.
private struct PathText: View {
    let folder: URL
    let name: String?
    let highlight: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text(PathTools.abbreviate(folder.path) + "/")
                .foregroundStyle(highlight ? Theme.info : Theme.textSecondary)
                .lineLimit(1).truncationMode(.middle)
                .layoutPriority(0)
            if let name {
                Text(name).fontWeight(.semibold).foregroundStyle(Theme.highlight)
                    .lineLimit(1).truncationMode(.middle)
                    .layoutPriority(1)
            }
        }
        .font(.system(.callout, design: .monospaced))
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).accessibilityHidden(true) }
            Text(text).lineLimit(1)
        }
        .font(.caption2.bold())
        .foregroundStyle(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.16)))
    }
}

// MARK: - Detail panel

private struct PreviewDetailPanel: View {
    let detail: PreviewDetail
    let discard: ([PreviewItem]) -> Void
    let run: ([PreviewItem]) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    FileIconView(url: detail.item.file, size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(detail.item.file.lastPathComponent).font(.headline).foregroundStyle(Theme.textPrimary)
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        Text(PreviewText.meta(detail)).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }

                PathBox(title: "From", url: detail.item.file, highlightName: false, tint: Theme.textSecondary)
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.down").font(.title2.bold()).foregroundStyle(Theme.highlight)
                        Text(PreviewText.sentence(detail)).font(.caption).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
                    }
                    Spacer()
                }
                if detail.goesToTrash {
                    PanelNote(icon: "trash.fill", text: "Goes to the Trash. Nothing is deleted for good; you can undo it.",
                              color: Theme.danger)
                } else if let final = detail.finalLocation {
                    PathBox(title: "To", url: final, highlightName: detail.nameChanges, tint: Theme.info)
                }

                ForEach(PreviewText.explanations(detail), id: \.text) { note in
                    PanelNote(icon: note.icon, text: note.text, color: note.color)
                }

                if detail.steps.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Steps, in order").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                        ForEach(detail.steps) { step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(step.index + 1)").font(.caption.bold()).frame(width: 18, height: 18)
                                    .background(Circle().fill(PreviewText.verbGradient(step.verb)))
                                Text(PreviewText.stepText(step)).font(.caption).foregroundStyle(Theme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .glassCard(padding: 12, radius: 14)
                }

                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([detail.item.file]) }
                        .buttonStyle(GlassButtonStyle())
                    Spacer()
                    Button("Discard") { discard([detail.item]) }.buttonStyle(GlassButtonStyle())
                    Button("Run") { run([detail.item]) }.buttonStyle(GradientButtonStyle())
                }
            }
            .padding(16)
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.cardStroke))
    }
}

private struct PathBox: View {
    let title: String
    let url: URL
    let highlightName: Bool
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10, weight: .heavy)).foregroundStyle(tint)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "folder.fill").foregroundStyle(tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(PathTools.abbreviate(url.deletingLastPathComponent().path) + "/")
                        .font(.system(.callout, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                    Text(url.lastPathComponent)
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                        .foregroundStyle(highlightName ? Theme.highlight : Theme.textPrimary)
                }
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 12, radius: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct PanelNote: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).accessibilityHidden(true)
            Text(text).font(.caption).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.14)))
    }
}

/// Finder's icon for a file, cached.
struct FileIconView: View {
    let url: URL
    let size: CGFloat

    @MainActor private static var cache: [String: NSImage] = [:]

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @MainActor private var icon: NSImage {
        if let cached = FileIconView.cache[url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        FileIconView.cache[url.path] = image
        return image
    }
}

// MARK: - Wording

private struct Note {
    let text: String
    let icon: String
    let color: Color
}

private enum PreviewText {
    static let orange = Theme.warning
    static let red = Theme.danger
    static let green = Theme.done

    static func verbTitle(_ verb: String) -> String {
        switch verb {
        case "move": return "MOVE"
        case "copy": return "COPY"
        case "rename": return "RENAME"
        case "trash": return "TRASH"
        case "archive": return "ZIP"
        case "extract": return "EXTRACT"
        case "alias": return "ALIAS"
        case "shortcut": return "SHORTCUT"
        case "add_tags", "remove_tags": return "TAGS"
        case "set_color": return "COLOR"
        case "open": return "OPEN"
        default: return verb.uppercased()
        }
    }

    static func verbGradient(_ verb: String) -> LinearGradient {
        switch verb {
        case "move": return Theme.cool
        case "copy", "archive", "extract", "alias": return AppSection.activity.gradient
        case "rename": return AppSection.ai.gradient
        case "trash": return AppSection.smartTrash.gradient
        default: return AppSection.general.gradient
        }
    }

    static func meta(_ detail: PreviewDetail) -> String {
        var parts = [detail.kind.title]
        if let size = detail.size { parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        if let added = detail.added { parts.append("added \(added.formatted(date: .abbreviated, time: .omitted))") }
        return parts.joined(separator: " · ")
    }

    static func sentence(_ detail: PreviewDetail) -> String {
        "\(detail.item.ruleName): \(detail.item.summary)"
    }

    static func stepText(_ step: StepPreview) -> String {
        let to = step.finalTo.map { PathTools.abbreviate($0.path) } ?? step.plannedTo.map { PathTools.abbreviate($0.path) } ?? ""
        switch step.verb {
        case "move": return "Move to \(to)"
        case "copy": return "Copy to \(to) (original stays)"
        case "rename": return "Rename to “\((step.finalTo ?? step.plannedTo)?.lastPathComponent ?? "")”"
        case "archive": return "Zip to \(to) (original stays)"
        case "trash": return "Move to the Trash"
        default:
            return PlannedStep(action: step.action, source: step.from, target: step.plannedTo).summary
        }
    }

    static func warnings(_ detail: PreviewDetail) -> [Note] {
        var notes: [Note] = []
        for step in detail.steps {
            switch step.conflict {
            case .numbered(let name): notes.append(Note(text: "Name taken → “\(name)”", icon: "number", color: orange))
            case .skipped: notes.append(Note(text: "Name taken → skipped", icon: "forward.fill", color: red))
            case .replaces: notes.append(Note(text: "Replaces existing file", icon: "arrow.triangle.2.circlepath", color: red))
            case .blocked: notes.append(Note(text: "Name taken, replacing not allowed", icon: "hand.raised.fill", color: red))
            case .movesExistingAside(let name):
                notes.append(Note(text: "Existing file → “\(name)”", icon: "arrow.left.arrow.right", color: orange))
            case .none: break
            }
        }
        if detail.createsFolder { notes.append(Note(text: "Creates folder", icon: "folder.badge.plus", color: green)) }
        return notes
    }

    static func explanations(_ detail: PreviewDetail) -> [Note] {
        var notes: [Note] = []
        for step in detail.steps {
            switch step.conflict {
            case .numbered(let name):
                notes.append(Note(text: "A file named “\(step.plannedTo?.lastPathComponent ?? "")” is already there (or another waiting item takes that name), so this one will be saved as “\(name)”. Nothing is overwritten.",
                                  icon: "number", color: orange))
            case .skipped:
                notes.append(Note(text: "A file with the same name is already there and the rule says “skip”, so this item stays where it is.",
                                  icon: "forward.fill", color: red))
            case .replaces:
                notes.append(Note(text: "The file already at the destination goes to the Trash first, then this one takes its place. Undo brings both back.",
                                  icon: "arrow.triangle.2.circlepath", color: red))
            case .blocked:
                notes.append(Note(text: "The rule asks to replace the existing file but “Allow replacing existing files” is off for it, so this item stays where it is.",
                                  icon: "hand.raised.fill", color: red))
            case .movesExistingAside(let name):
                notes.append(Note(text: "A file with this name is already there. It will be renamed to “\(name)” and this item takes the name. Undo swaps them back.",
                                  icon: "arrow.left.arrow.right", color: orange))
            case .none:
                break
            }
            if step.createsFolder, let folder = step.plannedTo?.deletingLastPathComponent() {
                notes.append(Note(text: "The folder \(PathTools.abbreviate(folder.path)) doesn't exist yet and will be created.",
                                  icon: "folder.badge.plus", color: green))
            }
        }
        if notes.isEmpty && !detail.goesToTrash {
            notes.append(Note(text: "No conflicts: the destination is free.", icon: "checkmark.circle.fill", color: green))
        }
        notes.append(Note(text: "Every step is logged and can be undone from Activity.", icon: "arrow.uturn.backward.circle", color: Theme.info))
        return notes
    }
}

private struct SummaryChip: View {
    let value: String
    let label: String
    let icon: String
    let gradient: LinearGradient
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                GradientIcon(systemName: icon, gradient: gradient, size: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(value).font(.system(.headline, design: .rounded).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                    Text(label).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(active ? Theme.rowFillActive : Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(active ? Theme.highlight.opacity(0.7) : Theme.cardStroke))
        }
        .buttonStyle(.plain)
        .help("Show only: \(label)")
        .accessibilityLabel("\(value) \(label)")
    }
}
