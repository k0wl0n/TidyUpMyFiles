import Foundation
import ImageIO

/// Everything the rule engine may look at for one file. Plain data, so tests can build it by hand.
public struct FileFacts: Equatable, Sendable {
    public var url: URL
    public var isDirectory: Bool
    public var size: Int64
    public var created: Date?
    public var modified: Date?
    public var added: Date?
    public var tags: [String]
    public var colorLabel: ColorLabel
    public var sourceURLs: [String]
    /// When a photo was taken, from its EXIF data.
    public var taken: Date?
    public var lastOpened: Date?
    public var isEmpty: Bool
    /// Filled only when a rule looks at file contents (it can be slow).
    public var textContent: String?
    /// Filled only when a rule looks for duplicates: the earlier item with identical content.
    public var duplicateOf: URL?

    public init(url: URL, isDirectory: Bool = false, size: Int64 = 0, created: Date? = nil, modified: Date? = nil,
                added: Date? = nil, tags: [String] = [], colorLabel: ColorLabel = .none, sourceURLs: [String] = [],
                taken: Date? = nil, lastOpened: Date? = nil, isEmpty: Bool = false,
                textContent: String? = nil, duplicateOf: URL? = nil) {
        self.url = url
        self.isDirectory = isDirectory
        self.size = size
        self.created = created
        self.modified = modified
        self.added = added
        self.tags = tags
        self.colorLabel = colorLabel
        self.sourceURLs = sourceURLs
        self.taken = taken
        self.lastOpened = lastOpened
        self.isEmpty = isEmpty
        self.textContent = textContent
        self.duplicateOf = duplicateOf
    }

    public var fileName: String { url.lastPathComponent }
    public var baseName: String { (fileName as NSString).deletingPathExtension }
    public var fileExtension: String { (fileName as NSString).pathExtension }
    public var kind: FileKind { FileKind.classify(fileName: fileName, isDirectory: isDirectory) }

    /// Date used for "age": when it arrived in its folder, else when it was created.
    public var ageReferenceDate: Date? { added ?? created ?? modified }
}

public enum FileFactsReader {
    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .fileSizeKey, .totalFileAllocatedSizeKey, .creationDateKey,
        .contentModificationDateKey, .addedToDirectoryDateKey, .tagNamesKey, .labelNumberKey,
    ]

    /// Reads a file's facts. Slow details (Spotlight lookups, folder sizes, photo EXIF) are read only when
    /// `needs` asks for them; by default everything is read.
    public static func read(_ url: URL, needs: FactNeeds = .all) throws -> FileFacts {
        let values = try url.resourceValues(forKeys: keys)
        let isDirectory = values.isDirectory ?? false
        let size = isDirectory ? (needs.contains(.folderSize) ? directorySize(url) : 0) : Int64(values.fileSize ?? 0)
        let kind = FileKind.classify(fileName: url.lastPathComponent, isDirectory: isDirectory)
        return FileFacts(
            url: url,
            isDirectory: isDirectory,
            size: size,
            created: values.creationDate,
            modified: values.contentModificationDate,
            added: values.addedToDirectoryDate,
            tags: values.tagNames ?? [],
            colorLabel: ColorLabel(rawValue: values.labelNumber ?? 0) ?? .none,
            sourceURLs: needs.contains(.sourceURL) ? whereFroms(url) : (whereFromsAttribute(url) ?? []),
            taken: kind == .image && needs.contains(.taken) ? photoTakenDate(url) : nil,
            lastOpened: needs.contains(.lastOpened) ? lastOpenedDate(url) : nil,
            isEmpty: isDirectory ? folderIsEmpty(url) : size == 0
        )
    }

    /// EXIF "DateTimeOriginal" of a photo, read from its header only.
    public static func photoTakenDate(_ url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        guard let text = (exif?[kCGImagePropertyExifDateTimeOriginal] ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }

    private static func lastOpenedDate(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    private static func folderIsEmpty(_ url: URL) -> Bool {
        let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                                     options: [.skipsHiddenFiles])) ?? []
        return children.isEmpty
    }

    /// Download origin. The extended attribute is read first because Spotlight may not index every folder.
    public static func whereFroms(_ url: URL) -> [String] {
        if let fromAttribute = whereFromsAttribute(url), !fromAttribute.isEmpty { return fromAttribute }
        guard let item = MDItemCreateWithURL(nil, url as CFURL),
              let value = MDItemCopyAttribute(item, kMDItemWhereFroms) else { return [] }
        return (value as? [String]) ?? []
    }

    static func whereFromsAttribute(_ url: URL) -> [String]? {
        let name = "com.apple.metadata:kMDItemWhereFroms"
        return url.withUnsafeFileSystemRepresentation { path -> [String]? in
            guard let path else { return nil }
            let length = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard length > 0 else { return nil }
            var data = Data(count: length)
            let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, length, 0, XATTR_NOFOLLOW) }
            guard read == length else { return nil }
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String]
        }
    }

    /// Total size of a folder; stops after `limit` items so a huge folder can't stall a scan.
    private static func directorySize(_ url: URL, limit: Int = 50_000) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        var count = 0
        for case let child as URL in enumerator {
            total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            count += 1
            if count >= limit { break }
        }
        return total
    }
}

/// Slow facts a scan may skip when no rule uses them.
public struct FactNeeds: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Spotlight lookup of the download source (the fast extended-attribute read always happens).
    public static let sourceURL = FactNeeds(rawValue: 1 << 0)
    public static let lastOpened = FactNeeds(rawValue: 1 << 1)
    /// Adding up everything inside a folder.
    public static let folderSize = FactNeeds(rawValue: 1 << 2)
    public static let taken = FactNeeds(rawValue: 1 << 3)
    public static let text = FactNeeds(rawValue: 1 << 4)
    public static let duplicates = FactNeeds(rawValue: 1 << 5)
    public static let all: FactNeeds = [.sourceURL, .lastOpened, .folderSize, .taken, .text, .duplicates]

    /// What the enabled rules look at, in their conditions and in their name/folder templates.
    public static func forRules(_ rules: [Rule]) -> FactNeeds {
        var needs: FactNeeds = []
        for rule in rules where rule.enabled {
            if rule.condition.contains(where: { if case .sourceURL = $0 { return true } else { return false } }) { needs.insert(.sourceURL) }
            if rule.condition.contains(where: { if case .lastOpened = $0 { return true } else { return false } }) { needs.insert(.lastOpened) }
            if rule.condition.contains(where: { if case .size = $0 { return true } else { return false } }) { needs.insert(.folderSize) }
            if rule.condition.contains(where: { if case .taken = $0 { return true } else { return false } }) { needs.insert(.taken) }
            if rule.condition.needsText { needs.insert(.text) }
            if rule.condition.needsDuplicates { needs.insert(.duplicates) }
            for action in rule.actions {
                let template: String
                switch action {
                case .move(let destination, _, _), .copy(let destination, _, _), .archive(let destination, _),
                     .extract(let destination, _), .makeAlias(let destination): template = destination
                case .rename(let pattern, _): template = pattern
                default: template = ""
                }
                if template.contains("{taken") { needs.insert(.taken) }
            }
        }
        return needs
    }
}
