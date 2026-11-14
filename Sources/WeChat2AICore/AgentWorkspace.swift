import Foundation

/// Files exposed to Agents live outside application-internal storage.
public enum AgentWorkspace {
    public static var root: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("WeChat2AI", isDirectory: true) }
    public static var projects: URL { root.appendingPathComponent("Projects", isDirectory: true) }
    public static var handoffs: URL { root.appendingPathComponent("Handoffs", isDirectory: true) }

    // Walk existing ancestors: FileManager.fileExists alone misses dangling symlinks.
    static func ensureDirectory(_ url: URL, create: Bool = true) throws {
        guard url.isFileURL else { throw CoreError.invalid("工作区必须是本地目录。") }
        let path = url.standardizedFileURL
        if path.path == "/" { return }
        // macOS supplies /var and /tmp as system aliases. User-controlled aliases stay rejected.
        if ["/var", "/tmp"].contains(path.path),
           ["private" + path.path, "/private" + path.path].contains((try? FileManager.default.destinationOfSymbolicLink(atPath: path.path)) ?? "") {
            try LibraryIO.directory(URL(fileURLWithPath: "/private" + path.path)); return
        }
        try ensureDirectory(path.deletingLastPathComponent(), create: create)
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path.path)
            guard attrs[.type] as? FileAttributeType == .typeDirectory else { throw CoreError.invalid("工作区路径被文件或符号链接占用：\(path.path)") }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            if create { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false) }
        }
    }

}
