import AppKit

// Presentation-only preferences. Existing library/queue/Agent keys remain unchanged.
enum TranscriptMode: String, CaseIterable { case reading, source
    var title: String { self == .reading ? "阅读" : "原文" }
}
struct LibrarySelection: Codable { var sourceID: String; var batchID: String? }

enum DisplayFormat {
    static let iso = ISO8601DateFormatter()
    static let full: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"; return f }()
    static let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    static let sameYear: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; return f }()
    static let otherYear: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f }()
    static func imported(_ value: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date = iso.date(from: value) else { return value }
        if calendar.isDate(date, inSameDayAs: now) { return "今天 " + clock.string(from: date) }
        return (calendar.component(.year, from: date) == calendar.component(.year, from: now) ? sameYear : otherYear).string(from: date)
    }
    // Source timestamps are wall-clock strings: do not run them through a timezone conversion.
    static func chatRange(_ m: ImportManifest) -> String {
        guard let first = m.firstTimestampOriginal ?? m.firstTimestamp, let last = m.lastTimestampOriginal ?? m.lastTimestamp else { return "未识别聊天时间" }
        func parts(_ value: String) -> [Int]? {
            let normalized = value.replacingOccurrences(of: "年", with: "-").replacingOccurrences(of: "月", with: "-").replacingOccurrences(of: "日", with: " ").replacingOccurrences(of: "T", with: " ")
            let pattern = #"^(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})"#
            guard let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) else { return nil }
            let values = (1...5).compactMap { Range(match.range(at: $0), in: normalized).flatMap { Int(normalized[$0]) } }
            return values.count == 5 ? values : nil
        }
        guard let a = parts(first), let b = parts(last) else { return "聊天 " + first + (first == last ? "" : " – " + last) }
        func short(_ values: [Int], includeYear: Bool) -> String {
            (includeYear ? String(format: "%04d-", values[0]) : "") + String(format: "%02d-%02d %02d:%02d", values[1], values[2], values[3], values[4])
        }
        let includeYear = a[0] != b[0], start = short(a, includeYear: includeYear)
        if a == b { return "聊天 " + start }
        return "聊天 " + start + " – " + (Array(a.prefix(3)) == Array(b.prefix(3)) ? String(format: "%02d:%02d", b[3], b[4]) : short(b, includeYear: includeYear))
    }
}

struct ReadingDocument: Equatable { let messages: [Message]; let hasUnparsedText: Bool }
struct PreviewPayload { let transcript: String; let reading: ReadingDocument?; let fallback: String? }
enum PreviewLoader {
    static func load(_ batch: LibraryBatch) throws -> PreviewPayload {
        let rawURL = try LibraryIO.child("transcript.md", of: batch.workspace)
        try LibraryIO.regular(rawURL)
        let raw = try String(contentsOf: rawURL, encoding: .utf8)
        guard batch.manifest.parseStatus != "raw-fallback", batch.manifest.messageCount > 0 else {
            return PreviewPayload(transcript: raw, reading: nil, fallback: "未识别到可排版的消息，已显示原文。")
        }
        do {
            let file = try LibraryIO.child("messages.jsonl", of: batch.workspace)
            try LibraryIO.regular(file)
            guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 64 * 1024 * 1024 else { throw CoreError.invalid("消息文件过大。") }
            let data = try Data(contentsOf: file)
            let messages = try data.split(separator: 10).map { try JSONDecoder().decode(Message.self, from: Data($0)) }
            guard messages.count == batch.manifest.messageCount, !messages.isEmpty else { throw CoreError.invalid("消息数量与清单不一致。") }
            return PreviewPayload(transcript: raw, reading: ReadingDocument(messages: messages,
                hasUnparsedText: batch.manifest.warnings.contains { $0.contains("未解析") }), fallback: nil)
        } catch { return PreviewPayload(transcript: raw, reading: nil, fallback: "阅读数据无法读取，已显示原文：" + error.localizedDescription) }
    }
}
