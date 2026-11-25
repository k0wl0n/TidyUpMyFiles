import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview, rules, preview, activity, smartTrash, ai, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .rules: return "Rules"
        case .preview: return "Preview"
        case .activity: return "Activity"
        case .smartTrash: return "Smart Trash"
        case .ai: return "AI Assistant"
        case .general: return "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "Everything at a glance"
        case .rules: return "What to look for and what to do"
        case .preview: return "Waiting for your OK — nothing has happened yet"
        case .activity: return "Every step, searchable and undoable"
        case .smartTrash: return "Let old Trash items go"
        case .ai: return "Optional suggestions, always reviewed by you"
        case .general: return "Watching, startup, import and export"
        }
    }

    /// Shown when hovering over the sidebar item.
    var tooltip: String {
        switch self {
        case .overview: return "Scan your folders and tidy them with one button"
        case .rules: return "What to look for and where it goes — ready-made rules and your own"
        case .preview: return "Everything waiting for your OK, with each file's from → to"
        case .activity: return "What happened to every file, with Undo and readable log files"
        case .smartTrash: return "Optionally let old items leave the Trash after a while"
        case .ai: return "Optional AI suggestions for where files should go — always reviewed by you"
        case .general: return "Watching, startup, notifications, permissions, import and export"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "sparkles"
        case .rules: return "slider.horizontal.3"
        case .preview: return "eye.fill"
        case .activity: return "clock.arrow.circlepath"
        case .smartTrash: return "trash.fill"
        case .ai: return "wand.and.stars"
        case .general: return "gearshape.fill"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .overview: return Theme.accent
        case .rules: return Theme.cool
        case .preview: return Theme.gradient(Color(red: 1, green: 0.72, blue: 0.2), Color(red: 1, green: 0.45, blue: 0.25))
        case .activity: return Theme.gradient(Color(red: 0.25, green: 0.9, blue: 0.6), Color(red: 0.1, green: 0.65, blue: 0.7))
        case .smartTrash: return Theme.gradient(Color(red: 1, green: 0.4, blue: 0.45), Color(red: 0.85, green: 0.2, blue: 0.5))
        case .ai: return Theme.gradient(Theme.purple, Color(red: 0.3, green: 0.35, blue: 1))
        case .general: return Theme.gradient(Color(white: 0.6), Color(red: 0.4, green: 0.45, blue: 0.6))
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    /// `TIDYUP_START_SECTION=rules` opens another section first (handy for screenshots).
    @State private var section: AppSection = AppSection(rawValue: ProcessInfo.processInfo.environment["TIDYUP_START_SECTION"] ?? "") ?? .overview

    var body: some View {
        ZStack {
            AppBackdrop()
            HStack(spacing: 0) {
                sidebar
                content
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.pink)
        .onChange(of: model.requestedSection) { requested in
            guard let requested else { return }
            section = requested
            model.requestedSection = nil
        }
        .frame(minWidth: 940, minHeight: 600)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                AppLogo(size: 34)
                Text("TidyUpMyFiles").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 10)
            .padding(.top, 44)
            .padding(.bottom, 18)

            ForEach(AppSection.allCases) { item in
                Button { section = item } label: {
                    HStack(spacing: 10) {
                        GradientIcon(systemName: item.icon, gradient: item.gradient, size: 24)
                        Text(item.title).font(.system(.body, design: .rounded).weight(.medium))
                        Spacer()
                        if let badge = badge(for: item) {
                            Text(badge).font(.caption2.bold())
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.pink))
                        }
                    }
                    .foregroundStyle(.white.opacity(section == item ? 1 : 0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(section == item ? 0.13 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .help(item.tooltip)
                .accessibilityAddTraits(section == item ? .isSelected : [])
            }

            Spacer()
            statusPill
        }
        .padding(12)
        .frame(width: 220)
        .background(Color.black.opacity(0.22))
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            if model.busy || model.work != nil {
                ProgressView().controlSize(.mini).tint(.white)
            } else {
                Circle().fill(model.settings.paused ? Color.orange : Color.green).frame(width: 8, height: 8)
            }
            Text(model.busy || model.work != nil ? "Scanning…" : (model.settings.paused ? "Paused" : "Watching"))
                .font(.callout.weight(.medium))
            Spacer()
            Button(model.settings.paused ? "Resume" : "Pause") { model.togglePause() }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(Theme.pink)
        }
        .help("Watching means new files in your folders are handled as they arrive. Pause stops that until you resume.")
        .foregroundStyle(.white)
        .glassCard(padding: 10, radius: 12)
        .accessibilityElement(children: .combine)
    }

    private func badge(for item: AppSection) -> String? {
        switch item {
        case .preview: return model.previews.isEmpty ? nil : "\(model.previews.count)"
        case .ai: return model.aiSuggestions.isEmpty ? nil : "\(model.aiSuggestions.count)"
        default: return nil
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            if section != .overview {
                SectionHeader(title: section.title, subtitle: section.subtitle, icon: section.icon, gradient: section.gradient)
            }
            WorkBanner()
            if section != .overview {
                // The Overview tells the same story around its main button.
                RunReportCard()
            }
            Group {
                switch section {
                case .overview: OverviewView(openSection: { section = $0 })
                case .rules: RulesTab()
                case .preview: PreviewTab()
                case .activity: ActivityTab()
                case .smartTrash: SmartTrashTab()
                case .ai: AITab()
                case .general: GeneralTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let message = model.message {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(Theme.cyan).accessibilityHidden(true)
                    Text(message).lineLimit(3).foregroundStyle(.white)
                    Spacer()
                    ForEach(Array(model.messageActions.enumerated()), id: \.element.id) { index, action in
                        Button(action.title) { model.handle(action) }
                            .buttonStyle(GradientButtonStyle(gradient: index == model.messageActions.count - 1 ? Theme.accent : Theme.cool))
                    }
                    Button("Dismiss") { model.message = nil }.buttonStyle(GlassButtonStyle())
                }
                .font(.callout)
                .glassCard(padding: 12, radius: 14)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 36)
        .padding(.bottom, 20)
    }
}
