import TidyUpMyFilesCore
import SwiftUI

struct RuleEditor: View {
    @EnvironmentObject private var model: AppModel
    @Binding var rule: Rule
    let folder: WatchedFolder
    @State private var matches: [PreviewItem] = []
    @State private var loadingMatches = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                EditorCard(title: "When", icon: "line.3.horizontal.decrease", gradient: Theme.cool) {
                    ConditionEditor(condition: $rule.condition, onDelete: nil)
                }
                EditorCard(title: "Do, in order", icon: "arrow.right", gradient: Theme.accent) {
                    ActionListEditor(actions: $rule.actions)
                }
                livePreview
            }
            .padding(20)
        }
        .task(id: rule) { await refreshMatches() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Rule name", text: $rule.name)
                    .font(.title3)
                    .textFieldStyle(.roundedBorder)
                Toggle("On", isOn: $rule.enabled)
                    .toggleStyle(.switch)
                    .accessibilityLabel("Rule enabled")
            }
            HStack(spacing: 18) {
                Picker("Mode", selection: $rule.mode) {
                    Text("Preview only").tag(RuleMode.preview)
                    Text("Live").tag(RuleMode.live)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                .help("Preview only lists what would happen; Live acts automatically")
                Toggle("Continue matching after this rule", isOn: $rule.continueMatching)
            }
            Toggle("Allow replacing existing files (on conflict: overwrite)", isOn: $rule.allowOverwrite)
            if rule.allowOverwrite {
                Text("Replaced files are moved to the Trash and come back if you undo.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing: 14) {
                Text("Watching \(folder.path)").font(.caption).foregroundStyle(.secondary)
                let others = model.config.folders.filter { $0.id != folder.id }
                if !others.isEmpty {
                    Menu("Also use in…") {
                        ForEach(others) { other in
                            Button(other.path) { model.copyRule(rule, to: other) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .font(.caption)
                    .help("Copy this rule to another watched folder, so it works there too")
                }
            }
        }
    }

    private var livePreview: some View {
        EditorCard(title: "Live preview — matching items now", icon: "eye.fill", gradient: AppSection.preview.gradient) {
            VStack(alignment: .leading, spacing: 6) {
                if loadingMatches {
                    ProgressView().controlSize(.small)
                } else if matches.isEmpty {
                    Text("No items in \(folder.path) match right now.").foregroundStyle(.secondary)
                } else {
                    ForEach(matches.prefix(40)) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: "doc").foregroundStyle(.secondary).accessibilityHidden(true)
                            Text(item.file.lastPathComponent).lineLimit(1)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                            Text(item.summary).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        .font(.callout)
                    }
                    if matches.count > 40 {
                        Text("…and \(matches.count - 40) more").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Run This Rule on These \(matches.count) Item(s)") { model.approve(matches) }
                        .buttonStyle(GradientButtonStyle())
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func refreshMatches() async {
        loadingMatches = true
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        matches = await model.simulate(folder, rule: rule)
        loadingMatches = false
    }
}

/// A titled frosted section inside the rule editor.
struct EditorCard<Content: View>: View {
    let title: String
    let icon: String
    let gradient: LinearGradient
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                GradientIcon(systemName: icon, gradient: gradient, size: 22)
                Text(title).font(.system(.headline, design: .rounded))
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16, radius: 16)
    }
}
