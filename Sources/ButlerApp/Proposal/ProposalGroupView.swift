import AppKit
import ButlerCore
import SwiftUI
import UniformTypeIdentifiers

/// One destination folder: a header line and its rows.
struct ProposalGroupView: View {
    @ObservedObject var page: FolderViewModel
    let group: PlanTableNode
    let mode: StageMode
    let selection: Set<String>
    let changed: Set<String>
    let select: (String, NSEvent.ModifierFlags) -> Void
    let quickLook: (URL) -> Void
    @Binding var collapsed: Set<String>

    private var isOpen: Bool { !collapsed.contains(group.id) }
    private var isTrash: Bool { group.name == "Trash" }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isOpen {
                ForEach(group.children ?? []) { row in
                    ProposalRowView(
                        page: page,
                        node: row,
                        destination: group.name,
                        showsOnlyTarget: mode == .before,
                        selected: selection.contains(row.id),
                        revisionMark: changed.contains(row.name) ? "rev \(page.plan?.revision ?? 2)" : nil,
                        select: { select(row.id, $0) },
                        quickLook: quickLook
                    )
                }
            }
        }
    }

    private var header: some View {
        let done = page.applyState(of: group) == .done
        return HStack(spacing: 10) {
            InkCheckbox(state: page.state(of: group.operationIds), label: "Include \(group.name)") {
                page.setIncluded(group.operationIds, to: $0)
            }
            .disabled(!page.canDecide)
            Button {
                if isOpen { collapsed.insert(group.id) } else { collapsed.remove(group.id) }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Stock.secondary)
                    .rotationEffect(.degrees(isOpen ? 0 : -90))
                    .frame(width: 12, height: Layout.rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOpen ? "Collapse \(group.name)" : "Expand \(group.name)")
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(group.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Stock.ink)
                Text("(\(group.children?.count ?? 0))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Stock.secondary)
                if group.isNewFolder {
                    Text("new")
                        .font(.system(size: 11))
                        .foregroundStyle(Stock.tertiary)
                }
                if done {
                    Text("done")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Stock.accent)
                        .transition(.opacity)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            SizeText(bytes: group.size)
                .foregroundStyle(Stock.tertiary)
                .frame(width: Layout.sizeColumn + 40, alignment: .trailing)
            Color.clear.frame(width: Layout.markColumn, height: 1)
        }
        .padding(.horizontal, Layout.margin)
        .frame(height: Layout.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if isOpen { collapsed.insert(group.id) } else { collapsed.remove(group.id) }
        }
    }
}

/// One file: the checkbox, the icon, the name, where it goes, and its size.
struct ProposalRowView: View {
    @ObservedObject var page: FolderViewModel
    let node: PlanTableNode
    let destination: String
    /// Before lists the folder as it is, so the column says only where a file goes.
    var showsOnlyTarget = false
    let selected: Bool
    let revisionMark: String?
    let select: (NSEvent.ModifierFlags) -> Void
    let quickLook: (URL) -> Void

    private var inclusion: InclusionState { page.state(of: node.operationIds) }
    private var excluded: Bool { inclusion == .excluded }

    var body: some View {
        let applied = page.applyState(of: node)
        HStack(spacing: 10) {
            InkCheckbox(state: inclusion, label: "Include \(node.name)") {
                page.setIncluded(node.operationIds, to: $0)
            }
            .disabled(!page.canDecide || page.blockReason(node.operationIds.first) != nil)
            .padding(.leading, 22)
            HStack(spacing: 10) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                name(failed: applied == .failed)
                Spacer(minLength: 8)
                if applied == .failed, let failure = page.applyFailure {
                    Text(failure)
                        .font(.system(size: 11))
                        .foregroundStyle(Stock.red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                } else {
                    path.frame(width: Layout.pathColumn, alignment: .leading)
                    Text(node.kindLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Stock.secondary)
                        .lineLimit(1)
                        .frame(width: Layout.kindColumn, alignment: .leading)
                }
                SizeText(bytes: node.size, placeholder: "--")
                    .foregroundStyle(Stock.secondary)
                    .frame(width: Layout.sizeColumn, alignment: .trailing)
            }
            .opacity(applied == .done ? 0.4 : excluded ? 0.45 : 1)
            ZStack(alignment: .trailing) {
                Color.clear
                mark(applied)
            }
            .frame(width: Layout.markColumn, height: Layout.rowHeight)
        }
        .padding(.horizontal, Layout.margin)
        .frame(height: Layout.rowHeight)
        .background(selected ? Stock.wash : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
        }
        .simultaneousGesture(TapGesture().onEnded { select(NSEvent.modifierFlags) })
        .contextMenu { menu }
        .help(page.blockReason(node.operationIds.first) ?? node.reason)
        .animation(.easeInOut(duration: 0.15), value: excluded)
    }

