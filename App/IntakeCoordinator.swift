import Foundation

@MainActor
final class IntakeCoordinator {
    var pendingURLs: [URL] = []
    var attempted = Set<String>()
}

@MainActor
extension AppModel {
    func receive(_ urls: [URL]) { intake.pendingURLs += urls; drainQueue() }
    func drainQueue() {
        guard started, idle else { return }
        if !intake.pendingURLs.isEmpty {
            let url = intake.pendingURLs.removeFirst()
            do {
                if let queue = try environment.intakeRegistry.candidate(for: url) {
                    if try !environment.intakeRegistry.isRegistered(queue) { confirmIntakeDirectory(queue, input: url); return }
                } else {
                    guard store != nil else { intake.pendingURLs.insert(url, at: 0); return }
                    performImport(url); return
                }
            } catch { fail(error) }
            if !intake.pendingURLs.isEmpty { DispatchQueue.main.async { self.drainQueue() }; return }
        }
        processNextIntake()
    }
    func intakeSnapshot() -> (jobs: [(IntakeQueue, IntakeJob)], errors: [String]) {
        let registered = environment.intakeRegistry.queues()
        var jobs: [(IntakeQueue, IntakeJob)] = [], errors = registered.errors
        for queue in registered.values {
            do { jobs += try queue.jobs().map { (queue, $0) } }
            catch { errors.append(error.localizedDescription) }
        }
        intakeCount = jobs.count
        intakeHasErrors = !errors.isEmpty
        intakeHasFailures = jobs.contains { $0.1.state == "failed" || $0.1.issue != nil }
        return (jobs, errors)
    }
    func processNextIntake() {
        guard idle else { return }
        let snapshot = intakeSnapshot()
        guard let (queue, job) = snapshot.jobs.first(where: {
            ["ready", "processing"].contains($0.1.state) && $0.1.receipt != nil && !intake.attempted.contains($0.0.metadata.queueID + "/" + $0.1.id)
        }) else { return }
        intake.attempted.insert(queue.metadata.queueID + "/" + job.id)
        let target = store.map { IntakeTarget(libraryID: $0.metadata.libraryID, path: $0.root.path) } ?? environment.librarySettings.intakeTarget
        run("正在将接收记录保存到资料库…", task: {
            try IntakeProcessor.process(job.id, in: queue, defaultTarget: target)
        }, done: { result in
            _ = self.intakeSnapshot()
            if let batch = result.batch, result.completion.receipt.target?.libraryID == self.store?.metadata.libraryID {
                self.selectedSource = batch.source?.id ?? "unfiled"
                self.reload(select: batch.id) { self.didImport(batch) }
            } else { self.setStatus("接收任务已入库，暂存包已清理。", tone: .success) }
        })
    }
}
