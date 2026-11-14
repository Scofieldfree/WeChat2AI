import SwiftUI

final class AnalysisContextDraft: ObservableObject {
    let batchID: String
    let task: AnalysisTask
    let delivery: TaskDelivery
    let candidates: [LibraryBatch]
    let files: [URL]
    @Published var historyIDs = Set<String>()
    @Published var resultFiles = Set<URL>()
    @Published var error: String?
    init(batchID: String, task: AnalysisTask, delivery: TaskDelivery, candidates: [LibraryBatch], files: [URL]) {
        self.batchID = batchID; self.task = task; self.delivery = delivery; self.candidates = candidates; self.files = files
    }
    func validate() throws {
        guard historyIDs.isSubset(of: Set(candidates.map(\.id))), resultFiles.isSubset(of: Set(files)),
            historyIDs.count + resultFiles.count <= 20, task.action != .compare || !historyIDs.isEmpty else {
            throw CoreError.invalid("对比至少勾选一批同群历史资料；参考资料合计最多 20 项。")
        }
    }
}

struct AnalysisContextView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var draft: AnalysisContextDraft
    var body: some View {
        W2ASheetLayout(title: draft.task.title + "：选择参考资料", subtitle: "仅使用勾选资料，合计最多 20 项。导入先后不等于聊天先后。更新结论只输出建议，写文件前需在 Agent 确认。") {
            Text("主批次 · " + String(draft.batchID.prefix(8))).font(W2ATheme.TypeStyle.metadata)
            Text("同群其他批次（默认不选）").font(W2ATheme.TypeStyle.section)
            if draft.candidates.isEmpty { Text("没有其他同群批次。").foregroundStyle(Color.w2aSecondary) }
            ForEach(draft.candidates, id: \.id) { batch in
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(DisplayFormat.chatRange(batch.manifest),
                        isOn: Binding(get: { draft.historyIDs.contains(batch.id) }, set: { if $0 { draft.historyIDs.insert(batch.id) } else { draft.historyIDs.remove(batch.id) } }))
                        .toggleStyle(.checkbox).fixedSize(horizontal: false, vertical: true)
                    Text("导入 \(DisplayFormat.imported(batch.manifest.importedAt)) · \(batch.manifest.messageCount) 条 · ID \(batch.id.prefix(8))")
                        .font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary)
                }
            }
            if draft.task.action == .conclusions {
                W2ADivider()
                Text("群项目 results 中的 Markdown / TXT 成果").font(W2ATheme.TypeStyle.section)
                if draft.files.isEmpty { Text("暂无成果，可先形成结论初稿。").foregroundStyle(Color.w2aSecondary) }
                ForEach(draft.files, id: \.self) { file in
                    Toggle(file.lastPathComponent, isOn: Binding(get: { draft.resultFiles.contains(file) }, set: { if $0 { draft.resultFiles.insert(file) } else { draft.resultFiles.remove(file) } }))
                        .toggleStyle(.checkbox).fixedSize(horizontal: false, vertical: true).help(file.path)
                }
            }
        } actions: {
            if let error = draft.error { W2AStatus(message: error, tone: .error).lineLimit(3) }
            else { Text("已选 \(draft.historyIDs.count + draft.resultFiles.count) / 20 项").foregroundStyle(Color.w2aSecondary).font(W2ATheme.TypeStyle.metadata) }
            Spacer(minLength: 0)
            Button("取消") { model.dismissSheet() }.keyboardShortcut(.cancelAction)
            Button(draft.delivery.agent.map { "准备并打开 " + $0.title } ?? "准备并复制任务") { model.deliverContext(draft) }
                .buttonStyle(W2AButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
        }
    }
}

@MainActor
extension AppModel {
    func chooseAnalysisContext(_ task: AnalysisTask, delivery: TaskDelivery) {
        guard idle, let batch = selected, let source = batch.source, let store else {
            setStatus("此任务需要明确群归属，请先将本批资料归入一个群/对话。", tone: .warning); return
        }
        let candidates = contents.batches.filter { $0.source?.id == source.id && $0.id != batch.id }
        if task.action == .compare && candidates.isEmpty {
            setStatus("此群还没有其他批次。请先导入并归入同群，再选择对比资料。", tone: .warning); drainQueue(); return
        }
        run("正在检查可选参考资料…", task: {
            var files: [URL] = []
            if task.action == .conclusions, let project = try ManagedProjects.existing(libraryID: store.metadata.libraryID, sourceID: source.id, at: self.environment.projectsRoot) {
                files = try FileManager.default.contentsOfDirectory(at: project.appendingPathComponent("results"), includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
                    .filter { ["md", "txt"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                for file in files { try LibraryIO.regular(file) }
            }
            return files
        }, done: { files in
            self.present(.context(AnalysisContextDraft(batchID: batch.id, task: task, delivery: delivery, candidates: candidates, files: files)))
        })
    }
    func deliverContext(_ draft: AnalysisContextDraft) {
        guard case .context(let active) = sheet, active === draft, selected?.id == draft.batchID else { return }
        do {
            try draft.validate()
            let ids = draft.candidates.filter { draft.historyIDs.contains($0.id) }.map(\.id)
            let files = draft.files.filter { draft.resultFiles.contains($0) }
            dismissSheet { self.performTaskDelivery(draft.task, historyIDs: ids, resultFiles: files, delivery: draft.delivery) }
        } catch { draft.error = error.localizedDescription }
    }
}
