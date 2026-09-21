import ButlerCore
import SwiftUI

/// Everything the page shows beyond the plan itself: the status label, the
/// request that is still with the engine, and how far the applier has come.
@MainActor
final class ProposalPresentation: ObservableObject {
    @Published private(set) var machine = ProposalStatusMachine()
    @Published private(set) var trace: ApplyTrace?
    @Published private(set) var failure: String?
    @Published private(set) var appliedCount: Int?
    @Published var pendingRequest: String?
    private var reachedIndex = 0

    var status: ProposalStatus { machine.status }

    func apply(_ event: ProposalEvent) {
        machine.apply(event)
    }

    func reset(to status: ProposalStatus = .proposed) {
        machine = ProposalStatusMachine(status: status)
        trace = nil
        failure = nil
        appliedCount = nil
        pendingRequest = nil
        reachedIndex = 0
    }

    func beginApplying(_ operations: [PlanOperation]) {
        trace = ApplyTrace(operations: operations)
        failure = nil
        appliedCount = nil
        reachedIndex = 0
        apply(.applyStarted)
    }

    /// Progress can arrive late and out of order; the trace only moves forward.
    func reached(_ index: Int) {
        guard index > reachedIndex else { return }
        reachedIndex = index
        withAnimation(.easeInOut(duration: 0.2)) { trace?.reached(index) }
    }

    /// `stoppedAt` is the index the applier itself last reported, read after it
    /// returned, so a failure is pinned to the right row.
    func finishApplying(_ outcome: ApplyOutcome, stoppedAt index: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            trace?.reached(index)
            trace?.finish(failure: !outcome.succeeded)
            failure = outcome.failure
            appliedCount = outcome.itemCount
            apply(outcome.succeeded ? .applyFinished : .applyFailed)
        }
    }

    /// A plan that was applied in an earlier session still reads as applied.
    func restore(applied operations: [PlanOperation], undone: Bool, count: Int) {
        var restored = ApplyTrace(operations: operations)
        restored.finish(failure: false)
        trace = undone ? nil : restored
        appliedCount = undone ? nil : count
        machine = ProposalStatusMachine(status: undone ? .undone : .approved)
    }

    /// A run that stopped at a failure in an earlier session: what it did is
    /// dimmed, the error is shown, and the plan is still only proposed.
    func restore(stopped operations: [PlanOperation], failure message: String) {
        var restored = ApplyTrace(operations: operations)
        restored.finish(failure: false)
        trace = restored
        failure = message
        machine = ProposalStatusMachine(status: .proposed)
    }

    func clearTrace() {
        withAnimation(.easeInOut(duration: 0.2)) {
            trace = nil
            appliedCount = nil
        }
    }
}
