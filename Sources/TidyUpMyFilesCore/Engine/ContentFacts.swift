import AppKit
import CryptoKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

extension Condition {
    /// True when this condition (or one nested inside it) satisfies `predicate`.
    func contains(where predicate: (Condition) -> Bool) -> Bool {
        if predicate(self) { return true }
        switch self {
        case .all(let list), .any(let list): return list.contains { $0.contains(where: predicate) }
        case .not(let inner): return inner.contains(where: predicate)
        default: return false
        }
    }

    var needsText: Bool { contains { if case .contents = $0 { return true } else { return false } } }
    var needsDuplicates: Bool { contains { if case .duplicate = $0 { return true } else { return false } } }
}

/// Reads the text inside documents for `contents` conditions. Bounded so huge files stay quick.
public enum ContentReader {
    static let maxCharacters = 200_000
    static let maxPDFPages = 30
    static let maxPlainBytes = 1_000_000

    public static func text(of url: URL) -> String? {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return nil }
        if type.conforms(to: .pdf) {
            guard let document = PDFDocument(url: url) else { return nil }
            var text = ""
            for index in 0..<min(document.pageCount, maxPDFPages) {
                text += document.page(at: index)?.string ?? ""
                text += "\n"
                if text.count > maxCharacters { break }
            }
            return String(text.prefix(maxCharacters))
        }
        if type.conforms(to: .rtf) || type.conforms(to: .rtfd)
            || ["doc", "docx", "odt", "webarchive"].contains(url.pathExtension.lowercased()) {
            let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil)
            return attributed.map { String($0.string.prefix(maxCharacters)) }
        }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .json) || type.conforms(to: .xml) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            return String(decoding: handle.readData(ofLength: maxPlainBytes), as: UTF8.self)
        }
        return nil
    }
}

/// Finds items with identical content among a folder's items. Sizes are compared first; only same-size
/// files are fingerprinted (SHA-256). The earliest arrival counts as the original, later ones as duplicates.
public final class DuplicateIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var bySize: [Int64: [URL]] = [:]
    private var hashes: [String: String] = [:]

    public init(items: [URL]) {
        for url in items {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, let size = values.fileSize, size > 0 else { continue }
            bySize[Int64(size), default: []].append(url)
        }
    }

    /// The earlier item `url` duplicates, or nil when it is unique or itself the original.
    public func originalFor(_ url: URL) -> URL? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size > 0 else { return nil }
        let path = PathTools.canonical(url)
        let others = lock.withLock { bySize[Int64(size)] ?? [] }.filter { PathTools.canonical($0) != path }
        guard !others.isEmpty, let mine = hash(url) else { return nil }
        let twins = others.filter { hash($0) == mine }
        guard !twins.isEmpty else { return nil }
        let earliest = (twins + [url]).min { DuplicateIndex.isEarlier($0, than: $1) }
        guard let earliest, PathTools.canonical(earliest) != path else { return nil }
        return earliest
    }

    private func hash(_ url: URL) -> String? {
        let key = PathTools.canonical(url)
        if let cached = lock.withLock({ hashes[key] }) { return cached }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        lock.withLock { hashes[key] = digest }
        return digest
    }

    private static func isEarlier(_ first: URL, than second: URL) -> Bool {
        func date(_ url: URL) -> Date {
            let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
            return values?.addedToDirectoryDate ?? values?.creationDate ?? .distantFuture
        }
        let (a, b) = (date(first), date(second))
        return a == b ? first.lastPathComponent < second.lastPathComponent : a < b
    }
}
