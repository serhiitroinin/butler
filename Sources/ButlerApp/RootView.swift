import ButlerCore
import SwiftUI

enum SidebarItem: Hashable {
    case folder(UUID)
    case rules
    case history
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            FolderList()
                .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 280)
        } detail: {
            detail
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = model.selectedFolder {
            Fitted {
                switch model.selection {
                case .rules:
                    RulesPage(page: model.page(for: id))
                case .history:
                    HistoryPage(page: model.page(for: id))
                default:
                    FolderDetail(page: model.page(for: id))
                        .id(id)
                }
            }
        } else {
            NoFolders()
        }
    }
}

/// No managed folders: a glyph, two lines, and the way in, on the bare stock.
struct NoFolders: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Stock.accent)
                .padding(.bottom, 6)
            Text("A little order starts here.")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Stock.ink)
            Text("Add a folder for Butler to organise.")
                .font(.system(size: 13))
                .foregroundStyle(Stock.secondary)
            Button("Add Folder…") { model.addFolder() }
                .buttonStyle(.borderedProminent)
                .tint(Stock.fill)
                .controlSize(.large)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPaper()
        .overlay(alignment: .top) { Hairline() }
        .navigationTitle("Butler")
    }
}

struct FolderList: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            Section {
                ForEach(model.store.folders) { folder in
                    SidebarRow(
                        title: folder.name,
                        count: folder.currentPlan?.operations.count ?? 0,
                        selected: model.selection == .folder(folder.id)
                    ) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    .tag(SidebarItem.folder(folder.id))
                    .contextMenu {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([folder.url])
                        }
                        Button("Remove Folder") { model.removeFolder(folder.id) }
                    }
                }
            } header: {
                Text("Butler")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Stock.ink)
                    .textCase(nil)
                    .padding(.bottom, 6)
            }
            Section {
                SidebarRow(title: "House Rules", count: 0, selected: model.selection == .rules) {
                    Image(systemName: "doc.plaintext")
                }
                .tag(SidebarItem.rules)
                SidebarRow(
                    title: "History",
                    count: model.store.folders.map(\.history.count).reduce(0, +),
                    selected: model.selection == .history
                ) {
                    Image(systemName: "clock")
                }
                .tag(SidebarItem.history)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Stock.sidebar.ignoresSafeArea())
        .navigationTitle("Butler")
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls: urls)
            return true
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Hairline()
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(Stock.ink.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .frame(height: 44)
            }
            .background(Stock.sidebar)
        }
        .toolbar {
            ToolbarItem {
                Button { model.addFolder() } label: {
                    Label("Add Folder", systemImage: "plus")
                }
                .help("Add a folder for Butler to organise")
            }
        }
    }
}

/// A sidebar line that draws its own olive selection, because the system's
/// highlight would be the user's accent colour.
private struct SidebarRow<Icon: View>: View {
    let title: String
    let count: Int
    let selected: Bool
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(spacing: 7) {
            icon
                .frame(width: 18)
                .foregroundStyle(selected ? Stock.onFill : Stock.ink.opacity(0.7))
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(selected ? Stock.onFill : Stock.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(selected ? Stock.onFill.opacity(0.85) : Stock.secondary)
            }
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Stock.fill : Color.clear)
                .padding(.horizontal, 10)
        )
    }
}


/// Pins a page to the size of its column. Without it a long proposal asks for
/// more height than the window has and draws outside it.
struct Fitted<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            content.frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
