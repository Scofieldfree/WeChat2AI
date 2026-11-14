import Foundation

/// Product locations for application data, libraries and CLI imports.
public enum StoragePaths {
    public static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WeChat2AI", isDirectory: true)
    }
    public static var library: URL { applicationSupport.appendingPathComponent("Library", isDirectory: true) }
    public static var imports: URL { applicationSupport.appendingPathComponent("Imports", isDirectory: true) }
    public static var taskSettings: URL { applicationSupport.appendingPathComponent("task-settings.json") }
}
