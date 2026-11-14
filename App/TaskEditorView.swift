import SwiftUI

final class TaskEditorDraft: ObservableObject {
    let seed: AnalysisTask
    let previousKey: String
    let sourceKey: String?
    @Published var title: String
    @Published var instruction: String
    @Published var saveTemplate: Bool
    @Published var makeDefault: Bool
    let wasDefault: Bool
    var clearDefault: Bool { wasDefault && !makeDefault }
    let managementOnly: Bool
    let sourceName: String?
    @Published var error: String?
    init(seed: AnalysisTask, key: String, sourceKey: String?, isDefault: Bool, managementOnly: Bool = false, sourceName: String? = nil) {
        wasDefault = isDefault; self.managementOnly = managementOnly; self.sourceName = sourceName
        self.seed = seed; previousKey = key; self.sourceKey = sourceKey
        title = seed.title; instruction = seed.instruction; saveTemplate = key.hasPrefix("template:"); makeDefault = isDefault
    }
}

struct TaskEditorView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var draft: TaskEditorDraft
    let continuation: (() -> Void)?
    @FocusState private var titleFocused: Bool
    @FocusState private var instructionFocused: Bool
    var body: some View {
        W2ASheetLayout(title: "编辑任务要求", subtitle: "编辑本次要求，或保存模板。发送前仍可在目标 Agent 编辑。") {
            Text("任务名称 · \(draft.title.count) / 80").font(W2ATheme.TypeStyle.section)
            TextField("任务名称", text: $draft.title).textFieldStyle(.plain)
                .padding(W2ATheme.Space.sm).background(Color.w2aCanvas, in: RoundedRectangle(cornerRadius: W2ATheme.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: W2ATheme.Radius.control).strokeBorder(Color.w2aBorder))
                .overlay { if titleFocused { RoundedRectangle(cornerRadius: W2ATheme.Radius.control + 2).stroke(Color.w2aAccent, lineWidth: 2).padding(-4) } }
                .accessibilityLabel("任务名称").focused($titleFocused)
            Text("分析要求 · \(draft.instruction.count) / 4,000").font(W2ATheme.TypeStyle.section)
            TextEditor(text: $draft.instruction).font(W2ATheme.TypeStyle.body)
                .scrollContentBackground(.hidden).padding(W2ATheme.Space.sm)
                .background(Color.w2aCanvas, in: RoundedRectangle(cornerRadius: W2ATheme.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: W2ATheme.Radius.control).strokeBorder(Color.w2aBorder))
                .overlay { if instructionFocused { RoundedRectangle(cornerRadius: W2ATheme.Radius.control + 2).stroke(Color.w2aAccent, lineWidth: 2).padding(-4) } }
                .frame(minHeight: 170).accessibilityLabel("分析要求").focused($instructionFocused)
            Toggle("保存为个人模板（已选模板将更新）", isOn: $draft.saveTemplate).disabled(draft.managementOnly)
            if !draft.managementOnly {
                Toggle("设为“\(draft.sourceName ?? "此来源")”的默认任务", isOn: $draft.makeDefault).disabled(draft.sourceKey == nil)
                if let key = draft.sourceKey, let value = model.taskSettings.sourceDefaults[key] {
                    Text("当前默认：" + ((try? model.taskSettings.resolve(value).title) ?? "不可用") + (draft.wasDefault ? "；关闭开关将清除默认关联。" : ""))
                        .foregroundStyle(Color.w2aSecondary)
                }
                if draft.sourceKey == nil { Text("先选择已归档来源，才能设置来源默认任务。").foregroundStyle(Color.w2aSecondary) }
            }
        } actions: {
            if let error = draft.error { W2AStatus(message: error, tone: .error).lineLimit(3) }
            Spacer(minLength: 0)
            Button("取消") { model.cancelTaskEditor(draft) }.keyboardShortcut(.cancelAction)
            Button(draft.managementOnly ? "保存模板" : draft.saveTemplate ? "保存模板并应用" : "应用到本次") { model.applyTaskEditor(draft, continuation: continuation) }
                .buttonStyle(W2AButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
        }.onAppear { titleFocused = true }
    }
}

