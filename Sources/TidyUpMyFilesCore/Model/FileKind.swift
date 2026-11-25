import Foundation

public enum FileKind: String, Codable, CaseIterable, Sendable {
    case image, pdf, archive, installer, document, spreadsheet, presentation, code, ebook, font, video, audio, folder, other

    /// Words people use for each kind, for labels.
    public var title: String {
        switch self {
        case .pdf: return "PDF"
        case .document: return "Word & text"
        case .code: return "Code & data"
        case .ebook: return "E-book"
        default: return rawValue.capitalized
        }
    }

    private static let extensionsByKind: [(FileKind, Set<String>)] = [
        (.pdf, ["pdf"]),
        (.image, ["png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp", "svg",
                  "avif", "ico", "psd", "raw", "cr2", "cr3", "nef", "arw", "dng"]),
        (.archive, ["zip", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz", "7z", "rar", "zst", "lz", "lzma"]),
        (.installer, ["dmg", "pkg", "mpkg"]),
        (.video, ["mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv", "mpg", "mpeg", "3gp"]),
        (.audio, ["mp3", "m4a", "aac", "wav", "flac", "aif", "aiff", "ogg", "opus", "wma", "caf"]),
        (.document, ["doc", "docx", "pages", "txt", "rtf", "rtfd", "md", "odt", "tex", "dotx"]),
        (.spreadsheet, ["xls", "xlsx", "xlsm", "numbers", "csv", "tsv", "ods"]),
        (.presentation, ["ppt", "pptx", "key", "odp"]),
        (.code, ["json", "xml", "yaml", "yml", "toml", "ini", "sql", "log", "py", "js", "ts", "tsx", "jsx", "html", "htm",
                 "css", "swift", "java", "kt", "c", "h", "cpp", "hpp", "cs", "go", "rs", "rb", "php", "sh", "zsh",
                 "ipynb", "r", "lua", "pl", "graphql", "proto", "env"]),
        (.ebook, ["epub", "mobi", "azw", "azw3", "fb2"]),
        (.font, ["ttf", "otf", "woff", "woff2", "ttc"]),
    ]

    public static func classify(fileName: String, isDirectory: Bool) -> FileKind {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if isDirectory {
            // Packages such as .rtfd or .pages bundles still count as their document kind.
            if let packaged = kind(forExtension: ext) { return packaged }
            return .folder
        }
        return kind(forExtension: ext) ?? .other
    }

    private static func kind(forExtension ext: String) -> FileKind? {
        guard !ext.isEmpty else { return nil }
        return extensionsByKind.first(where: { $0.1.contains(ext) })?.0
    }
}
