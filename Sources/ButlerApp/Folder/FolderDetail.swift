import ButlerCore
import QuickLook
import SwiftUI

struct FolderDetail: View {
    @ObservedObject var page: FolderViewModel
    @EnvironmentObject private var model: AppModel
    @Environment(\.undoManager) private var undoManager

    @State private var mode: StageMode = .changes
    @State private var search = ""
    @State private var showsInspector = false
    @State private var preview: URL?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onPaper()
            .overlay(alignment: .top) { Hairline() }
            .navigationTitle(page.folder?.name ?? "Butler")
            .navigationSubtitle(page.stateLine)
            .searchable(text: $search, prompt: "Search files")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if page.showsBottomBar {
                    BottomBar(page: page, undoManager: undoManager)
                }
            }
            .inspector(isPresented: $showsInspector) {
                RulesInspector(page: page, selected: selectedNode)
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
            }
            .toolbar { toolbar }
            .quickLookPreview($preview)
            .onAppear {
                showsInspector = LaunchOptions.page == "why"
                mode = LaunchOptions.stage ?? .changes
                if let text = LaunchOptions.search { search = text }
            }
            .onChange(of: page.plan?.id) { _, value in
                guard value != nil, page.plan?.revision == 1, LaunchOptions.selectedRows > 0 else { return }
                page.sheetSelection = Set(page.sheetRowIds.prefix(LaunchOptions.selectedRows))
            }
    }

    @ViewBuilder
    private var content: some View {
        if page.plan != nil {
            ProposalPage(
                page: page,
                mode: mode,
                search: search,
                selection: $page.sheetSelection,
                preview: $preview
            )
        } else {
            EmptyPage(page: page)
        }
    }

    private var selectedNode: PlanTableNode? {
        guard let id = page.sheetSelection.first else { return nil }
        return page.groups(mode: mode)
            .flatMap { [$0] + ($0.children ?? []) }
            .first { $0.id == id }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ModePicker(mode: $mode)
                .disabled(page.plan == nil)
                .help("The proposal, the folder as it is, or the folder as it will be")
        }
        ToolbarItemGroup {
            EngineMenu(page: page)
            if page.run.phase.isRunning {
                Button { page.stop() } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut(".", modifiers: .command)
            } else {
                Button { page.startRun() } label: {
                    Label("Organise", systemImage: "wand.and.stars")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!page.canRun)
            }
            Button { showsInspector.toggle() } label: {
                Label("Why", systemImage: "sidebar.trailing")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}

/// No proposal yet, or the first one is on its way: the header and a few
/// plain lines on the bare stock.
struct EmptyPage: View {
    @ObservedObject var page: FolderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(page: page, mode: .changes)
            Hairline()
            if page.run.phase.isRunning {
                working
            } else {
                idle
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var working: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preparing a proposal…")
                .font(.system(size: 13))
                .foregroundStyle(Stock.ink)
            ProgressLine()
                .frame(maxWidth: 520)
            Text((page.run.activity.last?.text ?? "Reading the folder…") + "  No files moved.")
                .font(.system(size: 11))
                .foregroundStyle(Stock.secondary)
                .lineLimit(2)
            Button("Stop") { page.stop() }
                .buttonStyle(.ghost)
                .padding(.top, 6)
        }
        .padding(.horizontal, Layout.margin)
        .padding(.top, 18)
    }

    private var idle: some View {
        VStack(spacing: 10) {
            Text(page.status == .rejected ? "The proposal was rejected. Nothing was moved." : "No proposal yet.")
                .font(.system(size: 13))
                .foregroundStyle(Stock.secondary)
            if let error = page.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Stock.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Button("Organise") { page.startRun() }
                .buttonStyle(.borderedProminent)
                .tint(Stock.fill)
                .disabled(!page.canRun)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Proposal · Before · After. SwiftUI's segmented `Picker` and AppKit's
/// `NSSegmentedControl` both ignore a selected-segment colour inside a toolbar
/// and show the user's accent or grey, so the three segments are drawn here
/// and presented to accessibility as the picker they are.
struct ModePicker: View {
    @Binding var mode: StageMode
    @Environment(\.isEnabled) private var isEnabled
    private static let modes: [(StageMode, String)] = [(.changes, "Proposal"), (.before, "Before"), (.after, "After")]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.modes, id: \.0) { value, title in
                Button {
                    mode = value
                } label: {
                    Text(title)
                        .font(.system(size: 12, weight: mode == value ? .medium : .regular))
                        .foregroundStyle(mode == value && isEnabled ? Stock.onFill : Stock.ink.opacity(0.8))
                        .padding(.horizontal, 12)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(mode == value && isEnabled ? Stock.fill : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Stock.ink.opacity(0.07)))
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.easeInOut(duration: 0.12), value: mode)
        .accessibilityRepresentation {
            Picker("View", selection: $mode) {
                ForEach(Self.modes, id: \.0) { value, title in Text(title).tag(value) }
            }
            .pickerStyle(.segmented)
        }
    }
}
