import AppKit
import Combine

@MainActor
final class AppModel: NSObject, ObservableObject {
    enum StatusTone {
        case neutral, success, working, warning, error
        var symbol: String {
            switch self {
            case .neutral: return "info.circle"
            case .success: return "checkmark.circle.fill"
            case .working: return "clock"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
    }
    let environment: AppEnvironment
    let operations = AppOperations()
    let intake = IntakeCoordinator()
    weak var window: NSWindow?
    weak var sheetReturnResponder: NSResponder?
    @Published var libraryUnavailable = false
    @Published var lastDelivery: DeliveryRecord?
    @Published var deliveries: [String: DeliveryRecord] = [:]
    @Published var deliveryPreparing = false
    @Published var agentAvailability: [AgentTarget: Bool] = [:]
    @Published var sourceCounts: [String: Int] = [:]
    @Published var intakeHasErrors = false
    @Published var intakeHasFailures = false
    @Published var readingDocument: ReadingDocument?
    @Published var readingFallback: String?
    @Published var previewIndicatorVisible = false
    @Published var sidebarCanShow = true
    @Published var sourcePopoverVisible = false
    @Published var sidebarCollapsed = false
    @Published var assignAfterImport = true
    @Published var transcriptMode = TranscriptMode.reading
    @Published var settingsTab = 0
    @Published var intakeConnections: [IntakeConnectionState] = []
    @Published var settingsError: String?
    var settingsWindow: NSWindow?
    weak var sheetParent: NSWindow?
    var restoredBatchID: String?

    @Published var store: LibraryStore?
    @Published var contents = LibraryContents()
    @Published var batches: [LibraryBatch] = []
    @Published var selected: LibraryBatch?
    @Published var selectedSource = "unfiled"
    @Published var selectedAgent = AgentTarget.codex
    @Published var selectedTaskKey = TaskSettings.builtinKey(.summary)
    @Published var taskSettings = TaskSettings()
    var taskSettingsError: String?
    var draftTask: AnalysisTask?
    var taskSourceKey: String?
    @Published var busy = false
    @Published var showingSheet = false
    @Published var sheet: AppSheet?
    @Published var transcript = ""
    @Published var previewLoading = false
    @Published var previewError: String?
    @Published var detailText = "暂无已导入批次"
    @Published var statusMessage = ""
    @Published var statusTone = StatusTone.neutral
    @Published var intakeCount = 0
    var previewRequest = UUID()
    var started = false
    var startedOperations = 0

    init(environment: AppEnvironment = .production) {
        self.environment = environment; super.init()
        sidebarCollapsed = environment.defaults.bool(forKey: "ui.sidebarCollapsed")
        assignAfterImport = environment.defaults.object(forKey: "ui.assignAfterImport") as? Bool ?? true
        transcriptMode = TranscriptMode(rawValue: environment.defaults.string(forKey: "ui.transcriptMode") ?? "") ?? .reading
    }
    var interactionAvailable: Bool { !busy && !showingSheet }
    var activeDelivery: DeliveryRecord? { selected.flatMap { deliveries[deliveryKey($0.id)] } }
    func deliveryKey(_ batchID: String) -> String { (store?.metadata.libraryID ?? "unavailable") + "/" + batchID }
    func recordDelivery(_ record: DeliveryRecord) { lastDelivery = record; deliveries[deliveryKey(record.batch.id)] = record }
    var libraryDisplayName: String {
        guard let url = store?.root ?? environment.librarySettings.currentURL else { return "未打开资料库" }
        if url.standardizedFileURL == environment.libraryRoot.standardizedFileURL { return "默认资料库" }
        return url.lastPathComponent == "WeChat2AI Library" ? url.deletingLastPathComponent().lastPathComponent : url.lastPathComponent
    }
    var assignmentTitle: String { selected?.source == nil ? "归档到来源…" : "改归…" }
    var deliveryButtonTitle: String { deliveryPreparing ? "正在准备…" : "交给 " + selectedAgent.title }
    var isSourceDefaultTask: Bool { currentTaskSourceKey.flatMap { taskSettings.sourceDefaults[$0] } == selectedTaskKey }
    func sourceName(_ source: ChatSource) -> String {
        let same = contents.sources.filter { $0.name == source.name && $0.note == source.note }.count > 1
        return source.name + (same ? " · " + source.id.prefix(6) : "")
    }

    var idle: Bool { !busy && !showingSheet && !previewLoading }
    var currentSource: ChatSource? { contents.sources.first { $0.id == selectedSource } }
    var selectedBatchID: String? { selected?.id }
    var libraryPath: String { store?.root.path ?? environment.librarySettings.currentURL?.path ?? "未打开资料库" }
    var warningText: String { contents.warnings.isEmpty ? "" : "\n" + contents.warnings.joined(separator: "；") }
    var currentTaskSourceKey: String? {
        guard let store, let source = currentSource else { return nil }
        return TaskSettings.sourceKey(libraryID: store.metadata.libraryID, sourceID: source.id)
    }
    var sourceTitle: String { sourceOptions.first { $0.1 == selectedSource }?.0 ?? "待分类" }
    var sourceOptions: [(String, String)] { [("待分类", "unfiled")] + contents.sources.map { (sourceName($0), $0.id) } }
    var taskOptions: [(String, String)] {
        ChatAction.allCases.map { ($0.title, TaskSettings.builtinKey($0)) } + taskSettings.templates.map { ("模板 · " + $0.title, "template:" + $0.id) }
    }
    func start() {
        guard !started else { return }; started = true
        refreshAgentAvailability()
        selectedAgent = AgentTarget.restored(environment.defaults.string(forKey: AgentTarget.preferenceKey))
        do { taskSettings = try TaskSettings.load(at: environment.taskSettingsURL) } catch { taskSettingsError = error.localizedDescription }
        run("正在打开资料库…", task: { try self.environment.librarySettings.load() }, done: { store in
            self.store = store; self.restoreSelection()
            self.reload()
        }, onFailure: { self.libraryUnavailable = true })
    }
    func canPerform(_ key: String) -> Bool {
        guard interactionAvailable else { return false }
        switch key {
        case "newSource", "import", "libraryFinder": return store != nil
        case "rename": return currentSource != nil
        case "project": return selected?.source != nil
        case "assign": return selected != nil && store != nil
        case "agent", "copy": return selected != nil && previewError == nil && !previewLoading
        case "handoffInfo": return activeDelivery != nil
        case "read", "find": return selected != nil && !previewLoading && previewError == nil
        case "finder", "share": return selected != nil
        default: return true
        }
    }
    func setStatus(_ message: String, tone: StatusTone = .neutral) { statusMessage = message; statusTone = tone }
    func fail(_ error: Error) { setStatus(error.localizedDescription, tone: .error) }
    func formatImport(_ value: String) -> String {
        guard let date = DisplayFormat.iso.date(from: value) else { return value }
        return DisplayFormat.full.string(from: date)
    }
    func refresh() {
        guard interactionAvailable else { return }; intake.attempted.removeAll()
        if store == nil { started = false; start(); return }
        reload(); drainQueue()
    }
    @discardableResult func reload(select batchID: String? = nil, completion: (() -> Void)? = nil) -> Bool {
        // Called after serialized mutations. Filesystem work and preview IO stay off the main thread.
        guard !busy else { return false }
        let store = self.store, sourceID = selectedSource
        let desired = batchID ?? selected?.id ?? restoredBatchID
        restoredBatchID = nil
        run("正在刷新资料库…", task: {
            let contents = try store?.contents() ?? LibraryContents()
            let validID = (["unfiled"] + contents.sources.map(\.id)).contains(sourceID) ? sourceID : "unfiled"
            let batches = contents.batches.filter { ($0.source?.id ?? "unfiled") == validID }
            return (contents, validID, batches)
        }, done: { contents, sourceID, batches in
            self.sourceCounts = Dictionary(grouping: contents.batches, by: { $0.source?.id ?? "unfiled" }).mapValues(\.count)
            self.window?.title = "WeChat2AI · " + self.libraryDisplayName + (ProcessInfo.processInfo.arguments.contains("--ui-test-root") ? " · 隔离验证（虚构资料）" : "")
            self.libraryUnavailable = false
            self.contents = contents; self.selectedSource = sourceID; self.batches = batches
            if self.taskSourceKey != self.currentTaskSourceKey {
                self.taskSourceKey = self.currentTaskSourceKey
                self.selectTask(key: self.taskSourceKey.flatMap { self.taskSettings.sourceDefaults[$0] } ?? TaskSettings.builtinKey(.summary))
            }
            if let batch = batches.first(where: { $0.id == desired }) ?? batches.first { self.display(batch) }
            else { self.clearSelection() }
            completion?()
        }, onFailure: {
            self.libraryUnavailable = true
            self.batches = []; self.clearSelection()
            self.detailText = "资料库暂不可用"
        })
        return true
    }
    func clearSelection() {
        previewRequest = UUID(); previewLoading = false; previewIndicatorVisible = false; selected = nil; previewError = nil; readingDocument = nil; readingFallback = nil
        detailText = "暂无已导入批次"
        setStatus("暂无已导入批次，请导入聊天记录。" + warningText, tone: contents.warnings.isEmpty ? .neutral : .warning)
        persistSelection()
        transcript = "从微信分享聊天记录，或点击「导入聊天记录」。\n\n记录先保存在待分类。归档时选择已有群/对话，或新建来源。每次导入独立保留，不自动去重。"
    }
    func selectSource(_ id: String) {
        guard interactionAvailable, sourceOptions.contains(where: { $0.1 == id }) else { return }
        selectedSource = id; selected = nil; reload()
    }
    func selectBatch(_ id: String?) {
        guard !busy, !showingSheet, let batch = batches.first(where: { $0.id == id }) else { return }
        display(batch)
    }
    func display(_ batch: LibraryBatch) {
        if selected?.id != batch.id { transcript = ""; readingDocument = nil; readingFallback = nil }
        selected = batch; previewError = nil; previewLoading = true; previewIndicatorVisible = false
        persistSelection()
        let request = UUID(); previewRequest = request
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.previewRequest == request, self.previewLoading else { return }
            self.previewIndicatorVisible = true
        }
        let m = batch.manifest
        detailText = "\(batch.source?.name ?? "待分类")\n\(m.messageCount) 条消息 · \(m.linkedAttachmentCount) 个附件 · 聊天 \(m.firstTimestampOriginal ?? m.firstTimestamp ?? "未知") — \(m.lastTimestampOriginal ?? m.lastTimestamp ?? "未知")（来源时区未提供）\n导入 \(formatImport(m.importedAt))"
        operations.perform({ try self.environment.loadPreview(batch) }) { result in
            guard self.previewRequest == request, self.selected?.id == batch.id else { return }
            self.previewLoading = false; self.previewIndicatorVisible = false
            switch result {
            case .success(let payload):
                self.transcript = payload.transcript; self.readingDocument = payload.reading; self.readingFallback = payload.fallback
                let saved = batch.source == nil ? "已保存到待分类 · 可直接交接，或先归档到来源。" : "资料保存在本机。"
                self.setStatus((m.warnings.isEmpty ? saved : m.warnings.joined(separator: "；")) + self.warningText,
                    tone: m.warnings.isEmpty && self.contents.warnings.isEmpty ? .success : .warning)
            case .failure(let error):
                self.previewError = error.localizedDescription; self.transcript = "无法读取此批次正文：\(error.localizedDescription)"; self.fail(error)
            }
            self.drainQueue()
        }
    }
    func selectTask(key: String) { selectedTaskKey = taskOptions.contains(where: { $0.1 == key }) ? key : TaskSettings.builtinKey(.summary) }
    func chooseTask(_ key: String) { guard interactionAvailable else { return }; selectTask(key: key); if key == TaskSettings.builtinKey(.custom) { showTaskEditor() } }
    func currentTask() throws -> AnalysisTask {
        if selectedTaskKey == TaskSettings.builtinKey(.custom) {
            guard let draftTask else { throw CoreError.invalid("请先填写自定义任务。") }; return draftTask
        }
        return try taskSettings.resolve(selectedTaskKey)
    }
    func chooseAgent(_ target: AgentTarget) {
        guard interactionAvailable, AgentTarget.pickerTargets.contains(target) else { return }
        selectedAgent = target; refreshAgentAvailability(); environment.defaults.set(target.rawValue, forKey: AgentTarget.preferenceKey)
    }
    func run<T>(_ message: String, task: @escaping () throws -> T, done: @escaping (T) -> Void, onFailure: (() -> Void)? = nil) {
        guard !busy, !showingSheet else { return }
        busy = true; startedOperations += 1; setStatus(message, tone: .working)
        operations.perform(task) { result in
            self.busy = false
            switch result {
            case .success(let value): done(value)
            case .failure(let error): onFailure?(); self.fail(error)
            }
            self.drainQueue()
        }
    }
    func refreshAgentAvailability() { agentAvailability = Dictionary(uniqueKeysWithValues: AgentTarget.allCases.map { ($0, environment.applicationURL($0.bundleIdentifier) != nil) }) }
    func persistSelection() {
        guard let store else { return }
        var values = (environment.defaults.data(forKey: "ui.lastSelection.v1").flatMap { try? JSONDecoder().decode([String: LibrarySelection].self, from: $0) }) ?? [:]
        values[store.metadata.libraryID] = LibrarySelection(sourceID: selectedSource, batchID: selected?.id)
        if let data = try? JSONEncoder().encode(values) { environment.defaults.set(data, forKey: "ui.lastSelection.v1") }
    }
    func restoreSelection() {
        let values = environment.defaults.data(forKey: "ui.lastSelection.v1").flatMap { try? JSONDecoder().decode([String: LibrarySelection].self, from: $0) }
        let value = store.flatMap { values?[$0.metadata.libraryID] }
        selectedSource = value?.sourceID ?? "unfiled"; selected = nil; restoredBatchID = value?.batchID
    }
    func toggleSidebar() { guard interactionAvailable else { return }; if !sidebarCanShow { sourcePopoverVisible.toggle(); return }; sidebarCollapsed.toggle(); environment.defaults.set(sidebarCollapsed, forKey: "ui.sidebarCollapsed") }
    func chooseTranscriptMode(_ value: TranscriptMode) { guard interactionAvailable else { return }; transcriptMode = value; environment.defaults.set(value.rawValue, forKey: "ui.transcriptMode") }
    func chooseAssignAfterImport(_ value: Bool) { guard interactionAvailable else { return }; assignAfterImport = value; environment.defaults.set(value, forKey: "ui.assignAfterImport") }
    func copyBatchID(_ batch: LibraryBatch) { guard interactionAvailable else { return }; environment.copyText(batch.id); setStatus("已复制批次 ID。", tone: .success) }
    func revealAttachment(_ path: String, batchID: String) {
        guard interactionAvailable, let batch = selected, batch.id == batchID else { return }
        run("正在检查附件路径…", task: { let url = try LibraryIO.child(path, of: batch.workspace); try LibraryIO.regular(url); return url }, done: { url in self.environment.revealFiles([url]); self.setStatus("已请求在 Finder 中定位附件。") })
    }
    func setStore(_ store: LibraryStore) { self.store = store }
}
