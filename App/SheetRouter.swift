import SwiftUI

enum AppSheet {
    case task(TaskEditorDraft, (() -> Void)?)
    case context(AnalysisContextDraft)
    case intake([(IntakeQueue, IntakeJob)], [String])
    case intakeDetail(IntakeQueue, IntakeJob, Bool)
    case assignment(AssignmentDraft)
    case status
    case info(String, String)
    case handoff
}

struct AppSheetView: View {
    @ObservedObject var model: AppModel
    let route: AppSheet
    @ViewBuilder var body: some View {
        switch route {
        case .task(let draft, let continuation): TaskEditorView(model: model, draft: draft, continuation: continuation)
        case .context(let draft): AnalysisContextView(model: model, draft: draft)
        case .intake(let jobs, let errors): IntakeStatusView(model: model, jobs: jobs, errors: errors)
        case .intakeDetail(let queue, let job, let acknowledged): IntakeDetailView(model: model, queue: queue, job: job, acknowledged: acknowledged)
        case .assignment(let draft): AssignmentView(model: model, draft: draft)
        case .status: information(title: "完整状态信息", message: model.statusMessage)
        case .info(let title, let message): information(title: title, message: message)
        case .handoff:
            if let record = model.lastDelivery {
                W2ASheetLayout(title: record.stage, subtitle: "交接只准备资料并请求打开客户端。请在目标应用检查并自行发送。") {
                    Text(record.details).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                } actions: {
                    if let workspace = record.workspace {
                        Button("查看副本") { model.environment.revealFiles([workspace]) }
                        Button("复制此副本任务") { model.copyLastDelivery() }
                    }
                    Spacer()
                    Button("关闭") { model.dismissSheet() }.keyboardShortcut(.cancelAction)
                }
            }
        }
    }
    private func information(title: String, message: String) -> some View {
        W2ASheetLayout(title: title, subtitle: "") {
            Text(message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            Button("复制信息") { model.environment.copyText(message) }
            Spacer()
            Button("关闭") { model.dismissSheet() }.keyboardShortcut(.cancelAction)
        }
    }
}

@MainActor
extension AppModel {
    func present(_ route: AppSheet, from parent: NSWindow? = nil) {
        guard !busy, !showingSheet else { return }
        sheet = route; showingSheet = true
        guard let window = parent ?? window else { return } // Headless behavior tests exercise the same route.
        sheetParent = window
        sheetReturnResponder = window.firstResponder
        let ideal: NSSize
        switch route {
        case .task: ideal = NSSize(width: 620, height: 570)
        case .context: ideal = NSSize(width: 660, height: 540)
        case .intake: ideal = NSSize(width: 620, height: 480)
        case .assignment: ideal = NSSize(width: 640, height: 510)
        case .intakeDetail: ideal = NSSize(width: 660, height: 420)
        default: ideal = NSSize(width: 660, height: 460)
        }
        let available = window.contentLayoutRect.size
        let size = NSSize(width: min(ideal.width, available.width - 48), height: min(ideal.height, available.height - 48))
        let host = NSHostingController(rootView: AppSheetView(model: self, route: route).frame(width: size.width, height: size.height))
        let panel = NSWindow(contentViewController: host)
        panel.styleMask = [.titled]; panel.title = "WeChat2AI"; panel.isReleasedWhenClosed = false
        panel.appearance = window.appearance
        panel.setContentSize(size)
        window.beginSheet(panel)
    }
    func dismissSheet(then: (() -> Void)? = nil) {
        guard sheet != nil else { return }
        if let parent = sheetParent ?? window, let panel = parent.attachedSheet {
            parent.endSheet(panel); panel.orderOut(nil)
            if let responder = sheetReturnResponder { parent.makeFirstResponder(responder) }
        }
        sheetReturnResponder = nil; sheetParent = nil; sheet = nil; showingSheet = false
        if then == nil, statusTone == .working { setStatus("已取消准备，原资料未改动。") }
        then?()
        drainQueue()
    }
    func showStatus() { guard interactionAvailable else { return }; present(.status) }
    func showLibraryInfo() { guard interactionAvailable else { return }; present(.info("当前资料库", libraryPath + warningText)) }
    func showBatchInfo(_ provided: LibraryBatch? = nil) {
        guard interactionAvailable, let batch = provided ?? selected else { return }
        let m = batch.manifest
        let details = (batch.source?.label ?? "待分类") + "\n" + DisplayFormat.chatRange(m) + "（导出本地时间，未提供时区）\n\(m.messageCount) 条消息 · \(m.participants.count) 位发言人 · \(m.linkedAttachmentCount) 个附件\n导入 " + formatImport(m.importedAt)
        present(.info("本批资料与提醒", details + "\n批次 ID：" + batch.id + "\n资料目录：" + batch.workspace.path + "\n\n" + (batch.manifest.warnings.isEmpty ? "没有解析提醒。" : batch.manifest.warnings.joined(separator: "\n"))))
    }
    func showUsageHelp() {
        guard interactionAvailable else { return }
        present(.info("使用步骤", "在微信多选消息 → 合并转发 → 转发到其他应用 → WeChat2AI。\n\n首次分享时选择接收目录，然后在主 App 连接该目录。若分享菜单中找不到 WeChat2AI，请在 macOS 系统分享菜单的“编辑扩展”中启用。也可直接导入微信导出的 ZIP、文件夹、TXT 或 .w2adrop。\n\n来源是用户指定的群聊或私聊对话，不会自动识别；交接只准备副本并请求打开客户端，请自行检查并发送。"))
    }
    func showPrivacyInfo() {
        guard interactionAvailable else { return }
        present(.info("隐私与本地数据", "资料保存在本机普通文件中，没有应用层加密。应用不读取微信私有数据库，不调用云端 AI API，不自动发送任务。\n\n交给 Agent 后的读取与处理取决于目标客户端及其权限。卸载不会删除资料库、接收目录、项目或交接副本。设置中的“移除连接”仅移除主 App 登记，不删除文件，也不撤销分享扩展保存的授权。"))
    }
    func showHandoff() { guard interactionAvailable, let record = activeDelivery else { return }; lastDelivery = record; present(.handoff) }
}
