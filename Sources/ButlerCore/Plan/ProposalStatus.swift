import Foundation

/// What the label next to the folder name reads.
public enum ProposalStatus: String, Sendable, Equatable {
    case proposed = "Proposed"
    case working = "Working"
    case approved = "Approved"
    case rejected = "Rejected"
    case undone = "Undone"
}

public enum ProposalEvent: Sendable, Equatable {
    case runStarted
    case planArrived
    case runFailed
    case applyStarted
    case applyFinished
    case applyFailed
    case rejected
    case undone
}

/// The label never claims more than happened: a failed apply leaves the plan
/// proposed, and only a finished apply marks it approved.
public struct ProposalStatusMachine: Sendable, Equatable {
    public private(set) var status: ProposalStatus

    public init(status: ProposalStatus = .proposed) {
        self.status = status
    }

    public mutating func apply(_ event: ProposalEvent) {
        switch event {
        case .runStarted, .applyStarted:
            status = .working
        case .planArrived, .runFailed, .applyFailed:
            status = .proposed
        case .applyFinished:
            status = .approved
        case .rejected:
            status = .rejected
        case .undone:
            status = .undone
        }
    }

    public func next(_ event: ProposalEvent) -> ProposalStatus {
        var copy = self
        copy.apply(event)
        return copy.status
    }
}

/// One "You: … / Butler: …" pair. The reply is missing while the engine works.
public struct ConversationTurn: Sendable, Equatable, Identifiable {
    public let revision: Int
    public let request: String
    public let reply: String?

    public var id: Int { revision }
}

public enum ProposalConversation {
    /// Every revision that a change request produced carries that request and
    /// its own note. A request still with the engine has no reply yet.
    public static func turns(revisions: [Plan], pending: String? = nil) -> [ConversationTurn] {
        var turns = revisions.compactMap { plan -> ConversationTurn? in
            guard let request = plan.changeRequest, !request.isEmpty else { return nil }
            return ConversationTurn(
                revision: plan.revision,
                request: request,
                reply: plan.summary.isEmpty ? nil : plan.summary
            )
        }
        if let pending, !pending.isEmpty {
            turns.append(ConversationTurn(
                revision: (revisions.last?.revision ?? 0) + 1,
                request: pending,
                reply: nil
            ))
        }
        return turns
    }
}

/// How far the applier has come, so the page can dim exactly what is done.
public struct ApplyTrace: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case pending
        case done
        case failed
    }

    public let operationIds: [UUID]
    public private(set) var completed: Set<UUID> = []
    public private(set) var failed: UUID?

    public init(operations: [PlanOperation]) {
        operationIds = operations.map(\.id)
    }

    /// The applier reports the index it is about to perform, so everything
    /// before that index has finished.
    public mutating func reached(_ index: Int) {
        completed = Set(operationIds.prefix(max(0, min(index, operationIds.count))))
    }

    public mutating func finish(failure: Bool) {
        if failure {
            failed = operationIds.first { !completed.contains($0) }
        } else {
            completed = Set(operationIds)
        }
    }

    /// A row or a group is done when every one of its operations that is being
    /// applied has finished. Excluded operations are not waited for.
    public func state(of ids: [UUID]) -> State {
        if let failed, ids.contains(failed) { return .failed }
        let applied = ids.filter(operationIds.contains)
        guard !applied.isEmpty else { return .pending }
        return applied.allSatisfy(completed.contains) ? .done : .pending
    }
}
