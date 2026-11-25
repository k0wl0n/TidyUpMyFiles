import TidyUpMyFilesCore
import SwiftUI

struct ActionListEditor: View {
    @EnvironmentObject private var model: AppModel
    @Binding var actions: [Action]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if actions.isEmpty {
                Text("No actions yet.").foregroundStyle(.secondary)
            }
            ForEach(Array(actions.indices), id: \.self) { index in
                HStack(alignment: .top) {
                    Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary).padding(.top, 4)
                    ActionRow(action: Binding(
                        get: { actions.indices.contains(index) ? actions[index] : .open },
                        set: { if actions.indices.contains(index) { actions[index] = $0 } }),
                              shellAllowed: model.settings.allowShellScripts)
                    VStack(spacing: 4) {
                        Button { move(index, -1) } label: { Image(systemName: "chevron.up") }
                            .accessibilityLabel("Move action up")
                        Button { move(index, 1) } label: { Image(systemName: "chevron.down") }
                            .accessibilityLabel("Move action down")
                    }
                    .buttonStyle(.borderless)
                    DeleteButton { if actions.indices.contains(index) { actions.remove(at: index) } }
                        .padding(.top, 4)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
            }
            Button {
                actions.append(.move(destination: "~/Documents", createFolders: true, onConflict: .rename))
            } label: {
                Label("Add action", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    private func move(_ index: Int, _ offset: Int) {
        let target = index + offset
        guard actions.indices.contains(index), actions.indices.contains(target) else { return }
        actions.swapAt(index, target)
    }
}

private enum ActionType: String, CaseIterable, Identifiable {
    case move = "Move to folder", copy = "Copy to folder", rename = "Rename", addTags = "Add tags",
         removeTags = "Remove tags", setColor = "Set color label", trash = "Move to Trash", open = "Open",
         archive = "Compress to zip", extract = "Extract archive", alias = "Make an alias",
         shortcut = "Run a Shortcut", shell = "Run shell script"

    var id: String { rawValue }

    init(_ action: Action) {
        switch action {
        case .move: self = .move
        case .copy: self = .copy
        case .rename: self = .rename
        case .addTags: self = .addTags
        case .removeTags: self = .removeTags
        case .setColor: self = .setColor
        case .trash: self = .trash
        case .open: self = .open
        case .shell: self = .shell
        case .archive: self = .archive
        case .extract: self = .extract
        case .makeAlias: self = .alias
        case .runShortcut: self = .shortcut
        }
    }

    var defaultAction: Action {
        switch self {
        case .move: return .move(destination: "~/Documents", createFolders: true, onConflict: .rename)
        case .copy: return .copy(destination: "~/Documents", createFolders: true, onConflict: .rename)
        case .rename: return .rename(pattern: "{date:yyyy-MM-dd} {name}.{ext}", onConflict: .rename)
        case .addTags: return .addTags(["Sorted"])
        case .removeTags: return .removeTags(["Sorted"])
        case .setColor: return .setColor(.blue)
        case .trash: return .trash
        case .open: return .open
        case .shell: return .shell(script: "echo \"$TIDYUP_FILE\"")
        case .archive: return .archive(destination: "", onConflict: .rename)
        case .extract: return .extract(destination: "", onConflict: .rename)
        case .alias: return .makeAlias(destination: "~/Desktop")
        case .shortcut: return .runShortcut(name: "")
        }
    }
}

private struct ActionRow: View {
    @Binding var action: Action
    let shellAllowed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: Binding(get: { ActionType(action) }, set: { action = $0.defaultAction })) {
                ForEach(ActionType.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 180)
            .accessibilityLabel("Action type")
            details
        }
    }

