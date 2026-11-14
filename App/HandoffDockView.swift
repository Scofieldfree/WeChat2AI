import SwiftUI

struct HandoffDockView: View {
    @ObservedObject var model: AppModel
    let availableWidth: CGFloat
    private var needsContext: Bool { (try? model.currentTask().needsContext) == true }
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("任务").foregroundStyle(Color.w2aSecondary)
                TaskMenuView(model: model)
                Button { model.editTask() } label: { Image(systemName: "square.and.pencil").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).accessibilityLabel("编辑任务要求…").disabled(!model.interactionAvailable)
                Spacer(minLength: 8)
                Text("Agent").foregroundStyle(Color.w2aSecondary)
                if availableWidth >= 700 { agentSegments }
                else {
                    Picker("Agent", selection: Binding(get: { model.selectedAgent }, set: { model.chooseAgent($0) })) {
                        ForEach(AgentTarget.pickerTargets, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().pickerStyle(.menu).fixedSize().disabled(!model.interactionAvailable)
                }
            }.frame(height: 28)
            HStack(spacing: 8) {
                feedback
                Spacer(minLength: 8)
                Button("复制给 AI") { model.copyContext() }.disabled(!model.canPerform("copy"))
                Button { model.openInAgent() } label: { Text(model.deliveryButtonTitle).frame(minWidth: 132) }
                    .buttonStyle(W2AButtonStyle(primary: true)).disabled(!model.canPerform("agent"))
            }.frame(height: 32)
        }.font(W2ATheme.TypeStyle.section).padding(.horizontal, 16).padding(.vertical, 12)
            .frame(width: availableWidth, height: W2ATheme.Layout.dock).background(Color.w2aSurface)
            .buttonStyle(W2AButtonStyle(compact: true))
    }
    private var agentSegments: some View {
        Picker("Agent", selection: Binding(get: { model.selectedAgent }, set: { model.chooseAgent($0) })) {
            ForEach(AgentTarget.pickerTargets, id: \.self) { Text($0.title).tag($0) }
        }.labelsHidden().pickerStyle(.segmented).frame(width: 286).disabled(!model.interactionAvailable)
    }
    @ViewBuilder private var feedback: some View {
        if let reason = disabledReason {
            Text(reason).font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary).lineLimit(1).truncationMode(.tail).help(reason)
        } else if let record = model.activeDelivery {
            Button { model.showHandoff() } label: {
                Label(record.stage + " · " + record.task.title + " · " + DisplayFormat.clock.string(from: record.completedAt) + " · 详情",
                    systemImage: record.issue == nil ? "checkmark.circle" : "exclamationmark.triangle")
                    .lineLimit(1).truncationMode(.tail)
            }.buttonStyle(W2ALinkButtonStyle()).disabled(!model.interactionAvailable)
                .accessibilityLabel("本批最近一次交接：" + record.stage + "，查看详情")
        } else if model.agentAvailability[model.selectedAgent] == false {
            Text("未找到 \(model.selectedAgent.title) 桌面端，可使用“复制给 AI”。")
                .font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary).lineLimit(1).truncationMode(.tail)
        } else {
            Text(needsContext ? "交接前选择同群参考（最多 20 项）" : "本批 \(model.selected?.manifest.messageCount ?? 0) 条与 \(model.selected?.manifest.linkedAttachmentCount ?? 0) 个附件 · 在目标应用确认并发送")
                .font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary).lineLimit(1).truncationMode(.tail)
        }
    }
    private var disabledReason: String? {
        if model.busy { return model.deliveryPreparing ? "正在准备副本并请求打开，请稍候。" : model.statusMessage }
        if model.previewLoading { return "正在读取正文，完成后可交接或复制。" }
        if model.previewError != nil { return "正文读取失败，请先重新读取。" }
        return nil
    }
}

struct TaskMenuView: View {
    @ObservedObject var model: AppModel
    private let groups: [(String, [ChatAction])] = [
        ("常用", [.summary, .todos, .links, .resources]),
        ("深度分析", [.opportunities, .knowledge, .viewpoints, .requirements]),
        ("需要历史参考", [.compare, .conclusions]), ("其他", [.raw, .custom])]
    private var title: String { ((try? model.currentTask().title) ?? "自定义任务…") + (model.isSourceDefaultTask ? " · 默认" : "") }
    private var width: CGFloat { min(188, (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width + 28) }
    var body: some View {
        Menu {
            Picker("本次任务", selection: Binding(get: { model.selectedTaskKey }, set: { model.chooseTask($0) })) {
                ForEach(groups, id: \.0) { title, actions in
                    Section(title) {
                        ForEach(actions, id: \.rawValue) { Text($0.title).tag(TaskSettings.builtinKey($0)) }
                    }
                }
                if !model.taskSettings.templates.isEmpty {
                    Section("我的模板") {
                        ForEach(model.taskSettings.templates, id: \.id) { Text($0.title).tag("template:" + $0.id) }
                    }
                }
            }.pickerStyle(.inline).labelsHidden()
            Divider()
            Button("编辑任务要求…") { model.editTask() }
            Button("管理模板…") { model.showSettings(tab: 3) }
        } label: {
            Text(title)
                .lineLimit(1).truncationMode(.tail)
        }.fixedSize().frame(width: width, alignment: .leading).disabled(!model.interactionAvailable)
            .accessibilityLabel("选择本次任务")
    }
}
