import ButlerCore
import SwiftUI

@main
struct ButlerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 940, idealWidth: 1180, minHeight: 600, idealHeight: 760)
                .background(WindowSetup())
                .onAppear { LaunchOptions.apply() }
                .task { await model.service.start() }
        }
        .defaultSize(width: 1180, height: 760)
        .commands { ButlerCommands(model: model) }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

struct ButlerCommands: Commands {
    @ObservedObject var model: AppModel

    private var page: FolderViewModel? { model.currentPage }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Folder…") { model.addFolder() }
                .keyboardShortcut("o")
            Button("Remove Folder") { model.removeSelectedFolder() }
                .disabled(model.currentPage == nil)
        }
        CommandMenu("Folder") {
            Button("Organise") { page?.startRun() }
                .keyboardShortcut("r")
                .disabled(page?.canRun != true)
            Button("Stop") { page?.stop() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(page?.run.phase.isRunning != true)
            Divider()
            Button("Approve Plan") { page?.approve(undoManager: nil) }
                .disabled(page?.canDecide != true)
            Button("Reject Plan") { page?.reject() }
                .disabled(page?.canDecide != true)
            Button("Ask for Changes") { page?.requestChanges() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(page?.canDecide != true || page?.changeRequest.isEmpty != false)
            Divider()
            Button("Include Selected") { page?.setSelectionIncluded(true) }
                .disabled(page?.canDecide != true || page?.sheetSelection.isEmpty != false)
            Button("Exclude Selected") { page?.setSelectionIncluded(false) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(page?.canDecide != true || page?.sheetSelection.isEmpty != false)
            Divider()
            Button("Undo Last Run") { page?.undoLastRun() }
                .disabled(page?.lastUndoableRun == nil)
        }
        CommandMenu("Go") {
            Button("Proposal") {
                if let id = model.selectedFolder { model.selection = .folder(id) }
            }
            .keyboardShortcut("1")
            .disabled(model.selectedFolder == nil)
            Button("House Rules") { model.selection = .rules }
                .keyboardShortcut("2")
                .disabled(model.selectedFolder == nil)
            Button("History") { model.selection = .history }
                .keyboardShortcut("3")
                .disabled(model.selectedFolder == nil)
        }
    }
}
