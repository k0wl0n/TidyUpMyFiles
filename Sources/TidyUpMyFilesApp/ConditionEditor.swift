import TidyUpMyFilesCore
import SwiftUI

/// Edits a condition tree: AND/OR groups, NOT, and single tests, nested to any depth.
struct ConditionEditor: View {
    @Binding var condition: Condition
    let onDelete: (() -> Void)?

    var body: some View {
        switch condition {
        case .all, .any:
            AnyView(GroupConditionEditor(condition: $condition, onDelete: onDelete))
        case .not(let inner):
            AnyView(
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("NOT").font(.caption.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.15), in: Capsule())
                        Text("none of this may be true").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove NOT") { condition = inner }.buttonStyle(.borderless).font(.caption)
                        if let onDelete { DeleteButton(action: onDelete) }
                    }
                    ConditionEditor(condition: Binding(get: { inner }, set: { condition = .not($0) }), onDelete: nil)
                        .padding(.leading, 16)
                }
            )
        default:
            AnyView(LeafConditionEditor(condition: $condition, onDelete: onDelete))
        }
    }
}

struct DeleteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete")
    }
}

private struct GroupConditionEditor: View {
    @Binding var condition: Condition
    let onDelete: (() -> Void)?

    private var isAll: Bool {
        if case .all = condition { return true }
        return false
    }

    private var children: [Condition] {
        switch condition {
        case .all(let list), .any(let list): return list
        default: return []
        }
    }

    private func setChildren(_ list: [Condition]) {
        condition = isAll ? .all(list) : .any(list)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("", selection: Binding(get: { isAll }, set: { condition = $0 ? .all(children) : .any(children) })) {
                    Text("All of these (AND)").tag(true)
                    Text("Any of these (OR)").tag(false)
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Group type")
                Spacer()
                Menu {
                    Button("Condition") { setChildren(children + [.name(TextMatch(contains: ""))]) }
                    Button("AND group") { setChildren(children + [.all([.kind(.image)])]) }
                    Button("OR group") { setChildren(children + [.any([.kind(.image)])]) }
                    Button("NOT") { setChildren(children + [.not(.name(TextMatch(contains: "")))]) }
                    Divider()
                    Button("Wrap this group in NOT") { condition = .not(condition) }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                if let onDelete { DeleteButton(action: onDelete) }
            }
            if children.isEmpty {
                Text(isAll ? "Empty AND group: matches every item." : "Empty OR group: matches nothing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(children.indices), id: \.self) { index in
                ConditionEditor(
                    condition: Binding(
                        get: { children.indices.contains(index) ? children[index] : .all([]) },
                        set: { newValue in
                            var list = children
                            guard list.indices.contains(index) else { return }
                            list[index] = newValue
                            setChildren(list)
                        }),
                    onDelete: {
                        var list = children
                        guard list.indices.contains(index) else { return }
                        list.remove(at: index)
                        setChildren(list)
                    })
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
            }
        }
    }
}

private enum LeafType: String, CaseIterable, Identifiable {
    case name = "Name", fileExtension = "Extension", kind = "Kind", size = "Size", created = "Date created",
         modified = "Date modified", added = "Date added", age = "Age (days)", tag = "Finder tag",
         color = "Color label", source = "Downloaded from", folder = "Is a folder",
         contents = "Contents (text inside)", duplicate = "Is a duplicate", taken = "Photo taken",
         lastOpened = "Last opened", empty = "Is empty"

    var id: String { rawValue }

    init(_ condition: Condition) {
        switch condition {
        case .name: self = .name
        case .fileExtension: self = .fileExtension
        case .kind: self = .kind
        case .size: self = .size
        case .created: self = .created
        case .modified: self = .modified
        case .added: self = .added
        case .ageDays: self = .age
        case .tag: self = .tag
        case .color: self = .color
        case .sourceURL: self = .source
        case .contents: self = .contents
        case .duplicate: self = .duplicate
        case .taken: self = .taken
        case .lastOpened: self = .lastOpened
        case .isEmpty: self = .empty
        default: self = .folder
        }
    }

    var defaultCondition: Condition {
        switch self {
        case .name: return .name(TextMatch(contains: ""))
        case .fileExtension: return .fileExtension(["pdf"])
        case .kind: return .kind(.image)
        case .size: return .size(NumberMatch(greaterThan: 10_000_000))
        case .created: return .created(DateMatch(olderThanDays: 7))
        case .modified: return .modified(DateMatch(olderThanDays: 7))
        case .added: return .added(DateMatch(olderThanDays: 7))
        case .age: return .ageDays(NumberMatch(greaterThan: 30))
        case .tag: return .tag(TagMatch(has: "Red"))
        case .color: return .color(.red)
        case .source: return .sourceURL(TextMatch(contains: ""))
        case .folder: return .isFolder(true)
        case .contents: return .contents(TextMatch(contains: ""))
        case .duplicate: return .duplicate(true)
        case .taken: return .taken(DateMatch(olderThanDays: 365))
        case .lastOpened: return .lastOpened(DateMatch(olderThanDays: 90))
        case .empty: return .isEmpty(true)
        }
    }
}

private enum TextOperator: String, CaseIterable {
    case contains = "contains", startsWith = "starts with", endsWith = "ends with", equals = "is", regex = "matches regex",
         glob = "matches pattern (*, ?)"

