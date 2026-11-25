import SwiftUI
import TidyUpMyFilesCore

/// TidyUpMyFiles's look: a deep violet-to-teal backdrop with soft glows, frosted cards and bright gradient icons.
enum Theme {
    static let ink = Color(red: 0.07, green: 0.05, blue: 0.16)
    static let violet = Color(red: 0.23, green: 0.09, blue: 0.40)
    static let deepTeal = Color(red: 0.04, green: 0.20, blue: 0.32)
    static let pink = Color(red: 1.00, green: 0.37, blue: 0.64)
    static let purple = Color(red: 0.55, green: 0.36, blue: 0.97)
    static let cyan = Color(red: 0.19, green: 0.82, blue: 1.00)
    static let done = Color(red: 0.4, green: 0.95, blue: 0.65)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let cardFill = Color.white.opacity(0.07)
    static let cardStroke = Color.white.opacity(0.12)

    static let accent = LinearGradient(colors: [pink, purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cool = LinearGradient(colors: [cyan, Color(red: 0.25, green: 0.45, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func gradient(_ first: Color, _ second: Color) -> LinearGradient {
        LinearGradient(colors: [first, second], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Full-window backdrop with two blurred colour glows.
struct AppBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.ink, Theme.violet, Theme.deepTeal], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Theme.pink.opacity(0.35), .clear], center: .init(x: 0.85, y: 0.1), startRadius: 10, endRadius: 520)
            RadialGradient(colors: [Theme.cyan.opacity(0.22), .clear], center: .init(x: 0.15, y: 0.95), startRadius: 10, endRadius: 560)
        }
        .ignoresSafeArea()
    }
}

/// Frosted card used for every panel.
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
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .accessibilityHidden(true)
    }
}

/// Large pill button with the accent gradient.
struct GradientButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Capsule().fill(gradient))
            .shadow(color: Theme.pink.opacity(configuration.isPressed ? 0.15 : 0.35), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Quiet translucent pill for secondary actions.
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0.10)))
            .overlay(Capsule().stroke(Theme.cardStroke))
    }
}

/// The big round button in the middle of Overview. It "breathes" (slowly grows and glows) while it waits,
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
                Circle().fill(Theme.accent.opacity(inhale && animates ? 0.42 : 0.24))
                    .frame(width: 190, height: 190).blur(radius: 22)
                Circle().stroke(Color.white.opacity(0.14), lineWidth: 1).frame(width: 164, height: 164)
                if let progress, busy {
                    Circle().trim(from: 0, to: max(0.02, progress))
                        .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 164, height: 164)
                        .animation(.easeOut(duration: 0.2), value: progress)
                }
                Circle().fill(Theme.accent).frame(width: 140, height: 140)
                    .shadow(color: Theme.pink.opacity(inhale && animates ? 0.75 : 0.45), radius: inhale && animates ? 28 : 16)
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
            .scaleEffect(inhale && animates ? 1.05 : 1.0)
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
                ProgressView().controlSize(.small).tint(.white)
                VStack(alignment: .leading, spacing: 5) {
                    Text(WorkText.title(model)).font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(.white)
                    Text(WorkText.detail(model.work)).font(.caption).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                    if let work = model.work, work.total > 0 {
                        ProgressView(value: work.fraction).tint(Theme.pink)
                    } else {
                        ProgressView().progressViewStyle(.linear).tint(Theme.pink)
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
