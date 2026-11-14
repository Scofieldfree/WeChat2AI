import SwiftUI

struct IntakeConnectionState: Identifiable {
    let registration: IntakeRegistration
    let pendingCount: Int?
    let issue: String?
    var id: String { registration.id }
    static func load(_ registry: IntakeRegistry) throws -> [Self] {
        try registry.registrations.map { registration in
            do {
                let queue = try IntakeQueue(at: URL(fileURLWithPath: registration.path))
                guard queue.metadata.queueID == registration.queueID else { throw CoreError.invalid("接收目录身份发生变化。") }
                return Self(registration: registration, pendingCount: try queue.jobs().count, issue: nil)
            } catch { return Self(registration: registration, pendingCount: nil, issue: error.localizedDescription) }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TabView(selection: $model.settingsTab) {
                general.tabItem { Label("通用", systemImage: "gearshape") }.tag(0)
                data.tabItem { Label("资料库与数据", systemImage: "externaldrive") }.tag(1)
                intake.tabItem { Label("接收", systemImage: "tray.and.arrow.down") }.tag(2)
                tasks.tabItem { Label("任务与 Agent", systemImage: "text.badge.checkmark") }.tag(3)
            }
            if !model.interactionAvailable { Text("主窗口有面板或正在处理，请完成后再修改设置。").font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary) }
            if let error = model.settingsError ?? (model.statusTone == .error ? model.statusMessage : nil) { W2AStatus(message: error, tone: .error) }
        }.padding(16).font(W2ATheme.TypeStyle.section).foregroundStyle(Color.w2aText)
            .background(Color.w2aSurface).tint(Color.w2aAccent).accentColor(Color.w2aAccent)
            .buttonStyle(W2AButtonStyle(compact: true)).frame(width: 560, height: 570)
    }
    private var general: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("导入后").font(W2ATheme.TypeStyle.title)
            Picker("归档方式", selection: Binding(get: { model.assignAfterImport }, set: { model.chooseAssignAfterImport($0) })) {
                Text("每次询问归属").tag(true); Text("先放入待分类").tag(false)
            }.pickerStyle(.radioGroup)
            Text("先放入待分类时，可稍后从详情头或批次菜单归档；不会自动识别来源。").foregroundStyle(Color.w2aSecondary)
            W2ADivider()
            Picker("正文默认视图", selection: Binding(get: { model.transcriptMode }, set: { model.chooseTranscriptMode($0) })) {
                ForEach(TranscriptMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.radioGroup)
            Text("阅读视图只改变排版。“复制给 AI”和交接副本继续使用原文。外观跟随 macOS。").foregroundStyle(Color.w2aSecondary)
            Spacer()
        }.padding(20).disabled(!model.interactionAvailable)
    }
    private var data: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.libraryDisplayName).font(W2ATheme.TypeStyle.title)
                Text("资料库 ID：" + (model.store?.metadata.libraryID ?? "不可用")).textSelection(.enabled)
                Text("\(model.contents.sources.count) 个来源 · \(model.contents.batches.count) 个批次").foregroundStyle(Color.w2aSecondary)
                HStack {
                    Button("打开其他资料库…") { model.chooseLibrary(create: false, from: model.settingsWindow) }
                    Button("新建资料库…") { model.chooseLibrary(create: true, from: model.settingsWindow) }
                }
                W2ADivider()
                location("当前资料库", URL(fileURLWithPath: model.libraryPath))
                location("群项目", model.environment.projectsRoot)
                location("未归群交接副本", model.environment.handoffRoot)
                location("任务设置文件", model.environment.taskSettingsURL)
                Text("数据以普通文件保存，没有应用层加密。卸载不会删除这些位置；清理前请自行确认每份副本。此处不提供删除资料操作。").foregroundStyle(Color.w2aSecondary)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.disabled(!model.interactionAvailable)
    }
    private func location(_ title: String, _ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Button("在 Finder 中显示") { model.revealDataLocation(url) } }
            Text(url.path).font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var intake: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("连接接收目录…") { model.connectIntakeDirectory(from: model.settingsWindow) }
                Button("待处理接收…") { model.showIntakeJobs(from: model.settingsWindow) }
                Spacer()
                Button("刷新") { model.refreshSettings() }
            }.disabled(!model.interactionAvailable)
            Text("分享扩展的授权保存在扩展自己的设置中，首次分享时选择。移除连接只移除主 App 本机登记，不删除目录、接收包或扩展授权。").foregroundStyle(Color.w2aSecondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.intakeConnections.isEmpty { Text("尚未连接接收目录。").foregroundStyle(Color.w2aSecondary) }
                    ForEach(model.intakeConnections) { connection in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(connection.registration.path).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            W2AStatus(message: connection.issue.map { "不可读：" + $0 } ?? "可用 · 待处理 \(connection.pendingCount ?? 0) 项", tone: connection.issue == nil ? .success : .warning)
                            HStack {
                                Button("在 Finder 中显示") { model.revealDataLocation(URL(fileURLWithPath: connection.registration.path)) }
                                Button("移除连接…") { model.confirmRemoveConnection(connection) }
                            }.disabled(!model.interactionAvailable)
                        }.padding(12).background(Color.w2aElevated, in: RoundedRectangle(cornerRadius: 8))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(20)
    }
    private var tasks: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("个人模板").font(W2ATheme.TypeStyle.title)
                if let error = model.taskSettingsError { W2AStatus(message: "设置无法读取，未覆盖原文件：" + error, tone: .error) }
                if model.taskSettings.templates.isEmpty { Text("暂无个人模板，可从主窗口“编辑任务要求…”保存。").foregroundStyle(Color.w2aSecondary) }
                ForEach(model.taskSettings.templates, id: \.id) { template in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.title).font(W2ATheme.TypeStyle.section)
                        let count = model.taskSettings.sourceDefaults.values.filter { $0 == "template:" + template.id }.count
                        Text("\(AnalysisTask(action: template.action).needsContext ? "需要历史参考" : "仅本批资料") · \(count) 个来源默认使用").font(W2ATheme.TypeStyle.metadata).foregroundStyle(Color.w2aSecondary)
                        HStack {
                            Button("编辑…") { model.editTemplate(template) }
                            Button("删除…") { model.confirmDeleteTemplate(template) }
                        }.disabled(!model.interactionAvailable || model.taskSettingsError != nil)
                    }
                    W2ADivider()
                }
                Text("来源默认任务").font(W2ATheme.TypeStyle.title)
                if model.taskSettings.sourceDefaults.isEmpty { Text("没有设置来源默认任务。").foregroundStyle(Color.w2aSecondary) }
                ForEach(model.taskSettings.sourceDefaults.keys.sorted(), id: \.self) { key in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.defaultSourceLabel(key))
                            Text((try? model.taskSettings.resolve(model.taskSettings.sourceDefaults[key] ?? "").title) ?? "任务不可用").foregroundStyle(Color.w2aSecondary)
                        }
                        Spacer()
                        Button("清除") { model.clearSourceDefault(key) }.disabled(!model.interactionAvailable || model.taskSettingsError != nil)
                    }
                }
                W2ADivider()
                Text("Agent 客户端").font(W2ATheme.TypeStyle.title)
                ForEach(AgentTarget.allCases, id: \.self) { target in
                    HStack { Text(target.title); Spacer(); Text(model.agentAvailability[target] == true ? "已检测到" : "未检测到").foregroundStyle(Color.w2aSecondary) }
                }
                Text("交接目标仍在主窗口选择，不会自动切换客户端。").foregroundStyle(Color.w2aSecondary)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor
extension AppModel {
    func showSettings(tab: Int? = nil) {
        guard interactionAvailable else { return }
        if let tab { settingsTab = tab }
        if settingsWindow == nil, window != nil {
            let host = NSHostingController(rootView: SettingsView(model: self))
            let panel = NSWindow(contentViewController: host)
            panel.styleMask = [.titled, .closable, .miniaturizable]; panel.title = "WeChat2AI 设置"; panel.isReleasedWhenClosed = false
            panel.appearance = window?.appearance
            panel.setContentSize(NSSize(width: 560, height: 570)); panel.center(); settingsWindow = panel
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        refreshSettings()
    }
    func refreshSettings() {
        guard interactionAvailable else { return }
        refreshAgentAvailability(); settingsError = nil
        run("正在检查接收连接…", task: { try IntakeConnectionState.load(self.environment.intakeRegistry) }, done: { connections in self.intakeConnections = connections; self.setStatus("接收连接已更新。", tone: connections.contains { $0.issue != nil } ? .warning : .neutral) }, onFailure: { self.settingsError = "无法读取接收连接，请查看完整状态信息。" })
    }
    func revealDataLocation(_ url: URL) { guard interactionAvailable else { return }; environment.revealFiles([url]) }
    func defaultSourceLabel(_ key: String) -> String {
        let parts = key.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return key }
        if parts[0] == store?.metadata.libraryID, let source = contents.sources.first(where: { $0.id == parts[1] }) { return sourceName(source) }
        return "其他资料库来源 · " + parts[1].prefix(6)
    }
    func clearSourceDefault(_ key: String) {
        guard interactionAvailable, taskSettingsError == nil else { return }
        var updated = taskSettings; updated.sourceDefaults.removeValue(forKey: key)
        saveManagedTasks(updated)
    }
    func saveManagedTasks(_ updated: TaskSettings) {
        guard interactionAvailable, taskSettingsError == nil else { return }
        run("正在保存任务设置…", task: { try updated.save(at: self.environment.taskSettingsURL) }, done: { _ in
            self.taskSettings = updated
            if !self.taskOptions.contains(where: { $0.1 == self.selectedTaskKey }) { self.selectTask(key: TaskSettings.builtinKey(.summary)) }
            self.setStatus("任务设置已保存。", tone: .success)
        })
    }
    func confirmDeleteTemplate(_ template: TaskTemplate) {
        guard interactionAvailable, taskSettingsError == nil, let parent = settingsWindow ?? window else { return }
        let affected = taskSettings.sourceDefaults.values.filter { $0 == "template:" + template.id }.count
        let alert = NSAlert(); alert.messageText = "删除模板“\(template.title)”？"
        alert.informativeText = "将清除 \(affected) 个来源的默认关联，这些来源恢复为未设置。聊天、资料和交接副本不删除。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "删除模板")
        beginNativePanel()
        environment.panels.alert(alert, parent) { response in
            self.finishNativePanel()
            if response == .alertSecondButtonReturn {
                do { var updated = self.taskSettings; try updated.removeTemplate(id: template.id); self.saveManagedTasks(updated) }
                catch { self.fail(error) }
            }
            self.drainQueue()
        }
    }
    func confirmRemoveConnection(_ connection: IntakeConnectionState) {
        guard interactionAvailable, let parent = settingsWindow ?? window else { return }
        // Re-read before confirming: pending counts in an open settings window can be stale.
        run("正在检查接收目录…", task: {
            try IntakeConnectionState.load(self.environment.intakeRegistry).first { $0.id == connection.id }
        }, done: { current in
            guard let current else { self.refreshSettings(); return }
            let alert = NSAlert(); alert.messageText = "移除此接收连接？"
            let amount = current.pendingCount.map { "仍有 \($0) 项待处理接收。" } ?? "无法读取待处理数量，目录中仍可能有接收包。"
            alert.informativeText = current.registration.path + "\n\n" + amount + "仅移除本机登记，不删除目录、接收包或分享扩展授权。"
            alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "移除连接")
            self.beginNativePanel()
            self.environment.panels.alert(alert, parent) { response in
                self.finishNativePanel()
                if response == .alertSecondButtonReturn {
                    self.run("正在移除接收连接…", task: { try self.environment.intakeRegistry.remove(current.registration) }, done: { _ in
                        self.intakeConnections.removeAll { $0.id == current.id }; _ = self.intakeSnapshot()
                        self.setStatus("接收连接已移除，目录与接收包仍保留。", tone: .success)
                    })
                }
                if response != .alertSecondButtonReturn { self.setStatus("已保留接收连接。") }
                self.drainQueue()
            }
        })
    }
}