    static func of(_ match: TextMatch) -> (TextOperator, String) {
        if let value = match.startsWith { return (.startsWith, value) }
        if let value = match.endsWith { return (.endsWith, value) }
        if let value = match.equals { return (.equals, value) }
        if let value = match.regex { return (.regex, value) }
        if let value = match.glob { return (.glob, value) }
        return (.contains, match.contains ?? "")
    }

    func make(_ value: String) -> TextMatch {
        switch self {
        case .contains: return TextMatch(contains: value)
        case .startsWith: return TextMatch(startsWith: value)
        case .endsWith: return TextMatch(endsWith: value)
        case .equals: return TextMatch(equals: value)
        case .regex: return TextMatch(regex: value)
        case .glob: return TextMatch(glob: value)
        }
    }
}

private enum DateOperator: String, CaseIterable {
    case olderThan = "is more than N days ago", newerThan = "is within the last N days", before = "is before", after = "is after"
}

private struct LeafConditionEditor: View {
    @Binding var condition: Condition
    let onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Picker("", selection: Binding(get: { LeafType(condition) }, set: { condition = $0.defaultCondition })) {
                ForEach(LeafType.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 128)
            .accessibilityLabel("Condition type")
            fields
            Spacer(minLength: 0)
            Menu {
                Button("Wrap in AND group") { condition = .all([condition]) }
                Button("Wrap in OR group") { condition = .any([condition]) }
                Button("Wrap in NOT") { condition = .not(condition) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("More options")
            if let onDelete { DeleteButton(action: onDelete) }
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch condition {
        case .name(let match):
            textFields(match) { condition = .name($0) }
        case .sourceURL(let match):
            textFields(match) { condition = .sourceURL($0) }
        case .contents(let match):
            textFields(match) { condition = .contents($0) }
        case .taken(let match):
            DateFields(match: match) { condition = .taken($0) }
        case .lastOpened(let match):
            DateFields(match: match) { condition = .lastOpened($0) }
        case .duplicate(let flag):
            Picker("", selection: Binding(get: { flag }, set: { condition = .duplicate($0) })) {
                Text("yes — same content as an earlier item").tag(true)
                Text("no").tag(false)
            }
            .labelsHidden().fixedSize()
        case .isEmpty(let flag):
            Picker("", selection: Binding(get: { flag }, set: { condition = .isEmpty($0) })) {
                Text("yes").tag(true)
                Text("no").tag(false)
            }
            .labelsHidden().fixedSize()
        case .fileExtension(let list):
            TextField("pdf, docx", text: Binding(
                get: { list.joined(separator: ", ") },
                set: { condition = .fileExtension($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }) }))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 90)
                .layoutPriority(1)
                .accessibilityLabel("Extensions, separated by commas")
        case .kind(let kind):
            Picker("", selection: Binding(get: { kind }, set: { condition = .kind($0) })) {
                ForEach(FileKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden().fixedSize()
        case .size(let match):
            SizeFields(match: match) { condition = .size($0) }
        case .ageDays(let match):
            NumberCompareFields(match: match, unitLabel: "days") { condition = .ageDays($0) }
        case .created(let match):
            DateFields(match: match) { condition = .created($0) }
        case .modified(let match):
            DateFields(match: match) { condition = .modified($0) }
        case .added(let match):
            DateFields(match: match) { condition = .added($0) }
        case .tag(let match):
            Picker("", selection: Binding(
                get: { match.lacks == nil },
                set: { has in condition = .tag(has ? TagMatch(has: match.lacks ?? match.has ?? "") : TagMatch(lacks: match.has ?? match.lacks ?? "")) })) {
                Text("has").tag(true)
                Text("doesn't have").tag(false)
            }
            .labelsHidden().fixedSize()
            TextField("Tag", text: Binding(
                get: { match.has ?? match.lacks ?? "" },
                set: { condition = .tag(match.lacks == nil ? TagMatch(has: $0) : TagMatch(lacks: $0)) }))
                .textFieldStyle(.roundedBorder)
        case .color(let label):
            ColorLabelPicker(label: Binding(get: { label }, set: { condition = .color($0) }))
        case .isFolder(let flag):
            Picker("", selection: Binding(get: { flag }, set: { condition = .isFolder($0) })) {
                Text("yes").tag(true)
                Text("no").tag(false)
            }
            .labelsHidden().fixedSize()
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func textFields(_ match: TextMatch, update: @escaping (TextMatch) -> Void) -> some View {
        let (op, value) = TextOperator.of(match)
        Picker("", selection: Binding(get: { op }, set: { update($0.make(value)) })) {
            ForEach(TextOperator.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .labelsHidden().fixedSize()
        .accessibilityLabel("Comparison")
        TextField("text", text: Binding(get: { value }, set: { update(op.make($0)) }))
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 90)
            .layoutPriority(1)
            .accessibilityLabel("Text to compare")
    }
}

private struct NumberCompareFields: View {
    let match: NumberMatch
    let unitLabel: String
    let update: (NumberMatch) -> Void

    private var isGreater: Bool { match.lessThan == nil }
    private var value: Double { match.greaterThan ?? match.lessThan ?? match.atLeast ?? match.atMost ?? 0 }

    var body: some View {
        Picker("", selection: Binding(get: { isGreater }, set: { update($0 ? NumberMatch(greaterThan: value) : NumberMatch(lessThan: value)) })) {
            Text("more than").tag(true)
            Text("less than").tag(false)
        }
        .labelsHidden().fixedSize()
        TextField("", value: Binding(get: { value }, set: { update(isGreater ? NumberMatch(greaterThan: $0) : NumberMatch(lessThan: $0)) }),
                  format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
            .accessibilityLabel("Amount in \(unitLabel)")
        Text(unitLabel).foregroundStyle(.secondary)
    }
}

private struct SizeFields: View {
    let match: NumberMatch
    let update: (NumberMatch) -> Void

    private static let units: [(String, Double)] = [("KB", 1e3), ("MB", 1e6), ("GB", 1e9)]
    private var isGreater: Bool { match.lessThan == nil }
    private var bytes: Double { match.greaterThan ?? match.lessThan ?? 0 }
    private var unit: Double { SizeFields.units.last(where: { bytes >= $0.1 })?.1 ?? 1e3 }

    private func make(greater: Bool, bytes: Double) -> NumberMatch {
        greater ? NumberMatch(greaterThan: bytes) : NumberMatch(lessThan: bytes)
    }

    var body: some View {
        Picker("", selection: Binding(get: { isGreater }, set: { update(make(greater: $0, bytes: bytes)) })) {
            Text("larger than").tag(true)
            Text("smaller than").tag(false)
        }
        .labelsHidden().fixedSize()
        TextField("", value: Binding(get: { bytes / unit }, set: { update(make(greater: isGreater, bytes: $0 * unit)) }), format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
            .accessibilityLabel("Size")
        Picker("", selection: Binding(get: { unit }, set: { update(make(greater: isGreater, bytes: bytes / unit * $0)) })) {
            ForEach(SizeFields.units, id: \.1) { Text($0.0).tag($0.1) }
        }
        .labelsHidden().fixedSize()
        .accessibilityLabel("Unit")
    }
}

private struct DateFields: View {
    let match: DateMatch
    let update: (DateMatch) -> Void

    private var op: DateOperator {
        if match.newerThanDays != nil { return .newerThan }
        if match.before != nil { return .before }
        if match.after != nil { return .after }
        return .olderThan
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        Picker("", selection: Binding(get: { op }, set: { newOp in
            let today = DateFields.dayFormatter.string(from: Date())
            switch newOp {
            case .olderThan: update(DateMatch(olderThanDays: 7))
            case .newerThan: update(DateMatch(newerThanDays: 7))
            case .before: update(DateMatch(before: today))
            case .after: update(DateMatch(after: today))
            }
        })) {
            ForEach(DateOperator.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .labelsHidden().fixedSize()
        switch op {
        case .olderThan, .newerThan:
            TextField("", value: Binding(
                get: { match.olderThanDays ?? match.newerThanDays ?? 0 },
                set: { update(op == .olderThan ? DateMatch(olderThanDays: $0) : DateMatch(newerThanDays: $0)) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .accessibilityLabel("Days")
            Text("days").foregroundStyle(.secondary)
        case .before, .after:
            DatePicker("", selection: Binding(
                get: { DateFields.dayFormatter.date(from: match.before ?? match.after ?? "") ?? Date() },
                set: {
                    let text = DateFields.dayFormatter.string(from: $0)
                    update(op == .before ? DateMatch(before: text) : DateMatch(after: text))
                }), displayedComponents: .date)
                .labelsHidden()
        }
    }
}

struct ColorLabelPicker: View {
    @Binding var label: ColorLabel

    var body: some View {
        Picker("", selection: $label) {
            ForEach(ColorLabel.allCases, id: \.self) { item in
                Text(item.name.capitalized).tag(item)
            }
        }
        .labelsHidden().fixedSize()
        .accessibilityLabel("Color label")
    }
}
