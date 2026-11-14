import Foundation

struct IntakeRegistration: Codable, Identifiable, Equatable {
    var id: String { queueID + "@" + path }
    let path: String
    let queueID: String
}
struct IntakeRegistry {
    let defaults: UserDefaults
    private let key = "intakeQueues.v1"
    var registrations: [IntakeRegistration] {
        get throws {
            guard let data = defaults.data(forKey: key) else { return [] }
            return try JSONDecoder().decode([IntakeRegistration].self, from: data)
        }
    }
    func register(_ queue: IntakeQueue) throws {
        var values = try registrations
        if let previous = values.first(where: { $0.path == queue.root.path }), previous.queueID != queue.metadata.queueID {
            throw CoreError.invalid("此位置的接收队列已被替换，请保留原任务并选择其他位置。")
        }
        // Explicit registration can reconnect a moved queue with the same identity.
        values.removeAll { $0.queueID == queue.metadata.queueID }
        values.append(IntakeRegistration(path: queue.root.path, queueID: queue.metadata.queueID))
        defaults.set(try JSONEncoder().encode(values), forKey: key)
    }
    /// Disconnect this exact registration only; never delete queue files or extension bookmarks.
    func remove(_ registration: IntakeRegistration) throws {
        var values = try registrations
        values.removeAll { $0 == registration }
        defaults.set(try JSONEncoder().encode(values), forKey: key)
    }
    func queues() -> (values: [IntakeQueue], errors: [String]) {
        var queues: [IntakeQueue] = [], errors: [String] = []
        do {
            for entry in try registrations {
                do {
                    let queue = try IntakeQueue(at: URL(fileURLWithPath: entry.path))
                    guard queue.metadata.queueID == entry.queueID else { throw CoreError.invalid("接收目录身份发生变化。") }
                    queues.append(queue)
                } catch { errors.append("\(entry.path)：\(error.localizedDescription)") }
            }
        } catch { errors.append("接收目录设置无法读取：\(error.localizedDescription)") }
        return (queues, errors)
    }
    func candidate(for url: URL) throws -> IntakeQueue? {
        let file = url.standardizedFileURL
        let root: URL
        if file.lastPathComponent == ".intake.w2adrop" {
            root = file.deletingLastPathComponent()
            let queue = try IntakeQueue(at: root)
            let link = try IntakeIO.read(IntakeQueueMetadata.self, at: IntakeIO.child(".intake.w2adrop/queue-link.json", in: queue.root))
            guard link.schemaVersion == 1, link.queueID == queue.metadata.queueID else { throw CoreError.invalid("接收通知包身份不一致。") }
        } else {
            guard file.lastPathComponent == "payload.w2adrop", IntakeIO.validID(file.deletingLastPathComponent().lastPathComponent) else { return nil }
            let state = file.deletingLastPathComponent().deletingLastPathComponent()
            guard ["ready", "processing", "failed"].contains(state.lastPathComponent) else { return nil }
            root = state.deletingLastPathComponent()
        }
        let known = try registrations.contains { $0.path == root.path }
        guard known || FileManager.default.fileExists(atPath: root.appendingPathComponent("queue.json").path) else { return nil }
        let queue = try IntakeQueue(at: root)
        if let entry = try registrations.first(where: { $0.path == root.path }), entry.queueID != queue.metadata.queueID {
            throw CoreError.invalid("接收队列身份变化，未导入或清理。")
        }
        return queue
    }
    func isRegistered(_ queue: IntakeQueue) throws -> Bool {
        try registrations.contains { $0.path == queue.root.path && $0.queueID == queue.metadata.queueID }
    }
}
