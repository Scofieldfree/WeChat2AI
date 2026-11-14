import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Decode only bounded local raster images; never ask a web view or URL loader to render chat content.
enum InlineImageLoader {
    static let maximumFileSize = 32 * 1024 * 1024
    static func load(_ path: String, in root: URL) throws -> CGImage {
        let url = try LibraryIO.child(path, of: root)
        try LibraryIO.regular(url)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size > 0, size <= maximumFileSize else { throw CoreError.invalid("图片超过 32 MiB，点击文件名查看原件。") }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        let data = try file.read(upToCount: maximumFileSize + 1) ?? Data()
        guard data.count <= maximumFileSize,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier), type.conforms(to: .image), type != .svg,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= 100_000_000 else {
            throw CoreError.invalid("图片格式不支持、已损坏或像素过大，点击文件名查看原件。")
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw CoreError.invalid("图片无法预览，点击文件名查看原件。") }
        return image
    }
}

final class InlineImageCell: NSTextAttachmentCell {
    let path: String
    let messageIndex: Int
    var preview: NSImage?
    var issue: String?
    var previewSize = NSSize(width: 320, height: 160)
    init(path: String, index: Int) {
        self.path = path; messageIndex = index
        super.init(imageCell: nil)
    }
    required init(coder: NSCoder) { path = ""; messageIndex = 0; super.init(coder: coder) }
    override func cellSize() -> NSSize { previewSize }
    override func draw(withFrame frame: NSRect, in view: NSView?) {
        if let preview {
            preview.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
            let label = issue ?? "正在加载图片…"
            let rect = frame.insetBy(dx: 12, dy: 12)
            W2ATheme.Colors.surface.setFill(); NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).fill()
            (label as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: W2ATheme.Colors.secondaryText, .paragraphStyle: paragraph])
        }
    }
    static func size(for image: NSImage) -> NSSize {
        let ratio = min(1, min(420 / max(1, image.size.width), 280 / max(1, image.size.height)))
        return NSSize(width: max(1, floor(image.size.width * ratio)), height: max(1, floor(image.size.height * ratio)))
    }
}

private final class CachedInlineImage: NSObject {
    let image: NSImage
    init(_ cgImage: CGImage) { image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)) }
}

/// One viewport plus a small prefetch margin. Offscreen cells release their bitmap while retaining layout.
@MainActor
final class InlineImageCoordinator {
    private weak var view: NSTextView?
    private var root: URL?
    private var loadID: UUID?
    private var batchID: String?
    private var reading = false
    private var generation = UUID()
    private var cells: [(InlineImageCell, NSRange)] = []
    private let cache = NSCache<NSString, CachedInlineImage>()
    private var loading = Set<String>()
    private var operations: [String: Operation] = [:]
    private var failures: [String: String] = [:]
    private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 2; q.qualityOfService = .userInitiated; return q }()
    private var observer: NSObjectProtocol?
    private var pending: DispatchWorkItem?
    var decode: (String, URL) throws -> CGImage = InlineImageLoader.load
    init() { cache.totalCostLimit = 24 * 1024 * 1024 }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) }; pending?.cancel(); queue.cancelAllOperations() }

    func configure(view: NSTextView, root: URL?, batchID: String?, loadID: UUID?, reading: Bool) {
        if self.root != root || self.batchID != batchID || self.loadID != loadID {
            generation = UUID(); queue.cancelAllOperations(); operations.removeAll(); loading.removeAll(); failures.removeAll(); cache.removeAllObjects()
            for (cell, _) in cells { cell.preview = nil; cell.issue = nil }
        }
        self.root = root; self.batchID = batchID; self.loadID = loadID; self.reading = reading; self.view = view
        if observer == nil, let clip = view.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.schedule() }
            }
        }
    }
    func rendered() {
        cells.removeAll()
        if reading, root != nil, let storage = view?.textStorage {
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if let cell = (value as? NSTextAttachment)?.attachmentCell as? InlineImageCell { cells.append((cell, range)) }
            }
        }
        schedule()
    }
    func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateVisible() }; pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }
    func updateVisible() {
        guard reading, let root, let view, let manager = view.layoutManager, let container = view.textContainer,
              let storage = view.textStorage, storage.length > 0 else { return }
        let rect = view.visibleRect.insetBy(dx: 0, dy: -280).offsetBy(dx: -view.textContainerInset.width, dy: -view.textContainerInset.height)
        let glyphs = manager.glyphRange(forBoundingRect: rect, in: container)
        let visible = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let wanted = Set(cells.filter { NSIntersectionRange($0.1, visible).length > 0 }.map { $0.0.path })
        for (path, operation) in operations where !wanted.contains(path) && !operation.isExecuting {
            operation.cancel(); loading.remove(path); operations.removeValue(forKey: path)
        }
        var resized = false
        let scroll = view.enclosingScrollView, origin = scroll?.contentView.bounds.origin ?? .zero
        let anchorGlyphs = manager.glyphRange(forBoundingRect: view.visibleRect.offsetBy(dx: -view.textContainerInset.width, dy: -view.textContainerInset.height), in: container)
        let anchor = anchorGlyphs.location < manager.numberOfGlyphs ? manager.characterIndexForGlyph(at: anchorGlyphs.location) : 0
        let before = anchorGlyphs.location < manager.numberOfGlyphs ? manager.lineFragmentRect(forGlyphAt: anchorGlyphs.location, effectiveRange: nil).minY : 0
        for (cell, range) in cells {
            guard NSIntersectionRange(range, visible).length > 0 else { cell.preview = nil; continue }
            if let cached = cache.object(forKey: cell.path as NSString) {
                cell.preview = cached.image; cell.issue = nil
                let size = InlineImageCell.size(for: cached.image)
                if cell.previewSize != size { cell.previewSize = size; resized = true }
            } else if let failure = failures[cell.path] {
                cell.issue = failure
                if cell.previewSize.height != 48 { cell.previewSize = NSSize(width: 420, height: 48); resized = true }
            } else if !loading.contains(cell.path) {
                loading.insert(cell.path)
                let request = generation, path = cell.path, decode = self.decode
                let operation = BlockOperation { [weak self] in
                    let result = Result { try decode(path, root) }
                    DispatchQueue.main.async {
                        guard let self, self.generation == request else { return }
                        self.loading.remove(path); self.operations.removeValue(forKey: path)
                        switch result {
                        case .success(let cgImage): self.cache.setObject(CachedInlineImage(cgImage), forKey: path as NSString, cost: cgImage.bytesPerRow * cgImage.height)
                        case .failure(let error): self.failures[path] = error.localizedDescription
                        }
                        self.updateVisible()
                    }
                }
                operations[path] = operation; queue.addOperation(operation)
            }
        }
        if resized {
            manager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
            manager.ensureLayout(for: container)
            if let scroll, anchor < storage.length {
                let glyph = manager.glyphIndexForCharacter(at: anchor)
                let after = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
                scroll.contentView.scroll(to: NSPoint(x: origin.x, y: max(0, origin.y + after - before)))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            schedule()
        }
        manager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: storage.length)); view.needsDisplay = true
    }
}
