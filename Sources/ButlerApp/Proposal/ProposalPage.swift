import ButlerCore
import QuickLook
import SwiftUI

/// The proposal: a header, column heads, and one group per destination folder,
/// set straight on the window's stock.
struct ProposalPage: View {
    @ObservedObject var page: FolderViewModel
    let mode: StageMode
    let search: String
    @Binding var selection: Set<String>
    @Binding var preview: URL?
    @State private var collapsed: Set<String> = []
    @State private var anchor: String?

    var body: some View {
        let groups = visibleGroups
        VStack(spacing: 0) {
            PageHeader(page: page, mode: mode)
            columnHeads(groups)
            Hairline()
            if groups.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            if index > 0 { Hairline().padding(.leading, Layout.margin) }
                            ProposalGroupView(
                                page: page,
                                group: group,
                                mode: mode,
                                selection: selection,
                                changed: page.changedInLatestRevision,
                                select: { id, event in select(id, event, in: groups) },
                                quickLook: { preview = $0 },
                                collapsed: $collapsed
                            )
                        }
                    }
                    .padding(.bottom, 8)
                }
                .defaultScrollAnchor(.top)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard let url = selectedURLs(groups).first else { return .ignored }
            preview = preview == nil ? url : nil
            return .handled
        }
        .onKeyPress(.upArrow) { move(-1, in: groups) }
        .onKeyPress(.downArrow) { move(1, in: groups) }
    }

    private func columnHeads(_ groups: [PlanTableNode]) -> some View {
        let ids = groups.flatMap(\.operationIds)
        return HStack(spacing: 10) {
            InkCheckbox(state: page.state(of: ids), label: "Include everything") {
                page.setIncluded(ids, to: $0)
            }
            .disabled(!page.canDecide || ids.isEmpty)
            Text("Name").padding(.leading, 22)
            Spacer(minLength: 8)
            Text(mode == .before ? "To" : "From → To").frame(width: Layout.pathColumn, alignment: .leading)
            Text("Kind").frame(width: Layout.kindColumn, alignment: .leading)
            Text("Size").frame(width: Layout.sizeColumn, alignment: .trailing)
            Color.clear.frame(width: Layout.markColumn, height: 1)
        }
        .font(.system(size: 11))
        .foregroundStyle(Stock.secondary)
        .padding(.horizontal, Layout.margin)
        .frame(height: Layout.rowHeight)
    }

    private var empty: some View {
        Text(search.isEmpty ? "Nothing to show." : "Nothing matches “\(search)”.")
            .font(.system(size: 12))
            .foregroundStyle(Stock.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var visibleGroups: [PlanTableNode] {
        let all = page.groups(mode: mode)
        guard !search.isEmpty else { return all }
        return all.compactMap { group in
            if group.name.localizedCaseInsensitiveContains(search) { return group }
            let children = (group.children ?? []).filter { $0.name.localizedCaseInsensitiveContains(search) }
            guard !children.isEmpty else { return nil }
            var copy = group
            copy.children = children
            return copy
        }
    }

    private func rows(_ groups: [PlanTableNode]) -> [PlanTableNode] {
        groups.filter { !collapsed.contains($0.id) }.flatMap { $0.children ?? [] }
    }

    private func selectedURLs(_ groups: [PlanTableNode]) -> [URL] {
        rows(groups)
            .filter { selection.contains($0.id) }
            .map { URL(fileURLWithPath: $0.path) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Click selects, ⌘-click toggles, ⇧-click extends from the last click.
    private func select(_ id: String, _ flags: NSEvent.ModifierFlags, in groups: [PlanTableNode]) {
        let order = rows(groups).map(\.id)
        if flags.contains(.shift), let anchor,
           let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) {
            selection = Set(order[min(from, to)...max(from, to)])
            return
        }
        if flags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
        anchor = id
    }

    private func move(_ step: Int, in groups: [PlanTableNode]) -> KeyPress.Result {
        let order = rows(groups).map(\.id)
        guard !order.isEmpty else { return .ignored }
        let current = anchor.flatMap(order.firstIndex(of:)) ?? (step > 0 ? -1 : order.count)
        let next = min(order.count - 1, max(0, current + step))
        selection = [order[next]]
        anchor = order[next]
        return .handled
    }
}

/// The folder name, the status label beside it, the revision menu, and one
/// line of counts.
struct PageHeader: View {
    @ObservedObject var page: FolderViewModel
    let mode: StageMode

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(page.folder?.name ?? "Butler")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Stock.ink)
                .lineLimit(1)
            if page.showsStatus {
                StatusLabel(status: page.status)
                    .alignmentGuide(.firstTextBaseline) { $0[.firstTextBaseline] + 2 }
                    .animation(.easeInOut(duration: 0.2), value: page.status)
            }
            if page.revisionNumbers.count > 1 {
                Menu {
                    ForEach(page.revisionNumbers.reversed(), id: \.self) { number in
                        Button {
                            page.show(revision: number)
                        } label: {
                            Text(number == page.revisionNumbers.max() ? "Revision \(number) (latest)" : "Revision \(number)")
                        }
                    }
                } label: {
                    Text(page.revisionLabel)
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(page.isBusy)
                .help("Look at an earlier revision")
            }
            Spacer(minLength: 12)
            Text(caption)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Stock.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Layout.margin)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var caption: String {
        guard page.plan != nil else { return "" }
        switch mode {
        case .changes: return page.headerLine
        case .before: return "As it is now · " + page.headerLine
        case .after: return "As it will be · " + page.headerLine
        }
    }
}