    @ViewBuilder
    private var details: some View {
        switch action {
        case .move(let destination, let createFolders, let policy), .copy(let destination, let createFolders, let policy):
            let isMove = ActionType(action) == .move
            let rebuild: (String, Bool, ConflictPolicy) -> Action = { d, c, p in
                isMove ? .move(destination: d, createFolders: c, onConflict: p) : .copy(destination: d, createFolders: c, onConflict: p)
            }
            HStack {
                TextField("Folder, e.g. ~/Pictures/{added.year}", text: Binding(
                    get: { destination }, set: { action = rebuild($0, createFolders, policy) }))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Destination folder")
                Button("Choose…") {
                    if let path = AppModel.chooseFolder(startingAt: destination) { action = rebuild(path, createFolders, policy) }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Create missing folders", isOn: Binding(get: { createFolders }, set: { action = rebuild(destination, $0, policy) }))
                    .fixedSize()
                ConflictPicker(policy: Binding(get: { policy }, set: { action = rebuild(destination, createFolders, $0) }))
            }
            TokenHint()
        case .rename(let pattern, let policy):
            TextField("New name", text: Binding(get: { pattern }, set: { action = .rename(pattern: $0, onConflict: policy) }))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("New name pattern")
            ConflictPicker(policy: Binding(get: { policy }, set: { action = .rename(pattern: pattern, onConflict: $0) }))
            TokenHint()
        case .addTags(let tags):
            tagField(tags) { action = .addTags($0) }
        case .removeTags(let tags):
            tagField(tags) { action = .removeTags($0) }
        case .setColor(let label):
            ColorLabelPicker(label: Binding(get: { label }, set: { action = .setColor($0) }))
        case .trash:
            Text("Goes to the Trash (never deleted for good). Can be undone.").font(.caption).foregroundStyle(.secondary)
        case .open:
            Text("Opens the item with its default app.").font(.caption).foregroundStyle(.secondary)
        case .extract(let destination, let policy):
            HStack {
                TextField("Folder to unpack into (empty = next to the archive)", text: Binding(
                    get: { destination }, set: { action = .extract(destination: $0, onConflict: policy) }))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Folder to unpack into")
                Button("Choose…") {
                    if let path = AppModel.chooseFolder(startingAt: destination.isEmpty ? "~" : destination) {
                        action = .extract(destination: path, onConflict: policy)
                    }
                }
                .help("Pick the folder the archive is unpacked into")
            }
            ConflictPicker(policy: Binding(get: { policy }, set: { action = .extract(destination: destination, onConflict: $0) }))
            Text("Unpacks .zip and .tar(.gz) into a folder named after the archive; the archive stays. .7z and .rar are skipped.")
                .font(.caption).foregroundStyle(.secondary)
        case .makeAlias(let destination):
            HStack {
                TextField("Folder for the alias", text: Binding(get: { destination }, set: { action = .makeAlias(destination: $0) }))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Folder for the alias")
                Button("Choose…") {
                    if let path = AppModel.chooseFolder(startingAt: destination) { action = .makeAlias(destination: path) }
                }
                .help("Pick where the alias goes")
            }
            Text("A Finder alias points to the file wherever it moves. Undo sends the alias to the Trash.")
                .font(.caption).foregroundStyle(.secondary)
        case .runShortcut(let name):
            TextField("Shortcut name, exactly as in the Shortcuts app", text: Binding(
                get: { name }, set: { action = .runShortcut(name: $0) }))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Shortcut name")
            Label("Runs the Shortcut with the file as input. Turn on “Allow Shortcuts” in Settings first; it can't be undone.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        case .archive(let destination, let policy):
            HStack {
                TextField("Folder for the zip (empty = next to the file)", text: Binding(
                    get: { destination }, set: { action = .archive(destination: $0, onConflict: policy) }))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Zip destination folder")
                Button("Choose…") {
                    if let path = AppModel.chooseFolder(startingAt: destination.isEmpty ? "~" : destination) {
                        action = .archive(destination: path, onConflict: policy)
                    }
                }
            }
            ConflictPicker(policy: Binding(get: { policy }, set: { action = .archive(destination: destination, onConflict: $0) }))
            Text("Makes name.ext.zip; the original stays. Add “Move to Trash” after it to replace the original.")
                .font(.caption).foregroundStyle(.secondary)
        case .shell(let script):
            TextEditor(text: Binding(get: { script }, set: { action = .shell(script: $0) }))
                .font(.system(.body, design: .monospaced))
                .frame(height: 60)
                .border(Color.secondary.opacity(0.3))
                .accessibilityLabel("Shell script")
            Label(shellAllowed
                  ? "Scripts can change or delete anything your account can, and cannot be undone. The item's path is in $TIDYUP_FILE."
                  : "Shell scripts are off. Turn them on in General if you trust this rule; until then this step is skipped.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func tagField(_ tags: [String], update: @escaping ([String]) -> Void) -> some View {
        TextField("Tags, separated by commas", text: Binding(
            get: { tags.joined(separator: ", ") },
            set: { update($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }) }))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Tags")
    }
}

private struct ConflictPicker: View {
    @Binding var policy: ConflictPolicy

    var body: some View {
        Picker("If the name is taken", selection: $policy) {
            Text("Add a number to the new file").tag(ConflictPolicy.rename)
            Text("Rename the existing file").tag(ConflictPolicy.renameExisting)
            Text("Skip").tag(ConflictPolicy.skip)
            Text("Old file to Trash, then replace (needs permission)").tag(ConflictPolicy.overwrite)
        }
        .fixedSize()
        .help("What happens when a file with the same name is already there. Nothing is ever deleted for good.")
    }
}

private struct TokenHint: View {
    var body: some View {
        Text("Tokens: {name} {ext} {kind} {counter} {date:yyyy-MM-dd} {added.year} {added.month} {created:…} {modified:…}")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}
