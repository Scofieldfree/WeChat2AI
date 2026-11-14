import AppKit

/// The extension owns its bookmark; it is not passed to the host process.
final class IntakeLocation {
    private let key = "intakeDirectoryBookmark.v1"
    private var accessed: URL?
    func restore() throws -> IntakeQueue? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        guard url.startAccessingSecurityScopedResource() else { throw CoreError.invalid("接收目录授权失效，请重新连接。") }
        accessed = url
        let queue = try IntakeQueue(at: url)
        if stale { try remember(url) }
        return queue
    }
    func connect(_ selected: URL) throws -> IntakeQueue {
        release()
        let access = selected.startAccessingSecurityScopedResource()
        defer { if access { selected.stopAccessingSecurityScopedResource() } }
        let isQueue = FileManager.default.fileExists(atPath: selected.appendingPathComponent("queue.json").path)
        let queue = try IntakeQueue.create(at: isQueue ? selected : selected.appendingPathComponent("WeChat2AI Receipts"))
        try remember(queue.root)
        guard let restored = try restore() else { throw CoreError.invalid("无法保存接收目录授权。") }
        return restored
    }
    private func remember(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: key)
    }
    func release() { accessed?.stopAccessingSecurityScopedResource(); accessed = nil }
    deinit { release() }
}
