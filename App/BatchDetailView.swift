import SwiftUI

struct BatchDetailView: View {
    @ObservedObject var model: AppModel
    let availableWidth: CGFloat
    private var effectiveMode: TranscriptMode { model.transcriptMode == .reading && model.readingDocument != nil ? .reading : .source }
    var body: some View {
        VStack(spacing: 0) {
            if model.libraryUnavailable {
                W2AEmptyState(symbol: "externaldrive.badge.exclamationmark", title: "资料库暂不可用", message: "请确认保存路径和磁盘连接。原资料不会自动搬迁，完整原因可在底部详情中查看。") {
                    HStack { Button("重新读取") { model.refresh() }; Button("打开资料库…") { model.openLibrary() } }.disabled(!model.interactionAvailable)
                }
            } else if let batch = model.selected {
                header(batch)
                W2ADivider()
                if !model.previewLoading, model.transcriptMode == .reading, let fallback = model.readingFallback {
                    Text(fallback).font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary).lineLimit(1).help(fallback).padding(.horizontal, 16).frame(height: 24)
                } else if effectiveMode == .reading && model.readingDocument?.hasUnparsedText == true {
                    HStack { Label("含未解析原文，请核对。", systemImage: "exclamationmark.triangle"); Button("切到原文") { model.chooseTranscriptMode(.source) }; Spacer() }
                        .font(W2ATheme.TypeStyle.metadata).padding(.horizontal, 16).frame(height: 28)
                }
                ZStack {
                    TranscriptTextView(text: model.transcript, batchID: batch.id,
                        reading: effectiveMode == .reading ? model.readingDocument : nil, attachmentRoot: batch.workspace, loadID: model.previewRequest,
                        onAttachment: { path in model.revealAttachment(path, batchID: batch.id) })
                        .opacity(model.previewError != nil || model.transcript.isEmpty ? 0 : 1)
                        .accessibilityHidden(model.previewLoading || model.previewError != nil)
                    if model.previewIndicatorVisible { ProgressView("正在读取正文…").padding(16).background(Color.w2aCanvas) }
                    else if let error = model.previewError {
                        W2AEmptyState(symbol: "doc.badge.ellipsis", title: "正文读取失败", message: error) {
                            HStack { Button("重新读取") { model.selectBatch(batch.id) }; Button("在 Finder 中显示") { model.reveal() } }.disabled(!model.interactionAvailable)
                        }
                    } else if !model.previewLoading && model.transcript.isEmpty {
                        W2AEmptyState(symbol: "doc.text", title: "没有可预览的正文", message: "原始文件和附件仍可在本批目录查看。") { Button("在 Finder 中显示") { model.reveal() } }
                    }
                }.frame(width: availableWidth).frame(maxHeight: .infinity)
                W2ADivider()
                HandoffDockView(model: model, availableWidth: availableWidth)
            } else if model.busy {
                ProgressView("正在打开资料库…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { empty }
        }.frame(width: availableWidth).frame(maxHeight: .infinity).background(Color.w2aCanvas)
    }
    private func header(_ batch: LibraryBatch) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(DisplayFormat.chatRange(batch.manifest)).font(W2ATheme.TypeStyle.title).lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).help("聊天时间为导出文件中的本地时间，未提供时区。")
                Picker("正文视图", selection: Binding(get: { effectiveMode }, set: { model.chooseTranscriptMode($0) })) {
                    Text("阅读").tag(TranscriptMode.reading).disabled(model.readingDocument == nil)
                    Text("原文").tag(TranscriptMode.source)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 96).disabled(!model.interactionAvailable || model.previewLoading)
                Button(model.assignmentTitle) { model.assignSelected() }.disabled(!model.canPerform("assign"))
                Menu {
                    Button("本批资料与提醒…") { model.showBatchInfo() }
                    Button("在 Finder 中显示") { model.reveal() }
                    Button("查看项目目录") { model.revealProject() }.disabled(!model.canPerform("project"))
                    Button("分享原件…") { model.shareOriginal() }
                    Button("复制批次 ID") { model.copyBatchID(batch) }
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(!model.interactionAvailable).accessibilityLabel("本批资料与操作")
            }.frame(height: 28)
            HStack(spacing: 6) {
                Text("\(batch.manifest.messageCount) 条消息 · \(batch.manifest.participants.count) 位发言人 · \(batch.manifest.linkedAttachmentCount) 个附件 · 导入 \(DisplayFormat.imported(batch.manifest.importedAt)) · ID \(batch.id.prefix(8))")
                    .lineLimit(1).truncationMode(.middle)
                if !batch.manifest.warnings.isEmpty {
                    Button { model.showBatchInfo() } label: { Label("\(batch.manifest.warnings.count) 项提醒", systemImage: "exclamationmark.triangle") }.buttonStyle(W2ALinkButtonStyle())
                }
            }.font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary).frame(height: 18)
        }.padding(.horizontal, 16).frame(width: availableWidth, height: W2ATheme.Layout.detailHeader)
            .buttonStyle(W2AButtonStyle(compact: true))
    }
    private var empty: some View {
        let first = model.contents.batches.isEmpty
        return W2AEmptyState(symbol: "tray.and.arrow.down", title: first ? "从一份聊天记录开始" : "此来源暂无导入批次",
            message: first ? "1. 在微信多选消息并合并转发\n2. 选择“转发到其他应用 → WeChat2AI”\n3. 首次连接接收目录，记录会先保存在待分类" : "导入记录后，从详情头归档到此来源。") {
            VStack(spacing: 8) {
                Button("导入聊天记录") { model.chooseImport() }.buttonStyle(W2AButtonStyle(primary: true)).disabled(!model.canPerform("import"))
                if first {
                    Button("连接接收目录…") { model.connectIntakeDirectory() }.disabled(!model.interactionAvailable)
                    Button("分享菜单里找不到 WeChat2AI？") { model.showUsageHelp() }.buttonStyle(W2ALinkButtonStyle())
                }
            }
        }
    }
}
