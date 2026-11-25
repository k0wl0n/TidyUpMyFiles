import TidyUpMyFilesCore
import SwiftUI

struct SmartTrashTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var plan: SmartTrashPlan?
    @State private var confirmEmpty = false

    private var settings: Binding<SmartTrashSettings> {
        Binding(get: { model.settings.smartTrash }, set: {
            model.settings.smartTrash = $0
            model.saveSettings()
        })
    }

    var body: some View {
        Form {
            Section("Smart Trash") {
                Text("Removes items that have been in the Trash for a while, so it doesn't grow forever. This is the only feature that deletes for good, so it shows you what it will remove first.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Empty old items automatically (checked every hour)", isOn: Binding(
                    get: { settings.wrappedValue.enabled },
                    set: { enabled in
                        settings.wrappedValue.enabled = enabled
                        if enabled && !settings.wrappedValue.confirmed { plan = model.planSmartTrash() }
                    }))
                Stepper(value: settings.olderThanDays, in: 1...365) {
                    Text("Older than \(Int(settings.wrappedValue.olderThanDays)) days")
                }
                Toggle("Also keep the Trash under a size limit", isOn: Binding(
                    get: { settings.wrappedValue.maxSizeGB != nil },
                    set: { settings.wrappedValue.maxSizeGB = $0 ? 10 : nil }))
                if let limit = settings.wrappedValue.maxSizeGB {
                    Stepper(value: Binding(get: { limit }, set: { settings.wrappedValue.maxSizeGB = $0 }), in: 1...500) {
                        Text("Size limit: \(Int(limit)) GB (oldest items go first)")
                    }
                }
                if settings.wrappedValue.enabled && !settings.wrappedValue.confirmed {
                    Label("Automatic emptying waits until you confirm the summary below once.", systemImage: "hand.raised.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section("What would be removed now") {
                HStack {
                    Button("Check Trash") { plan = model.planSmartTrash() }
                        .help("List what would be removed right now. Nothing is removed yet.")
                    if let plan {
                        Text("\(plan.items.count) item(s), \(ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file))")
                            .foregroundStyle(.secondary)
                    }
                }
                if let plan {
                    ForEach(plan.items.prefix(30)) { item in
                        LabeledContent(item.url.lastPathComponent,
                                       value: "\(item.trashedAt.formatted(date: .abbreviated, time: .omitted)) · \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))")
                    }
                    if plan.items.count > 30 { Text("…and \(plan.items.count - 30) more").foregroundStyle(.secondary) }
                    HStack {
                        if settings.wrappedValue.enabled && !settings.wrappedValue.confirmed {
                            Button("Confirm: Empty Like This Automatically") {
                                settings.wrappedValue.confirmed = true
                                confirmEmpty = true
                            }
                        }
                        Button("Empty These Now…", role: .destructive) { confirmEmpty = true }
                            .disabled(plan.items.isEmpty)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { if ShotScene.is("smart-trash") { plan = model.planSmartTrash() } }
        .clearScrollBackground()
        .alert("Delete \(plan?.items.count ?? 0) item(s) from the Trash for good?", isPresented: $confirmEmpty) {
            Button("Delete", role: .destructive) {
                if let plan { model.emptySmartTrash(plan) }
                plan = model.planSmartTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }
}
