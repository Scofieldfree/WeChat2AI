import SwiftUI
import UniformTypeIdentifiers

final class AssignmentDraft: ObservableObject {
    let batch: LibraryBatch
    let libraryID: String
    let afterImport: Bool
    @Published var targetID: String?
    @Published var filter = ""
    init(batch: LibraryBatch, libraryID: String, afterImport: Bool) {
        self.batch = batch; self.libraryID = libraryID; self.afterImport = afterImport
    }
    var canSubmit: Bool { targetID != nil && targetID != (batch.source?.id ?? "unfiled") }
}

struct AssignmentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var draft: AssignmentDraft
    var body: some View {
        W2ASheetLayout(title: "归档到来源", subtitle: "来源是一个群聊或私聊对话。不会自动识别来源，也不合并重复导入。") {
            Text(DisplayFormat.chatRange(draft.batch.manifest)).font(W2ATheme.TypeStyle.title)
            Text("\(draft.batch.manifest.messageCount) 条消息 · \(draft.batch.manifest.linkedAttachmentCount) 个附件").foregroundStyle(Color.w2aSecondary)
            if model.contents.sources.count > 8 { TextField("筛选来源名称或备注", text: $draft.filter).textFieldStyle(.roundedBorder).accessibilityLabel("筛选归档来源") }
            Button { model.createSourceForAssignment(draft) } label: { Label("新建来源…", systemImage: "plus") }
            choice(id: "unfiled", name: "待分类", note: "保存在当前资料库，暂不归属来源", symbol: "tray")
            ForEach(model.contents.sources.filter { draft.filter.isEmpty || ($0.name + " " + $0.note).localizedCaseInsensitiveContains(draft.filter) }, id: \.id) { source in
                choice(id: source.id, name: model.sourceName(source), note: source.note, symbol: source.kind == "direct" ? "person" : "person.2")
            }
        } actions: {
            Text(draft.targetID == (draft.batch.source?.id ?? "unfiled") ? "已在此来源，选择其他来源后可归档。" : "仅改变本批归属，不改变已生成的交接副本。").font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary)
            Spacer(minLength: 0)
            Button(draft.afterImport ? "暂不归档" : "取消") { model.dismissSheet() }.keyboardShortcut(.cancelAction)
            Button { model.applyAssignment(draft) } label: {
                Text("归入 " + (model.sourceOptions.first { $0.1 == draft.targetID }?.0 ?? "所选来源"))
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 180)
            }.help(model.sourceOptions.first { $0.1 == draft.targetID }?.0 ?? "请先选择归档来源")
                .buttonStyle(W2AButtonStyle(primary: true)).disabled(!draft.canSubmit).keyboardShortcut(.defaultAction)
        }
    }
    private func choice(id: String, name: String, note: String, symbol: String) -> some View {
        Button { draft.targetID = id } label: {
            HStack(spacing: 8) {
                Image(systemName: draft.targetID == id ? "largecircle.fill.circle" : "circle").foregroundStyle(draft.targetID == id ? Color.w2aAccent : .w2aSecondary)
                Image(systemName: symbol).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) { Text(name); if !note.isEmpty { Text(note).font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary) } }
                Spacer(); Text("\(model.sourceCounts[id] ?? 0) 批").foregroundStyle(Color.w2aSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityAddTraits(draft.targetID == id ? [.isSelected] : [])
    }
}

@MainActor
extension AppModel {
    func showAssignment(_ batch: LibraryBatch, afterImport: Bool = false) {
        guard interactionAvailable, let store else { return }
        present(.assignment(AssignmentDraft(batch: batch, libraryID: store.metadata.libraryID, afterImport: afterImport)))
    }
    func applyAssignment(_ draft: AssignmentDraft) {
        guard case .assignment(let active) = sheet, active === draft, store?.metadata.libraryID == draft.libraryID,
            draft.canSubmit, let id = draft.targetID, sourceOptions.contains(where: { $0.1 == id }) else { return }
        dismissSheet { self.assign(draft.batch, to: id == "unfiled" ? nil : id) }
    }
    func createSourceForAssignment(_ draft: AssignmentDraft) {
        guard case .assignment(let active) = sheet, active === draft else { return }
        dismissSheet { self.editSource(nil) { source in
            guard self.store?.metadata.libraryID == draft.libraryID else { return }
            draft.targetID = source.id; self.present(.assignment(draft))
        } }
    }
    func didImport(_ batch: LibraryBatch) {
        if assignAfterImport { showAssignment(batch, afterImport: true) }
        else { setStatus("已保存到待分类 · 可直接交接，或先归档到来源。", tone: .success) }
    }
    func dragToken(_ batch: LibraryBatch) -> String {
        "w2a-batch/v1|\(store?.metadata.libraryID ?? "")|\(batch.id)"
    }
    func assignDropped(_ token: String, to sourceID: String) -> Bool {
        let parts = token.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard canPerform("newSource"), parts.count == 3, parts[0] == "w2a-batch/v1", parts[1] == store?.metadata.libraryID,
            sourceID == "unfiled" || contents.sources.contains(where: { $0.id == sourceID }),
            let batch = contents.batches.first(where: { $0.id == parts[2] }),
            (batch.source?.id ?? "unfiled") != sourceID else { return false }
        assign(batch, to: sourceID == "unfiled" ? nil : sourceID)
        return true
    }
}
