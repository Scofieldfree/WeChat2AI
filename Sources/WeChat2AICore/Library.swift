import Foundation
import CryptoKit

public struct LibraryMetadata: Codable {
    public var schemaVersion = 1
    public let libraryID: String
    public let createdAt: String
}

public struct ChatSource: Codable, Equatable {
    public var schemaVersion = 1
    public let id: String
    public var name: String
    public var note: String
    public var kind: String
    public let createdAt: String
    public let directoryName: String
    public var label: String { name + (note.isEmpty ? "" : " · " + note) + " · " + id.prefix(6) }
}

public struct LibraryBatch {
    public let workspace: URL
    public let manifest: ImportManifest
    public let source: ChatSource?
    public var id: String { manifest.id }
}

public struct LibraryContents {
    public var sources: [ChatSource] = []
    public var batches: [LibraryBatch] = []
    public var warnings: [String] = []
}

struct MoveOperation: Codable {
    let id: String
    let batchID: String
    let from: String
    let to: String
    let manifestHash: String
}

enum LibraryIO {
    static let fm = FileManager.default
    static func now() -> String { ISO8601DateFormatter().string(from: Date()) }
    static func uuid() -> String { UUID().uuidString.lowercased() }

    static func directory(_ url: URL) throws {
        let v = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard v.isDirectory == true, v.isSymbolicLink != true else { throw CoreError.invalid("目录不存在或为符号链接：\(url.lastPathComponent)") }
    }

    static func regular(_ url: URL) throws {
        let v = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard v.isRegularFile == true, v.isSymbolicLink != true else { throw CoreError.invalid("不是可读取的普通文件：\(url.lastPathComponent)") }
    }

    static func read<T: Decodable>(_ type: T.Type, _ url: URL) throws -> T {
        try regular(url)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 20 * 1024 * 1024 else { throw CoreError.invalid("元信息文件过大。") }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    static func write<T: Encodable>(_ value: T, _ url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    static func relative(_ url: URL, to root: URL) throws -> String {
        let path = url.standardizedFileURL.path, prefix = root.standardizedFileURL.path + "/"
        guard path.hasPrefix(prefix) else { throw CoreError.invalid("路径不在资料库内。") }
        return String(path.dropFirst(prefix.count))
    }

    // Resolve each existing component without permitting symlink escapes.
    static func child(_ relative: String, of root: URL) throws -> URL {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else {
            throw CoreError.invalid("资料包含无效相对路径。")
        }
        var cursor = root
        try directory(root)
        for (index, part) in parts.enumerated() {
            cursor.appendPathComponent(String(part))
            if let values = try? cursor.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]) {
                guard values.isSymbolicLink != true else { throw CoreError.invalid("资料路径包含符号链接。") }
                if index < parts.count - 1, values.isDirectory != true { throw CoreError.invalid("资料路径中间项不是目录。") }
            }
        }
        return cursor
    }

    static func hash(_ url: URL) throws -> String {
        try regular(url)
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func hashes(_ root: URL, excluding: Set<String> = []) throws -> [String: String] {
        try directory(root)
        var result: [String: String] = [:], traversalError: Error?
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey], errorHandler: { _, error in
            traversalError = error; return false
        }) else { throw CoreError.invalid("无法枚举资料。") }
        var count = 0
        for case let url as URL in enumerator {
            count += 1
            guard count <= SafeFiles.fileLimit + 20 else { throw CoreError.invalid("资料项目过多。") }
            let relative = try self.relative(url, to: root)
            let v = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard v.isSymbolicLink != true, v.isDirectory == true || v.isRegularFile == true else { throw CoreError.invalid("资料含符号链接或特殊文件。") }
            if v.isRegularFile == true, !excluding.contains(relative) { result[relative] = try hash(url) }
        }
        if let error = traversalError { throw error }
        return result
    }

    static func manifest(_ workspace: URL) throws -> ImportManifest {
        try directory(workspace)
        let manifest = try read(ImportManifest.self, workspace.appendingPathComponent("manifest.json"))
        guard manifest.schemaVersion == 1, UUID(uuidString: manifest.id) != nil else { throw CoreError.invalid("不支持的批次格式或无效 ID。") }
        try regular(workspace.appendingPathComponent("transcript.md"))
        try regular(workspace.appendingPathComponent("messages.jsonl"))
        try directory(workspace.appendingPathComponent("original"))
        guard manifest.transcriptPath.hasPrefix("original/") else { throw CoreError.invalid("原文路径无效。") }
        try regular(child(manifest.transcriptPath, of: workspace))
        return manifest
    }

    static func validatedCopy(_ source: URL, to destination: URL) throws {
        let before = try hashes(source)
        try SafeFiles.copy(source, to: destination)
        guard try hashes(destination) == before, try hashes(source) == before else { throw CoreError.invalid("复制校验失败或原始数据在复制期间发生变化。") }
        _ = try manifest(destination)
    }
}
