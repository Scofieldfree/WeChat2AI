import SwiftUI

/// Both display modes use one native text view; copy-for-AI always uses the model's raw Markdown.
struct TranscriptTextView: NSViewRepresentable {
    let text: String
    let batchID: String?
    var reading: ReadingDocument? = nil
    var attachmentRoot: URL? = nil
    var loadID: UUID? = nil
    var onAttachment: ((String) -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        let images = InlineImageCoordinator()
        var batchID: String?; var initialized = false; var source = ""; var reading: ReadingDocument?
        var onAttachment: ((String) -> Void)?
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let token = link as? String, token.hasPrefix("w2a-file:"), let index = Int(token.dropFirst(9)),
                let message = reading?.messages.first(where: { $0.index == index }), let path = message.attachmentPath else { return true }
            onAttachment?(path); return true // Never let untrusted message content open a URL.
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = W2ATranscriptScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let view = W2ATranscriptNativeView()
        view.isEditable = false; view.isSelectable = true; view.isRichText = true
        view.font = W2ATheme.TypeStyle.nativeBody; view.delegate = context.coordinator
        view.usesFindBar = true; view.isIncrementalSearchingEnabled = true
        view.textContainerInset = NSSize(width: W2ATheme.Space.panel, height: W2ATheme.Space.lg)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.setAccessibilityLabel("聊天正文预览，可选择、复制与全选")
        view.onRender = { [weak coordinator = context.coordinator] in coordinator?.images.rendered() }
        scroll.documentView = view
        return scroll
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 0,
            height: proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? 120)
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? W2ATranscriptNativeView else { return }
        scroll.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let coordinator = context.coordinator
        view.attachmentRoot = attachmentRoot
        coordinator.images.configure(view: view, root: attachmentRoot, batchID: batchID, loadID: loadID, reading: reading != nil)
        let changedBatch = !coordinator.initialized || coordinator.batchID != batchID
        let changedMode = (coordinator.reading == nil) != (reading == nil)
        let changed = coordinator.reading != reading || (reading == nil && coordinator.source != text)
        let origin = scroll.contentView.bounds.origin, selection = view.selectedRange()
        if changed || !coordinator.initialized {
            view.reading = reading
            if reading == nil {
                view.string = text
                let style = NSMutableParagraphStyle()
                style.minimumLineHeight = 23; style.maximumLineHeight = 23; style.paragraphSpacing = 8
                view.textStorage?.setAttributes([.font: W2ATheme.TypeStyle.nativeBody, .paragraphStyle: style], range: NSRange(location: 0, length: view.string.utf16.count))
            }
            view.applyTheme()
            if !changedBatch && !changedMode {
                let location = min(selection.location, view.string.utf16.count)
                view.setSelectedRange(NSRange(location: location, length: min(selection.length, view.string.utf16.count - location)))
                scroll.contentView.scroll(to: origin); scroll.reflectScrolledClipView(scroll.contentView)
            }
        } else { view.applyTheme() }
        if changedBatch || changedMode { view.setSelectedRange(NSRange(location: 0, length: 0)); view.scrollToBeginningOfDocument(nil) }
        coordinator.batchID = batchID; coordinator.source = text; coordinator.reading = reading
        coordinator.onAttachment = onAttachment; coordinator.initialized = true
        coordinator.images.rendered()
    }
}

