import TidyUpMyFilesCore
import SwiftUI

struct AITab: View {
    @EnvironmentObject private var model: AppModel
    @State private var apiKey = ""
    @State private var keySaved = false
    @State private var selected = Set<String>()

    private var ai: Binding<AISettings> {
        Binding(get: { model.settings.ai }, set: {
            model.settings.ai = $0
            model.saveSettings()
        })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                Section("AI sorting (optional)") {
                    Toggle("Let AI suggest where files should go", isOn: ai.enabled)
                    Text("AI only suggests. Every suggestion waits here until you approve it. TidyUpMyFiles works fully without AI and without internet.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Provider", selection: Binding(get: { ai.wrappedValue.provider }, set: { kind in
                        ai.wrappedValue.provider = kind
                        ai.wrappedValue.endpoint = kind.defaultEndpoint
                        ai.wrappedValue.model = kind.defaultModel
                        apiKey = ""
                        keySaved = KeychainStore.key(for: kind) != nil
                    })) {
                        ForEach(AIProviderKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    TextField("Address", text: ai.endpoint)
                    TextField("Model", text: ai.model)
                    if ai.wrappedValue.provider != .ollama {
                        HStack {
                            SecureField(keySaved ? "Key saved in Keychain" : "API key (your own)", text: $apiKey)
                            Button("Save Key") {
                                keySaved = KeychainStore.setKey(apiKey, for: ai.wrappedValue.provider) && !apiKey.isEmpty
                                apiKey = ""
                            }
                            .disabled(apiKey.isEmpty)
                            if keySaved {
                                Button("Remove") {
                                    KeychainStore.setKey(nil, for: ai.wrappedValue.provider)
                                    keySaved = false
                                }
                            }
                        }
                    }
                    dataNotice
                }
                Section("Folders AI may look at") {
                    if model.config.folders.isEmpty {
                        Text("Add watched folders in Rules first.").foregroundStyle(.secondary)
                    }
                    ForEach(model.config.folders) { folder in
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(folder.path, isOn: membership(\.allowedFolders, folder.path))
                            if ai.wrappedValue.allowedFolders.contains(folder.path) {
                                Toggle("Also send the first 2 KB of text files", isOn: membership(\.readContentsFolders, folder.path))
                                    .font(.caption)
                                    .padding(.leading, 20)
                                Button("Ask for Suggestions") { model.requestAISuggestions(for: folder) }
                                    .help("Ask the AI where these files could go. You approve each suggestion.")
                                    .disabled(!ai.wrappedValue.enabled || model.busy)
                                    .padding(.leading, 20)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .clearScrollBackground()
        .clearScrollBackground()
            .frame(width: 430)

            suggestions
                .glassCard(padding: 4, radius: 20)
        }
        .onAppear { keySaved = KeychainStore.key(for: ai.wrappedValue.provider) != nil }
    }

    private var dataNotice: some View {
        let local = ai.wrappedValue.provider.isLocal && (ai.wrappedValue.endpoint.contains("localhost") || ai.wrappedValue.endpoint.contains("127.0.0.1"))
        return Label(local ? "Data stays on this Mac (local Ollama)." : "File names and metadata leave this Mac and go to \(ai.wrappedValue.endpoint).",
                     systemImage: local ? "lock.shield" : "network")
            .foregroundStyle(local ? .green : .orange)
            .font(.callout)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggestions").font(.headline)
            if model.aiSuggestions.isEmpty {
                Text("None yet. Allow a folder, then ask for suggestions.").foregroundStyle(.secondary)
                Spacer()
            } else {
                List(model.aiSuggestions, selection: $selected) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.file.lastPathComponent).bold()
                        Text("\(item.suggestion.category): \(item.summary)").font(.caption).foregroundStyle(.secondary)
                        Button("Make This a Rule") { model.makePermanentRule(item) }
                            .buttonStyle(.link).font(.caption)
                    }
                    .padding(.vertical, 4)
                }
                .clearScrollBackground()
                HStack {
                    Button("Discard") {
                        model.aiSuggestions.removeAll { selected.contains($0.id) }
                        selected.removeAll()
                    }
                    .disabled(selected.isEmpty)
                    Spacer()
                    Button("Approve Selected") {
                        model.approveAI(model.aiSuggestions.filter { selected.contains($0.id) })
                        selected.removeAll()
                    }
                    .disabled(selected.isEmpty)
                    Button("Approve All") { model.approveAI(model.aiSuggestions) }
                        .help("Do every suggestion. Every step can be undone.")
                        .buttonStyle(GradientButtonStyle())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func membership(_ keyPath: WritableKeyPath<AISettings, [String]>, _ path: String) -> Binding<Bool> {
        Binding(get: { ai.wrappedValue[keyPath: keyPath].contains(path) }, set: { on in
            var list = ai.wrappedValue[keyPath: keyPath]
            list.removeAll { $0 == path }
            if on { list.append(path) }
            ai.wrappedValue[keyPath: keyPath] = list
        })
    }
}
