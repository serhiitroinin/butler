import Foundation

/// The application data directory. A development run keeps its own directory so
/// a test never touches a real installation.
public enum ButlerPaths {
    public static var applicationSupport: URL {
        if let override = ProcessInfo.processInfo.environment["BUTLER_DATA_DIR"] {
            return URL(fileURLWithPath: override)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Butler", isDirectory: true)
    }

    public static var harnessStore: URL { applicationSupport.appendingPathComponent("harness-store") }
    public static var stateFile: URL { applicationSupport.appendingPathComponent("state.json") }

    /// A development build finds the sidecar next to the repository; a bundled
    /// build finds it inside its own Resources directory.
    public static func sidecarDirectory() -> URL? {
        if let override = ProcessInfo.processInfo.environment["BUTLER_SIDECAR_DIR"] {
            return URL(fileURLWithPath: override)
        }
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Sidecar")
        if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("host.mjs").path) {
            return bundled
        }
        var directory = Bundle.main.bundleURL
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent("Sidecar")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("host.mjs").path) {
                return candidate
            }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }
}

@MainActor
public final class ButlerStore: ObservableObject {
    @Published public private(set) var folders: [ManagedFolder] = []
    @Published public var settings = ButlerSettings() { didSet { save() } }

    private let file: URL

    public init(file: URL = ButlerPaths.stateFile) {
        self.file = file
        load()
    }

    public func folder(_ id: UUID) -> ManagedFolder? {
        folders.first { $0.id == id }
    }

    @discardableResult
    public func addFolder(at url: URL) -> ManagedFolder {
        let path = url.standardizedFileURL.path
        if let existing = folders.first(where: { $0.path == path }) { return existing }
        let folder = ManagedFolder(path: path, rules: settings.defaultRules, choice: settings.choice)
        folders.append(folder)
        save()
        return folder
    }

    public func removeFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        save()
    }

    public func update(_ id: UUID, _ change: (inout ManagedFolder) -> Void) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        change(&folders[index])
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(ButlerState.self, from: data) else { return }
        folders = state.folders
        settings = state.settings
    }

    private func save() {
        let state = ButlerState(settings: settings, folders: folders)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: file, options: .atomic)
    }
}