enum ReadingRenderer {
    static func attributed(_ document: ReadingDocument, appearance: NSAppearance, includeImages: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        appearance.performAsCurrentDrawingAppearance {
            let primary = W2ATheme.Colors.primaryText.usingColorSpace(.sRGB) ?? W2ATheme.Colors.primaryText
            let secondary = W2ATheme.Colors.secondaryText.usingColorSpace(.sRGB) ?? W2ATheme.Colors.secondaryText
            func paragraph(_ height: CGFloat, after: CGFloat) -> NSParagraphStyle {
                let p = NSMutableParagraphStyle(); p.minimumLineHeight = height; p.maximumLineHeight = height; p.paragraphSpacing = after; return p
            }
            for message in document.messages {
                result.append(NSAttributedString(string: message.sender + "  ", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: primary, .paragraphStyle: paragraph(18, after: 0)]))
                result.append(NSAttributedString(string: (message.sourceTimestamp ?? message.timestamp) + "\n", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: secondary, .paragraphStyle: paragraph(18, after: 0)]))
                if let name = message.attachmentName {
                    let available = message.attachmentPath != nil
                    let marker = available ? (message.kind == "image" ? "▧ " : "▤ ") : "⚠ 附件缺失 · "
                    var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondary, .paragraphStyle: paragraph(23, after: 14)]
                    if available { attributes[.link] = "w2a-file:\(message.index)"; attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                    let imagePath = includeImages && message.kind == "image" ? message.attachmentPath : nil
                    if imagePath != nil { attributes[.paragraphStyle] = paragraph(23, after: 4) }
                    result.append(NSAttributedString(string: marker + name + "\n", attributes: attributes))
                    if let path = imagePath {
                        let attachment = NSTextAttachment()
                        attachment.attachmentCell = InlineImageCell(path: path, index: message.index)
                        let imageLine = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
                        imageLine.append(NSAttributedString(string: "\n"))
                        imageLine.addAttribute(.paragraphStyle, value: paragraph(0, after: 14), range: NSRange(location: 0, length: imageLine.length))
                        result.append(imageLine)
                    }
                } else {
                    result.append(NSAttributedString(string: message.body + "\n", attributes: [.font: W2ATheme.TypeStyle.nativeBody, .foregroundColor: primary, .paragraphStyle: paragraph(23, after: 14)]))
                }
            }
        }
        return result
    }
}

private final class W2ATranscriptNativeView: NSTextView {
    var reading: ReadingDocument?
    var attachmentRoot: URL?
    var onRender: (() -> Void)?
    private var renderedRoot: URL?
    private var renderedAppearance: String?
    private var renderedDocument: ReadingDocument?
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); applyTheme() }
    func applyTheme() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            backgroundColor = W2ATheme.Colors.canvas.usingColorSpace(.sRGB) ?? W2ATheme.Colors.canvas
            enclosingScrollView?.backgroundColor = backgroundColor
            if let reading {
                let name = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue
                if renderedDocument != reading || renderedAppearance != name || renderedRoot != attachmentRoot {
                    let selection = selectedRange(), origin = enclosingScrollView?.contentView.bounds.origin
                    textStorage?.setAttributedString(ReadingRenderer.attributed(reading, appearance: effectiveAppearance, includeImages: attachmentRoot != nil))
                    setSelectedRange(NSRange(location: min(selection.location, string.utf16.count), length: min(selection.length, max(0, string.utf16.count - selection.location))))
                    if let origin, let scroll = enclosingScrollView { scroll.contentView.scroll(to: origin); scroll.reflectScrolledClipView(scroll.contentView) }
                    renderedDocument = reading; renderedAppearance = name; renderedRoot = attachmentRoot
                    onRender?()
                }
                linkTextAttributes = [.foregroundColor: W2ATheme.Colors.primaryText, .underlineStyle: NSUnderlineStyle.single.rawValue]
            } else {
                renderedDocument = nil; renderedAppearance = nil
                textColor = W2ATheme.Colors.primaryText.usingColorSpace(.sRGB)
            }
        }
    }
}

private final class W2ATranscriptScrollView: NSScrollView {
    private var reportedSize: NSSize = .zero
    override func tile() {
        super.tile()
        guard let text = documentView as? NSTextView else { return }
        let inset = max(W2ATheme.Space.panel, (contentSize.width - W2ATheme.Layout.readingWidth) / 2)
        let next = NSSize(width: inset, height: W2ATheme.Space.lg)
        if text.textContainerInset != next { text.textContainerInset = next }
        if ProcessInfo.processInfo.arguments.contains("--ui-test-root"), bounds.size != reportedSize {
            reportedSize = bounds.size
            FileHandle.standardOutput.write(Data("Reading viewport: \(Int(bounds.width)) × \(Int(bounds.height)) pt\n".utf8))
        }
    }
}
