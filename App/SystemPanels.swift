import AppKit
import UniformTypeIdentifiers

/// Native presentation is replaceable independently of paths and external application effects.
struct SystemPanels {
    var file: (NSSavePanel, NSWindow, @escaping (NSApplication.ModalResponse) -> Void) -> Void
    var alert: (NSAlert, NSWindow, @escaping (NSApplication.ModalResponse) -> Void) -> Void
    static let live = SystemPanels(
        file: { panel, window, done in panel.beginSheetModal(for: window, completionHandler: done) },
        alert: { alert, window, done in alert.beginSheetModal(for: window, completionHandler: done) })
    static let cancelled = SystemPanels(file: { _, _, done in done(.cancel) }, alert: { _, _, done in done(.cancel) })
}

@MainActor
extension AppModel {
    func beginNativePanel() { showingSheet = true }
    func finishNativePanel() { showingSheet = false }

    func chooseImport() {
        guard !busy, !showingSheet, let window else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.message = "选择微信导出的 ZIP、TXT、文件夹或 .w2adrop 接收包。"
        beginNativePanel()
        environment.panels.file(panel, window) { response in
            self.finishNativePanel()
            if response == .OK, let url = panel.url { self.intake.pendingURLs.append(url) }
            self.drainQueue()
        }
    }
    func performImport(_ url: URL) {
        guard !busy, !showingSheet, let store else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        run("正在保存到待分类…", task: {
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try store.importData(from: url)
        }, done: { batch in
            self.selectedSource = "unfiled"; self.reload(select: batch.id) { self.didImport(batch) }
        })
    }
    func createLibrary() { chooseLibrary(create: true) }
    func openLibrary() { chooseLibrary(create: false) }
    func chooseLibrary(create: Bool, from parent: NSWindow? = nil) {
        guard interactionAvailable, let window = parent ?? window else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = create
        panel.message = create ? "选择父文件夹，将在其中创建 WeChat2AI Library 子目录。现有资料不会自动搬迁。" : "选择包含 library.json 的已有资料库目录。"
        beginNativePanel()
        environment.panels.file(panel, window) { response in
            self.finishNativePanel()
            guard response == .OK, let url = panel.url else { self.drainQueue(); return }
            self.openLibrary(at: url, create: create)
        }
    }
    func openLibrary(at url: URL, create: Bool = false) {
        guard interactionAvailable else { return }
        run("正在打开资料库…", task: {
            try create ? LibraryStore.create(at: url.appendingPathComponent("WeChat2AI Library")) : LibraryStore.open(at: url)
        }, done: { newStore in
            self.persistSelection()
            self.environment.librarySettings.save(newStore); self.store = newStore
            self.restoreSelection(); self.reload()
        })
    }
    func revealLibrary() { guard canPerform("libraryFinder") else { return }; if let store { environment.revealFiles([store.root]) } }
    func newSource() { editSource(nil) }
    func renameSource() { if let source = currentSource { editSource(source) } }
    func renameSource(id: String) { if let source = contents.sources.first(where: { $0.id == id }) { editSource(source) } }
    func editSource(_ source: ChatSource?, then: ((ChatSource) -> Void)? = nil) {
        guard !busy, !showingSheet, let window, let store else { return }
        let alert = NSAlert(); alert.messageText = source == nil ? "新建来源" : "重命名来源"
        alert.informativeText = "名称可重复，用备注区分。改名不会移动原来的文件夹。"
        alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消")
        let name = NSTextField(string: source?.name ?? ""); name.placeholderString = "群名或对话名称"
        let note = NSTextField(string: source?.note ?? ""); note.placeholderString = "备注（可选）"
        let kind = NSPopUpButton(); kind.addItems(withTitles: ["群聊", "私聊"]); kind.selectItem(at: source?.kind == "direct" ? 1 : 0); kind.isEnabled = source == nil
        func row(_ title: String, _ field: NSView) -> NSView {
            let label = NSTextField(labelWithString: title); label.frame.size.width = 48
            let stack = NSStackView(views: [label, field]); stack.orientation = .horizontal; stack.spacing = 8
            field.widthAnchor.constraint(equalToConstant: 300).isActive = true
            return stack
        }
        let form = NSStackView(views: [row("名称", name), row("备注", note), row("类型", kind), NSTextField(labelWithString: source == nil ? "来源是一个群聊或私聊对话。" : "类型创建后不可更改。")])
        form.orientation = .vertical; form.alignment = .leading; form.spacing = 12
        form.frame = NSRect(x: 0, y: 0, width: 360, height: 144)
        alert.accessoryView = form; beginNativePanel()
        environment.panels.alert(alert, window) { response in
            self.finishNativePanel()
            guard response == .alertFirstButtonReturn else { self.drainQueue(); return }
            let value = name.stringValue, memo = note.stringValue, type = kind.indexOfSelectedItem == 1 ? "direct" : "group"
            self.run("正在保存来源…", task: {
                if let source { try store.renameSource(id: source.id, name: value, note: memo); var updated = source; updated.name = value; updated.note = memo; return updated }
                return try store.createSource(name: value, note: memo, kind: type)
            }, done: { saved in
                if let then { self.reload { then(saved) } }
                else { self.selectedSource = saved.id; self.selected = nil; self.reload() }
            })
        }
        window.attachedSheet?.makeFirstResponder(name)
    }
    func assignSelected() { guard canPerform("assign") else { return }; if let batch = selected { showAssignment(batch) } }
    func assign(_ batch: LibraryBatch, to sourceID: String?) {
        guard !busy, !showingSheet, let store else { return }
        run("正在归档…", task: {
            try store.assign(batchID: batch.id, to: sourceID)
        }, done: { updated in
            self.selectedSource = updated.source?.id ?? "unfiled"; self.reload(select: updated.id)
            self.setStatus("已归入\(updated.source?.name ?? "待分类")。" + self.warningText, tone: self.contents.warnings.isEmpty ? .success : .warning)
        })
    }
    func confirmIntakeDirectory(_ queue: IntakeQueue, input: URL) {
        guard !busy, !showingSheet, let window else { return }
        let alert = NSAlert(); alert.messageText = "连接自动接收目录？"
        alert.informativeText = "仅首次连接。此目录中的分享任务会自动导入资料库，成功后清理接收副本。\n\n" + queue.root.path
        alert.addButton(withTitle: "连接并导入"); alert.addButton(withTitle: "取消")
        if input.lastPathComponent != ".intake.w2adrop" { alert.addButton(withTitle: "仅导入此文件") }
        beginNativePanel()
        environment.panels.alert(alert, window) { response in
            self.finishNativePanel()
            do {
                if response == .alertFirstButtonReturn { try self.environment.intakeRegistry.register(queue) }
                else if response == .alertThirdButtonReturn, self.store != nil { self.performImport(input) }
            } catch { self.fail(error) }
            self.drainQueue()
        }
    }
    func connectIntakeDirectory(from parent: NSWindow? = nil) {
        guard interactionAvailable, let window = parent ?? window else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "选择分享扩展已创建的 WeChat2AI Receipts 接收目录。"
        beginNativePanel()
        environment.panels.file(panel, window) { response in
            self.finishNativePanel()
            if response == .OK, let url = panel.url {
                do {
                    let queue = try IntakeQueue(at: url)
                    try self.environment.intakeRegistry.register(queue); self.intake.attempted.removeAll()
                    self.setStatus("接收目录已连接。", tone: .success)
                    if parent != nil { self.refreshSettings() }
                } catch { self.fail(error) }
            }
            self.drainQueue()
        }
    }
    func exportIntake(_ job: IntakeJob, from parent: NSWindow? = nil) {
        guard !busy, !showingSheet, let window = parent ?? window else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "WeChat-\(job.id.prefix(8)).w2adrop"
        panel.allowedContentTypes = [UTType(importedAs: "local.scofield.wechat2ai.drop", conformingTo: .package)]
        beginNativePanel()
        environment.panels.file(panel, window) { response in
            self.finishNativePanel()
            guard response == .OK, let target = panel.url else { self.drainQueue(); return }
            self.run("正在另存接收包…", task: {
                guard !FileManager.default.fileExists(atPath: target.path) else { throw CoreError.invalid("此位置已有文件，请换一个名称。") }
                try SafeFiles.copy(job.payload, to: target)
            }, done: { _ in self.setStatus("已另存接收包。队列中的任务仍保留，可稍后重试或丢弃。", tone: .success) })
        }
    }
    func discardIntake(_ queue: IntakeQueue, job: IntakeJob, from parent: NSWindow? = nil) {
        guard !busy, !showingSheet, let window = parent ?? window else { return }
        let alert = NSAlert(); alert.messageText = "丢弃此接收任务？"
        alert.informativeText = "将删除此任务的接收副本，无法撤销。已入库的批次不会删除；尚未入库的内容建议先另存。"
        alert.addButton(withTitle: "保留"); alert.addButton(withTitle: "丢弃接收任务")
        beginNativePanel()
        environment.panels.alert(alert, window) { response in
            self.finishNativePanel()
            guard response == .alertSecondButtonReturn else { self.drainQueue(); return }
            self.run("正在丢弃接收任务…", task: { try queue.discard(job.id) }, done: { _ in
                _ = self.intakeSnapshot(); self.setStatus("接收任务已丢弃。", tone: .neutral)
            })
        }
    }
}
