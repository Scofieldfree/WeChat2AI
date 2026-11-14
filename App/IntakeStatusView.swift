import SwiftUI

struct IntakeStatusView: View {
    @ObservedObject var model: AppModel
    let jobs: [(IntakeQueue, IntakeJob)]
    let errors: [String]
    var body: some View {
        W2ASheetLayout(title: "待处理接收 · \(jobs.count) 项", subtitle: "失败的接收包会保留。可查看原因、重试、另存或丢弃。") {
            ForEach(Array(errors.enumerated()), id: \.offset) { _, error in W2AStatus(message: error, tone: .error) }
            if jobs.isEmpty { Text("没有待处理任务。首次分享时设置接收位置，之后自动导入。").foregroundStyle(Color.w2aSecondary) }
            ForEach(Array(jobs.enumerated()), id: \.offset) { _, entry in
                Button {
                    let parent = model.sheetParent
                    model.dismissSheet { model.showIntakeDetail(entry.0, job: entry.1, from: parent) }
                } label: {
                    VStack(alignment: .leading, spacing: W2ATheme.Space.xs) {
                        Text("\(stateTitle(entry.1.state)) · \(entry.1.id.prefix(8))")
                        Text(entry.1.receipt?.createdAt ?? "接收尚未完成").font(W2ATheme.TypeStyle.metadata)
                        if let issue = entry.1.issue { Text(issue).font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary).lineLimit(2) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } actions: {
            Button("连接接收目录…") { let parent = model.sheetParent; model.dismissSheet { model.connectIntakeDirectory(from: parent) } }
            Spacer()
            Button("关闭") { model.dismissSheet() }.keyboardShortcut(.cancelAction)
        }
    }
    func stateTitle(_ state: String) -> String {
        ["incoming": "接收中 / 未完成", "ready": "等待导入", "processing": "处理中 / 待恢复", "failed": "需要处理"][state] ?? state
    }
}

struct IntakeDetailView: View {
    @ObservedObject var model: AppModel
    let queue: IntakeQueue
    let job: IntakeJob
    let acknowledged: Bool
    var body: some View {
        W2ASheetLayout(title: "待处理接收 \(job.id.prefix(8))", subtitle: acknowledged ? "已入库，暂存清理未完成。重试不会重复导入。" : "原接收副本保留，可按实际状态恢复。") {
            W2AStatus(message: job.issue ?? "记录已接收，等待导入。", tone: job.issue == nil ? .neutral : .warning)
            Text("目标资料库：\(job.receipt?.target?.path ?? "尚未绑定")\n接收位置：\(job.directory.path)")
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("重试") { model.dismissSheet { model.retryIntake(queue, job: job) } }.disabled(job.receipt == nil || job.state == "incoming")
                Button("另存接收包…") { let parent = model.sheetParent; model.dismissSheet { model.exportIntake(job, from: parent) } }.disabled(job.state == "incoming" || !FileManager.default.fileExists(atPath: job.payload.path))
                Button("改投当前资料库") { model.dismissSheet { model.retargetIntake(queue, job: job) } }.disabled(model.store == nil || job.receipt == nil || acknowledged || job.state == "incoming")
            }
            if job.state == "incoming" { Text("接收尚未完成，暂不能重试、另存或改投。请等待分享完成，或重新分享。").foregroundStyle(Color.w2aSecondary) }
            if acknowledged { Text("此任务已入库，不能改投其他资料库；重试只清理暂存。").foregroundStyle(Color.w2aSecondary) }
        } actions: {
            Button("丢弃…", role: .destructive) { let parent = model.sheetParent; model.dismissSheet { model.discardIntake(queue, job: job, from: parent) } }.disabled(!IntakeIO.validID(job.id))
            Button("在 Finder 中查看") { model.environment.revealFiles([job.directory]) }
            Spacer()
            Button("关闭") { model.dismissSheet() }.keyboardShortcut(.cancelAction)
        }
    }
}

@MainActor
extension AppModel {
    func showIntakeJobs(from parent: NSWindow? = nil) {
        guard interactionAvailable else { return }
        let snapshot = intakeSnapshot(); present(.intake(snapshot.jobs, snapshot.errors), from: parent)
    }
    func showIntakeDetail(_ queue: IntakeQueue, job: IntakeJob, from parent: NSWindow? = nil) {
        guard interactionAvailable else { return }
        present(.intakeDetail(queue, job, (try? queue.completion(job.id)) != nil), from: parent)
    }
    func retryIntake(_ queue: IntakeQueue, job: IntakeJob) {
        guard idle, job.receipt != nil, job.state != "incoming" else { return }
        run("正在恢复接收任务…", task: { try queue.retry(job.id) }, done: { _ in self.intake.attempted.remove(queue.metadata.queueID + "/" + job.id) })
    }
    func retargetIntake(_ queue: IntakeQueue, job: IntakeJob) {
        guard idle, let store, job.receipt != nil, job.state != "incoming" else { return }
        let target = IntakeTarget(libraryID: store.metadata.libraryID, path: store.root.path)
        run("正在变更接收目标…", task: { try IntakeProcessor.retarget(job.id, in: queue, to: target) }, done: { _ in self.intake.attempted.remove(queue.metadata.queueID + "/" + job.id) })
    }
}
