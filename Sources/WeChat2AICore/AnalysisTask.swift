import Foundation

public struct AnalysisTask: Codable {
    public let action: ChatAction
    public let title: String
    public let instruction: String
    public init(action: ChatAction, title: String? = nil, instruction: String? = nil) {
        self.action = action; self.title = title ?? action.title; self.instruction = instruction ?? action.instruction
    }
    public var needsContext: Bool { action == .compare || action == .conclusions }
    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 80, !title.contains(where: { $0.isNewline }),
              instruction.count <= 4000, action == .raw || !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoreError.invalid("任务名称须为 1–80 字，分析要求须为 1–4,000 字。")
        }
    }
}

public struct TaskTemplate: Codable {
    public let id: String
    public var title: String
    public var instruction: String
    public var action: ChatAction = .custom
}

public struct TaskSettings: Codable {
    public var schemaVersion = 1
    public var templates: [TaskTemplate] = []
    public var sourceDefaults: [String: String] = [:]
    public init() {}
    public static var defaultURL: URL { StoragePaths.taskSettings }
    public static func builtinKey(_ action: ChatAction) -> String { "builtin:\(action.rawValue)" }
    public static func sourceKey(libraryID: String, sourceID: String) -> String { libraryID + "/" + sourceID }
    public func resolve(_ key: String) throws -> AnalysisTask {
        if key.hasPrefix("builtin:"), let id = Int(key.dropFirst(8)), let action = ChatAction(rawValue: id) {
            return AnalysisTask(action: action)
        }
        guard let template = templates.first(where: { "template:" + $0.id == key }) else { throw CoreError.invalid("任务模板已不存在，请重新选择。") }
        return AnalysisTask(action: template.action, title: template.title, instruction: template.instruction)
    }
    /// Removes only the template and its explicit defaults; batch data is untouched.
    @discardableResult public mutating func removeTemplate(id: String) throws -> Int {
        try validate()
        guard templates.contains(where: { $0.id == id }) else { throw CoreError.invalid("任务模板已不存在。") }
        let key = "template:" + id
        let affected = sourceDefaults.values.filter { $0 == key }.count
        templates.removeAll { $0.id == id }
        sourceDefaults = sourceDefaults.filter { $0.value != key }
        try validate()
        return affected
    }
    public func validate() throws {
        guard schemaVersion == 1, templates.count <= 100, Set(templates.map(\.id)).count == templates.count else {
            throw CoreError.invalid("任务设置版本不支持或模板记录冲突。")
        }
        for template in templates {
            guard UUID(uuidString: template.id) != nil else { throw CoreError.invalid("任务模板 ID 无效。") }
            try AnalysisTask(action: template.action, title: template.title, instruction: template.instruction).validate()
        }
        for (source, key) in sourceDefaults {
            let parts = source.split(separator: "/")
            guard parts.count == 2, parts.allSatisfy({ UUID(uuidString: String($0)) != nil }), key != Self.builtinKey(.custom) else {
                throw CoreError.invalid("群默认任务关联无效。")
            }
            _ = try resolve(key)
        }
    }
    public static func load(at url: URL = defaultURL) throws -> TaskSettings {
        if !LibraryIO.fm.fileExists(atPath: url.path) {
            // Also reject dangling symlinks rather than replacing them.
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw CoreError.invalid("任务设置不能是符号链接。") }
            return TaskSettings()
        }
        let settings = try LibraryIO.read(TaskSettings.self, url); try settings.validate(); return settings
    }
    public func save(at url: URL = defaultURL) throws {
        try validate()
        _ = try Self.load(at: url)
        try LibraryIO.directory(url.deletingLastPathComponent())
        try LibraryIO.write(self, url)
    }
}

public struct AnalysisReference: Codable {
    public let kind: String
    public let batchID: String?
    public let relativePath: String
    public let label: String
}
public struct AnalysisTaskManifest: Codable {
    public var schemaVersion = 1
    public let task: AnalysisTask
    public let primaryBatchID: String
    public let references: [AnalysisReference]
    public let outputPolicy: String
}

public enum AnalysisContext {
    /// Snapshots only explicit references; never treats the whole project as selected context.
    static func attach(to handoff: HandoffResult, task: AnalysisTask, history: [LibraryBatch], resultFiles: [URL]) throws -> HandoffResult {
        try task.validate()
        guard history.count + resultFiles.count <= 20, task.needsContext || (history.isEmpty && resultFiles.isEmpty),
              task.action != .compare || !history.isEmpty, task.action == .conclusions || resultFiles.isEmpty else {
            throw CoreError.invalid("请选择有效分析范围：对比至少需要一批历史资料，参考资料合计最多 20 项。")
        }
        let fm = LibraryIO.fm, root = handoff.workspace, context = root.appendingPathComponent("context")
        try fm.createDirectory(at: context, withIntermediateDirectories: false)
        var references: [AnalysisReference] = []
        for batch in history {
            let copy = try HandoffPackage.create(workspace: batch.workspace, libraryID: handoff.metadata.libraryID,
                                                 source: batch.source, at: context.appendingPathComponent("history"))
            references.append(AnalysisReference(kind: "history-batch", batchID: batch.id,
                relativePath: try LibraryIO.relative(copy.workspace, to: root), label: batch.manifest.importedAt))
        }
        if !resultFiles.isEmpty {
            guard let project = handoff.project else { throw CoreError.invalid("请先将记录归入群，再选择群项目成果。") }
            let results = project.appendingPathComponent("results"); try LibraryIO.directory(results)
            let target = context.appendingPathComponent("results"); try fm.createDirectory(at: target, withIntermediateDirectories: false)
            for (index, url) in resultFiles.enumerated() {
                guard url.isFileURL, url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == results.standardizedFileURL.resolvingSymlinksInPath().path,
                      ["md", "txt"].contains(url.pathExtension.lowercased()) else { throw CoreError.invalid("请选择该群 results 目录中的 Markdown 或 TXT 成果。") }
                try LibraryIO.regular(url)
                guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max <= 20 * 1024 * 1024 else { throw CoreError.invalid("单份成果超过 20 MiB。") }
                let hash = try LibraryIO.hash(url), copy = target.appendingPathComponent("\(index)-" + url.lastPathComponent)
                try SafeFiles.copy(url, to: copy)
                guard try LibraryIO.hash(copy) == hash, try LibraryIO.hash(url) == hash else { throw CoreError.invalid("成果文件在复制时发生变化。") }
                references.append(AnalysisReference(kind: "result-file", batchID: nil,
                    relativePath: try LibraryIO.relative(copy, to: root), label: url.lastPathComponent))
            }
        }
        let manifest = AnalysisTaskManifest(task: task, primaryBatchID: handoff.metadata.batchID,
            references: references, outputPolicy: "reply-only; confirm with the user before writing project files")
        try LibraryIO.write(manifest, root.appendingPathComponent("task.json"))
        let inventory = try IntakeIO.inventory(root)
        let files = try LibraryIO.hashes(root, excluding: ["handoff.json"])
        let old = handoff.metadata
        let updated = HandoffMetadata(id: old.id, libraryID: old.libraryID, batchID: old.batchID,
            sourceID: old.sourceID, sourceName: old.sourceName, createdAt: old.createdAt,
            scope: references.isEmpty ? "single-batch" : "primary-with-selected-context", files: files,
            byteCount: inventory.filter { $0.key != "handoff.json" }.values.reduce(0) { $0 + Int64($1.size) })
        try LibraryIO.write(updated, root.appendingPathComponent("handoff.json"))
        return HandoffResult(workspace: root, metadata: updated, project: handoff.project)
    }
}
