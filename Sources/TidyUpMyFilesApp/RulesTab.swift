import TidyUpMyFilesCore
import SwiftUI

enum RuleSelection: Hashable {
    case folder(UUID)
    case rule(folder: UUID, rule: UUID)

    var folderID: UUID {
        switch self {
        case .folder(let id), .rule(let id, _): return id
        }
    }
}

struct RulesTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: RuleSelection?
    /// Where the gallery adds ready-made rules; nil means each rule's usual folder.
    @State private var galleryTarget: String?

    var body: some View {
        HStack(spacing: 14) {
            sidebar
                .frame(width: 240)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.cardFill))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.cardStroke))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear(perform: stageRuleEditor)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.cardFill))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.cardStroke))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(model.config.folders) { folder in
                    Section {
                        ForEach(folder.rules) { rule in
                            RuleRow(rule: rule).tag(RuleSelection.rule(folder: folder.id, rule: rule.id))
                        }
                    } header: {
                        Label(folder.path, systemImage: folder.enabled ? "folder.fill" : "folder")
                            .foregroundStyle(folder.enabled ? .primary : .secondary)
                            .tag(RuleSelection.folder(folder.id))
                            .contentShape(Rectangle())
                            .onTapGesture { selection = .folder(folder.id) }
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            .listStyle(.sidebar)
            .clearScrollBackground()
            .overlay {
                if model.config.folders.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                        Text("No folders yet").font(.headline)
                        Text("Add a folder or a ready-made rule to start.").font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }

            Divider().overlay(Theme.cardStroke)
            HStack(spacing: 8) {
                Button { model.addFolder() } label: { Image(systemName: "folder.badge.plus") }
                    .help("Watch a folder")
                    .accessibilityLabel("Add folder")
                Button { addRule() } label: { Image(systemName: "plus") }
                    .help("New rule in the selected folder")
                    .accessibilityLabel("Add rule")
                    .disabled(selection == nil)
                Button { removeSelected() } label: { Image(systemName: "minus") }
                    .help("Remove the selected rule or folder")
                    .accessibilityLabel("Remove")
                    .disabled(selection == nil)
                Button { moveSelected(-1) } label: { Image(systemName: "arrow.up") }
                    .help("Higher priority")
                    .accessibilityLabel("Move rule up")
                Button { moveSelected(1) } label: { Image(systemName: "arrow.down") }
                    .help("Lower priority")
                    .accessibilityLabel("Move rule down")
                Spacer()
                templatesMenu
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    private var templatesMenu: some View {
        Menu("Templates") {
            if let folder = selectedFolder {
                // Add ready-made rules to the folder that's selected, whatever their usual folder is.
                Section("Add to \(folder.path)") {
                    ForEach(Templates.all) { template in
                        let added = model.isInstalled(template, folderPath: folder.path)
                        Button(added ? "\(template.title) ✓" : template.title) { model.install(template, folderPath: folder.path) }
                            .disabled(added)
                    }
                }
            } else {
                ForEach(Templates.all) { template in
                    Menu(template.title) { AddToFolderItems(template: template) }
                }
            }
            Divider()
            Button("Add All Recommended") { model.installRecommended() }
                .disabled(model.missingRecommendedCount == 0)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Add a ready-made rule to the selected folder")
    }

    private var selectedFolder: WatchedFolder? {
        guard let id = selection?.folderID else { return nil }
        return model.config.folders.first { $0.id == id }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .rule(let folderID, let ruleID):
            if let binding = ruleBinding(folderID, ruleID), let folder = model.config.folders.first(where: { $0.id == folderID }) {
                RuleEditor(rule: ShotScene.is("rule-live") ? Self.shownAsLive(binding) : binding, folder: folder)
                    .id(ruleID)
            } else {
                emptyState
            }
        case .folder(let folderID):
            if let binding = folderBinding(folderID) {
                FolderDetail(folder: binding)
            } else {
                emptyState
            }
        case nil:
            emptyState
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tidy folders automatically").font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Pick a folder to watch, then add rules: what to look for and what to do with it. New rules start in preview mode, so nothing moves until you say so. Nothing is ever deleted for good — removed files go to the Trash and every step can be undone.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Watch a Folder…") { model.addFolder() }
                        .buttonStyle(GradientButtonStyle(gradient: Theme.cool))
                    Button("Simulate All Folders") { model.simulateAll() }
                        .buttonStyle(GlassButtonStyle())
                        .disabled(model.config.folders.isEmpty)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Ready-made rules").font(.headline)
                    Spacer()
                    galleryTargetPicker
                }
                .padding(.top, 8)
                Text(galleryTarget.map { "Each Add puts the rule in \($0). A rule can be used in as many folders as you like." }
                     ?? "Each rule goes to the folder it's made for. Use “Add to” to put rules in another folder — a rule can be in several folders.")
                    .font(.callout).foregroundStyle(.secondary)
                TemplateGrid(target: galleryTarget)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var galleryTargetPicker: some View {
        Menu {
            Button { galleryTarget = nil } label: { checkLabel("Each rule's usual folder", galleryTarget == nil) }
            if !model.config.folders.isEmpty {
                Section("Your folders") {
                    ForEach(model.config.folders) { folder in
                        Button { galleryTarget = folder.path } label: { checkLabel(folder.path, galleryTarget == folder.path) }
                    }
                }
            }
            Divider()
            Button("Another Folder…") { if let path = model.pickFolderForRules() { galleryTarget = path } }
        } label: {
            Label("Add to: \(galleryTarget ?? "usual folder")", systemImage: "folder")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Choose which folder the Add buttons put rules in")
    }

    @ViewBuilder
    private func checkLabel(_ title: String, _ checked: Bool) -> some View {
        if checked { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    /// Screenshot scene "rule-editor": open a rule (TIDYUP_SHOT_RULE, else the first one).
    private func stageRuleEditor() {
        if ShotScene.is("rules-folder"), let folder = model.config.folders.last {
            selection = .folder(folder.id)
            return
        }
        guard ShotScene.is("rule-editor") || ShotScene.is("rule-live") else { return }
        let wanted = ProcessInfo.processInfo.environment["TIDYUP_SHOT_RULE"]
        for folder in model.config.folders {
            if let rule = folder.rules.first(where: { wanted == nil || $0.name == wanted }) {
                selection = .rule(folder: folder.id, rule: rule.id)
                return
            }
        }
    }

    /// Screenshot scene "rule-live": the rule as it looks switched to Live, without saving that change.
    private static func shownAsLive(_ binding: Binding<Rule>) -> Binding<Rule> {
        Binding(get: { var rule = binding.wrappedValue; rule.mode = .live; return rule }, set: { _ in })
    }

    // MARK: Editing helpers

    private func folderBinding(_ id: UUID) -> Binding<WatchedFolder>? {
        guard model.config.folders.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { model.config.folders.first(where: { $0.id == id }) ?? WatchedFolder(path: "") },
            set: { newValue in
                if let index = model.config.folders.firstIndex(where: { $0.id == id }) { model.config.folders[index] = newValue }
            })
    }

    private func ruleBinding(_ folderID: UUID, _ ruleID: UUID) -> Binding<Rule>? {
        guard let folder = model.config.folders.first(where: { $0.id == folderID }),
              folder.rules.contains(where: { $0.id == ruleID }) else { return nil }
        return Binding(
            get: {
                model.config.folders.first(where: { $0.id == folderID })?.rules.first(where: { $0.id == ruleID })
                    ?? Rule(name: "", condition: .all([]), actions: [])
            },
            set: { newValue in
                guard let f = model.config.folders.firstIndex(where: { $0.id == folderID }),
                      let r = model.config.folders[f].rules.firstIndex(where: { $0.id == ruleID }) else { return }
                model.config.folders[f].rules[r] = newValue
            })
    }

    private func addRule() {
        guard let folderID = selection?.folderID,
              let index = model.config.folders.firstIndex(where: { $0.id == folderID }) else { return }
        let rule = Rule(name: "New rule", condition: .all([.kind(.image)]),
                        actions: [.move(destination: "~/Pictures", createFolders: true, onConflict: .rename)])
        model.config.folders[index].rules.append(rule)
        selection = .rule(folder: folderID, rule: rule.id)
    }

    private func removeSelected() {
        switch selection {
        case .rule(let folderID, let ruleID):
            guard let f = model.config.folders.firstIndex(where: { $0.id == folderID }) else { return }
            model.config.folders[f].rules.removeAll { $0.id == ruleID }
            selection = .folder(folderID)
        case .folder(let folderID):
            model.config.folders.removeAll { $0.id == folderID }
            selection = nil
        case nil:
            break
        }
    }

    private func moveSelected(_ offset: Int) {
        guard case .rule(let folderID, let ruleID) = selection,
              let f = model.config.folders.firstIndex(where: { $0.id == folderID }),
              let r = model.config.folders[f].rules.firstIndex(where: { $0.id == ruleID }) else { return }
        let target = r + offset
        guard model.config.folders[f].rules.indices.contains(target) else { return }
        model.config.folders[f].rules.swapAt(r, target)
    }
}

struct RuleRow: View {
    let rule: Rule

    var body: some View {
        HStack {
            Image(systemName: rule.enabled ? "circle.fill" : "circle")
                .font(.system(size: 7))
                .foregroundStyle(rule.enabled ? .green : .secondary)
                .accessibilityHidden(true)
            Text(rule.name).lineLimit(1).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(rule.mode == .live ? "Live" : "Preview")
                .font(.caption2.bold())
                .foregroundStyle(rule.mode == .live ? Color(red: 0.4, green: 1, blue: 0.7) : Color(red: 1, green: 0.75, blue: 0.4))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(rule.mode == .live ? Color.green.opacity(0.22) : Color.orange.opacity(0.22), in: Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.name), \(rule.enabled ? "on" : "off"), \(rule.mode == .live ? "live" : "preview only")")
    }
}

/// Ready-made rule cards in two columns; `target` nil adds each rule to its usual folder.
struct TemplateGrid: View {
    let target: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(Templates.all) { template in
                TemplateCard(template: template, target: target)
            }
        }
    }
}

struct TemplateCard: View {
    @EnvironmentObject private var model: AppModel
    let template: Templates.Template
    let target: String?

    private var targetPath: String { target ?? template.folderPath }
    private var targetName: String { PathTools.abbreviate(PathTools.expandTilde(targetPath)) }
    private var addedHere: Bool { model.isInstalled(template, folderPath: targetPath) }

    var body: some View {
        let having = model.folders(having: template)
        VStack(alignment: .leading, spacing: 6) {
            GradientIcon(systemName: TemplateStyle.icon(template.id), gradient: TemplateStyle.gradient(template.id), size: 30)
            Text(template.title).font(.headline)
            Text(TemplateText.detail(template, in: target)).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !having.isEmpty {
                FolderChips(paths: having.map(\.path))
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if addedHere {
                    Label(target == nil ? "Added" : "Added here", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.done)
                        .lineLimit(1)
                        .padding(.vertical, 8)
                        .accessibilityLabel("\(template.title) already added to \(targetName)")
                } else {
                    Button("Add to \(targetName)") { model.install(template, folderPath: targetPath) }
                        .buttonStyle(GradientButtonStyle())
                        .lineLimit(1)
                        .help("Add this rule to \(targetName) in preview mode")
                        .accessibilityLabel("Add \(template.title) to \(targetName)")
                }
                Menu {
                    AddToFolderItems(template: template)
                } label: {
                    Label(addedHere ? "Other folder" : "More", systemImage: "folder.badge.plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add this rule to another folder too")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(addedHere ? Theme.done.opacity(0.45) : Theme.cardStroke))
    }
}

/// Menu items: add a template to its usual folder, any watched folder, or a folder picked now.
struct AddToFolderItems: View {
    @EnvironmentObject private var model: AppModel
    let template: Templates.Template

    var body: some View {
        Section("Add “\(template.title)” to") {
            let usual = PathTools.abbreviate(PathTools.expandTilde(template.folderPath))
            let paths = [usual] + model.config.folders.map(\.path).filter { PathTools.canonical(URL(fileURLWithPath: PathTools.expandTilde($0)))
                != PathTools.canonical(URL(fileURLWithPath: PathTools.expandTilde(usual))) }
            ForEach(paths, id: \.self) { path in
                let added = model.isInstalled(template, folderPath: path)
                Button(added ? "\(path) ✓" : path) { model.install(template, folderPath: path) }
                    .disabled(added)
            }
        }
        Divider()
        Button("Another Folder…") { model.installInPickedFolder(template) }
    }
}

/// "In ~/Downloads · ~/Documents": where a ready-made rule is already used.
struct FolderChips: View {
    let paths: [String]

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.done)
            Text("In " + (paths.prefix(3).joined(separator: " · ") + (paths.count > 3 ? " +\(paths.count - 3)" : "")))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Theme.done.opacity(0.16), in: Capsule())
        .accessibilityLabel("Already used in \(paths.joined(separator: ", "))")
    }
}

enum TemplateText {
    /// The card's description, naming the folder the rule would be added to.
    static func detail(_ template: Templates.Template, in target: String?) -> String {
        guard let target, PathTools.canonical(URL(fileURLWithPath: PathTools.expandTilde(target)))
                != PathTools.canonical(URL(fileURLWithPath: PathTools.expandTilde(template.folderPath))) else { return template.detail }
        let place = PathTools.abbreviate(PathTools.expandTilde(target))
        return template.detail
            .replacingOccurrences(of: "in \(ScreenshotLocation.folderPath) (where your Mac saves them)", with: "in \(place)")
            .replacingOccurrences(of: "in Downloads", with: "in \(place)")
    }
}

struct FolderDetail: View {
    @EnvironmentObject private var model: AppModel
    @Binding var folder: WatchedFolder
    @State private var simulated: [PreviewItem] = []
    @State private var simulating = false

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Folder", text: $folder.path).textFieldStyle(.roundedBorder)
                Button("Choose…") {
                    if let path = AppModel.chooseFolder(startingAt: folder.path) { folder.path = path }
                }
            }
            Toggle("Watch this folder", isOn: $folder.enabled)
            Toggle("Include items in subfolders", isOn: $folder.includeSubfolders)
            Text("\(folder.rules.count) rule(s). Rules are checked top to bottom; the first match wins unless it says “continue matching”.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Run Now") { model.runNow(folder) }
                    .buttonStyle(GradientButtonStyle())
                    .help("Handle what is already in the folder with the live rules")
                Button("Simulate") {
                    simulating = true
                    let snapshot = folder
                    Task {
                        simulated = await model.simulate(snapshot)
                        simulating = false
                    }
                }
                if simulating { ProgressView().controlSize(.small) }
            }
            if !simulated.isEmpty {
                Text("Would happen now (nothing changed yet)").font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(simulated) { item in
                        VStack(alignment: .leading) {
                            Text(item.file.lastPathComponent)
                            Text("\(item.ruleName): \(item.summary)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Send These to Preview") { model.previews += simulated.filter { new in !model.previews.contains { $0.id == new.id } } }
            }
            Text("Ready-made rules for \(folder.path)").font(.headline).padding(.top, 10)
            Text("Add any of these to this folder. Rules already here show “Added”; the same rule can also be used in other folders.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TemplateGrid(target: folder.path)
        }
        .padding(20)
        }
    }
}
