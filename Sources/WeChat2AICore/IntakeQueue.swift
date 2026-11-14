import Foundation
import CryptoKit
import Darwin

public struct IntakeFile: Codable, Equatable {
    public let size: Int
    public let sha256: String
}
public struct IntakeTarget: Codable, Equatable {
    public let libraryID: String
    public let path: String
    public init(libraryID: String, path: String) { self.libraryID = libraryID; self.path = path }
}
public struct IntakeReceipt: Codable {
    public var schemaVersion = 1
    public let queueID: String
    public let id: String
    public let createdAt: String
    public let files: [String: IntakeFile]
    public var target: IntakeTarget?
    public var error: String?
}
public struct IntakeCompletion: Codable {
    public var schemaVersion = 1
    public let receipt: IntakeReceipt
    public let batchID: String
}
public struct IntakeOrigin: Codable {
    public var schemaVersion = 1
    public let queueID: String
    public let receiptID: String
    public let batchID: String
    public let files: [String: IntakeFile]
}
public struct IntakeQueueMetadata: Codable {
    public var schemaVersion = 1
    public let queueID: String
}
public struct IntakeJob {
    public let id: String
    public let state: String
    public let directory: URL
    public let receipt: IntakeReceipt?
    public let issue: String?
    public var payload: URL { directory.appendingPathComponent("payload.w2adrop") }
}

// Small shared module: extension-safe Foundation APIs only, no library or AppKit dependency.
public enum IntakeIO {
    public static func uuid() -> String { UUID().uuidString.lowercased() }
    public static func validID(_ id: String) -> Bool { UUID(uuidString: id)?.uuidString.lowercased() == id }
    public static func directory(_ url: URL) throws {
        let v = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard v.isDirectory == true, v.isSymbolicLink != true else { throw CoreError.invalid("接收目录不存在或包含符号链接。") }
    }
    public static func child(_ path: String, in root: URL) throws -> URL {
        try directory(root)
        var url = root
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { throw CoreError.invalid("接收路径无效。") }
        for part in parts {
            guard !part.isEmpty, part != ".", part != "..", !part.contains("\0") else { throw CoreError.invalid("接收路径无效。") }
            url.appendPathComponent(String(part))
            if let v = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), v.isSymbolicLink == true {
                throw CoreError.invalid("接收路径包含符号链接。")
            }
        }
        return url
    }
    public static func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        let v = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard v.isRegularFile == true, v.isSymbolicLink != true, (v.fileSize ?? Int.max) <= 8 * 1024 * 1024 else {
            throw CoreError.invalid("接收元信息无效或过大。")
        }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
    public static func write<T: Encodable>(_ value: T, at url: URL) throws {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(value).write(to: url, options: .atomic)
    }
    public static func inventory(_ root: URL, hashFiles: Bool = true) throws -> [String: IntakeFile] {
        try directory(root)
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var failure: Error?, result: [String: IntakeFile] = [:], count = 0, total = 0
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, errorHandler: { _, error in failure = error; return false }) else {
            throw CoreError.invalid("无法读取接收文件。")
        }
        for case let url as URL in e {
            count += 1
            let v = try url.resourceValues(forKeys: Set(keys))
            guard v.isSymbolicLink != true, v.isDirectory == true || v.isRegularFile == true else { throw CoreError.invalid("接收文件包含符号链接或特殊文件。") }
            guard count <= SafeFiles.fileLimit else { throw CoreError.invalid("接收文件合计超过 10,000 项。") }
            if v.isRegularFile == true {
                let size = v.fileSize ?? SafeFiles.byteLimit + 1
                guard size <= SafeFiles.byteLimit - total else { throw CoreError.invalid("接收文件合计超过 512 MB。") }
                total += size
                let filePath = url.standardizedFileURL.path, prefix = root.standardizedFileURL.path + "/"
                guard filePath.hasPrefix(prefix) else { throw CoreError.invalid("接收文件路径不在任务内。") }
                let relative = String(filePath.dropFirst(prefix.count))
                if !hashFiles { result[relative] = IntakeFile(size: size, sha256: ""); continue }
                let f = try FileHandle(forReadingFrom: url); defer { try? f.close() }
                var hash = SHA256(), actual = 0
                while let bytes = try f.read(upToCount: 1024 * 1024), !bytes.isEmpty {
                    actual += bytes.count
                    guard actual <= size else { throw CoreError.invalid("接收文件在校验期间发生变化。") }
                    hash.update(data: bytes)
                }
                guard actual == size else { throw CoreError.invalid("接收文件在校验期间发生变化。") }
                result[relative] = IntakeFile(size: size, sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
            }
        }
        if let failure { throw failure }
        return result
    }
}

public final class IntakeDraft {
    public let id: String
    public let directory: URL
    public var payload: URL { directory.appendingPathComponent("payload.w2adrop") }
    private var lockFD: Int32
    fileprivate init(id: String, directory: URL, fd: Int32) { self.id = id; self.directory = directory; self.lockFD = fd }
    fileprivate func release() { if lockFD >= 0 { flock(lockFD, LOCK_UN); Darwin.close(lockFD); lockFD = -1 } }
    deinit { release() }
}

