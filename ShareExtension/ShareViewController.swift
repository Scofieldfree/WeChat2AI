import AppKit
import UniformTypeIdentifiers

@objc(ShareViewController)
final class ShareViewController: NSViewController {
    private let status = NSTextField(wrappingLabelWithString: "正在准备接收…")
    private var retryButton: NSButton!
    private var exportButton: NSButton!
    private var cancelButton: NSButton!
    private let location = IntakeLocation()
    private let io = DispatchQueue(label: "local.scofield.wechat2ai.share-receive", qos: .userInitiated)
    private let stateLock = NSLock()
    private var cancelled = false
    private var started = false
    private var queue: IntakeQueue?
    private var draft: IntakeDraft?
    private var published: URL?
    private var completeInput = false
    private var isCancelled: Bool { stateLock.lock(); defer { stateLock.unlock() }; return cancelled }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 220))
        preferredContentSize = view.frame.size
        let title = NSTextField(labelWithString: "接收微信聊天记录")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        retryButton = NSButton(title: "连接接收目录…", target: self, action: #selector(reconnect))
        exportButton = NSButton(title: "另存接收包…", target: self, action: #selector(exportPackage))
        cancelButton = NSButton(title: "取消", target: self, action: #selector(cancel))
        for b in [retryButton!, exportButton!, cancelButton!] { b.bezelStyle = .rounded }
        retryButton.isHidden = true; exportButton.isHidden = true
        let row = NSStackView(views: [cancelButton, exportButton, retryButton]); row.spacing = 8
        let stack = NSStackView(views: [title, status, row])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor)])
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        guard !started else { return }; started = true
        do {
            if let restored = try location.restore() { queue = restored; beginReceive() }
            else { reconnect() }
        } catch { fail(error) }
    }
    @objc private func reconnect() {
        guard !isCancelled, draft == nil, published == nil, let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "使用此位置"
        panel.message = "仅首次设置：选择本机接收位置。之后分享将自动导入，成功后清理接收包；也可选择已有的 WeChat2AI Receipts 文件夹。"
        retryButton.isHidden = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, !self.isCancelled else { return }
            guard response == .OK, let url = panel.url else { self.cancel(); return }
            do { self.queue = try self.location.connect(url); self.beginReceive() }
            catch { self.fail(error) }
        }
    }
    private func beginReceive() {
        guard let queue, !isCancelled else { return }
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty, providers.count <= 20 else { fail(CoreError.invalid("请选择 1–20 个文件。")); return }
        do {
            draft = try queue.begin(); status.stringValue = "正在接收文件…"
            retryButton.isHidden = true; exportButton.isHidden = true
            receive(providers, index: 0)
        } catch { fail(error) }
    }
    private func receive(_ providers: [NSItemProvider], index: Int) {
        guard !isCancelled, let queue, let draft else { return }
        guard index < providers.count else {
            completeInput = true
            io.async {
                do {
                    guard !self.isCancelled else { return }
                    let target = try queue.publish(draft)
                    DispatchQueue.main.async {
                        // Once published, cancel only closes the UI; the durable task stays queued.
                        self.published = target; self.draft = nil
                        if !self.isCancelled { self.openHost(target) }
                    }
                } catch { DispatchQueue.main.async { if !self.isCancelled { self.fail(error) } } }
            }
            return
        }
        status.stringValue = "正在接收 \(index + 1)/\(providers.count)…"
        let provider = providers[index]
        let folder = draft.payload.appendingPathComponent(String(format: "%02d", index + 1))
        // Synchronous copy while the provider URL is valid. All file work is serialized with cancellation.
        let accept: (URL?, Error?) -> Void = { [weak self] url, error in
            guard let self else { return }
            do {
                try self.io.sync {
                    guard !self.isCancelled else { return }
                    if let error { throw error }
                    guard let url, url.isFileURL else { throw CoreError.invalid("分享内容不是本地文件。") }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                    try SafeFiles.copy(url, to: folder.appendingPathComponent(url.lastPathComponent))
                    _ = try IntakeIO.inventory(draft.payload, hashFiles: false) // Hash once at publication; enforce cumulative limits after every provider.
                }
                DispatchQueue.main.async { self.receive(providers, index: index + 1) }
            } catch { DispatchQueue.main.async { if !self.isCancelled { self.fail(error) } } }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, error in
                let url: URL?
                if let v = value as? URL { url = v }
                else if let v = value as? Data { url = URL(dataRepresentation: v, relativeTo: nil) }
                else if let v = value as? String { url = URL(string: v) }
                else { url = nil }
                accept(url, error)
            }
        } else if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .data) == true }) {
            provider.loadFileRepresentation(forTypeIdentifier: type, completionHandler: accept)
        } else { fail(CoreError.invalid("分享内容没有可读取的文件，请分享微信导出的 ZIP。")) }
    }
    private func openHost(_ target: URL) {
        status.stringValue = "已接收，正在交给 WeChat2AI…"
        let signal: URL
        do {
            guard let queue else { throw CoreError.invalid("接收目录未连接。") }
            signal = try queue.signalURL()
        } catch { fail(error); return }
        let host = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        NSWorkspace.shared.open([signal], withApplicationAt: host, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self, !self.isCancelled else { return }
                if let error {
                    self.status.stringValue = "接收包已保留。无法打开 WeChat2AI：\(error.localizedDescription) 若尚未连接接收目录，可另存后导入。"
                    self.exportButton.isHidden = false; self.cancelButton.title = "完成"
                } else { self.location.release(); self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil) }
            }
        }
    }
    private func fail(_ error: Error) {
        status.stringValue = error.localizedDescription
        retryButton.isHidden = draft != nil || published != nil
        exportButton.isHidden = !completeInput && published == nil
        if draft != nil && !completeInput { status.stringValue += " 接收未完成，请取消后重新分享。" }
    }
    @objc private func exportPackage() {
        let publishedID = published?.deletingLastPathComponent().lastPathComponent
        let current = try? queue?.jobs().first(where: { $0.id == publishedID })?.payload
        guard let source = current ?? published ?? (completeInput ? draft?.payload : nil), let window = view.window else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "WeChat-\(IntakeIO.uuid().prefix(8)).w2adrop"
        panel.allowedContentTypes = [UTType(importedAs: "local.scofield.wechat2ai.drop", conformingTo: .package)]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let target = panel.url else { return }
            let scoped = target.startAccessingSecurityScopedResource()
            self.io.async {
                defer { if scoped { target.stopAccessingSecurityScopedResource() } }
                do {
                    guard !FileManager.default.fileExists(atPath: target.path) else { throw CoreError.invalid("此位置已有文件，请换一个名称。") }
                    try SafeFiles.copy(source, to: target)
                    DispatchQueue.main.async { self.status.stringValue = "已另存接收包，可双击导入。队列中的原任务仍保留。" }
                } catch { DispatchQueue.main.async { self.fail(error) } }
            }
        }
    }
    @objc private func cancel() {
        stateLock.lock(); cancelled = true; stateLock.unlock()
        cancelButton.isEnabled = false
        let draft = self.draft, queue = self.queue
        io.async {
            // publish may have moved this directory already: never remove the ready task.
            if let draft, let queue, FileManager.default.fileExists(atPath: draft.directory.path) { try? queue.cancel(draft) }
            DispatchQueue.main.async {
                self.draft = nil; self.location.release()
                if self.published != nil { self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil) }
                else { self.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)) }
            }
        }
    }
}
