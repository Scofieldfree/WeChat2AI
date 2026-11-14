import AppKit
import SwiftUI
import Combine

@main
struct WeChat2AIApplication {
    @MainActor static func main() {
        if Bundle.main.bundleIdentifier == "local.scofield.wechat2ai.ui-test", !ProcessInfo.processInfo.arguments.contains("--ui-test-root") {
            FileHandle.standardError.write(Data("Isolated host requires --ui-test-root; refusing daily settings.\n".utf8)); return
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate; application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    let model: AppModel
    var menus: AppMenus?
    var observation: AnyCancellable?
    var pendingSettings = ProcessInfo.processInfo.arguments.contains("--ui-settings")
    override init() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--ui-test-root"), args.indices.contains(index + 1) {
            let root = URL(fileURLWithPath: args[index + 1], isDirectory: true)
            let defaults = UserDefaults(suiteName: "local.scofield.wechat2ai.ui-tests." + root.lastPathComponent)!
            var environment = AppEnvironment.isolated(at: root, defaults: defaults)
            environment.panels = .live
            model = AppModel(environment: environment)
        } else { model = AppModel() }
        super.init()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        menus = AppMenus(model: model); menus?.install()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: W2ATheme.Layout.initial.width, height: W2ATheme.Layout.initial.height), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = ProcessInfo.processInfo.arguments.contains("--ui-test-root") ? "WeChat2AI · 隔离验证（虚构资料）" : "WeChat2AI · 数据资料库"; window.contentMinSize = W2ATheme.Layout.minimum; window.isReleasedWhenClosed = false
        self.window = window; model.window = window
        let host = NSHostingView(rootView: MainWindowView(model: model))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(W2ATheme.Layout.initial)
        model.start()
        observation = Publishers.CombineLatest(model.$busy, model.$previewLoading).receive(on: RunLoop.main).sink { [weak self] _, _ in
            guard let self, self.pendingSettings, self.model.idle, self.model.store != nil else { return }
            self.pendingSettings = false; self.model.showSettings()
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-dark") { window.appearance = NSAppearance(named: .darkAqua) }
        if ProcessInfo.processInfo.arguments.contains("--ui-minimum") { window.setContentSize(W2ATheme.Layout.minimum) }
        if ProcessInfo.processInfo.arguments.contains("--ui-wide") { window.setContentSize(NSSize(width: 1440, height: 900)) }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.arguments.contains("--ui-test-root") {
            DispatchQueue.main.async {
                let size = window.contentView?.bounds.size ?? .zero
                FileHandle.standardOutput.write(Data("Isolated content size: \(Int(size.width)) × \(Int(size.height)) pt\n".utf8))
            }
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        model.receive(urls); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window?.makeKeyAndOrderFront(nil); return true }
    func applicationDidBecomeActive(_ notification: Notification) { if window != nil { model.refreshAgentAvailability(); model.drainQueue() } }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.busy || model.previewLoading { model.setStatus("请等待当前保存或交接完成后退出。", tone: .warning); return .terminateCancel }
        return .terminateNow
    }
}