public final class IntakeQueue {
    public let root: URL
    public let metadata: IntakeQueueMetadata
    private let fm = FileManager.default
    public static let folders = ["incoming", "ready", "processing", "failed", "completed"]

    public init(at root: URL) throws {
        try IntakeIO.directory(root)
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        try IntakeIO.directory(self.root)
        metadata = try IntakeIO.read(IntakeQueueMetadata.self, at: self.root.appendingPathComponent("queue.json"))
        guard metadata.schemaVersion == 1, IntakeIO.validID(metadata.queueID) else { throw CoreError.invalid("接收队列版本或标识不支持。") }
        for name in Self.folders { try IntakeIO.directory(IntakeIO.child(name, in: self.root)) }
    }
    public static func create(at root: URL) throws -> IntakeQueue {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.path) { return try IntakeQueue(at: root) }
        try IntakeIO.directory(root.deletingLastPathComponent())
        let temp = root.deletingLastPathComponent().appendingPathComponent(".new-intake-" + IntakeIO.uuid())
        try fm.createDirectory(at: temp, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: temp) }
        for name in folders { try fm.createDirectory(at: temp.appendingPathComponent(name), withIntermediateDirectories: false) }
        try IntakeIO.write(IntakeQueueMetadata(queueID: IntakeIO.uuid()), at: temp.appendingPathComponent("queue.json"))
        try fm.moveItem(at: temp, to: root)
        return try IntakeQueue(at: root)
    }
    public func withLock<T>(_ body: () throws -> T) throws -> T {
        let current = try IntakeQueue(at: root)
        guard current.metadata.queueID == metadata.queueID else { throw CoreError.invalid("接收目录身份发生变化。") }
        let fd = Darwin.open(try IntakeIO.child(".consumer.lock", in: root).path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw CoreError.invalid("无法锁定接收队列。") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw CoreError.invalid("接收队列正在处理中，请稍后重试。") }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
    public func begin() throws -> IntakeDraft {
        let id = IntakeIO.uuid(), dir = try IntakeIO.child("incoming/\(id).partial", in: root)
        try fm.createDirectory(at: dir, withIntermediateDirectories: false)
        let fd = Darwin.open(dir.appendingPathComponent(".producer.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            if fd >= 0 { Darwin.close(fd) }; throw CoreError.invalid("无法建立接收任务。")
        }
        do { try fm.createDirectory(at: dir.appendingPathComponent("payload.w2adrop"), withIntermediateDirectories: false) }
        catch { Darwin.close(fd); throw error }
        return IntakeDraft(id: id, directory: dir, fd: fd)
    }
    /// LaunchServices must finish opening a stable URL even if the consumer already moved/cleaned a job.
    /// This tiny package holds only the queue identity, never chat data, and stays in place.
    public func signalURL() throws -> URL {
        let target = try IntakeIO.child(".intake.w2adrop", in: root)
        if !fm.fileExists(atPath: target.path) {
            let temp = try IntakeIO.child(".signal-" + IntakeIO.uuid(), in: root)
            try fm.createDirectory(at: temp, withIntermediateDirectories: false)
            defer { try? fm.removeItem(at: temp) }
            try IntakeIO.write(metadata, at: temp.appendingPathComponent("queue-link.json"))
            do { try fm.moveItem(at: temp, to: target) }
            catch { if !fm.fileExists(atPath: target.path) { throw error } }
        }
        try IntakeIO.directory(target)
        let link = try IntakeIO.read(IntakeQueueMetadata.self, at: target.appendingPathComponent("queue-link.json"))
        guard link.schemaVersion == 1, link.queueID == metadata.queueID else { throw CoreError.invalid("接收通知包身份不一致。") }
        return target
    }
    public func publish(_ draft: IntakeDraft) throws -> URL {
        guard draft.directory.standardizedFileURL.path == (try IntakeIO.child("incoming/\(draft.id).partial", in: root)).standardizedFileURL.path else { throw CoreError.invalid("接收任务不属于此队列。") }
        let files = try IntakeIO.inventory(draft.payload)
        guard !files.isEmpty else { throw CoreError.invalid("未收到可导入的文件。") }
        let receipt = IntakeReceipt(queueID: metadata.queueID, id: draft.id, createdAt: ISO8601DateFormatter().string(from: Date()), files: files)
        try IntakeIO.write(receipt, at: draft.directory.appendingPathComponent("receipt.json"))
        let target = try IntakeIO.child("ready/" + draft.id, in: root)
        try fm.moveItem(at: draft.directory, to: target)
        draft.release()
        return target.appendingPathComponent("payload.w2adrop")
    }
    public func cancel(_ draft: IntakeDraft) throws {
        guard draft.directory.standardizedFileURL.path == (try IntakeIO.child("incoming/\(draft.id).partial", in: root)).standardizedFileURL.path else { throw CoreError.invalid("接收任务不属于此队列。") }
        try fm.removeItem(at: draft.directory); draft.release()
    }
    public func jobs() throws -> [IntakeJob] {
        var jobs: [IntakeJob] = []
        for state in ["processing", "ready", "failed", "incoming"] {
            let dir = try IntakeIO.child(state, in: root)
            for url in try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = url.lastPathComponent
                let id = state == "incoming" && name.hasSuffix(".partial") ? String(name.dropLast(8)) : name
                guard IntakeIO.validID(id) else {
                    jobs.append(IntakeJob(id: name, state: state, directory: url, receipt: nil, issue: "队列中有未知项目，请在 Finder 中检查；未自动处理或删除。"))
                    continue
                }
                do {
                    try IntakeIO.directory(IntakeIO.child(state + "/" + name, in: root))
                    if state == "incoming" {
                        jobs.append(IntakeJob(id: id, state: state, directory: url, receipt: nil, issue: "接收尚未完成；正在接收的任务不能丢弃。"))
                    } else {
                        let r = try receipt(at: url, id: id)
                        jobs.append(IntakeJob(id: id, state: state, directory: url, receipt: r, issue: r.error))
                    }
                } catch { jobs.append(IntakeJob(id: id, state: state, directory: url, receipt: nil, issue: error.localizedDescription)) }
            }
        }
        return jobs
    }
    public func receipt(at directory: URL, id: String) throws -> IntakeReceipt {
        let r = try IntakeIO.read(IntakeReceipt.self, at: directory.appendingPathComponent("receipt.json"))
        guard r.schemaVersion == 1, r.queueID == metadata.queueID, r.id == id, IntakeIO.validID(id), !r.files.isEmpty else {
            throw CoreError.invalid("接收任务标识或版本不一致。")
        }
        return r
    }
    public func completion(_ id: String) throws -> IntakeCompletion? {
        guard IntakeIO.validID(id) else { throw CoreError.invalid("接收任务 ID 无效。") }
        let url = try IntakeIO.child("completed/\(id).json", in: root)
        guard fm.fileExists(atPath: url.path) else { return nil }
        let c = try IntakeIO.read(IntakeCompletion.self, at: url)
        guard c.schemaVersion == 1, c.receipt.schemaVersion == 1, c.receipt.queueID == metadata.queueID,
              c.receipt.id == id, IntakeIO.validID(c.batchID), c.receipt.target != nil else { throw CoreError.invalid("成功回执无效，已保留接收文件。") }
        return c
    }
    // Caller holds the consumer lock. This is never used for user-selected external inputs.
    func cleanup(_ job: IntakeJob, completion: IntakeCompletion) throws {
        guard job.state != "incoming", completion.receipt.id == job.id,
              completion.receipt.queueID == metadata.queueID,
              job.directory.standardizedFileURL.path == (try IntakeIO.child(job.state + "/" + job.id, in: root)).standardizedFileURL.path else { throw CoreError.invalid("不允许清理队列外的数据。") }
        if fm.fileExists(atPath: job.payload.path) {
            let remaining = try IntakeIO.inventory(job.payload)
            guard remaining.allSatisfy({ completion.receipt.files[$0.key] == $0.value }) else { throw CoreError.invalid("已入库，但接收文件发生变化，未清理。") }
            // Remove only the known payload, then metadata. If interrupted midway, see completion before importing again.
            try fm.removeItem(at: job.payload)
        }
        try fm.removeItem(at: job.directory)
    }
    public func retry(_ id: String, target: IntakeTarget? = nil) throws {
        try withLock {
            guard let job = try jobs().first(where: { $0.id == id }), job.state != "incoming", var r = job.receipt else { throw CoreError.invalid("此任务不能重试，请先导出原始文件。") }
            if let target {
                guard r.target == nil || r.target == target else { throw CoreError.invalid("此任务已绑定其他资料库。请恢复原资料库，或另存后手动导入新库。") }
                r.target = target
            }
            r.error = nil
            try IntakeIO.write(r, at: job.directory.appendingPathComponent("receipt.json"))
            if job.state != "ready" { try fm.moveItem(at: job.directory, to: IntakeIO.child("ready/" + id, in: root)) }
        }
    }
    public func discard(_ id: String) throws {
        try withLock {
            guard IntakeIO.validID(id) else { throw CoreError.invalid("未知接收项目不能由程序删除，请在 Finder 中检查。") }
            guard let job = try jobs().first(where: { $0.id == id }) else { return }
            let directory = try IntakeIO.child(job.state + "/" + id + (job.state == "incoming" ? ".partial" : ""), in: root)
            let fd = Darwin.open(directory.appendingPathComponent(".producer.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { throw CoreError.invalid("无法检查接收任务，请稍后重试。") }
            defer { Darwin.close(fd) }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw CoreError.invalid("此任务仍在接收，请先在分享窗口取消。") }
            defer { flock(fd, LOCK_UN) }
            try fm.removeItem(at: directory)
        }
    }
}
