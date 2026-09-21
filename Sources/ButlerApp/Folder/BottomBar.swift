import ButlerCore
import SwiftUI

/// A status line, one field, and the decision, on the same stock as the rest.
/// The conversation sits flat above it when a change was asked for.
struct BottomBar: View {
    @ObservedObject var page: FolderViewModel
    let undoManager: UndoManager?
    @FocusState private var writing: Bool

    var body: some View {
        VStack(spacing: 0) {
            if page.plan != nil, !page.conversation.isEmpty {
                Hairline()
                ConversationBlock(turns: page.conversation)
            }
            Hairline()
            HStack(spacing: 12) {
                status
                Spacer(minLength: 12)
                controls
            }
            .padding(.horizontal, Layout.margin)
            .frame(height: 44)
        }
        .onPaper()
    }

    @ViewBuilder
    private var controls: some View {
        if page.status == .approved, page.lastUndoableRun != nil {
            undo
        } else if page.stoppedRun != nil {
            undo
        } else if page.plan != nil, !page.isLatestRevision {
            Button("Back to the Latest Revision") {
                page.show(revision: page.revisionNumbers.max() ?? 1)
            }
            .buttonStyle(.ghost)
        } else if page.plan != nil {
            TextField("Ask for changes…", text: $page.changeRequest)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, maxWidth: 340)
                .focused($writing)
                .onSubmit { page.requestChanges() }
                .disabled(!page.canDecide)
            Button("Reject") { page.reject() }
                .buttonStyle(.ghost)
                .disabled(!page.canDecide)
            Button("Approve") { page.approve(undoManager: undoManager) }
                .buttonStyle(.borderedProminent)
                .tint(Stock.fill)
                .keyboardShortcut(page.changeRequest.isEmpty ? .defaultAction : nil)
                .disabled(page.includedCount == 0 || !page.canDecide)
        } else if page.lastUndoableRun != nil {
            undo
        }
    }

    private var undo: some View {
        Button("Undo") { page.undoLastRun() }
            .buttonStyle(.borderedProminent)
            .tint(Stock.fill)
            .keyboardShortcut("z", modifiers: .command)
            .disabled(page.isBusy)
            .help("Put the items back")
    }

    @ViewBuilder
    private var status: some View {
        if let applying = page.applying {
            HStack(spacing: 10) {
                ProgressLine(fraction: Double(applying.completed) / Double(max(applying.total, 1)))
                    .frame(width: 160)
                Text("\(applying.completed) of \(applying.total) · \(applying.current)")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Stock.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else if page.run.phase.isRunning {
            HStack(spacing: 10) {
                ProgressLine().frame(width: 120)
                label(page.run.activity.last?.text ?? "Reading the folder…")
            }
        } else if page.status == .approved {
            label(page.tidiedLine, strong: true)
        } else if let failure = page.stoppedLine {
            Text(failure)
                .font(.system(size: 12))
                .foregroundStyle(Stock.red)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if page.plan != nil, !page.isLatestRevision {
            label("\(page.revisionLabel) · read only")
        } else {
            label(page.statusLine)
        }
    }

    private func label(_ text: String, strong: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12, weight: strong ? .medium : .regular))
            .monospacedDigit()
            .foregroundStyle(strong ? Stock.ink : Stock.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
