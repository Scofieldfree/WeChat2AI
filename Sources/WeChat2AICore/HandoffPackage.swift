import Foundation

public struct HandoffMetadata: Codable {
    public var schemaVersion = 1
    public let id: String
    public let libraryID: String
    public let batchID: String
    public let sourceID: String?
    public let sourceName: String
    public let createdAt: String
    public let scope: String
    public let files: [String: String]
    public let byteCount: Int64
}

public struct HandoffResult {
    public let workspace: URL
    public let metadata: HandoffMetadata
    public var project: URL? = nil
}

public enum HandoffPackage {
    public static var defaultRoot: URL { AgentWorkspace.handoffs }

    public static func create(workspace: URL, libraryID: String, source: ChatSource?, at root: URL = defaultRoot) throws -> HandoffResult {
        let fm = FileManager.default
        let manifest = try LibraryIO.manifest(workspace)
        try AgentWorkspace.ensureDirectory(root)
        try LibraryIO.directory(root)
        let id = LibraryIO.uuid(), temp = root.appendingPathComponent(".pending-" + LibraryIO.uuid())
        defer { try? fm.removeItem(at: temp) }
        try LibraryIO.validatedCopy(workspace, to: temp)
        let files = try LibraryIO.hashes(temp)
        var byteCount: Int64 = 0
        for file in files.keys {
            byteCount += Int64(try temp.appendingPathComponent(file).resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        let metadata = HandoffMetadata(id: id, libraryID: libraryID, batchID: manifest.id,
            sourceID: source?.id, sourceName: source?.name ?? "待分类",
            createdAt: LibraryIO.now(), scope: "single-batch", files: files, byteCount: byteCount)
        try LibraryIO.write(metadata, temp.appendingPathComponent("handoff.json"))
        let target = root.appendingPathComponent(id)
        try fm.moveItem(at: temp, to: target)
        return HandoffResult(workspace: target, metadata: metadata)
    }
}
