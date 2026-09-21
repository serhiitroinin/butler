import AppKit
import ButlerCore
import SwiftUI

/// What the page reads: the status label, the header line, the conversation,
/// and which rows the applier has already dealt with.
extension FolderViewModel {
    var status: ProposalStatus {
        if run.phase.isRunning { return .working }
        return presentation.status
    }

    /// The label shows once there is something to have a status about.
    var showsStatus: Bool { plan != nil || status != .proposed }

    var revisionNumbers: [Int] { folder?.revisions.map(\.revision) ?? [] }

    var revisionLabel: String {
        guard let plan else { return "" }
        return "Revision \(plan.revision) of \(revisionNumbers.max() ?? plan.revision)"
    }

    /// `57 selected · 2 excluded · 19 new folders`
    var headerLine: String {
        guard let plan else { return "" }
        let rows = groups(mode: .changes).flatMap { $0.children ?? [] }
        let excluded = rows.filter { state(of: $0.operationIds) == .excluded }.count
        var parts = ["\(rows.count - excluded) selected", "\(excluded) excluded"]
        let folders = plan.count(of: .mkdir)
        if folders > 0 { parts.append(Format.count(folders, "new folder", "new folders")) }
        return parts.joined(separator: " · ")
    }

    var conversation: [ConversationTurn] {
        ProposalConversation.turns(
            revisions: folder?.revisions ?? [],
            pending: presentation.pendingRequest
        )
    }

    var sheetRowIds: [String] {
        groups(mode: .changes).flatMap { $0.children ?? [] }.map(\.id)
    }

    func applyState(of node: PlanTableNode) -> ApplyTrace.State {
        presentation.trace?.state(of: node.operationIds) ?? .pending
    }

    var applyFailure: String? { presentation.failure }

    var tidiedLine: String {
        "Tidied · " + Format.count(presentation.appliedCount ?? 0, "item", "items")
    }

    /// Names that appear in this revision but not in the one before it.
    var changedInLatestRevision: Set<String> {
        guard let folder, let plan, isLatestRevision, folder.revisions.count > 1 else { return [] }
        let previous = folder.revisions[folder.revisions.count - 2]
        let before = Set(previous.operations.map { "\($0.kind.rawValue):\($0.source)→\($0.destination)" })
        let names = plan.operations
            .filter { !before.contains("\($0.kind.rawValue):\($0.source)→\($0.destination)") }
            .map(\.displayName)
        return Set(names)
    }
}
