import ButlerCore
import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    let store = ButlerStore()
    let service = HarnessService()
    @Published var selection: SidebarItem?
    /// The folder the window is about, whichever page is shown.
    @Published private(set) var lastFolder: UUID?
    private var pages: [UUID: FolderViewModel] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init() {
        selection = store.folders.first.map { .folder($0.id) }
        lastFolder = store.folders.first?.id
        if lastFolder != nil {
            switch LaunchOptions.page {
            case "rules": selection = .rules
            case "history": selection = .history
            default: break
            }
        }
        for child in [store.objectWillChange, service.objectWillChange] {
            child.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        }
    }

    func page(for id: UUID) -> FolderViewModel {
        if lastFolder != id { DispatchQueue.main.async { self.lastFolder = id } }
        if let page = pages[id] { return page }
        let page = FolderViewModel(folderId: id, store: store, service: service)
        // The menu bar reads the page through this model, so it has to hear it.
        page.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        pages[id] = page
        return page
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Manage"
        panel.message = "Choose a folder for Butler to organise."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        add(urls: [url])
    }

    func add(urls: [URL]) {
        for url in urls where isDirectory(url) {
            let folder = store.addFolder(at: url)
            selection = .folder(folder.id)
            lastFolder = folder.id
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    func removeSelectedFolder() {
        guard let id = selectedFolder else { return }
        removeFolder(id)
    }

    var selectedFolder: UUID? {
        if case let .folder(id) = selection { return id }
        return lastFolder ?? store.folders.first?.id
    }

    var selectedFolderValue: ManagedFolder? {
        selectedFolder.flatMap { store.folder($0) }
    }

    func removeFolder(_ id: UUID) {
        pages.removeValue(forKey: id)
        store.removeFolder(id)
        if selectedFolder == id {
            lastFolder = store.folders.first { $0.id != id }?.id
            selection = lastFolder.map { .folder($0) }
        }
    }

    var currentPage: FolderViewModel? {
        selectedFolder.map { page(for: $0) }
    }
}
