import SwiftUI

struct BatchListView: View {
    @ObservedObject var model: AppModel
    @StateObject private var keyboard = ListKeyboardTarget()
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(model.sourceTitle).font(W2ATheme.TypeStyle.title).lineLimit(2).help(model.sourceTitle)
                Spacer(minLength: 8)
                Text("\(model.batches.count) 批").font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            W2ADivider()
            if model.batches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.busy ? "正在加载批次…" : "此来源暂无批次")
                    Text("导入后可从详情头归档到来源。").font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary)
                }.padding(16)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(model.batches, id: \.id) { batch in
                                Button { keyboard.focus(); model.selectBatch(batch.id) } label: {
                                    BatchCard(batch: batch, selected: model.selectedBatchID == batch.id, focused: keyboard.hasFocus && model.selectedBatchID == batch.id)
                                }.buttonStyle(.plain).id(batch.id)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(DisplayFormat.chatRange(batch.manifest) + "，\(batch.manifest.messageCount) 条消息，\(batch.manifest.linkedAttachmentCount) 个附件，批次 " + batch.id.prefix(8))
                                    .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(model.selectedBatchID == batch.id ? [.isSelected] : [])
                                    .contextMenu {
                                        Button(batch.source == nil ? "归档到来源…" : "改归…") { model.showAssignment(batch) }
                                        Button("本批资料与提醒…") { model.showBatchInfo(batch) }
                                        Button("在 Finder 中显示") { model.revealDataLocation(batch.workspace) }
                                        Button("复制批次 ID") { model.copyBatchID(batch) }
                                    }
                                    .onDrag { NSItemProvider(object: model.dragToken(batch) as NSString) }
                            }
                        }.padding(8)
                    }.onChange(of: model.selectedBatchID) { id in if let id { proxy.scrollTo(id, anchor: .center) } }
                }.disabled(!model.interactionAvailable)
                    .accessibilityLabel("导入批次列表，使用方向键选择")
            }
        }.font(W2ATheme.TypeStyle.section).background(Color.w2aSurface)
            .background(ListKeyboardAnchor(target: keyboard, move: move).frame(width: 0, height: 0))
    }
    private func move(_ direction: MoveCommandDirection) {
        guard model.interactionAvailable, direction == .up || direction == .down, !model.batches.isEmpty else { return }
        let current = model.batches.firstIndex { $0.id == model.selectedBatchID } ?? 0
        let index = max(0, min(model.batches.count - 1, current + (direction == .down ? 1 : -1)))
        model.selectBatch(model.batches[index].id)
    }
}

private struct BatchCard: View {
    let batch: LibraryBatch
    let selected: Bool
    let focused: Bool
    @State private var hovered = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(DisplayFormat.chatRange(batch.manifest)).font(W2ATheme.TypeStyle.section).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if !batch.manifest.warnings.isEmpty { Image(systemName: "exclamationmark.triangle").accessibilityLabel("含解析提醒").foregroundStyle(Color.w2aSecondary) }
            }
            Text("\(batch.manifest.messageCount) 条 · \(batch.manifest.linkedAttachmentCount) 个附件 · 导入 \(DisplayFormat.imported(batch.manifest.importedAt))")
                .font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary).lineLimit(1).truncationMode(.tail)
        }.foregroundStyle(Color.w2aText).padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading).frame(height: 56)
            .background(selected ? Color(nsColor: W2ATheme.Colors.selected) : hovered ? Color(nsColor: W2ATheme.Colors.hover) : Color.w2aSurface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.w2aAccent : .w2aBorder, lineWidth: selected ? 1.5 : 1))
            .overlay(alignment: .leading) { if selected { RoundedRectangle(cornerRadius: 2).fill(Color.w2aAccent).frame(width: 3).padding(.vertical, 8) } }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? Color.w2aAccent : .clear, lineWidth: 2).padding(-2))
            .onHover { hovered = $0 }.help("导入 \(DisplayFormat.full.string(from: DisplayFormat.iso.date(from: batch.manifest.importedAt) ?? .distantPast))\n批次 ID：\(batch.id)\n\(batch.workspace.path)")
    }
}
