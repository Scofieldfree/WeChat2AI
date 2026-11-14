import Foundation
import Darwin

public final class LibraryStore {
    public let root: URL
    public let metadata: LibraryMetadata
    private let fm = FileManager.default

    public static var defaultRoot: URL { StoragePaths.library }

    private init(root: URL, metadata: LibraryMetadata) { self.root = root; self.metadata = metadata }

    public static func create(at location: URL) throws -> LibraryStore {
        let root = location.standardizedFileURL
        guard !LibraryIO.fm.fileExists(atPath: root.path) else { throw CoreError.invalid("此位置已存在内容，请打开已有资料库或选择其他位置。") }
        try LibraryIO.directory(root.deletingLastPathComponent())
        let temp = root.deletingLastPathComponent().appendingPathComponent(".new-library-" + LibraryIO.uuid())
        try LibraryIO.fm.createDirectory(at: temp, withIntermediateDirectories: false)
        defer { try? LibraryIO.fm.removeItem(at: temp) }
        for name in ["unfiled", "sources", ".staging", ".operations"] {
            try LibraryIO.fm.createDirectory(at: temp.appendingPathComponent(name), withIntermediateDirectories: false)
        }
        let metadata = LibraryMetadata(libraryID: LibraryIO.uuid(), createdAt: LibraryIO.now())
        try LibraryIO.write(metadata, temp.appendingPathComponent("library.json"))
        try LibraryIO.fm.moveItem(at: temp, to: root)
        return try open(at: root)
    }

    public static func open(at location: URL) throws -> LibraryStore {
        let root = location.standardizedFileURL
        try LibraryIO.directory(root)
        let metadata = try LibraryIO.read(LibraryMetadata.self, root.appendingPathComponent("library.json"))
        guard metadata.schemaVersion == 1, UUID(uuidString: metadata.libraryID) != nil else { throw CoreError.invalid("资料库版本不支持，未修改任何数据。") }
        let store = LibraryStore(root: root, metadata: metadata)
        try store.withLock { try store.recover() }
        return store
    }

