import Foundation

public enum OperationKind: String, Codable, Sendable, CaseIterable {
    case mkdir
    case move
    case rename
    case trash
}

/// One proposed change. `source` is empty for `mkdir`; `destination` is empty
/// for `trash`. Both paths are relative to the managed root.
public struct PlanOperation: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var kind: OperationKind
    public var source: String
    public var destination: String
    public var reason: String

    public init(
        id: UUID = UUID(),
        kind: OperationKind,
        source: String = "",
        destination: String = "",
        reason: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.destination = destination
        self.reason = reason
    }

    public var displayName: String {
        switch kind {
        case .mkdir: return (destination as NSString).lastPathComponent
        case .trash: return (source as NSString).lastPathComponent
        case .move, .rename: return (destination as NSString).lastPathComponent
        }
    }

    public var previousName: String { (source as NSString).lastPathComponent }
    public var destinationFolder: String { (destination as NSString).deletingLastPathComponent }
    public var sourceFolder: String { (source as NSString).deletingLastPathComponent }
}

public struct PlanUsage: Codable, Sendable, Hashable {
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var totalTokens: Int?
    public var costUsd: Double?

    public init(inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil, costUsd: Double? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.costUsd = costUsd
    }
}

public struct Plan: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var revision: Int
    public var summary: String
    public var operations: [PlanOperation]
    public var createdAt: Date
    public var engineId: String
    public var modelId: String?
    public var usage: PlanUsage?
    /// The plain-text change request that produced this revision.
    public var changeRequest: String?

    public init(
        id: UUID = UUID(),
        revision: Int,
        summary: String,
        operations: [PlanOperation],
        createdAt: Date = Date(),
        engineId: String,
        modelId: String? = nil,
        usage: PlanUsage? = nil,
        changeRequest: String? = nil
    ) {
        self.id = id
        self.revision = revision
        self.summary = summary
        self.operations = operations
        self.createdAt = createdAt
        self.engineId = engineId
        self.modelId = modelId
        self.usage = usage
        self.changeRequest = changeRequest
    }

    public func count(of kind: OperationKind) -> Int {
        operations.filter { $0.kind == kind }.count
    }

    public var headline: String {
        let parts = [
            countPhrase(count(of: .move), "file moves", "file moves"),
            countPhrase(count(of: .mkdir), "new folder", "new folders"),
            countPhrase(count(of: .rename), "rename", "renames"),
            countPhrase(count(of: .trash), "item to Trash", "items to Trash"),
        ].compactMap { $0 }
        return parts.isEmpty ? "No changes" : parts.joined(separator: " · ")
    }

    private func countPhrase(_ value: Int, _ singular: String, _ plural: String) -> String? {
        guard value > 0 else { return nil }
        return "\(value) \(value == 1 ? singular : plural)"
    }
}
