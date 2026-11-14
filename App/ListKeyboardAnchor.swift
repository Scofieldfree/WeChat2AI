import SwiftUI

/// One native first responder per list avoids nested SwiftUI button focus changing selection.
@MainActor
final class ListKeyboardTarget: ObservableObject {
    @Published var hasFocus = false
    weak var view: ListKeyboardNativeView?
    func focus() { if let view { view.window?.makeFirstResponder(view) } }
}

struct ListKeyboardAnchor: NSViewRepresentable {
    let target: ListKeyboardTarget
    let move: (MoveCommandDirection) -> Void
    func makeNSView(context: Context) -> ListKeyboardNativeView {
        let view = ListKeyboardNativeView(); view.target = target; view.move = move
        view.focusRingType = .none; view.setAccessibilityElement(false); target.view = view
        return view
    }
    func updateNSView(_ view: ListKeyboardNativeView, context: Context) { view.move = move }
}

final class ListKeyboardNativeView: NSView {
    weak var target: ListKeyboardTarget?
    var move: ((MoveCommandDirection) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { target?.hasFocus = true; return true }
    override func resignFirstResponder() -> Bool { target?.hasFocus = false; return true }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: move?(.down)
        case 126: move?(.up)
        case 48:
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(nil) }
            else { window?.selectNextKeyView(nil) }
        default: super.keyDown(with: event)
        }
    }
}
