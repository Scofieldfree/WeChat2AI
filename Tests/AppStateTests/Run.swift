import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct TestFailure: Error, CustomStringConvertible { let description: String }
func check(_ condition: @autoclosure () throws -> Bool, _ message: String = "Assertion failed", line: Int = #line) throws {
    if try !condition() { throw TestFailure(description: "line \(line): \(message)") }
}
@MainActor
func waitUntil(_ condition: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(15)
    while !condition() {
        guard Date() < deadline else { throw TestFailure(description: "Timed out waiting for application state") }
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
}
@MainActor
func makeSyntheticImage(_ url: URL, width: Int, height: Int, transparent: Bool = false, rotated: Bool = false) throws {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if !transparent { context.setFillColor(CGColor(red: 0.93, green: 0.89, blue: 0.80, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height)) }
    context.setFillColor(CGColor(red: 0.76, green: 0.39, blue: 0.27, alpha: 1))
    context.fill(CGRect(x: width / 8, y: height / 4, width: width * 3 / 4, height: height / 2))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    ("虚构图片 / SYNTHETIC" as NSString).draw(at: NSPoint(x: 12, y: 12), withAttributes: [.font: NSFont.systemFont(ofSize: CGFloat(max(12, min(width, height) / 14))), .foregroundColor: NSColor.black])
    NSGraphicsContext.restoreGraphicsState()
    let type = url.pathExtension == "jpg" ? UTType.jpeg.identifier : UTType.png.identifier
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, rotated ? [kCGImagePropertyOrientation: 6] as CFDictionary : nil)
    guard CGImageDestinationFinalize(destination) else { throw TestFailure(description: "Synthetic image creation failed") }
}
@MainActor
func makeSyntheticImageExport(at root: URL) throws -> URL {
    let folder = root.appendingPathComponent("SyntheticPhotoExport")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try makeSyntheticImage(folder.appendingPathComponent("synthetic-landscape.jpg"), width: 1600, height: 900)
    try makeSyntheticImage(folder.appendingPathComponent("synthetic-portrait.png"), width: 300, height: 900)
    try makeSyntheticImage(folder.appendingPathComponent("synthetic-alpha.png"), width: 320, height: 160, transparent: true)
    try makeSyntheticImage(folder.appendingPathComponent("synthetic-rotated.jpg"), width: 1200, height: 600, rotated: true)
    try Data("not an image".utf8).write(to: folder.appendingPathComponent("synthetic-corrupt.jpg"))
    let bodies = ["这些图片与聊天全部为虚构验收资料。", "[Photo] synthetic-landscape.jpg", "图片保持比例，文件名仍可定位原件。", "[Photo] synthetic-portrait.png", "[Photo] synthetic-alpha.png", "[Photo] synthetic-rotated.jpg", "[Photo] synthetic-corrupt.jpg", "[Photo] synthetic-missing.jpg", "后续正文仍然可以选择、查找与复制。"]
    try bodies.enumerated().map { "·虚构用户\($0.offset % 2 == 0 ? "甲" : "乙")\n2026-11-14 12:00\n" + $0.element + "\n\n" }.joined().write(to: folder.appendingPathComponent("Chat History.txt"), atomically: true, encoding: .utf8)
    return folder
}
@MainActor
func nativeText(in view: NSView) -> NSTextView? {
    if let text = view as? NSTextView { return text }
    return view.subviews.compactMap { nativeText(in: $0) }.first
}
func imageCells(in text: NSTextView) -> [(InlineImageCell, NSRange)] {
    var result: [(InlineImageCell, NSRange)] = []
    text.textStorage?.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.string.utf16.count)) { value, range, _ in
        if let cell = (value as? NSTextAttachment)?.attachmentCell as? InlineImageCell { result.append((cell, range)) }
    }
    return result
}
@MainActor
final class Fixture {
    let root: URL
    let suite: String
    let defaults: UserDefaults
    var environment: AppEnvironment
    var copied: [String] = []
    var launches: [DesktopLaunch] = []
    var model: AppModel!
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("WeChat2AI-State-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "local.scofield.wechat2ai.tests." + root.lastPathComponent
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "ui.assignAfterImport")
        environment = .isolated(at: root, defaults: defaults)
    }
    func start() throws {
        environment.copyText = { [unowned self] in self.copied.append($0) }
        model = AppModel(environment: environment); model.start(); try settle()
    }
    func settle() throws { try waitUntil { self.model.idle && self.model.intake.pendingURLs.isEmpty } }
    func close() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    func input(_ name: String = "input.txt", text: String = "·虚构用户\n2026-11-14 12:00\n这是隔离测试的虚构聊天。") throws -> URL {
        let url = root.appendingPathComponent(name); try text.write(to: url, atomically: true, encoding: .utf8); return url
    }
    @discardableResult func batch(_ name: String = "input.txt", source: ChatSource? = nil) throws -> LibraryBatch {
        let batch = try model.store!.importData(from: input(name, text: "·虚构用户\n2026-11-14 12:00\n这是隔离测试的虚构聊天：" + name))
        if let source { return try model.store!.assign(batchID: batch.id, to: source.id) }; return batch
    }
    func queue() throws -> (IntakeQueue, IntakeJob) {
        let queue = try IntakeQueue.create(at: root.appendingPathComponent("Queue"))
        let draft = try queue.begin()
        try "·虚构用户\n2026-11-14 12:00\n分享测试".write(to: draft.payload.appendingPathComponent("Chat History.txt"), atomically: true, encoding: .utf8)
        _ = try queue.publish(draft)
        try environment.intakeRegistry.register(queue)
        return (queue, try queue.jobs()[0])
    }
}

