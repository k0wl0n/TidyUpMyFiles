import TidyUpMyFilesCore
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    let openSection: (AppSection) -> Void
    @State private var confirmGoLive = false

    private var watchedCount: Int { model.config.folders.filter(\.enabled).count }
    private var ruleCount: Int { model.config.folders.reduce(0) { $0 + $1.rules.count } }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                hero
                HStack(spacing: 14) {
                    Button { openSection(.activity) } label: {
                        StatTile(value: "\(model.todayCount)", label: "Tidied today", icon: "checkmark.seal.fill", gradient: Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("See what was tidied in Activity")
                    Button { openSection(.preview) } label: {
                        StatTile(value: "\(model.previews.count)", label: "Waiting in preview", icon: "eye.fill",
                                 gradient: AppSection.preview.gradient)
                    }
                    .buttonStyle(.plain)
                    .help("Review what is waiting for your OK")
                    StatTile(value: "\(watchedCount)", label: "Folders watched", icon: "folder.fill", gradient: Theme.cool)
                        .help("Folders TidyUpMyFiles keeps tidy. Add more with “Watch a folder…”.")
                    StatTile(value: "\(ruleCount)", label: "Rules", icon: "slider.horizontal.3", gradient: AppSection.ai.gradient)
                        .help("Rules decide what goes where. Change them in Rules.")
                }
                HStack(alignment: .top, spacing: 14) {
                    recentCard
                    templatesCard
                }
            }
            .padding(.bottom, 8)
        }
    }

    /// One button leads the way: Scan (look first) → Tidy N files (do it) → All tidy (with Undo).
    private enum Stage { case setup, scan, working, results, done }

    private var stage: Stage {
        if watchedCount == 0 { return .setup }
        if model.busy { return .working }
        if !model.previews.isEmpty { return .results }
        if model.lastRun != nil { return .done }
        return .scan
    }

    private var hero: some View {
        VStack(spacing: 14) {
            orb.padding(.top, 26)
            Text(headline)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(explanation)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            stageDetails
            HStack(spacing: 22) {
                QuietLink(title: "Watch a folder…", icon: "folder.badge.plus",
                          help: "Choose another folder for TidyUpMyFiles to keep tidy") { model.addFolder() }
                if stage != .done {
                    QuietLink(title: "Undo last", icon: "arrow.uturn.backward",
                              help: "Take back the most recent step (every step can be undone from Activity)") { model.undoLast() }
                }
                QuietLink(title: "Rules", icon: "slider.horizontal.3",
                          help: "See and change what gets tidied and where it goes") { openSection(.rules) }
            }
            .padding(.top, 4)
            recommendedBar
        }
        .frame(maxWidth: .infinity)
        .alert("Turn on \(model.recommendedInPreviewCount) recommended rule(s)?", isPresented: $confirmGoLive) {
            Button("Turn On") { model.makeRecommendedLive() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Matching files will be moved automatically from now on, and old installers go to the Trash. Every step is logged and can be undone.")
        }
    }

    @ViewBuilder
    private var orb: some View {
        switch stage {
        case .setup:
            OrbButton(title: "Start", subtitle: "Set up rules", symbol: "sparkles", busy: false) {
                if model.missingRecommendedCount > 0 { model.installRecommended() } else { model.addFolder() }
            }
            .help("Adds the recommended rules (they only preview until you turn them on)")
        case .scan:
            OrbButton(title: "Scan", subtitle: "\(watchedCount) folder(s)", symbol: "magnifyingglass", busy: false) {
                model.simulateAll()
            }
            .help("Looks at your watched folders and shows what could be tidied. Nothing moves yet.")
        case .working:
            OrbButton(title: model.work?.kind == .simulating ? "Scanning…" : "Tidying…",
                      subtitle: model.work.map { "\(min($0.done + 1, $0.total)) of \($0.total)" },
                      busy: true, progress: model.work.flatMap { $0.total > 0 ? $0.fraction : nil }) {}
                .disabled(true)
                .help("Working — the banner at the top shows details and has Cancel")
        case .results:
            OrbButton(title: "See results", subtitle: "\(model.previews.count) file(s) found", symbol: "eye", busy: false) {
                openSection(.preview)
            }
            .help("Open Preview to check where each file would go. Nothing moves until you press Run there.")
        case .done:
            OrbButton(title: "All tidy", subtitle: "Scan again", symbol: "checkmark", busy: false, breathing: false) {
                model.lastRun = nil
                model.simulateAll()
            }
            .help("Everything found was tidied. Press to look again.")
        }
    }

    private var headline: String {
        switch stage {
        case .setup: return "Let's set up your first folder."
        case .scan: return "Ready when you are."
        case .working: return model.work?.kind == .simulating ? "Scanning your folders…" : "Tidying…"
        case .results: return "Scan finished — \(model.previews.count) file(s) found"
        case .done: return "All tidy ✓"
        }
    }

    private var explanation: String {
        switch stage {
        case .setup:
            return "Press Start to add the recommended rules. They only preview — nothing moves until you say so."
        case .scan:
            return "Press Scan to see what can be tidied in your \(watchedCount) watched folder(s). Nothing moves until you press Tidy."
        case .working:
            return model.work?.kind == .simulating ? "Only looking — nothing is moved while scanning." : "Every step is logged and can be undone."
        case .results:
            return "Nothing has moved. See results to check each file's from → to, then run what you want in Preview."
        case .done:
            return model.lastRun.map { "\($0.summary). Every step can be undone." } ?? ""
        }
    }

    /// Where the scanned files will go (results) or what just happened (done), with the next choices.
    @ViewBuilder
    private var stageDetails: some View {
        switch stage {
        case .results:
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(destinationSummary, id: \.title) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.icon).accessibilityHidden(true)
                            Text(item.title).lineLimit(1).truncationMode(.middle)
                            Text("\(item.count)").bold()
                        }
                        .font(.callout)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .overlay(Capsule().stroke(Theme.cardStroke))
                        .help("\(item.count) file(s) go to \(item.fullPath)")
                    }
                }
                HStack(spacing: 18) {
                    QuietLink(title: "Scan again", icon: "arrow.clockwise",
                              help: "Look at your folders again. Nothing moves.") { model.simulateAll() }
                    QuietLink(title: "Clear results", icon: "xmark.circle",
                              help: "Clear this list without changing anything") { model.discard(model.previews) }
                }
            }
        case .done:
            HStack(spacing: 18) {
                QuietLink(title: "See what happened", icon: "clock.arrow.circlepath",
                          help: "Open this run in Activity: every file's from → to") { model.showRun(model.lastRun?.batchIDs.first) }
                if let report = model.lastRun, !report.done.isEmpty {
                    QuietLink(title: "Undo", icon: "arrow.uturn.backward",
                              help: "Put every file from this run back where it was") { model.undoRun(report) }
                }
            }
        default:
            EmptyView()
        }
    }

    private struct DestinationCount {
        let title: String
        var fullPath: String = ""
        let icon: String
        let count: Int
    }

    private var destinationSummary: [DestinationCount] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for detail in model.previewDetails {
            let key = detail.goesToTrash ? "Trash"
                : detail.destinationFolder.map { PathTools.abbreviate($0.path) } ?? "Stays"
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }
        let top = order.sorted { counts[$0, default: 0] > counts[$1, default: 0] }.prefix(4)
        var summary = top.map { key in
            DestinationCount(title: key == "Trash" ? "Trash" : (key as NSString).lastPathComponent, fullPath: key,
                             icon: key == "Trash" ? "trash" : "folder", count: counts[key, default: 0])
        }
        let rest = order.count - top.count
        if rest > 0 {
            let restCount = order.dropFirst(0).filter { !top.contains($0) }.reduce(0) { $0 + counts[$1, default: 0] }
            summary.append(DestinationCount(title: "\(rest) more place(s)", fullPath: "other folders (see Review details)",
                                            icon: "ellipsis", count: restCount))
        }
        return summary
    }

    @ViewBuilder
    private var recommendedBar: some View {
        if model.missingRecommendedCount > 0 {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars").foregroundStyle(Theme.highlight).accessibilityHidden(true)
                Text("\(model.missingRecommendedCount) recommended rule(s) not set up yet.")
                    .foregroundStyle(Theme.textPrimary)
                Button("Use Recommended Rules") { model.installRecommended() }
                    .buttonStyle(GradientButtonStyle())
            }
            .font(.callout)
            .glassCard(padding: 10, radius: 16)
        } else if model.recommendedInPreviewCount > 0 {
            HStack(spacing: 10) {
                Image(systemName: "eye.fill").foregroundStyle(Theme.highlight).accessibilityHidden(true)
                Text("\(model.recommendedInPreviewCount) recommended rule(s) are only previewing.")
                    .foregroundStyle(Theme.textPrimary)
                Button("Turn Them On") { confirmGoLive = true }
                    .buttonStyle(GradientButtonStyle())
            }
            .font(.callout)
            .glassCard(padding: 10, radius: 16)
        }
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent activity").font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("See all") { openSection(.activity) }.buttonStyle(.plain).foregroundStyle(Theme.highlight)
            }
            if model.recent.isEmpty {
                Text("Nothing yet. Tidied files will show up here.").foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(model.recent.prefix(5)) { record in
                    ActivityLine(record: record).foregroundStyle(Theme.textPrimary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .glassCard()
    }

    private var templatesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ready-made rules").font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Open Rules") { openSection(.rules) }.buttonStyle(.plain).foregroundStyle(Theme.highlight)
            }
            ForEach(Templates.all) { template in
                HStack(spacing: 10) {
                    GradientIcon(systemName: TemplateStyle.icon(template.id), gradient: TemplateStyle.gradient(template.id), size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(template.title).foregroundStyle(Theme.textPrimary).font(.callout.weight(.semibold))
                        Text(template.detail).foregroundStyle(Theme.textSecondary).font(.caption).lineLimit(1)
                    }
                    Spacer()
                    if model.isInstalled(template) {
                        Image(systemName: "checkmark.circle.fill").font(.title3)
                            .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.65))
                            .accessibilityLabel("\(template.title) already added")
                    } else {
                        Button { model.install(template) } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.highlight)
                            .accessibilityLabel("Add template \(template.title)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .glassCard()
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let icon: String
    let gradient: LinearGradient

    var body: some View {
        HStack(spacing: 12) {
            GradientIcon(systemName: icon, gradient: gradient, size: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 14, radius: 16)
        .accessibilityElement(children: .combine)
    }
}

enum TemplateStyle {
    static func icon(_ id: String) -> String {
        switch id {
        case "screenshots": return "camera.viewfinder"
        case "old-installers": return "shippingbox.fill"
        case "images": return "photo.fill"
        case "pdf": return "doc.richtext.fill"
        case "archives": return "archivebox.fill"
        case "duplicates": return "doc.on.doc.fill"
        case "documents": return "doc.text.fill"
        case "spreadsheets": return "tablecells.fill"
        case "presentations": return "rectangle.on.rectangle.angled"
        case "videos": return "film.fill"
        case "audio": return "music.note"
        case "code": return "curlybraces"
        case "ebooks": return "book.fill"
        case "fonts": return "textformat"
        default: return "calendar.badge.clock"
        }
    }

    static func gradient(_ id: String) -> LinearGradient {
        switch id {
        case "screenshots": return Theme.cool
        case "old-installers": return AppSection.smartTrash.gradient
        case "images": return AppSection.activity.gradient
        case "pdf": return AppSection.preview.gradient
        case "archives": return AppSection.ai.gradient
        case "duplicates": return AppSection.smartTrash.gradient
        case "documents": return Theme.cool
        case "spreadsheets": return AppSection.activity.gradient
        case "presentations": return AppSection.preview.gradient
        case "videos": return Theme.gradient(Color(red: 1, green: 0.35, blue: 0.45), Theme.purple)
        case "audio": return Theme.gradient(Theme.highlight, Color(red: 1, green: 0.55, blue: 0.3))
        case "code": return AppSection.general.gradient
        case "ebooks": return Theme.gradient(Color(red: 0.55, green: 0.4, blue: 0.25), Color(red: 0.85, green: 0.6, blue: 0.3))
        case "fonts": return AppSection.ai.gradient
        default: return Theme.accent
        }
    }
}