@MainActor
extension AppModel {
    func editTemplate(_ template: TaskTemplate) {
        guard interactionAvailable, taskSettingsError == nil else { return }
        let draft = TaskEditorDraft(seed: AnalysisTask(action: template.action, title: template.title, instruction: template.instruction),
            key: "template:" + template.id, sourceKey: nil, isDefault: false, managementOnly: true)
        present(.task(draft, nil), from: settingsWindow)
    }
    func editTask() { showTaskEditor() }
    func showTaskEditor(then: (() -> Void)? = nil) {
        guard !busy, !showingSheet else { return }
        let seed = (try? currentTask()) ?? AnalysisTask(action: .custom, title: "我的分析任务", instruction: "")
        let draft = TaskEditorDraft(seed: seed, key: selectedTaskKey, sourceKey: currentTaskSourceKey,
            isDefault: currentTaskSourceKey.flatMap { taskSettings.sourceDefaults[$0] } == selectedTaskKey, sourceName: currentSource.map(sourceName))
        present(.task(draft, then))
    }
    func cancelTaskEditor(_ draft: TaskEditorDraft) {
        if !draft.managementOnly, draft.previousKey == TaskSettings.builtinKey(.custom), draftTask == nil { selectTask(key: TaskSettings.builtinKey(.summary)) }
        dismissSheet()
    }
    func applyTaskEditor(_ draft: TaskEditorDraft, continuation: (() -> Void)? = nil) {
        guard case .task(let active, _) = sheet, active === draft, showingSheet, !busy else { return }
        do {
            let unchanged = draft.title == draft.seed.title && draft.instruction == draft.seed.instruction
            let useBuiltin = draft.previousKey.hasPrefix("builtin:") && draft.previousKey != TaskSettings.builtinKey(.custom) && unchanged && !draft.saveTemplate
            let task = useBuiltin ? draft.seed : AnalysisTask(action: draft.seed.action == .raw ? .custom : draft.seed.action,
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines), instruction: draft.instruction.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !task.title.isEmpty, task.title.count <= 80, !task.title.contains(where: { $0.isNewline }) else { throw CoreError.invalid("任务名称须为 1–80 字，且不能换行。") }
            guard task.instruction.count <= 4000, task.action == .raw || !task.instruction.isEmpty else { throw CoreError.invalid("分析要求须为 1–4,000 字。") }
            try task.validate()
            var settings = taskSettings, key = draft.previousKey
            let shouldSave = draft.managementOnly || draft.saveTemplate || (draft.makeDefault && !useBuiltin)
            if shouldSave {
                let id = draft.previousKey.hasPrefix("template:") ? String(draft.previousKey.dropFirst(9)) : UUID().uuidString.lowercased()
                let template = TaskTemplate(id: id, title: task.title, instruction: task.instruction, action: task.action)
                if let i = settings.templates.firstIndex(where: { $0.id == id }) { settings.templates[i] = template } else { settings.templates.append(template) }
                key = "template:" + id
            } else if !useBuiltin { key = TaskSettings.builtinKey(.custom) }
            if let sourceKey = draft.sourceKey {
                if draft.makeDefault { settings.sourceDefaults[sourceKey] = key }
                if draft.clearDefault { settings.sourceDefaults.removeValue(forKey: sourceKey) }
            }
            let persist = shouldSave || draft.makeDefault || draft.clearDefault
            if persist, let error = taskSettingsError { throw CoreError.invalid("原任务设置无法读取，未覆盖：" + error) }
            try settings.validate()
            let updated = settings, selectedKey = key, path = environment.taskSettingsURL
            dismissSheet {
                self.run("正在应用任务…", task: { if persist { try updated.save(at: path) } }, done: { _ in
                    self.taskSettings = updated
                    if !draft.managementOnly {
                        if selectedKey == TaskSettings.builtinKey(.custom) { self.draftTask = task }
                        self.selectTask(key: selectedKey)
                    }
                    self.setStatus("任务已应用。发送前可继续编辑。", tone: .success)
                    continuation?()
                })
            }
        } catch { draft.error = error.localizedDescription }
    }
}