@main
struct AppStateTestRunner {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        if let index = CommandLine.arguments.firstIndex(of: "--prepare-ui-host"), CommandLine.arguments.indices.contains(index + 1) {
            try prepareHost(URL(fileURLWithPath: CommandLine.arguments[index + 1])); return
        }
        let tests: [(String, @MainActor (Fixture) throws -> Void)] = [
            ("Library identity and missing saved path", { f in
                try f.start(); let id = f.model.store!.metadata.libraryID
                let reopened = AppModel(environment: f.environment); reopened.start(); try waitUntil { reopened.idle }
                try check(reopened.store?.metadata.libraryID == id)
                try FileManager.default.removeItem(at: f.model.store!.root)
                let missing = AppModel(environment: f.environment); missing.start(); try waitUntil { missing.idle }
                try check(missing.store == nil && missing.statusTone == .error)
                try check(!FileManager.default.fileExists(atPath: f.environment.libraryRoot.path))
            }),
            ("Repeated operation and failure recovery", { f in
                try f.start(); let before = f.model.startedOperations
                var first = false, second = false
                f.model.run("first", task: { 1 }, done: { _ in first = true })
                f.model.run("second", task: { 2 }, done: { _ in second = true })
                f.model.selectSource("unavailable"); f.model.chooseAgent(.claudeCode); f.model.refresh()
                try f.settle(); try check(first && !second && f.model.startedOperations == before + 1)
                try check(f.model.selectedSource == "unfiled" && f.model.selectedAgent == .codex)
                f.model.run("failure", task: { throw TestFailure(description: "expected failure") }, done: { (_: Void) in })
                try f.settle(); try check(f.model.statusTone == .error)
                f.model.run("recovered", task: { 1 }, done: { _ in first = false }); try f.settle(); try check(!first)
            }),
            ("Stable selection, fallback, and stale preview rejection", { f in
                try f.start(); let a = try f.batch("a.txt"), b = try f.batch("b.txt")
                f.model.reload(select: b.id); try f.settle(); try check(f.model.selected?.id == b.id)
                f.model.refresh(); try f.settle(); try check(f.model.selected?.id == b.id)
                f.model.selectBatch(a.id); f.model.selectBatch(b.id); try f.settle()
                try check(f.model.selected?.id == b.id && f.model.transcript.contains("b.txt") && !f.model.transcript.contains("a.txt"))
                try FileManager.default.removeItem(at: b.workspace)
                f.model.refresh(); try f.settle(); try check(f.model.selected?.id == a.id)
                let source = try f.model.store!.createSource(name: "空群")
                f.model.reload(); try f.settle(); f.model.selectSource(source.id); try f.settle()
                try check(f.model.selected == nil && f.model.batches.isEmpty)
            }),
            ("Preview failure prevents copying stale text", { f in
                try f.start(); let batch = try f.batch()
                f.model.reload(select: batch.id); try f.settle()
                try FileManager.default.removeItem(at: batch.workspace.appendingPathComponent("transcript.md"))
                f.model.display(batch); try f.settle(); f.model.copyContext()
                try check(f.model.previewError != nil && f.copied.isEmpty)
            }),
            ("Draft cancellation and invalid edits are isolated", { f in
                try f.start(); f.model.showTaskEditor()
                guard case .task(let draft, _) = f.model.sheet else { throw TestFailure(description: "No editor") }
                draft.title = "丢弃的草稿"; draft.instruction = "不应保存"; draft.saveTemplate = true
                f.model.cancelTaskEditor(draft)
                try check(f.model.taskSettings.templates.isEmpty && f.model.draftTask == nil)
                try check(!FileManager.default.fileExists(atPath: f.environment.taskSettingsURL.path))
                f.model.showTaskEditor()
                guard case .task(let invalid, _) = f.model.sheet else { throw TestFailure(description: "No editor") }
                invalid.title = String(repeating: "字", count: 81)
                f.model.applyTaskEditor(invalid)
                try check(invalid.error != nil && f.model.showingSheet && !f.model.busy)
                f.model.cancelTaskEditor(invalid)
            }),
            ("History template semantics and per-library source defaults", { f in
                try f.start(); let source = try f.model.store!.createSource(name: "同名")
                f.model.reload(); try f.settle(); f.model.selectSource(source.id); try f.settle()
                f.model.chooseTask(TaskSettings.builtinKey(.compare)); f.model.showTaskEditor()
                guard case .task(let draft, _) = f.model.sheet else { throw TestFailure(description: "No editor") }
                draft.title = "对比模板"; draft.saveTemplate = true; draft.makeDefault = true
                f.model.applyTaskEditor(draft); try f.settle()
                let key = f.model.selectedTaskKey
                try check(try f.model.currentTask().action == .compare)
                try check(try TaskSettings.load(at: f.environment.taskSettingsURL).templates.count == 1)
                f.model.showTaskEditor()
                guard case .task(let update, _) = f.model.sheet else { throw TestFailure(description: "No template editor") }
                update.title = "更新后的对比模板"; f.model.applyTaskEditor(update); try f.settle()
                try check(f.model.taskSettings.templates.count == 1 && f.model.selectedTaskKey == key)
                f.model.selectSource("unfiled"); try f.settle(); f.model.selectSource(source.id); try f.settle()
                try check(f.model.selectedTaskKey == key)
                let other = try LibraryStore.create(at: f.root.appendingPathComponent("Other")); let otherSource = try other.createSource(name: "同名")
                f.model.openLibrary(at: other.root); try f.settle(); f.model.selectSource(otherSource.id); try f.settle()
                try check(f.model.selectedTaskKey == TaskSettings.builtinKey(.summary))
                f.model.openLibrary(at: f.environment.libraryRoot); try f.settle(); f.model.selectSource(source.id); try f.settle()
                try check(f.model.selectedTaskKey == key)
            }),
            ("Corrupt task settings remain byte-identical", { f in
                try FileManager.default.createDirectory(at: f.environment.taskSettingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let bad = Data("broken settings".utf8); try bad.write(to: f.environment.taskSettingsURL)
                try f.start(); f.model.showTaskEditor()
                guard case .task(let draft, _) = f.model.sheet else { throw TestFailure(description: "No editor") }
                draft.saveTemplate = true; f.model.applyTaskEditor(draft)
                try check(draft.error != nil && (try Data(contentsOf: f.environment.taskSettingsURL)) == bad)
                f.model.cancelTaskEditor(draft)
            }),
            ("Ordinary copy and missing client do not create handoffs", { f in
                try f.start(); let batch = try f.batch(); f.model.reload(select: batch.id); try f.settle()
                f.model.copyContext(); try check(f.copied.count == 1 && f.copied[0].contains("本次仅包含选中批次"))
                f.model.openInAgent(); try check(f.model.statusTone == .warning)
                try check(!FileManager.default.fileExists(atPath: f.environment.handoffRoot.path))
            }),
            ("Explicit history selection copies only chosen batches", { f in
                try f.start(); let source = try f.model.store!.createSource(name: "测试群")
                let a = try f.batch("a.txt", source: source), b = try f.batch("b.txt", source: source), c = try f.batch("c.txt", source: source)
                f.model.selectedSource = source.id; f.model.reload(select: a.id); try f.settle()
                f.model.chooseTask(TaskSettings.builtinKey(.compare)); f.model.copyContext(); try waitUntil { f.model.showingSheet || f.model.idle }
                guard case .context(let draft) = f.model.sheet else { throw TestFailure(description: "No context editor") }
                try check(draft.historyIDs.isEmpty && draft.resultFiles.isEmpty)
                f.model.deliverContext(draft); try check(draft.error != nil && f.model.showingSheet)
                draft.historyIDs = [b.id]; f.model.deliverContext(draft); try f.settle()
                let project = try ManagedProjects.existing(libraryID: f.model.store!.metadata.libraryID, sourceID: source.id, at: f.environment.projectsRoot)!
                let packages = try FileManager.default.contentsOfDirectory(at: project.appendingPathComponent("wechat-imports"), includingPropertiesForKeys: nil)
                try check(packages.count == 1 && f.copied.count == 1)
                let manifest = try LibraryIO.read(AnalysisTaskManifest.self, packages[0].appendingPathComponent("task.json"))
                try check(manifest.references.map(\.batchID) == [b.id] && !manifest.references.contains { $0.batchID == c.id })
            }),
            ("Foreign, unknown, and over-limit references rejected in UI", { f in
                try f.start(); let source = try f.model.store!.createSource(name: "群")
                var batches: [LibraryBatch] = []
                for i in 0..<21 { batches.append(try f.batch("\(i).txt", source: source)) }
                let draft = AnalysisContextDraft(batchID: "primary", task: AnalysisTask(action: .compare), delivery: .copy, candidates: batches, files: [])
                draft.historyIDs = ["foreign"]
                do { try draft.validate(); throw TestFailure(description: "Accepted foreign reference") } catch is CoreError {}
                draft.historyIDs = Set(batches.map(\.id))
                do { try draft.validate(); throw TestFailure(description: "Accepted over-limit references") } catch is CoreError {}
            }),
            ("Modal cancellation resumes duplicate notifications once", { f in
                try f.start(); f.model.showTaskEditor(); let (queue, job) = try f.queue()
                let signal = try queue.signalURL(); f.model.receive([signal, signal]); f.model.drainQueue()
                try check(try f.model.store!.contents().batches.isEmpty)
                guard case .task(let draft, _) = f.model.sheet else { throw TestFailure(description: "No editor") }
                f.model.cancelTaskEditor(draft); try f.settle()
                try check(try f.model.store!.contents().batches.count == 1)
                try check(try queue.completion(job.id) != nil && queue.jobs().isEmpty)
                f.model.receive([signal]); try f.settle()
                try check(try f.model.store!.contents().batches.count == 1)
            }),
            ("Native panel cancellation shares modal lock with SwiftUI", { f in
                var cancel: ((NSApplication.ModalResponse) -> Void)?
                f.environment.panels.file = { _, _, done in cancel = done }
                try f.start(); let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
                f.model.window = window; f.model.chooseImport(); f.model.showTaskEditor()
                try check(f.model.showingSheet && f.model.sheet == nil && cancel != nil)
                let (queue, _) = try f.queue(); f.model.receive([try queue.signalURL()])
                try check(try f.model.store!.contents().batches.isEmpty)
                f.model.window = nil; cancel?(.cancel); try f.settle()
                try check(try f.model.store!.contents().batches.count == 1)
            }),
            ("Failed intake recovers without permanent busy state", { f in
                try f.start(); let (queue, job) = try f.queue()
                let text = job.payload.appendingPathComponent("Chat History.txt"); let original = try Data(contentsOf: text)
                try Data("tampered".utf8).write(to: text)
                f.model.drainQueue(); try f.settle(); try check(f.model.statusTone == .error)
                let failed = try queue.jobs()[0]; try original.write(to: failed.payload.appendingPathComponent("Chat History.txt"))
                f.model.retryIntake(queue, job: failed); try f.settle()
                try check(try f.model.store!.contents().batches.count == 1 && queue.jobs().isEmpty)
            }),
            ("All three desktop adapters preserve snapshots on open failure", { f in
                f.environment.applicationURL = { _ in URL(fileURLWithPath: "/Applications/Fixture.app") }
                f.environment.openApplication = { launch, done in f.launches.append(launch); done(TestFailure(description: "fixture open failure")) }
                try f.start(); let batch = try f.batch(); f.model.reload(select: batch.id); try f.settle()
                for target in AgentTarget.allCases {
                    f.model.prepareTaskDelivery(.desktop(target)); try f.settle()
                    try check(f.model.statusTone == .error && f.model.statusMessage.contains("副本已保留"))
                }
                try check(f.launches.count == 3 && Set(f.launches.map { $0.handoff.workspace }).count == 3)
                for launch in f.launches { try check(launch.handoff.workspace.path.hasPrefix(f.root.path)); try LibraryIO.directory(launch.handoff.workspace) }
            }),
            ("Agent choices restore independently and unknown preferences fall back", { f in
                try f.start()
                for target in AgentTarget.pickerTargets {
                    f.model.chooseAgent(target)
                    let restarted = AppModel(environment: f.environment); restarted.start(); try waitUntil { restarted.idle }
                    try check(restarted.selectedAgent == target)
                    try check(f.defaults.string(forKey: AgentTarget.preferenceKey) == target.rawValue)
                }
                f.defaults.set("futureAgent", forKey: AgentTarget.preferenceKey)
                let restarted = AppModel(environment: f.environment); restarted.start(); try waitUntil { restarted.idle }
                try check(restarted.selectedAgent == .codex)
            }),
            ("Selected Agent launch, duplicate guard and retained-result copy", { f in
                f.environment.applicationURL = { _ in URL(fileURLWithPath: "/Applications/Fixture.app") }
                var complete: ((Error?) -> Void)?
                f.environment.openApplication = { launch, done in f.launches.append(launch); complete = done }
                try f.start(); let batch = try f.batch(); f.model.reload(select: batch.id); try f.settle()
                for target in AgentTarget.pickerTargets {
                    f.model.chooseAgent(target); f.model.openInAgent()
                    try waitUntil { complete != nil }
                    f.model.openInAgent(); f.model.chooseAgent(.codex)
                    try check(f.model.busy && f.model.selectedAgent == target)
                    let launch = f.launches.last!
                    let components = URLComponents(url: launch.url, resolvingAgainstBaseURL: false)!
                    try check(components.host == (target == .codex ? "threads" : target == .claudeCode ? "code" : "cowork"))
                    try check(f.model.lastDelivery?.agent == target && f.model.lastDelivery?.workspace == launch.handoff.workspace)
                    complete?(target == .claudeCowork ? TestFailure(description: "fixture failure") : nil); complete = nil
                    try f.settle()
                    try check(f.model.statusMessage.contains(target.title) && f.model.lastDelivery!.details.contains(target.title))
                }
                try check(f.launches.count == 3)
                let retained = f.model.lastDelivery!.workspace!
                f.model.chooseTask(TaskSettings.builtinKey(.todos))
                f.model.copyLastDelivery()
                try check(f.copied.count == 1 && f.copied[0].contains(retained.path))
                try check(f.model.lastDelivery?.task.action == .summary)
                try LibraryIO.directory(retained)
            }),
            ("Display names, cached counts and source-time presentation", { f in
                try f.start()
                let a = try f.model.store!.createSource(name: "同名", note: "备注甲")
                let b = try f.model.store!.createSource(name: "同名", note: "备注乙")
                let c = try f.model.store!.createSource(name: "同名", note: "备注甲")
                _ = try f.batch(source: a); f.model.reload(); try f.settle()
                try check(f.model.sourceName(a).contains(a.id.prefix(6)))
                try check(f.model.sourceName(c).contains(c.id.prefix(6)))
                try check(f.model.sourceName(b) == "同名" && f.model.sourceCounts[a.id] == 1)
                try check(f.model.sourceOptions.first?.1 == "unfiled")
                var m = f.model.contents.batches[0].manifest
                m.firstTimestampOriginal = "2026-11-12 09:30"; m.lastTimestampOriginal = "2026-11-12 18:02"
                try check(DisplayFormat.chatRange(m) == "聊天 11-12 09:30 – 18:02")
                m.lastTimestampOriginal = "2026-11-13 18:02"
                try check(DisplayFormat.chatRange(m) == "聊天 11-12 09:30 – 11-13 18:02")
                m.firstTimestampOriginal = "2025年1月2日 9:30"; m.lastTimestampOriginal = "2026-01-02 18:02"
                try check(DisplayFormat.chatRange(m) == "聊天 2025-01-02 09:30 – 2026-01-02 18:02")
                let now = DisplayFormat.iso.date(from: "2026-11-14T12:00:00Z")!
                try check(DisplayFormat.imported("2026-11-14T12:00:00Z", now: now).hasPrefix("今天 "))
                try check(DisplayFormat.imported("2025-11-14T12:00:00Z", now: now).hasPrefix("2025-11-14"))
            }),
            ("Preview fallbacks and rendered copy leave Markdown unchanged", { f in
                try f.start(); let batch = try f.batch()
                let rawFile = batch.workspace.appendingPathComponent("transcript.md")
                let before = try Data(contentsOf: rawFile)
                let loaded = try PreviewLoader.load(batch)
                try check(loaded.reading?.messages.count == 1 && loaded.fallback == nil)
                let rendered = ReadingRenderer.attributed(loaded.reading!, appearance: NSAppearance(named: .aqua)!).string
                try check(rendered.contains("虚构用户") && !rendered.contains("# 微信聊天记录") && !rendered.contains("> "))
                try Data("not json".utf8).write(to: batch.workspace.appendingPathComponent("messages.jsonl"))
                let fallback = try PreviewLoader.load(batch)
                try check(fallback.reading == nil && fallback.transcript == loaded.transcript && fallback.fallback != nil)
                let raw = try f.model.store!.importData(from: f.input("raw.txt", text: "未结构化的原文"))
                try check(try PreviewLoader.load(raw).reading == nil)
                var manifest = batch.manifest; manifest.messageCount = 0
                let zero = LibraryBatch(workspace: batch.workspace, manifest: manifest, source: batch.source)
                try check(try PreviewLoader.load(zero).reading == nil)
                try check(try Data(contentsOf: rawFile) == before)
                f.model.reload(select: batch.id); try f.settle(); f.model.chooseTranscriptMode(.reading); f.model.copyContext()
                try check(f.copied.last?.contains("# 微信聊天记录") == true)
            }),
            ("Preview loading permits configuration but guards delivery and stale results", { f in
                f.environment.loadPreview = { batch in Thread.sleep(forTimeInterval: 0.2); return try PreviewLoader.load(batch) }
                try f.start(); let a = try f.batch("a.txt"), b = try f.batch("b.txt")
                f.model.reload(select: a.id); try f.settle()
                f.model.display(a)
                try check(f.model.previewLoading && !f.model.previewIndicatorVisible)
                f.model.chooseAgent(.claudeCowork); f.model.chooseTask(TaskSettings.builtinKey(.todos))
                try check(f.model.selectedAgent == .claudeCowork && f.model.selectedTaskKey == TaskSettings.builtinKey(.todos))
                try check(f.model.canPerform("assign") && !f.model.canPerform("copy") && !f.model.canPerform("agent"))
                f.model.display(b); try f.settle()
                try check(f.model.transcript.contains("b.txt") && f.model.readingDocument?.messages.first?.body.contains("b.txt") == true)
                f.model.run("正在刷新", task: { 1 }, done: { _ in })
                try check(f.model.deliveryButtonTitle == "交给 Claude Cowork")
                try f.settle()
            }),
            ("Per-batch delivery records survive selection and library changes", { f in
                try f.start(); let a = try f.batch("a.txt"), b = try f.batch("b.txt")
                f.model.reload(select: a.id); try f.settle(); f.model.copyContext()
                f.model.selectBatch(b.id); try f.settle(); try check(f.model.activeDelivery == nil)
                f.model.copyContext(); f.model.selectBatch(a.id); try f.settle()
                try check(f.model.activeDelivery?.batch.id == a.id)
                f.model.showHandoff(); try check(f.model.lastDelivery?.batch.id == a.id); f.model.dismissSheet()
                let other = try LibraryStore.create(at: f.root.appendingPathComponent("Other"))
                f.model.openLibrary(at: other.root); try f.settle(); try check(f.model.activeDelivery == nil)
                f.model.openLibrary(at: f.environment.libraryRoot); try f.settle()
                try check(f.model.selected?.id == a.id && f.model.activeDelivery?.batch.id == a.id)
            }),
            ("Assignment draft validation, cancellation and queued reception", { f in
                try f.start(); let source = try f.model.store!.createSource(name: "归档目标")
                let batch = try f.batch(); f.model.reload(select: batch.id); try f.settle()
                f.model.showAssignment(batch)
                guard case .assignment(let draft) = f.model.sheet else { throw TestFailure(description: "No assignment draft") }
                try check(!draft.canSubmit); draft.targetID = "unfiled"; try check(!draft.canSubmit)
                draft.targetID = source.id; try check(draft.canSubmit)
                let (queue, job) = try f.queue(); f.model.receive([try queue.signalURL()])
                try check(try queue.completion(job.id) == nil)
                f.model.dismissSheet(); try f.settle()
                try check(try f.model.store!.contents().batches.first { $0.id == batch.id }?.source == nil)
                try check(try f.model.store!.contents().batches.count == 2)
                try check(try queue.completion(job.id) != nil)
                f.model.showAssignment(batch)
                guard case .assignment(let active) = f.model.sheet else { throw TestFailure(description: "No assignment draft") }
                active.targetID = source.id; f.model.applyAssignment(active); try f.settle()
                try check(f.model.selected?.source?.id == source.id)
            }),
            ("Import default asks once and stale assignment cannot affect next reception", { f in
                try f.start(); f.model.chooseAssignAfterImport(true)
                let (queue, first) = try f.queue(); f.model.drainQueue(); try waitUntil { f.model.showingSheet }
                guard case .assignment(let draft) = f.model.sheet else { throw TestFailure(description: "No import assignment") }
                let second = try queue.begin()
                try "·虚构用户\n2026-11-14 12:00\n第二份分享".write(to: second.payload.appendingPathComponent("Chat History.txt"), atomically: true, encoding: .utf8)
                _ = try queue.publish(second); f.model.receive([try queue.signalURL()])
                try check(try f.model.store!.contents().batches.count == 1)
                f.model.dismissSheet(); try waitUntil { f.model.showingSheet && f.model.selected?.id != draft.batch.id }
                f.model.applyAssignment(draft)
                try check(try f.model.store!.contents().batches.count == 2 && f.model.showingSheet)
                try check(try queue.completion(first.id) != nil)
                f.model.dismissSheet(); try f.settle()
            }),
            ("Disconnect removes only registration and preserves queue payload", { f in
                try f.start(); let (queue, _) = try f.queue()
                let registration = try f.environment.intakeRegistry.registrations[0]
                let before = try LibraryIO.hashes(queue.root)
                try f.environment.intakeRegistry.remove(registration)
                try check(try f.environment.intakeRegistry.registrations.isEmpty)
                try check(try LibraryIO.hashes(queue.root) == before)
                f.model.drainQueue(); try f.settle(); try check(try f.model.store!.contents().batches.isEmpty)
                try f.environment.intakeRegistry.register(queue)
                let movedRoot = f.root.appendingPathComponent("MovedQueue")
                try FileManager.default.moveItem(at: queue.root, to: movedRoot)
                let moved = try IntakeQueue(at: movedRoot); try f.environment.intakeRegistry.register(moved)
                try f.environment.intakeRegistry.remove(registration)
                try check(try f.environment.intakeRegistry.registrations.count == 1)
                try check(try f.environment.intakeRegistry.registrations[0].path == movedRoot.path)
            }),
            ("Preference restore falls back only for invalid selections", { f in
                try f.start(); let source = try f.model.store!.createSource(name: "已记住来源")
                let batch = try f.batch(source: source); f.model.reload(); try f.settle()
                f.model.selectSource(source.id); try f.settle(); f.model.toggleSidebar(); f.model.chooseTranscriptMode(.source)
                let restarted = AppModel(environment: f.environment); restarted.start(); try waitUntil { restarted.idle }
                try check(restarted.selectedSource == source.id && restarted.selected?.id == batch.id)
                try check(restarted.sidebarCollapsed && restarted.transcriptMode == .source)
                try FileManager.default.removeItem(at: batch.workspace)
                let missing = AppModel(environment: f.environment); missing.start(); try waitUntil { missing.idle }
                try check(missing.selectedSource == source.id && missing.selected == nil)
            }),
            ("Attachment reveal rejects traversal and symlink paths", { f in
                var revealed: [URL] = []; f.environment.revealFiles = { revealed += $0 }
                try f.start(); let batch = try f.batch(); f.model.reload(select: batch.id); try f.settle()
                f.model.revealAttachment("../outside.txt", batchID: batch.id); try f.settle(); try check(revealed.isEmpty && f.model.statusTone == .error)
                let outside = try f.input("outside.txt")
                try FileManager.default.createSymbolicLink(at: batch.workspace.appendingPathComponent("escape.txt"), withDestinationURL: outside)
                f.model.revealAttachment("escape.txt", batchID: batch.id); try f.settle(); try check(revealed.isEmpty && f.model.statusTone == .error)
                f.model.revealAttachment("transcript.md", batchID: batch.id); try f.settle(); try check(revealed == [batch.workspace.appendingPathComponent("transcript.md")])
            }),
            ("Drag archive validates library identity and existing source", { f in
                try f.start(); let source = try f.model.store!.createSource(name: "拖放目标")
                let batch = try f.batch(); f.model.reload(select: batch.id); try f.settle()
                let token = f.model.dragToken(batch)
                try check(!f.model.assignDropped("arbitrary text", to: source.id))
                try check(!f.model.assignDropped(token, to: "foreign"))
                try check(f.model.assignDropped(token, to: source.id)); try f.settle()
                try check(f.model.selected?.source?.id == source.id)
                let other = try LibraryStore.create(at: f.root.appendingPathComponent("Other")); f.model.openLibrary(at: other.root); try f.settle()
                try check(!f.model.assignDropped(token, to: "unfiled"))
            }),
            ("Settings confirmations preserve drafts and clean template defaults only on confirmation", { f in
                var response = NSApplication.ModalResponse.alertFirstButtonReturn
                var observedParent: NSWindow?, alertText = ""
                f.environment.panels.alert = { alert, parent, done in observedParent = parent; alertText = alert.informativeText; done(response) }
                try f.start(); let source = try f.model.store!.createSource(name: "虚构默认来源")
                let sourceKey = TaskSettings.sourceKey(libraryID: f.model.store!.metadata.libraryID, sourceID: source.id)
                let template = TaskTemplate(id: UUID().uuidString, title: "虚构模板", instruction: "要求")
                var settings = TaskSettings(); settings.templates = [template]; settings.sourceDefaults[sourceKey] = "template:" + template.id
                try settings.save(at: f.environment.taskSettingsURL); f.model.taskSettings = settings
                let parent = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: true)
                f.model.settingsWindow = parent
                f.model.confirmDeleteTemplate(template)
                try check(observedParent === parent && alertText.contains("1 个来源") && f.model.taskSettings.templates.count == 1)
                response = .alertSecondButtonReturn; f.model.confirmDeleteTemplate(template); try f.settle()
                try check(f.model.taskSettings.templates.isEmpty && f.model.taskSettings.sourceDefaults.isEmpty)
                try check(try TaskSettings.load(at: f.environment.taskSettingsURL).templates.isEmpty)
                let draft = TaskEditorDraft(seed: AnalysisTask(action: .summary), key: TaskSettings.builtinKey(.summary), sourceKey: sourceKey, isDefault: true)
                try check(!draft.clearDefault); draft.makeDefault = false; try check(draft.clearDefault)
                draft.makeDefault = true; try check(!draft.clearDefault)
            }),
            ("Native menu actions share modal guards and truthful busy labels", { f in
                try f.start(); let batch = try f.batch(); f.model.reload(select: batch.id); try f.settle()
                let previous = NSApp.mainMenu; defer { NSApp.mainMenu = previous }
                let menus = AppMenus(model: f.model); menus.install()
                let items = NSApp.mainMenu!.items.flatMap { $0.submenu?.items ?? [] }
                let deliver = items.first { $0.representedObject as? String == "agent" }!
                let settings = items.first { $0.representedObject as? String == "settings" }!
                try check(deliver.keyEquivalent == "\r" && settings.keyEquivalent == ",")
                try check(items.contains { $0.action == NSSelectorFromString("performTextFinderAction:") && $0.keyEquivalent == "f" })
                f.model.showAssignment(batch)
                try check(!menus.validateMenuItem(deliver) && !menus.validateMenuItem(settings))
                let count = f.model.startedOperations; menus.invoke(deliver); try check(f.model.startedOperations == count)
                f.model.dismissSheet(); f.model.busy = true
                try check(f.model.deliveryButtonTitle == "交给 Codex" && !menus.validateMenuItem(deliver))
                f.model.deliveryPreparing = true; try check(f.model.deliveryButtonTitle == "正在准备…")
                f.model.busy = false; f.model.deliveryPreparing = false
            }),
            ("Main reading viewport meets minimum and initial window budgets", { f in
                try f.start(); let input = try f.input(text: (1...30).map { "·虚构用户\n2026-11-14 12:00\n第\($0)条单行消息。\n\n" }.joined())
                let batch = try f.model.store!.importData(from: input); f.model.reload(select: batch.id); try f.settle()
                @MainActor func findText(_ view: NSView) -> NSTextView? { if let text = view as? NSTextView { return text }; return view.subviews.compactMap { findText($0) }.first }
                for (size, expectedHeight) in [(NSSize(width: 960, height: 620), CGFloat(372)), (NSSize(width: 1180, height: 760), CGFloat(512))] {
                    let host = NSHostingView(rootView: MainWindowView(model: f.model)); host.sizingOptions = []
                    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .titled, backing: .buffered, defer: true)
                    window.contentView = host; window.setContentSize(size); host.layoutSubtreeIfNeeded()
                    try waitUntil { findText(host)?.enclosingScrollView?.bounds.height == expectedHeight }
                    let text = findText(host)!, manager = text.layoutManager!, container = text.textContainer!
                    manager.ensureLayout(for: container)
                    let first = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
                    let nextStart = (text.string as NSString).range(of: "虚构用户", options: [], range: NSRange(location: 5, length: text.string.utf16.count - 5)).location
                    let next = manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: nextStart), effectiveRange: nil)
                    try check(abs(next.minY - first.minY - 55) < 1, "Single-line message spacing: \(next.minY - first.minY)")
                    print("  measured \(Int(size.width))×\(Int(size.height)): reading height \(Int(expectedHeight)), message stride \(next.minY - first.minY)")
                    window.contentView = nil
                }
            }),
            ("Inline images downsample, respect orientation and reject unsafe or unsupported files", { f in
                try f.start(); let folder = try makeSyntheticImageExport(at: f.root)
                let landscape = try InlineImageLoader.load("synthetic-landscape.jpg", in: folder)
                try check(max(landscape.width, landscape.height) <= 1024 && landscape.width > landscape.height)
                let rotated = try InlineImageLoader.load("synthetic-rotated.jpg", in: folder)
                try check(rotated.height > rotated.width)
                let alpha = try InlineImageLoader.load("synthetic-alpha.png", in: folder)
                try check(alpha.alphaInfo != .none && alpha.alphaInfo != .noneSkipLast && alpha.alphaInfo != .noneSkipFirst)
                let link = folder.appendingPathComponent("escape.jpg")
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder.appendingPathComponent("synthetic-landscape.jpg"))
                let oversized = folder.appendingPathComponent("oversized.jpg")
                FileManager.default.createFile(atPath: oversized.path, contents: nil)
                let file = try FileHandle(forWritingTo: oversized); try file.truncate(atOffset: UInt64(InlineImageLoader.maximumFileSize + 1)); try file.close()
                for path in ["../outside.jpg", "/tmp/outside.jpg", "https://example.invalid/image.jpg", "escape.jpg", "oversized.jpg", "synthetic-corrupt.jpg", "synthetic-missing.jpg"] {
                    do { _ = try InlineImageLoader.load(path, in: folder); throw TestFailure(description: "Unsafe image accepted: " + path) }
                    catch is TestFailure { throw TestFailure(description: "Unsafe image accepted: " + path) }
                    catch { }
                }
            }),
            ("Visible image loading preserves source copy and releases offscreen bitmaps", { f in
                try f.start(); let folder = try makeSyntheticImageExport(at: f.root)
                let batch = try f.model.store!.importData(from: folder), payload = try PreviewLoader.load(batch)
                let rawFile = batch.workspace.appendingPathComponent("transcript.md"), raw = try Data(contentsOf: rawFile)
                let id = UUID()
                let host = NSHostingView(rootView: TranscriptTextView(text: payload.transcript, batchID: batch.id, reading: payload.reading, attachmentRoot: batch.workspace, loadID: id))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: .titled, backing: .buffered, defer: true)
                host.sizingOptions = []; window.contentView = host; window.setContentSize(NSSize(width: 640, height: 480)); host.layoutSubtreeIfNeeded()
                try waitUntil { nativeText(in: host) != nil }; let text = nativeText(in: host)!
                try waitUntil { imageCells(in: text).first?.0.preview != nil }
                let cells = imageCells(in: text)
                try check(cells.count == 5 && text.string.contains("synthetic-missing.jpg"))
                try check(cells[0].0.previewSize.width <= 420 && cells[0].0.previewSize.height <= 280)
                text.setSelectedRange(NSRange(location: 0, length: 4))
                host.rootView = TranscriptTextView(text: payload.transcript, batchID: batch.id, reading: payload.reading, attachmentRoot: batch.workspace, loadID: id)
                host.layoutSubtreeIfNeeded(); try check(text.selectedRange() == NSRange(location: 0, length: 4))
                text.scrollRangeToVisible(cells.last!.1)
                try waitUntil { cells.last!.0.issue != nil }
                try check(cells[0].0.preview == nil, "Offscreen bitmap was retained")
                host.rootView = TranscriptTextView(text: payload.transcript, batchID: batch.id, attachmentRoot: batch.workspace, loadID: id)
                host.layoutSubtreeIfNeeded(); try check(imageCells(in: text).isEmpty && text.string == payload.transcript)
                f.model.reload(select: batch.id); try f.settle(); f.model.copyContext()
                try check(f.copied.last?.contains("# 微信聊天记录") == true && !f.copied.last!.contains("\u{fffc}"))
                try check(try Data(contentsOf: rawFile) == raw)
                window.contentView = nil
            }),
            ("Late image decode cannot replace another batch with the same attachment name", { f in
                try f.start(); let folder = try makeSyntheticImageExport(at: f.root)
                let a = try f.model.store!.importData(from: folder), payload = try PreviewLoader.load(a)
                let one = ReadingDocument(messages: [payload.reading!.messages[1]], hasUnparsedText: false)
                let host = NSHostingView(rootView: TranscriptTextView(text: payload.transcript, batchID: "a", reading: one, attachmentRoot: folder, loadID: UUID()))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: .titled, backing: .buffered, defer: true)
                host.sizingOptions = []; window.contentView = host; window.setContentSize(NSSize(width: 640, height: 480)); host.layoutSubtreeIfNeeded(); let text = nativeText(in: host)!
                let coordinator = (text.delegate as! TranscriptTextView.Coordinator).images
                let started = DispatchSemaphore(value: 0)
                coordinator.decode = { _, root in
                    if root == folder { started.signal(); Thread.sleep(forTimeInterval: 0.35); return try InlineImageLoader.load("synthetic-landscape.jpg", in: folder) }
                    return try InlineImageLoader.load("synthetic-portrait.png", in: folder)
                }
                try waitUntil { started.wait(timeout: .now()) == .success }
                host.rootView = TranscriptTextView(text: "new", batchID: "b", reading: one, attachmentRoot: f.root, loadID: UUID())
                host.layoutSubtreeIfNeeded()
                try waitUntil { imageCells(in: text).first?.0.preview != nil }
                RunLoop.current.run(until: Date().addingTimeInterval(0.45))
                let cell = imageCells(in: text).first!.0
                try check(cell.previewSize.height > cell.previewSize.width, "Late old bitmap replaced current batch")
                window.contentView = nil
            }),
            ("Transcript selection, scroll and live appearance remain stable", { f in
                try f.start()
                let host = NSHostingView(rootView: TranscriptTextView(text: "中文选择复制\n第二行", batchID: "a"))
                host.frame = NSRect(x: 0, y: 0, width: 300, height: 180); host.layoutSubtreeIfNeeded()
                @MainActor func findText(_ view: NSView) -> NSTextView? { if let text = view as? NSTextView { return text }; return view.subviews.compactMap { findText($0) }.first }
                try waitUntil { findText(host) != nil }
                let text = findText(host)!; text.setSelectedRange(NSRange(location: 0, length: 2))
                host.rootView = TranscriptTextView(text: "中文选择复制\n第二行", batchID: "a"); host.layoutSubtreeIfNeeded()
                try check(text.selectedRange() == NSRange(location: 0, length: 2))
                host.rootView = TranscriptTextView(text: "中文选择复制\n第二行（更新）", batchID: "a"); host.layoutSubtreeIfNeeded()
                try check(text.selectedRange() == NSRange(location: 0, length: 2))
                host.rootView = TranscriptTextView(text: "另一个批次", batchID: "b"); host.layoutSubtreeIfNeeded()
                try check(text.selectedRange() == NSRange(location: 0, length: 0))
                let long = "另一个批次\n" + String(repeating: "虚构正文与原生滚动\n", count: 200)
                host.rootView = TranscriptTextView(text: long, batchID: "b"); host.layoutSubtreeIfNeeded()
                let scroll = text.enclosingScrollView!
                text.layoutManager?.ensureLayout(for: text.textContainer!)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: 180)); scroll.reflectScrolledClipView(scroll.contentView)
                try check(scroll.contentView.bounds.origin.y > 0)
                let origin = scroll.contentView.bounds.origin
                text.setSelectedRange(NSRange(location: 0, length: 2))
                host.rootView = TranscriptTextView(text: long + "更新", batchID: "b"); host.layoutSubtreeIfNeeded()
                try check(text.selectedRange() == NSRange(location: 0, length: 2) && scroll.contentView.bounds.origin == origin)
                host.appearance = NSAppearance(named: .darkAqua); host.layoutSubtreeIfNeeded()
                try waitUntil { (text.textColor?.usingColorSpace(.sRGB)?.redComponent ?? 0) > 0.8 }
                try check(text.selectedRange() == NSRange(location: 0, length: 2))
                host.appearance = NSAppearance(named: .aqua); host.layoutSubtreeIfNeeded()
                try waitUntil { (text.textColor?.usingColorSpace(.sRGB)?.redComponent ?? 1) < 0.2 }
                try check(text.selectedRange() == NSRange(location: 0, length: 2))
            })
        ]
        var failures = 0
        for (name, test) in tests {
            let fixture = try Fixture()
            do { try test(fixture); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
            fixture.close()
        }
        print("\(tests.count) app state tests; \(failures) failures")
        if failures > 0 { exit(1) }
    }
    @MainActor static func prepareHost(_ root: URL) throws {
        let defaults = UserDefaults(suiteName: "local.scofield.wechat2ai.ui-tests." + root.lastPathComponent)!
        let environment = AppEnvironment.isolated(at: root, defaults: defaults)
        guard !FileManager.default.fileExists(atPath: environment.libraryRoot.path) else { throw TestFailure(description: "Host must use a new empty root") }
        let store = try environment.librarySettings.load()
        if CommandLine.arguments.contains("--ui-empty") { print(root.path); return }
        let longContent = CommandLine.arguments.contains("--ui-long")
        let source = try store.createSource(name: longContent ? "虚构 · 产品讨论与资料归档体验研究群 · 长来源名称与同名区分验证" : "虚构 · 产品讨论群", note: "仅用于主题验收")
        if longContent { _ = try store.createSource(name: source.name, note: "虚构的同名来源，独立 ID") }

        let input = root.appendingPathComponent("synthetic.txt")
        for index in 1...(longContent ? 12 : 3) {
            try "·虚构用户甲\n2026-11-14 12:00\n第\(index)批：讨论导入流程与任务确认。\n\n·虚构用户乙\n2026-11-14 12:01\n所有示例均为虚构资料。".write(to: input, atomically: true, encoding: .utf8)
            let batch = try store.importData(from: input); _ = try store.assign(batchID: batch.id, to: source.id)
        }
        if longContent {
            let paragraph = "·虚构用户甲\n2026-11-14 12:00\n讨论如何保存原文、整理需求并明确交接范围。所有姓名和内容均为虚构。\n\n·虚构用户乙\n2026-11-14 12:01\n长链接：https://example.invalid/" + String(repeating: "synthetic-long-path-", count: 35) + "\n\n"
            try String(repeating: paragraph, count: 100).write(to: input, atomically: true, encoding: .utf8)
        }
        if CommandLine.arguments.contains("--ui-density") {
            try (1...30).map { "·虚构用户\($0 % 2 == 0 ? "乙" : "甲")\n2026-11-14 12:00\n第\($0)条虚构单行消息。\n\n" }.joined().write(to: input, atomically: true, encoding: .utf8)
        }
        let finalInput = CommandLine.arguments.contains("--ui-images") ? try makeSyntheticImageExport(at: root) : input
        _ = try store.importData(from: finalInput)
        if CommandLine.arguments.contains("--ui-settings") {
            var settings = TaskSettings()
            settings.templates = [TaskTemplate(id: UUID().uuidString.lowercased(), title: "虚构 · 每周需求归纳", instruction: "区分事实与推断。"), TaskTemplate(id: UUID().uuidString.lowercased(), title: "虚构 · 历史变化对比", instruction: "只对比选定的同来源参考。", action: .compare)]
            settings.sourceDefaults[TaskSettings.sourceKey(libraryID: store.metadata.libraryID, sourceID: source.id)] = "template:" + settings.templates[0].id
            try settings.save(at: environment.taskSettingsURL)
            let queue = try IntakeQueue.create(at: root.appendingPathComponent("SyntheticReceipts"))
            let draft = try queue.begin()
            try Data("虚构未完成接收".utf8).write(to: draft.payload.appendingPathComponent("synthetic.txt"))
            try environment.intakeRegistry.register(queue)
        }
        if CommandLine.arguments.contains("--ui-library-missing") { try FileManager.default.removeItem(at: store.root) }
        print(root.path)
    }
}