    @ViewBuilder
    private func mark(_ applied: ApplyTrace.State) -> some View {
        if excluded {
            FlatCapsule(text: "Excluded")
        } else if applied == .done {
            Text("done")
                .font(.system(size: 10))
                .foregroundStyle(Stock.tertiary)
        } else if let revisionMark {
            Text(revisionMark)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Stock.accent)
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button(excluded ? "Include" : "Exclude") {
            if !selected { select([]) }
            page.setSelectionIncluded(excluded)
        }
        .disabled(!page.canDecide)
        Divider()
        Button("Quick Look") {
            quickLook(URL(fileURLWithPath: node.path))
        }
        .disabled(!FileManager.default.fileExists(atPath: node.path))
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
        }
    }

    private var path: some View {
        HStack(spacing: 5) {
            if showsOnlyTarget {
                Text(node.destination)
                    .foregroundStyle(node.destination == "Trash" ? AnyShapeStyle(Stock.red) : AnyShapeStyle(Stock.ink.opacity(0.78)))
            } else {
                Text(origin)
            }
            if !destination.isEmpty, !showsOnlyTarget {
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .medium))
                    .opacity(0.7)
                Text(destination)
                    .foregroundStyle(destination == "Trash" ? AnyShapeStyle(Stock.red) : AnyShapeStyle(Stock.ink.opacity(0.78)))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Stock.secondary)
        .lineLimit(1)
        .truncationMode(.head)
    }

    /// Where the file is now, with the managed folder's own name for its top
    /// level: `Downloads → Invoices/2024`.
    private var origin: String {
        let top = page.folder?.name ?? "Top Level"
        if destination == "Trash", let root = page.folder?.url.path {
            let parent = (node.path as NSString).deletingLastPathComponent
            return parent == root ? top : String(parent.dropFirst(root.count + 1))
        }
        return node.destination == "Top Level" ? top : node.destination
    }

    private func name(failed: Bool) -> some View {
        HStack(spacing: 5) {
            if let previous = node.previousName {
                Text(previous).foregroundStyle(Stock.secondary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Stock.secondary)
            }
            Text(node.name)
                .foregroundStyle(failed ? AnyShapeStyle(Stock.red) : AnyShapeStyle(Stock.ink))
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .truncationMode(.middle)
    }

    private var icon: NSImage {
        if FileManager.default.fileExists(atPath: node.path) {
            return NSWorkspace.shared.icon(forFile: node.path)
        }
        let suffix = (node.name as NSString).pathExtension
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: suffix) ?? .data)
    }
}

/// A size in SF Mono, with a narrow gap before the unit: a full mono space
/// reads as a hole in a right-aligned column.
struct SizeText: View {
    let bytes: Int64?
    var placeholder = ""

    var body: some View {
        if let bytes, bytes > 0 {
            let parts = Format.bytes(bytes).split(separator: " ", maxSplits: 1).map(String.init)
            (Text(parts.first ?? "").font(.system(size: 11, design: .monospaced))
                + Text(" ").font(.system(size: 5))
                + Text(parts.count > 1 ? parts[1] : "").font(.system(size: 11, design: .monospaced)))
        } else {
            Text(placeholder).font(.system(size: 11, design: .monospaced))
        }
    }
}
