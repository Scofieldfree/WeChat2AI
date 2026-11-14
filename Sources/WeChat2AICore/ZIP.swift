import Foundation
import CZlib

/// Small, bounded ZIP reader. Supports ordinary stored/deflated ZIPs, including
/// data descriptors (sizes come from the central directory). Rejects ZIP64,
/// encryption, links, duplicate paths and traversal instead of guessing.
public enum SafeZIP {
    public static func extract(_ source: URL, to root: URL) throws {
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= SafeFiles.byteLimit else { throw CoreError.invalid("ZIP 超过 512 MB。") }
        let data = try Data(contentsOf: source)
        func number(_ offset: Int, _ width: Int) throws -> Int {
            guard offset >= 0, offset <= data.count - width else { throw CoreError.invalid("ZIP 结构损坏。") }
            return (0..<width).reduce(0) { $0 | (Int(data[offset+$1]) << ($1*8)) }
        }
        guard data.count >= 22 else { throw CoreError.invalid("不是有效的 ZIP 文件。") }
        var end: Int?
        for offset in stride(from: data.count-22, through: max(0, data.count-65_557), by: -1) {
            if try number(offset, 4) == 0x06054b50, offset + 22 + (try number(offset+20, 2)) == data.count { end = offset; break }
        }
        guard let end else { throw CoreError.invalid("ZIP 缺少目录。") }
        let count = try number(end+10, 2)
        guard try number(end+4, 2) == 0, try number(end+6, 2) == 0,
              try number(end+8, 2) == count, count < 65_535, count <= SafeFiles.fileLimit else {
            throw CoreError.invalid("不支持分卷、ZIP64 或过多文件。")
        }
        var cursor = try number(end+16, 4)
        let directoryEnd = cursor + (try number(end+12, 4))
        guard directoryEnd <= end else { throw CoreError.invalid("ZIP 目录越界。") }
        var total = 0
        var paths = Set<String>()
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for _ in 0..<count {
            guard try number(cursor, 4) == 0x02014b50 else { throw CoreError.invalid("ZIP 目录损坏。") }
            let flags = try number(cursor+8, 2), method = try number(cursor+10, 2)
            let checksum = try number(cursor+16, 4), compressed = try number(cursor+20, 4), expanded = try number(cursor+24, 4)
            let nameLength = try number(cursor+28, 2), extraLength = try number(cursor+30, 2), commentLength = try number(cursor+32, 2)
            let attributes = try number(cursor+38, 4), local = try number(cursor+42, 4)
            let next = cursor + 46 + nameLength + extraLength + commentLength
            guard next <= directoryEnd, nameLength > 0, flags & 1 == 0,
                  (method == 0 || method == 8), compressed < 0xffffffff, expanded < 0xffffffff,
                  local < 0xffffffff, (attributes >> 16) & 0xf000 != 0xa000 else {
                throw CoreError.invalid("ZIP 含加密、链接、ZIP64 或不支持的压缩格式。")
            }
            guard let name = String(data: data.subdata(in: cursor+46..<cursor+46+nameLength), encoding: .utf8),
                  !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0"),
                  !name.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
                  !name.split(separator: "/").contains("."), !name.contains(":") else {
                throw CoreError.invalid("ZIP 文件名不安全或不是 UTF-8。")
            }
            let directory = name.hasSuffix("/")
            let normalized = name.trimmingCharacters(in: CharacterSet(charactersIn: "/")).precomposedStringWithCanonicalMapping.lowercased()
            guard !normalized.isEmpty, paths.insert(normalized).inserted else { throw CoreError.invalid("ZIP 存在重复路径。") }
            total += expanded
            guard total <= SafeFiles.byteLimit else { throw CoreError.invalid("ZIP 解压后超过 512 MB。") }
            let mode = (attributes >> 16) & 0xf000
            guard mode == 0 || mode == 0x8000 || (directory && mode == 0x4000) else { throw CoreError.invalid("ZIP 含特殊文件。") }
            guard try number(local, 4) == 0x04034b50, try number(local+8, 2) == method else { throw CoreError.invalid("ZIP 本地记录损坏。") }
            let localName = try number(local+26, 2)
            let start = local + 30 + localName + (try number(local+28, 2))
            guard start <= data.count, compressed <= data.count-start, start+compressed <= (try number(end+16, 4)),
                  localName == nameLength,
                  data.subdata(in: local+30..<local+30+localName) == data.subdata(in: cursor+46..<cursor+46+nameLength) else {
                throw CoreError.invalid("ZIP 本地文件路径或内容越界。")
            }
            let target = root.appendingPathComponent(name)
            if directory {
                guard expanded == 0 else { throw CoreError.invalid("ZIP 目录含非法数据。") }
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                let payload = data.subdata(in: start..<start+compressed)
                let output = method == 0 ? payload : try inflateData(payload, expected: expanded)
                guard output.count == expanded else { throw CoreError.invalid("ZIP 文件大小不匹配。") }
                let crc = output.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(output.count)) }
                guard Int(crc) == checksum else { throw CoreError.invalid("ZIP 文件校验失败。") }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try output.write(to: target, options: .withoutOverwriting)
            }
            cursor = next
        }
        guard cursor == directoryEnd else { throw CoreError.invalid("ZIP 目录长度不匹配。") }
    }

    private static func inflateData(_ data: Data, expected: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw CoreError.invalid("无法初始化 ZIP 解压。") }
        defer { inflateEnd(&stream) }
        var output = Data(count: max(expected, 1))
        let outputCount = output.count
        let result = data.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { bytes -> Int32 in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(data.count)
                stream.next_out = bytes.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outputCount)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard result == Z_STREAM_END, stream.total_out == expected, stream.total_in == data.count else { throw CoreError.invalid("ZIP 压缩数据损坏或大小不匹配。") }
        output.count = expected
        return output
    }
}
