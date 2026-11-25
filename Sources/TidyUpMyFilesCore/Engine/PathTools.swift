import Foundation

public enum PathTools {
    /// The home folder rules see as `~`. `TIDYUP_DEMO_HOME` swaps in a throwaway folder (demo and screenshot
    /// mode): `~`, the Trash, settings and logs then all live inside it and real files are never touched.
    public static var homeDirectory: String {
        if let demo = ProcessInfo.processInfo.environment["TIDYUP_DEMO_HOME"], !demo.isEmpty { return demo }
        return NSHomeDirectory()
    }

    public static var isDemoHome: Bool { homeDirectory != NSHomeDirectory() }

    public static func expandTilde(_ path: String) -> String {
        if path == "~" { return homeDirectory }
        if path.hasPrefix("~/") { return homeDirectory + path.dropFirst(1) }
        return (path as NSString).expandingTildeInPath
    }

    /// Resolves a destination template that was already rendered: `~` expands, relative paths sit beside the file.
    public static func resolveFolder(_ rendered: String, relativeTo folder: URL) -> URL {
        let expanded = expandTilde(rendered)
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded).standardizedFileURL }
        return folder.appendingPathComponent(expanded).standardizedFileURL
    }

    /// Makes a rendered name safe as a single file name.
    public static func sanitizeFileName(_ name: String) -> String {
        var cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while cleaned.hasSuffix(".") || cleaned.hasSuffix(" ") { cleaned.removeLast() }
        while cleaned.hasPrefix(" ") { cleaned.removeFirst() }
        return cleaned.isEmpty ? "untitled" : cleaned
    }

    /// `report.pdf` → `report 2.pdf` (counter starts at 2, like Finder).
    public static func numbered(_ fileName: String, _ counter: Int) -> String {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        return ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
    }

    /// True when `url` is somewhere inside `folder` (never the folder itself).
    public static func isInside(_ url: URL, folder: URL) -> Bool {
        let base = realPath(folder)
        return realPath(url).hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }

    /// Like `canonical`, but also for paths that don't exist yet: the deepest existing parent is resolved.
    static func realPath(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1 {
            rest.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        return rest.reduce(existing.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }.path
    }

    /// The real path with symlinks resolved, so `/var` and `/private/var` compare equal.
    public static func canonical(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

/// Places TidyUpMyFiles must never read from or write to, whatever a rule says.
public struct SafetyGuard: Sendable {
    public var homeDirectory: String

    public init(homeDirectory: String = PathTools.homeDirectory) {
        self.homeDirectory = homeDirectory
    }

    private static let systemRoots = ["/System", "/Library", "/usr", "/bin", "/sbin", "/etc", "/private/etc",
                                      "/private/var/db", "/Applications", "/cores", "/opt"]

    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case systemFolder(String)
        case userLibrary(String)
        case gitFolder(String)
        case appBundle(String)

        public var description: String {
            switch self {
            case .systemFolder(let path): return "\(path) is a system folder"
            case .userLibrary(let path): return "\(path) is inside ~/Library"
            case .gitFolder(let path): return "\(path) is inside a .git folder"
            case .appBundle(let path): return "\(path) is an app bundle or inside one"
            }
        }
    }

    public func check(_ url: URL) throws {
        let path = PathTools.canonical(url)
        for root in SafetyGuard.systemRoots where path == root || path.hasPrefix(root + "/") {
            throw Refusal.systemFolder(path)
        }
        let library = PathTools.canonical(URL(fileURLWithPath: homeDirectory).appendingPathComponent("Library"))
        if path == library || path.hasPrefix(library + "/") { throw Refusal.userLibrary(path) }
        let components = url.standardizedFileURL.pathComponents
        if components.contains(".git") { throw Refusal.gitFolder(path) }
        if components.contains(where: { $0.lowercased().hasSuffix(".app") }) { throw Refusal.appBundle(path) }
    }

    public func isAllowed(_ url: URL) -> Bool {
        (try? check(url)) != nil
    }
}
