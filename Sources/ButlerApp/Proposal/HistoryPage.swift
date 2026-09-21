import ButlerCore
import SwiftUI

/// History: a flat table of every run, and the selected run underneath.
struct HistoryPage: View {
    @ObservedObject var page: FolderViewModel
    @EnvironmentObject private var model: AppModel
    @State private var selected: UUID?

    private struct Entry: Identifiable {
        let folder: ManagedFolder
        let record: RunRecord
        var id: UUID { record.id }
    }

    private var entries: [Entry] {
        model.store.folders
            .flatMap { folder in folder.history.map { Entry(folder: folder, record: $0) } }
            .sorted { $0.record.appliedAt > $1.record.appliedAt }
    }

    var body: some View {
        let entries = entries
        let current = entries.first { $0.id == selected } ?? entries.first
        VStack(alignment: .leading, spacing: 0) {
            Text("History")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Stock.ink)
                .padding(.horizontal, Layout.margin)
                .padding(.top, 8)
                .padding(.bottom, 6)
            if entries.isEmpty {
                Hairline()
                Text("Nothing has been tidied yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Stock.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                heads
                Hairline()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            line(entry, selected: entry.id == current?.id)
                        }
                    }
                }
                .frame(maxHeight: min(CGFloat(entries.count), 8) * Layout.rowHeight + 4)
                Hairline()
                if let current {
                    HistoryDetail(entry: current.record, folder: current.folder, engine: label(current.record)) {
                        model.page(for: current.folder.id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onPaper()
        .overlay(alignment: .top) { Hairline() }
        .navigationTitle("History")
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { step(-1, entries.map(\.id), current?.id) }
        .onKeyPress(.downArrow) { step(1, entries.map(\.id), current?.id) }
    }

    private var heads: some View {
        HStack(spacing: 10) {
            Text("Date").frame(width: 200, alignment: .leading)
            Text("Folder").frame(width: 220, alignment: .leading)
            Text("Status").frame(width: 110, alignment: .leading)
            Text("Items")
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(Stock.secondary)
        .padding(.horizontal, Layout.margin)
        .frame(height: Layout.rowHeight)
    }

    private func line(_ entry: Entry, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Text(entry.record.appliedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                .monospacedDigit()
                .frame(width: 200, alignment: .leading)
            Text(entry.folder.name)
                .frame(width: 220, alignment: .leading)
            Text(entry.record.statusWord)
                .foregroundStyle(entry.record.statusTone)
                .frame(width: 110, alignment: .leading)
            Text(entry.record.rejected == true ? "--" : "\(entry.record.itemCount)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Stock.secondary)
            Spacer()
        }
        .font(.system(size: 12))
        .foregroundStyle(Stock.ink)
        .lineLimit(1)
        .padding(.horizontal, Layout.margin)
        .frame(height: Layout.rowHeight)
        .background(selected ? Stock.wash : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { self.selected = entry.id }
    }

    private func step(_ delta: Int, _ ids: [UUID], _ current: UUID?) -> KeyPress.Result {
        guard !ids.isEmpty else { return .ignored }
        let index = current.flatMap(ids.firstIndex(of:)) ?? 0
        selected = ids[min(ids.count - 1, max(0, index + delta))]
        return .handled
    }

    private func label(_ record: RunRecord) -> String {
        let engine = model.service.engine(record.plan.engineId)?.label ?? record.plan.engineId
        return record.plan.modelId.map { "\(engine) · \($0)" } ?? engine
    }
}

extension RunRecord {
    var statusWord: String {
        if rejected == true { return "Rejected" }
        if undoneAt != nil { return "Undone" }
        return failure == nil ? "Approved" : "Stopped"
    }

    var statusTone: Color {
        switch statusWord {
        case "Approved": return Stock.accent
        case "Rejected", "Stopped": return Stock.red
        default: return Stock.secondary
        }
    }
}

/// The selected run: what it was, what it moved, and the way back.
private struct HistoryDetail: View {
    let entry: RunRecord
    let folder: ManagedFolder
    let engine: String
    let owner: () -> FolderViewModel

    private var items: [AppliedAction] { entry.actions.filter { $0.kind != .createdFolder } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(folder.name) · \(entry.appliedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Stock.ink)
                Text(summary)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Stock.secondary)
                if let failure = entry.failure {
                    Text(failure)
                        .font(.system(size: 11))
                        .foregroundStyle(Stock.red)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, Layout.margin)
            .padding(.top, 12)
            .padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items.indices, id: \.self) { index in
                        item(items[index])
                    }
                }
            }
            Hairline()
            HStack {
                Spacer()
                if entry.canUndo {
                    Button("Undo") { owner().undo(entry) }
                        .buttonStyle(.borderedProminent)
                        .tint(Stock.fill)
                } else if entry.undoneAt != nil, !entry.actions.isEmpty {
                    Button("Redo") { owner().redo(entry) }
                        .buttonStyle(.ghost)
                }
            }
            .padding(.horizontal, Layout.margin)
            .frame(height: 44)
        }
    }

    private var summary: String {
        if entry.rejected == true {
            return "\(Format.count(entry.plan.operations.count, "change", "changes")) proposed, none applied · \(engine)"
        }
        let folders = entry.actions.filter { $0.kind == .createdFolder }.count
        let trashed = entry.actions.filter { $0.kind == .trashed }.count
        var parts = [Format.count(items.count - trashed, "file moved", "files moved")]
        if folders > 0 { parts.append(Format.count(folders, "new folder", "new folders")) }
        if trashed > 0 { parts.append("\(trashed) to Trash") }
        let excluded = entry.plan.operations.count - entry.appliedCount
        if entry.failure != nil {
            parts.append("stopped before the rest of \(Format.count(entry.appliedCount, "approved change", "approved changes"))")
        } else if excluded > 0 {
            parts.append("\(excluded) excluded")
        }
        parts.append(engine)
        return parts.joined(separator: " · ")
    }

    private func item(_ action: AppliedAction) -> some View {
        HStack(spacing: 10) {
            Text(action.source)
                .foregroundStyle(Stock.ink)
                .frame(width: 410, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Stock.tertiary)
            Text(action.kind == .trashed ? "Trash" : action.destination)
                .foregroundStyle(action.kind == .trashed ? AnyShapeStyle(Stock.red) : AnyShapeStyle(Stock.secondary))
            Spacer()
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, Layout.margin)
        .frame(height: Layout.rowHeight)
        .opacity(entry.undoneAt == nil ? 1 : 0.55)
    }
}
