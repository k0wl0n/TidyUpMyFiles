import SwiftUI
import TidyUpMyFilesCore

/// TidyUpMyFiles's look: plain macOS grays that follow the system's light or dark appearance, with colour
/// only where it means something (the system accent for actions, green for done, teal for information).
enum Theme {
    static let background = adaptive(light: 0.95, dark: 0.11)
    static let cardFill = adaptive(light: 1.0, dark: 0.17)
    static let cardStroke = Color.primary.opacity(0.09)

    /// Rows and boxes inside a card, and the same when focused or selected.
    static let rowFill = adaptive(light: 0.965, dark: 0.21)
    static let rowFillActive = adaptive(light: 0.915, dark: 0.26)

    static let highlight = Color.accentColor
    static let purple = Color(nsColor: .systemPurple)
    // Status colours are darker in light mode so text stays readable on white.
    static let info = adaptive(light: (0.0, 0.45, 0.58), dark: (0.35, 0.82, 0.95))
    static let done = adaptive(light: (0.10, 0.50, 0.22), dark: (0.40, 0.90, 0.60))
    static let warning = adaptive(light: (0.72, 0.38, 0.0), dark: (1.0, 0.72, 0.35))
    static let danger = adaptive(light: (0.78, 0.12, 0.18), dark: (1.0, 0.47, 0.52))

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary

    static let accent = LinearGradient(colors: [highlight, highlight], startPoint: .top, endPoint: .bottom)
    static let cool = gradient(Color(red: 0.0, green: 0.52, blue: 0.68), Color(red: 0.0, green: 0.40, blue: 0.80))

    /// A gray that is `light` (0–1) in light mode and `dark` in dark mode.
    private static func adaptive(light: CGFloat, dark: CGFloat) -> Color {
        adaptive(light: (light, light, light), dark: (dark, dark, dark))
    }

    /// An RGB colour with one value for light mode and one for dark mode.
    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }

    static func gradient(_ first: Color, _ second: Color) -> LinearGradient {
        LinearGradient(colors: [first, second], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Full-window background.
struct AppBackdrop: View {
    var body: some View {
        Theme.background.ignoresSafeArea()
    }
}

/// Card used for every panel.
struct GlassCard: ViewModifier {
    var padding: CGFloat = 18
    var radius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }
}

extension View {
    func glassCard(padding: CGFloat = 18, radius: CGFloat = 20) -> some View {
        modifier(GlassCard(padding: padding, radius: radius))
    }

    /// Lets the backdrop show through Forms, Lists and Tables.
    func clearScrollBackground() -> some View {
        scrollContentBackground(.hidden)
    }
}

/// A rounded square filled with a gradient and a white symbol.
struct GradientIcon: View {
    let systemName: String
    let gradient: LinearGradient
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(gradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: systemName).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
            .accessibilityHidden(true)
    }
}

/// Large pill button in the accent colour.
struct GradientButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Capsule().fill(gradient))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Quiet gray pill for secondary actions.
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07)))
            .overlay(Capsule().stroke(Theme.cardStroke))
    }
}

/// The big round button in the middle of Overview. It "breathes" (slowly grows) while it waits,
/// shows a progress ring while busy, and keeps still when Reduce motion is on.
struct OrbButton: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    let busy: Bool
    var progress: Double? = nil
    var breathing = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inhale = false

    private var animates: Bool { breathing && !busy && !reduceMotion }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.highlight.opacity(inhale && animates ? 0.16 : 0.08))
                    .frame(width: 176, height: 176)
                Circle().stroke(Theme.cardStroke, lineWidth: 1).frame(width: 164, height: 164)
                if let progress, busy {
                    Circle().trim(from: 0, to: max(0.02, progress))
                        .stroke(Theme.highlight, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 164, height: 164)
                        .animation(.easeOut(duration: 0.2), value: progress)
                }
                Circle().fill(Theme.accent).frame(width: 140, height: 140)
                VStack(spacing: 2) {
                    if busy && progress == nil {
                        ProgressView().controlSize(.regular).tint(.white)
                    } else if let symbol {
                        Image(systemName: symbol).font(.system(size: 34, weight: .bold))
                    }
                    Text(title).font(.system(size: busy ? 18 : 24, weight: .bold, design: .rounded))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 12, weight: .semibold, design: .rounded)).opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(width: 124)
            }
            .scaleEffect(inhale && animates ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .onAppear { startBreathing() }
        .onChange(of: animates) { _ in startBreathing() }
    }

    private func startBreathing() {
        guard animates else {
            inhale = false
            return
        }
        inhale = false
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { inhale = true }
    }
}

/// A quiet text button for secondary actions under the main flow.
struct QuietLink: View {
    let title: String
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.callout.weight(.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textSecondary)
        .help(help)
    }
}

/// Header shown at the top of each section.
struct SectionHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: LinearGradient

    var body: some View {
        HStack(spacing: 14) {
            GradientIcon(systemName: icon, gradient: gradient, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.callout).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }
}

/// The app icon as a small logo.
struct AppLogo: View {
    var size: CGFloat = 34
    private static let image = IconArt.image(pixels: 256)

    var body: some View {
        Image(nsImage: AppLogo.image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Words for what a long task is doing right now.
@MainActor
enum WorkText {
    static func title(_ model: AppModel) -> String {
        if let title = model.operationTitle { return title }
        switch model.work?.kind {
        case .checkingNewFiles: return "Checking new files"
        case .simulating: return "Simulating — nothing will be moved"
        case .tidying: return "Tidying"
        case .applying: return "Running approved items"
        case nil: return "Working"
        }
    }

    static func detail(_ progress: WorkProgress?) -> String {
        guard let progress else { return "Starting…" }
        var parts = [PathTools.abbreviate(progress.folder)]
        if progress.total > 0 { parts.append("\(min(progress.done + 1, progress.total)) of \(progress.total)") }
        if let item = progress.item { parts.append(item) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Shown on every screen while a scan or run is going, so it's always clear the app is busy.
struct WorkBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.busy || model.work != nil {
            HStack(spacing: 14) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 5) {
                    Text(WorkText.title(model)).font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text(WorkText.detail(model.work)).font(.caption).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                    if let work = model.work, work.total > 0 {
                        ProgressView(value: work.fraction).tint(Theme.highlight)
                    } else {
                        ProgressView().progressViewStyle(.linear).tint(Theme.highlight)
                    }
                }
                if model.busy {
                    Button("Cancel") { model.cancelWork() }
                        .buttonStyle(GlassButtonStyle())
                        .keyboardShortcut(.cancelAction)
                        .accessibilityHint("Stops after the current item; finished steps can be undone")
                }
            }
            .glassCard(padding: 12, radius: 14)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(WorkText.title(model)), \(WorkText.detail(model.work))")
        }
    }
}
