import Foundation

public struct IntakeOutcome {
    public let completion: IntakeCompletion
    public let batch: LibraryBatch?
}

public enum IntakeProcessor {
    public static func retarget(_ id: String, in queue: IntakeQueue, to target: IntakeTarget) throws {
        try queue.withLock {
            guard try queue.completion(id) == nil,
                  let job = try queue.jobs().first(where: { $0.id == id }), job.state != "incoming",
                  var receipt = job.receipt else { throw CoreError.invalid("已入库或未完成接收的任务不能改投。") }
            if let previous = receipt.target, previous.libraryID != target.libraryID {
                // Recover the old library first: it may already have committed before acknowledgement.
                // An unavailable old library cannot establish that a new import would be safe.
                let old: LibraryStore
                do { old = try LibraryStore.open(at: URL(fileURLWithPath: previous.path)) }
                catch { throw CoreError.invalid("请先恢复原资料库连接以确认是否已入库。也可另存后手动导入；原接收任务保留。") }
                guard old.metadata.libraryID == previous.libraryID else { throw CoreError.invalid("原资料库身份不一致，未改投。") }
                let contents = try old.contents()
                guard contents.warnings.isEmpty else { throw CoreError.invalid("原资料库有待恢复项目，暂不能改投。") }
                for batch in contents.batches {
                    let url = batch.workspace.appendingPathComponent("intake-origin.json")
                    if FileManager.default.fileExists(atPath: url.path) {
                        let origin = try IntakeIO.read(IntakeOrigin.self, at: url)
                        guard origin.schemaVersion == 1 else { throw CoreError.invalid("原资料库回执版本不支持。") }
                        if origin.queueID == receipt.queueID && origin.receiptID == receipt.id { throw CoreError.invalid("此任务已在原资料库入库，请重试以完成清理。") }
                    }
                }
            }
            let new = try LibraryStore.open(at: URL(fileURLWithPath: target.path))
            guard new.metadata.libraryID == target.libraryID else { throw CoreError.invalid("新资料库身份不一致。") }
            receipt.target = target; receipt.error = nil
            try IntakeIO.write(receipt, at: job.directory.appendingPathComponent("receipt.json"))
            if job.state != "ready" { try FileManager.default.moveItem(at: job.directory, to: IntakeIO.child("ready/" + id, in: queue.root)) }
        }
    }
    /// The queue lock spans recovery, library commit, acknowledgement and cleanup.
    public static func process(_ id: String, in queue: IntakeQueue, defaultTarget: IntakeTarget?) throws -> IntakeOutcome {
        try queue.withLock {
            let fm = FileManager.default
            let jobs = try queue.jobs().filter { $0.id == id }
            guard jobs.count <= 1 else { throw CoreError.invalid("接收任务状态重复，未修改数据。") }
            let completed = try queue.completion(id)
            guard let job = jobs.first else {
                if let completed { return IntakeOutcome(completion: completed, batch: nil) }
                throw CoreError.invalid("接收任务不存在。")
            }
            guard job.state != "incoming", var receipt = job.receipt else { throw CoreError.invalid(job.issue ?? "接收尚未完成。") }
            if let completed {
                guard completed.receipt.files == receipt.files, completed.receipt.target == receipt.target else { throw CoreError.invalid("成功回执与接收任务冲突。") }
                try queue.cleanup(job, completion: completed)
                return IntakeOutcome(completion: completed, batch: nil)
            }
            guard job.state != "failed" else { throw CoreError.invalid(receipt.error ?? "请在待处理接收中重试。") }
            var directory = job.directory
            do {
                if receipt.target == nil { receipt.target = defaultTarget }
                receipt.error = nil
                try IntakeIO.write(receipt, at: directory.appendingPathComponent("receipt.json"))
                if job.state != "processing" {
                    let target = try IntakeIO.child("processing/" + id, in: queue.root)
                    try fm.moveItem(at: directory, to: target); directory = target
                }
                guard let target = receipt.target else { throw CoreError.invalid("尚未连接资料库，请打开资料库后重试。") }
                let library = try LibraryStore.open(at: URL(fileURLWithPath: target.path))
                guard library.metadata.libraryID == target.libraryID else { throw CoreError.invalid("目标资料库身份发生变化，接收文件已保留。") }
                let payload = directory.appendingPathComponent("payload.w2adrop")
                let batch = try library.importIntake(from: payload, receipt: receipt)
                let completion = IntakeCompletion(receipt: receipt, batchID: batch.id)
                try IntakeIO.write(completion, at: IntakeIO.child("completed/\(id).json", in: queue.root))
                try queue.cleanup(IntakeJob(id: id, state: "processing", directory: directory, receipt: receipt, issue: nil), completion: completion)
                return IntakeOutcome(completion: completion, batch: batch)
            } catch {
                receipt.error = error.localizedDescription
                if fm.fileExists(atPath: directory.path) {
                    try? IntakeIO.write(receipt, at: directory.appendingPathComponent("receipt.json"))
                    let failed = try IntakeIO.child("failed/" + id, in: queue.root)
                    if directory != failed { try? fm.moveItem(at: directory, to: failed) }
                }
                throw error
            }
        }
    }
}
