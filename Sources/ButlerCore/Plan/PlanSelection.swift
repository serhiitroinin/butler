import Foundation

/// The include/exclude state of one proposal. Excluding an operation can make
/// another impossible, so the rest is validated again after every change.
public struct PlanSelection: Sendable {
    public private(set) var excluded: Set<UUID> = []
    public private(set) var blocked: [UUID: String] = [:]

    private let plan: Plan
    private let validator: PlanValidator

    public init(plan: Plan, validator: PlanValidator, excludeTrash: Bool = true) {
        self.plan = plan
        self.validator = validator
        if excludeTrash {
            excluded = Set(plan.operations.filter { $0.kind == .trash }.map(\.id))
        }
        recompute()
    }

    public func isIncluded(_ operation: PlanOperation) -> Bool {
        !excluded.contains(operation.id) && blocked[operation.id] == nil
    }

    public func blockReason(_ operation: PlanOperation) -> String? {
        blocked[operation.id]
    }

    public var included: [PlanOperation] {
        plan.operations.filter(isIncluded)
    }

    public var includedCount: Int { included.count }

    public mutating func toggle(_ operation: PlanOperation) {
        if excluded.contains(operation.id) {
            excluded.remove(operation.id)
        } else {
            excluded.insert(operation.id)
        }
        recompute()
    }

    public mutating func setAll(included: Bool) {
        excluded = included ? [] : Set(plan.operations.map(\.id))
        recompute()
    }

    private mutating func recompute() {
        blocked = [:]
        for _ in 0..<6 {
            let before = blocked
            applyFolderDependencies()
            applyValidation()
            if blocked == before { return }
        }
    }

    private mutating func applyFolderDependencies() {
        let missing = plan.operations
            .filter { $0.kind == .mkdir && (excluded.contains($0.id) || blocked[$0.id] != nil) }
            .map(\.destination)
        guard !missing.isEmpty else { return }
        for operation in plan.operations where blocked[operation.id] == nil && !excluded.contains(operation.id) {
            let target = operation.kind == .mkdir ? operation.destination : operation.destinationFolder
            guard !target.isEmpty else { continue }
            if let folder = missing.first(where: { target == $0 || target.hasPrefix($0 + "/") }) {
                blocked[operation.id] = "The folder \(folder) is not included."
            }
        }
    }

    private mutating func applyValidation() {
        let issues = validator.validate(included).issues
        for issue in issues {
            guard let id = issue.operationId, blocked[id] == nil, !excluded.contains(id) else { continue }
            blocked[id] = issue.message
        }
    }
}
