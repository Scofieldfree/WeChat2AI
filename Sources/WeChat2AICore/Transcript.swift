import Foundation

public struct Message: Codable, Equatable {
    public var index: Int
    public var sender: String
    /// Wall-clock time from the source. The export does not declare a timezone.
    public var timestamp: String
    public var body: String
    public var kind: String
    public var attachmentName: String?
    public var attachmentPath: String?
    /// Exact source time text preserves minute-only precision; when available in the source.
    public var sourceTimestamp: String? = nil
}

public struct ParsedTranscript {
    public var messages: [Message]
    public var warnings: [String]
    public var unparsedPrefix: String
}

public enum TranscriptParser {
    public static func parse(_ input: String) -> ParsedTranscript {
        let text = input.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
        let pattern = #"(?m)^·([^\n]+)\n(\d{4}(?:-|年)\d{1,2}(?:-|月)\d{1,2}日? [0-2]?\d:[0-5]\d(?::[0-5]\d)?)[ \t]*(?:\n|$)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        let headers = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).filter {
            normalizedDate(ns.substring(with: $0.range(at: 2))) != nil
        }
        guard !headers.isEmpty else {
            return ParsedTranscript(messages: [], warnings: ["未识别到消息边界，已保留完整原文。"], unparsedPrefix: text)
        }
        let prefix = ns.substring(to: headers[0].range.location).trimmingCharacters(in: .whitespacesAndNewlines)
        var warnings = prefix.isEmpty ? [] : ["消息之前存在未解析文字，请查看原文。"]
        let media = try! NSRegularExpression(pattern: #"^\[(Photo|Image|图片|Video|视频|File|文件)\]\s+(.+)$"#, options: .caseInsensitive)
        var messages: [Message] = []
        for (i, header) in headers.enumerated() {
            let start = NSMaxRange(header.range)
            let end = i + 1 < headers.count ? headers[i + 1].range.location : ns.length
            let body = ns.substring(with: NSRange(location: start, length: end-start)).trimmingCharacters(in: .newlines)
            var kind = "text"
            var name: String?
            if let match = media.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length)) {
                let label = (body as NSString).substring(with: match.range(at: 1)).lowercased()
                kind = ["photo", "image", "图片"].contains(label) ? "image" : (["video", "视频"].contains(label) ? "video" : "file")
                name = (body as NSString).substring(with: match.range(at: 2))
            }
            messages.append(Message(index: i+1, sender: ns.substring(with: header.range(at: 1)),
                timestamp: normalizedDate(ns.substring(with: header.range(at: 2)))!, body: body,
                kind: kind, attachmentName: name, attachmentPath: nil, sourceTimestamp: ns.substring(with: header.range(at: 2))))
        }
        if messages.contains(where: { $0.body.isEmpty }) { warnings.append("存在空消息，请与原文核对。") }
        return ParsedTranscript(messages: messages, warnings: warnings, unparsedPrefix: prefix)
    }

    private static func normalizedDate(_ value: String) -> String? {
        let parts = value.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }.compactMap(Int.init)
        guard parts.count == 5 || parts.count == 6 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4], second: parts.count == 6 ? parts[5] : 0)
        guard let date = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.year,.month,.day,.hour,.minute,.second], from: date)
        guard check.year == components.year, check.month == components.month, check.day == components.day,
              check.hour == components.hour, check.minute == components.minute, check.second == components.second else { return nil }
        return String(format: "%04d-%02d-%02d %02d:%02d:%02d", parts[0],parts[1],parts[2],parts[3],parts[4],parts.count == 6 ? parts[5] : 0)
    }
}
