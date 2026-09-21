import Foundation

public struct AppliedAction: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case createdFolder
        case moved
        case trashed
    }

    public var kind: Kind
    public var source: String
    public var destination: String
    public var trashPath: String?

    public init(kind: Kind, source: String, destination: String = "", trashPath: String? = nil) {
        self.kind = kind
        self.source = source
        self.destination = destination
        self.trashPath = trashPath
    }
}

public struct ApplyOutcome: Sendable {
    public var actions: [AppliedAction]
    public var failure: String?

    public var succeeded: Bool { failure == nil }
    /// The items really moved or put in the Trash; created folders are not items.
    public var itemCount: Int { actions.filter { $0.kind != .createdFolder }.count }
}

/// The only code in Butler that changes the user's files. A removal always goes
/// to the Trash, so every applied plan stays reversible.
public struct PlanApplier: Sendable {
    private let guardrail: PathGuard
    private var manager: FileManager { .default }

    public init(guardrail: PathGuard) {
        self.guardrail = guardrail
    }

    public func apply(
        _ operations: [PlanOperation],
        progress: (@Sendable (Int, PlanOperation) -> Void)? = nil
    ) -> ApplyOutcome {
        var actions: [AppliedAction] = []
        for (index, operation) in operations.enumerated() {
            progress?(index, operation)
            do {
                try perform(operation, into: &actions)
            } catch {
                return ApplyOutcome(actions: actions, failure: error.localizedDescription)
            }
        }
        return ApplyOutcome(actions: actions)
    }

    private func perform(_ operation: PlanOperation, into actions: inout [AppliedAction]) throws {
        switch operation.kind {
        case .mkdir:
            let path = operation.destination
            let url = try guardrail.resolve(path)
            guard !manager.fileExists(atPath: url.path) else {
                throw ButlerError.message("\(path) already exists.")
            }
            for folder in try missingFolders(for: url) + [url] {
                try manager.createDirectory(at: folder, withIntermediateDirectories: false)
                actions.append(AppliedAction(kind: .createdFolder, source: guardrail.relativePath(for: folder) ?? path))
            }
        case .move, .rename:
            let from = try guardrail.resolve(operation.source)
            let to = try guardrail.resolve(operation.destination)
            guard manager.fileExists(atPath: from.path) else {
                throw ButlerError.message("\(operation.source) is gone.")
            }
            guard !manager.fileExists(atPath: to.path) else {
                throw ButlerError.message("\(operation.destination) already exists. Butler never overwrites an item.")
            }
            for folder in try missingFolders(for: to) {
                try manager.createDirectory(at: folder, withIntermediateDirectories: false)
                actions.append(AppliedAction(kind: .createdFolder, source: guardrail.relativePath(for: folder) ?? ""))
            }
            do {
                try manager.moveItem(at: from, to: to)
            } catch {
                throw explained(error, for: from, path: operation.source)
            }
            actions.append(AppliedAction(kind: .moved, source: operation.source, destination: operation.destination))
        case .trash:
            let url = try guardrail.resolve(operation.source)
            guard manager.fileExists(atPath: url.path) else {
                throw ButlerError.message("\(operation.source) is gone.")
            }
            var trashed: NSURL?
            do {
                try manager.trashItem(at: url, resultingItemURL: &trashed)
            } catch {
                throw explained(error, for: url, path: operation.source)
            }
            actions.append(AppliedAction(
                kind: .trashed,
                source: operation.source,
                trashPath: (trashed as URL?)?.path
            ))
        }
    }

    /// The system blames the destination folder's permissions when the item is
    /// locked. Butler checks the real cause and says that instead.
    private func explained(_ error: Error, for url: URL, path: String) -> Error {
        let locked = (try? url.resourceValues(forKeys: [.isUserImmutableKey]))?.isUserImmutable == true
        guard locked else { return error }
        return ButlerError.message("\(path) is locked in Finder (Get Info), so it was not moved.")
    }

    public func undo(_ actions: [AppliedAction]) -> ApplyOutcome {
        var undone: [AppliedAction] = []
        for action in actions.reversed() {
            do {
                switch action.kind {
                case .moved:
                    let from = try guardrail.resolve(action.destination)
                    let to = try guardrail.resolve(action.source)
                    guard manager.fileExists(atPath: from.path) else { continue }
                    try manager.createDirectory(
                        at: to.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    guard !manager.fileExists(atPath: to.path) else {
                        throw ButlerError.message("\(action.source) exists again, so Butler did not move the item back.")
                    }
                    try manager.moveItem(at: from, to: to)
                case .trashed:
                    guard let trashPath = action.trashPath else {
                        throw ButlerError.message("\(action.source) is in the Trash. Butler did not record where.")
                    }
                    let to = try guardrail.resolve(action.source)
                    try manager.createDirectory(
                        at: to.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try manager.moveItem(at: URL(fileURLWithPath: trashPath), to: to)
                case .createdFolder:
                    try removeCreatedFolder(action.source)
                }
                undone.append(action)
            } catch {
                return ApplyOutcome(actions: undone, failure: error.localizedDescription)
            }
        }
        return ApplyOutcome(actions: undone)
    }

    /// Butler removes only an empty folder that Butler itself created, so no
    /// user content can be deleted by an undo.
    private func removeCreatedFolder(_ path: String) throws {
        let url = try guardrail.resolve(path)
        guard manager.fileExists(atPath: url.path) else { return }
        let contents = try manager.contentsOfDirectory(atPath: url.path)
        guard contents.isEmpty else { return }
        try manager.removeItem(at: url)
    }

    private func missingFolders(for url: URL) throws -> [URL] {
        var missing: [URL] = []
        var parent = url.deletingLastPathComponent()
        while parent.path.count > guardrail.root.path.count, !manager.fileExists(atPath: parent.path) {
            missing.append(parent)
            parent = parent.deletingLastPathComponent()
        }
        return missing.reversed()
    }
}
