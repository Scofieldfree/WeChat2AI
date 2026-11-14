import AppKit

/// Every persistent path and external side effect is explicit in the isolated host/tests.
struct AppEnvironment {
    let defaults: UserDefaults
    let libraryRoot: URL
    let taskSettingsURL: URL
    let projectsRoot: URL
    let handoffRoot: URL
    var loadPreview: (LibraryBatch) throws -> PreviewPayload = PreviewLoader.load
    var panels = SystemPanels.live
    var applicationURL: (String) -> URL?
    var copyText: (String) -> Void
    var revealFiles: ([URL]) -> Void
    var openApplication: (DesktopLaunch, @escaping (Error?) -> Void) -> Void

    var librarySettings: LibrarySettings { LibrarySettings(defaults: defaults, defaultRoot: libraryRoot) }
    var intakeRegistry: IntakeRegistry { IntakeRegistry(defaults: defaults) }
    static var production: AppEnvironment {
        AppEnvironment(defaults: .standard, libraryRoot: LibraryStore.defaultRoot,
            taskSettingsURL: TaskSettings.defaultURL,
            projectsRoot: AgentWorkspace.projects,
            handoffRoot: HandoffPackage.defaultRoot,
            applicationURL: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
            copyText: { NSPasteboard.general.clearContents(); NSPasteboard.general.setString($0, forType: .string) },
            revealFiles: { NSWorkspace.shared.activateFileViewerSelecting($0) },
            openApplication: { launch, done in
                NSWorkspace.shared.open([launch.url], withApplicationAt: launch.application,
                    configuration: NSWorkspace.OpenConfiguration()) { _, error in done(error) }
            })
    }
    static func isolated(at root: URL, defaults: UserDefaults) -> AppEnvironment {
        var environment = AppEnvironment(defaults: defaults, libraryRoot: root.appendingPathComponent("Library"),
            taskSettingsURL: root.appendingPathComponent("task-settings.json"),
            projectsRoot: root.appendingPathComponent("Projects"),
            handoffRoot: root.appendingPathComponent("Handoffs"),
            applicationURL: { _ in nil }, copyText: { _ in }, revealFiles: { _ in },
            openApplication: { _, done in done(CoreError.invalid("隔离宿主不打开外部客户端。")) })
        environment.panels = .cancelled
        return environment
    }
}
