import Foundation

struct LibrarySettings {
    let defaults: UserDefaults
    let defaultRoot: URL
    private let key = "currentLibraryPath"
    var currentURL: URL? {
        defaults.string(forKey: key).map { URL(fileURLWithPath: $0) }
    }

    func load() throws -> LibraryStore {
        if let location = currentURL { let store = try LibraryStore.open(at: location); save(store); return store }
        let location = defaultRoot
        // Only first setup may create the default library. A saved, missing path is never recreated.
        let fm = FileManager.default
        try fm.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = fm.fileExists(atPath: location.path) ? try LibraryStore.open(at: location) : try LibraryStore.create(at: location)
        save(store)
        return store
    }

    var intakeTarget: IntakeTarget? {
        guard let path = currentURL?.path, let id = defaults.string(forKey: "currentLibraryID") else { return nil }
        return IntakeTarget(libraryID: id, path: path)
    }
    func save(_ store: LibraryStore) {
        defaults.set(store.root.path, forKey: key)
        defaults.set(store.metadata.libraryID, forKey: "currentLibraryID")
    }
}
