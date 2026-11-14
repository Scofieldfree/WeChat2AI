import Foundation

public enum CoreError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

public enum SafeFiles {
    public static let byteLimit = 512 * 1024 * 1024
    public static let fileLimit = 10_000

    /// Copy regular files only; never follow symlinks out of a shared folder.
    public static func copy(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let sourcePath = source.standardizedFileURL.resolvingSymlinksInPath().path
        let destinationPath = destination.standardizedFileURL.resolvingSymlinksInPath().path
        guard destinationPath != sourcePath, !destinationPath.hasPrefix(sourcePath + "/") else {
            throw CoreError.invalid("保存位置位于导入目录内部。请选择聊天导出文件夹，不要导入整个资料库或其父目录。")
        }
        let root = try source.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey])
        guard root.isSymbolicLink != true else { throw CoreError.invalid("不支持符号链接。") }
        if root.isRegularFile == true {
            guard (root.fileSize ?? byteLimit + 1) <= byteLimit else { throw CoreError.invalid("单个文件超过 512 MB。") }
            try fm.copyItem(at: source, to: destination)
            return
        }
        guard root.isDirectory == true else { throw CoreError.invalid("不支持此文件类型。") }
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        var traversalError: Error?
        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: keys, errorHandler: { _, error in
            traversalError = error; return false
        }) else { throw CoreError.invalid("无法读取文件夹。") }
        var entries: [(URL, String, Bool)] = []
        var total = 0
        for case let url as URL in enumerator {
            let value = try url.resourceValues(forKeys: Set(keys))
            guard value.isSymbolicLink != true else { throw CoreError.invalid("文件夹含符号链接，导入已停止。") }
            guard value.isDirectory == true || value.isRegularFile == true else { throw CoreError.invalid("文件夹含不支持的特殊文件。") }
            total += value.fileSize ?? 0
            guard entries.count < fileLimit, total <= byteLimit else { throw CoreError.invalid("导入超过 10,000 个项目或 512 MB。") }
            let relative = String(url.resolvingSymlinksInPath().path.dropFirst(source.resolvingSymlinksInPath().path.count + 1))
            entries.append((url, relative, value.isDirectory == true))
        }
        if let error = traversalError { throw error }
        try fm.createDirectory(at: destination, withIntermediateDirectories: false)
        for (url, relative, directory) in entries {
            let target = destination.appendingPathComponent(relative)
            if directory { try fm.createDirectory(at: target, withIntermediateDirectories: true) }
            else {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: url, to: target)
            }
        }
    }
}