    // flock is released by the OS on exit; the lock file is never unlinked.
    // This also rejects concurrent writers opened through a second Store instance.
    func withLock<T>(_ body: () throws -> T) throws -> T {
        try LibraryIO.directory(root)
        let fd = Darwin.open(root.appendingPathComponent(".writer.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw CoreError.invalid("资料库无法写入，请检查位置、磁盘和权限。") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw CoreError.invalid("资料库正在被另一项操作使用，请稍后重试。") }
        defer { flock(fd, LOCK_UN) }
        let current = try LibraryIO.read(LibraryMetadata.self, root.appendingPathComponent("library.json"))
        guard current.schemaVersion == 1, current.libraryID == metadata.libraryID else { throw CoreError.invalid("资料库身份或版本发生变化，请重新打开。") }
        for path in ["unfiled", "sources", ".staging", ".operations"] { try LibraryIO.directory(root.appendingPathComponent(path)) }
        return try body()
    }

    public func contents() throws -> LibraryContents {
        try withLock {
            try recover()
            return try scan()
        }
    }

    private func children(_ url: URL) throws -> [URL] {
        try LibraryIO.directory(url)
        return try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func scan() throws -> LibraryContents {
        var result = LibraryContents()
        var locations: [(URL, ChatSource?)] = [(root.appendingPathComponent("unfiled"), nil)]
        for dir in try children(root.appendingPathComponent("sources")) {
            do {
                try LibraryIO.directory(dir)
                let source = try LibraryIO.read(ChatSource.self, dir.appendingPathComponent("source.json"))
                guard source.schemaVersion == 1, UUID(uuidString: source.id) != nil,
                      source.directoryName == dir.lastPathComponent, !source.name.isEmpty,
                      ["group", "direct"].contains(source.kind), !result.sources.contains(where: { $0.id == source.id }) else {
                    throw CoreError.invalid("来源格式、ID 或目录不一致。")
                }
                try LibraryIO.directory(dir.appendingPathComponent("batches"))
                result.sources.append(source); locations.append((dir.appendingPathComponent("batches"), source))
            } catch { result.warnings.append("来源 \(dir.lastPathComponent)：\(error.localizedDescription)") }
        }
        var seen = Set<String>(), duplicates = Set<String>()
        for (parent, source) in locations {
            for dir in try children(parent) {
                do {
                    let manifest = try LibraryIO.manifest(dir)
                    guard manifest.id == dir.lastPathComponent else { throw CoreError.invalid("批次 ID 与目录不符。") }
                    if !seen.insert(manifest.id).inserted {
                        duplicates.insert(manifest.id)
                        result.warnings.append("批次 ID 重复，已停止对该批次操作：\(manifest.id)")
                    } else { result.batches.append(LibraryBatch(workspace: dir, manifest: manifest, source: source)) }
                } catch { result.warnings.append("记录 \(dir.lastPathComponent)：\(error.localizedDescription)") }
            }
        }
        result.batches.removeAll { duplicates.contains($0.id) }
        result.batches.sort { $0.manifest.importedAt > $1.manifest.importedAt }
        result.sources.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let unfinished = try children(root.appendingPathComponent(".staging"))
        if !unfinished.isEmpty { result.warnings.append("有 \(unfinished.count) 项未完成的暂存数据，已保留在 .staging，未计入历史。") }
        return result
    }

    private func requireBatch(_ id: String) throws -> LibraryBatch {
        let data = try scan()
        guard let batch = data.batches.first(where: { $0.id == id }) else { throw CoreError.invalid("批次不存在、不可读或 ID 冲突。请刷新记录。") }
        return batch
    }

    private func destination(for sourceID: String?) throws -> URL {
        guard let sourceID else { return root.appendingPathComponent("unfiled") }
        guard let source = try scan().sources.first(where: { $0.id == sourceID }) else { throw CoreError.invalid("目标群/对话不存在或不可读。") }
        return try LibraryIO.child("sources/\(source.directoryName)/batches", of: root)
    }

    public func createSource(name: String, note: String = "", kind: String = "group") throws -> ChatSource {
        try withLock {
            try recover()
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean.count <= 100, note.count <= 300, ["group", "direct"].contains(kind) else { throw CoreError.invalid("名称须为 1–100 字，备注最多 300 字。") }
            let id = LibraryIO.uuid()
            let safe = String(clean.prefix(32)).map { "/:\\".contains($0) || $0.isNewline || $0.asciiValue.map({ $0 < 32 }) == true ? "_" : String($0) }.joined()
            let key = (safe.hasPrefix(".") ? "群_" : "") + safe + "-" + id
            let source = ChatSource(id: id, name: clean, note: note, kind: kind, createdAt: LibraryIO.now(), directoryName: key)
            let temp = root.appendingPathComponent(".staging/source-" + id)
            try fm.createDirectory(at: temp, withIntermediateDirectories: false)
            defer { try? fm.removeItem(at: temp) }
            try fm.createDirectory(at: temp.appendingPathComponent("batches"), withIntermediateDirectories: false)
            try LibraryIO.write(source, temp.appendingPathComponent("source.json"))
            try fm.moveItem(at: temp, to: root.appendingPathComponent("sources").appendingPathComponent(key))
            return source
        }
    }

    public func renameSource(id: String, name: String, note: String) throws {
        try withLock {
            try recover()
            guard var source = try scan().sources.first(where: { $0.id == id }) else { throw CoreError.invalid("来源不存在或不可读。") }
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean.count <= 100, note.count <= 300 else { throw CoreError.invalid("名称须为 1–100 字，备注最多 300 字。") }
            source.name = clean; source.note = note
            try LibraryIO.write(source, LibraryIO.child("sources/\(source.directoryName)/source.json", of: root))
        }
    }

    @discardableResult public func assign(batchID: String, to sourceID: String?) throws -> LibraryBatch {
        try withLock {
            try recover()
            let batch = try requireBatch(batchID)
            let target = try destination(for: sourceID).appendingPathComponent(batchID)
            if batch.workspace != target { try commitMove(batch.workspace, to: target, batchID: batchID) }
            return try requireBatch(batchID)
        }
    }

    @discardableResult public func importData(from source: URL) throws -> LibraryBatch {
        try withLock {
            try recover()
            let job = root.appendingPathComponent(".staging/import-" + LibraryIO.uuid())
            try fm.createDirectory(at: job, withIntermediateDirectories: false)
            let result: ImportResult
            do { result = try Importer.run(source: source, inbox: job) }
            catch { try? fm.removeItem(at: job); throw error }
            // A commit failure keeps the complete data and journal for recovery.
            try commitMove(result.workspace, to: root.appendingPathComponent("unfiled/" + result.manifest.id), batchID: result.manifest.id)
            try? fm.removeItem(at: job)
            return try requireBatch(result.manifest.id)
        }
    }

    /// A durable receipt is committed with the batch, before acknowledging the transport.
    public func importIntake(from payload: URL, receipt: IntakeReceipt) throws -> LibraryBatch {
        try withLock {
            try recover()
            guard receipt.schemaVersion == 1, IntakeIO.validID(receipt.id), IntakeIO.validID(receipt.queueID),
                  receipt.target?.libraryID == metadata.libraryID,
                  receipt.target?.path == root.path,
                  payload.lastPathComponent == "payload.w2adrop",
                  try IntakeIO.inventory(payload) == receipt.files else { throw CoreError.invalid("接收数据或目标资料库校验失败。") }
            let job = root.appendingPathComponent(".staging/intake-\(receipt.queueID)-\(receipt.id)")
            // This task's input is still verified in the queue. Uncommitted staging is safe to rebuild.
            // recover() above finishes any journalled commit before this point.
            if fm.fileExists(atPath: job.path) { try LibraryIO.directory(job); try fm.removeItem(at: job) }
            let existing = try scan()
            guard existing.warnings.isEmpty else { throw CoreError.invalid("资料库有待恢复或不可读项目，请先处理后重试接收。") }
            for batch in existing.batches {
                let url = batch.workspace.appendingPathComponent("intake-origin.json")
                guard fm.fileExists(atPath: url.path) else { continue }
                let origin = try LibraryIO.read(IntakeOrigin.self, url)
                guard origin.schemaVersion == 1 else { throw CoreError.invalid("不支持的接收入库回执版本。") }
                if origin.queueID == receipt.queueID && origin.receiptID == receipt.id {
                    guard origin.batchID == batch.id, origin.files == receipt.files,
                          try IntakeIO.inventory(batch.workspace.appendingPathComponent("original/payload.w2adrop")) == receipt.files else {
                        throw CoreError.invalid("同一接收任务的内容或已入库原文发生变化，未重复导入。")
                    }
                    return batch
                }
            }
            try fm.createDirectory(at: job, withIntermediateDirectories: false)
            let result: ImportResult
            do {
                result = try Importer.run(source: payload, inbox: job)
                guard try IntakeIO.inventory(result.workspace.appendingPathComponent("original/payload.w2adrop")) == receipt.files,
                      try IntakeIO.inventory(payload) == receipt.files else { throw CoreError.invalid("入库原始文件校验失败。") }
                let origin = IntakeOrigin(queueID: receipt.queueID, receiptID: receipt.id, batchID: result.manifest.id, files: receipt.files)
                try LibraryIO.write(origin, result.workspace.appendingPathComponent("intake-origin.json"))
                var manifest = result.manifest
                manifest.sourceName = "WeChat-\(receipt.createdAt.replacingOccurrences(of: ":", with: "-"))-\(receipt.id.prefix(6)).w2adrop"
                try LibraryIO.write(manifest, result.workspace.appendingPathComponent("manifest.json"))
            } catch { try? fm.removeItem(at: job); throw error }
            // A journalled commit failure must retain its staging for recover().
            try commitMove(result.workspace, to: root.appendingPathComponent("unfiled/" + result.manifest.id), batchID: result.manifest.id)
            try? fm.removeItem(at: job)
            return try requireBatch(result.manifest.id)
        }
    }


    public func createHandoff(batchID: String, at handoffRoot: URL = HandoffPackage.defaultRoot) throws -> HandoffResult {
        try withLock {
            try recover()
            let batch = try requireBatch(batchID)
            return try HandoffPackage.create(workspace: batch.workspace, libraryID: metadata.libraryID, source: batch.source, at: handoffRoot)
        }
    }

    public func createCodexHandoff(batchID: String, projectsRoot: URL = ManagedProjects.defaultRoot,
                                   handoffRoot: URL = HandoffPackage.defaultRoot) throws -> HandoffResult {
        try withLock {
            try recover()
            let batch = try requireBatch(batchID)
            if let source = batch.source {
                return try ManagedProjects.createHandoff(workspace: batch.workspace, libraryID: metadata.libraryID,
                                                          source: source, at: projectsRoot)
            }
            return try HandoffPackage.create(workspace: batch.workspace, libraryID: metadata.libraryID, source: nil, at: handoffRoot)
        }
    }

    public func createAnalysisHandoff(batchID: String, task: AnalysisTask, historyIDs: [String] = [], resultFiles: [URL] = [],
                                       projectsRoot: URL = ManagedProjects.defaultRoot,
                                       handoffRoot: URL = HandoffPackage.defaultRoot) throws -> HandoffResult {
        try withLock {
            try recover(); try task.validate()
            let batch = try requireBatch(batchID)
            guard Set(historyIDs).count == historyIDs.count, !historyIDs.contains(batchID) else {
                throw CoreError.invalid("历史资料不能重复或包含本批次。")
            }
            let history = try historyIDs.map { try requireBatch($0) }
            guard history.isEmpty || (batch.source != nil && history.allSatisfy { $0.source?.id == batch.source?.id }) else {
                throw CoreError.invalid("只能选择同一群的历史批次，请先归群。")
            }
            let handoff: HandoffResult
            if let source = batch.source {
                handoff = try ManagedProjects.createHandoff(workspace: batch.workspace, libraryID: metadata.libraryID, source: source, at: projectsRoot)
            } else {
                handoff = try HandoffPackage.create(workspace: batch.workspace, libraryID: metadata.libraryID, source: nil, at: handoffRoot)
            }
            do { return try AnalysisContext.attach(to: handoff, task: task, history: history, resultFiles: resultFiles) }
            catch { try? fm.removeItem(at: handoff.workspace); throw error }
        }
    }

    private func commitMove(_ from: URL, to: URL, batchID: String) throws {
        guard !fm.fileExists(atPath: to.path) else { throw CoreError.invalid("目标批次已经存在，未覆盖。") }
        let operation = MoveOperation(id: LibraryIO.uuid(), batchID: batchID, from: try LibraryIO.relative(from, to: root), to: try LibraryIO.relative(to, to: root), manifestHash: try LibraryIO.hash(from.appendingPathComponent("manifest.json")))
        let journal = root.appendingPathComponent(".operations/\(operation.id).json")
        try LibraryIO.write(operation, journal)
        try complete(operation)
        try fm.removeItem(at: journal)
    }

    private func validBatchLocation(_ relative: String, allowStaging: Bool) -> Bool {
        let p = relative.split(separator: "/")
        if allowStaging && p.first == ".staging" { return p.count == 2 || p.count == 3 }
        return (p.count == 2 && p[0] == "unfiled") || (p.count == 4 && p[0] == "sources" && p[2] == "batches")
    }

    private func complete(_ operation: MoveOperation) throws {
        guard UUID(uuidString: operation.id) != nil, UUID(uuidString: operation.batchID) != nil,
              validBatchLocation(operation.from, allowStaging: true), validBatchLocation(operation.to, allowStaging: false),
              operation.to.split(separator: "/").last == Substring(operation.batchID), operation.from != operation.to else {
            throw CoreError.invalid("归档恢复记录无效，已保留文件。")
        }
        let from = try LibraryIO.child(operation.from, of: root), to = try LibraryIO.child(operation.to, of: root)
        let hasFrom = fm.fileExists(atPath: from.path), hasTo = fm.fileExists(atPath: to.path)
        guard hasFrom != hasTo else { throw CoreError.invalid("归档恢复存在冲突或文件缺失：\(operation.batchID)。已保留现场。") }
        let existing = hasFrom ? from : to
        guard try LibraryIO.manifest(existing).id == operation.batchID,
              try LibraryIO.hash(existing.appendingPathComponent("manifest.json")) == operation.manifestHash else {
            throw CoreError.invalid("归档恢复校验失败，未移动或删除资料。")
        }
        if hasFrom {
            try LibraryIO.directory(to.deletingLastPathComponent())
            try fm.moveItem(at: from, to: to)
        }
    }

    private func recover() throws {
        for journal in try children(root.appendingPathComponent(".operations")) {
            let operation = try LibraryIO.read(MoveOperation.self, journal)
            guard journal.lastPathComponent == operation.id + ".json" else { throw CoreError.invalid("恢复记录名称与 ID 不符。") }
            try complete(operation)
            try fm.removeItem(at: journal)
        }
        // Empty import jobs left after a successful atomic commit are harmless.
        for job in try children(root.appendingPathComponent(".staging")) where job.lastPathComponent.hasPrefix("import-") || job.lastPathComponent.hasPrefix("intake-") {
            if (try? children(job).isEmpty) == true { try fm.removeItem(at: job) }
        }
    }

}
