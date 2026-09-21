import Foundation

public enum ControlValue: Codable, Sendable, Hashable {
    case text(String)
    case flag(Bool)
    case number(Double)

    public var display: String {
        switch self {
        case let .text(value): return value
        case let .flag(value): return value ? "On" : "Off"
        case let .number(value): return String(value)
        }
    }
}

public struct EngineChoice: Codable, Sendable, Hashable {
    public var engineId: String?
    public var modelId: String?
    public var effortId: String?
    public var controls: [String: ControlValue] = [:]

    public init(engineId: String? = nil, modelId: String? = nil, effortId: String? = nil, controls: [String: ControlValue] = [:]) {
        self.engineId = engineId
        self.modelId = modelId
        self.effortId = effortId
        self.controls = controls
    }

    public var isEmpty: Bool { engineId == nil }
}

public struct RunRecord: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var appliedAt: Date
    public var plan: Plan
    public var actions: [AppliedAction]
    public var appliedCount: Int
    public var failure: String?
    public var undoneAt: Date?
    /// A proposal the user turned down. Nothing was moved, so nothing undoes.
    public var rejected: Bool?

    public init(
        id: UUID = UUID(),
        appliedAt: Date = Date(),
        plan: Plan,
        actions: [AppliedAction],
        appliedCount: Int,
        failure: String? = nil,
        undoneAt: Date? = nil,
        rejected: Bool? = nil
    ) {
        self.id = id
        self.appliedAt = appliedAt
        self.plan = plan
        self.actions = actions
        self.appliedCount = appliedCount
        self.failure = failure
        self.undoneAt = undoneAt
        self.rejected = rejected
    }

    public var canUndo: Bool { undoneAt == nil && !actions.isEmpty }
    /// The items really moved or put in the Trash, from the journal.
    /// `appliedCount` is how many operations were approved.
    public var itemCount: Int { actions.filter { $0.kind != .createdFolder }.count }
}

public struct ManagedFolder: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var path: String
    public var rules: String
    public var choice: EngineChoice
    /// The open proposal chain. The last plan is the one under review.
    public var revisions: [Plan]
    public var history: [RunRecord]

    public init(
        id: UUID = UUID(),
        path: String,
        rules: String = "",
        choice: EngineChoice = EngineChoice(),
        revisions: [Plan] = [],
        history: [RunRecord] = []
    ) {
        self.id = id
        self.path = path
        self.rules = rules
        self.choice = choice
        self.revisions = revisions
        self.history = history
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var name: String { url.lastPathComponent }
    public var currentPlan: Plan? { revisions.last }

    public var statusLine: String {
        if let plan = currentPlan {
            return "Plan ready · \(plan.operations.count) changes"
        }
        if let last = history.first(where: { $0.undoneAt == nil && $0.rejected != true }) {
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            return "Applied \(formatter.localizedString(for: last.appliedAt, relativeTo: Date()))"
        }
        return "Never run"
    }
}

public struct ButlerSettings: Codable, Sendable, Hashable {
    public var defaultRules: String
    public var choice: EngineChoice

    public init(defaultRules: String = "", choice: EngineChoice = EngineChoice()) {
        self.defaultRules = defaultRules
        self.choice = choice
    }
}

struct ButlerState: Codable, Sendable {
    var settings = ButlerSettings()
    var folders: [ManagedFolder] = []
}
