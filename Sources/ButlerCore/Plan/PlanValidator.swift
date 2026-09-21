import Foundation

public struct PlanIssue: Sendable, Hashable, Identifiable {
    public let id = UUID()
    public let operationId: UUID?
    public let message: String

    public init(operationId: UUID?, message: String) {
        self.operationId = operationId
        self.message = message
    }
}

public struct PlanValidation: Sendable {
    public let issues: [PlanIssue]
    /// Every path that exists after the valid operations were simulated.
    public let result: [String: Bool]

    public var isValid: Bool { issues.isEmpty }
}

/// Validates a plan as one transaction against a snapshot of the folder.
public struct PlanValidator: Sendable {
    public static let maximumDepth = 4
    private let guardrail: PathGuard
    private let start: [String: Bool]

    public init(guardrail: PathGuard, existing: [String: Bool]) {
        self.guardrail = guardrail
        start = existing
    }

    public init(scanner: FolderScanner) throws {
        self.init(guardrail: scanner.guardrail, existing: try scanner.allPaths())
    }

    public func validate(_ operations: [PlanOperation]) -> PlanValidation {
        var tree = start
        var issues: [PlanIssue] = []
        for operation in operations {
            do {
                try apply(operation, to: &tree)
            } catch {
                issues.append(PlanIssue(
                    operationId: operation.id,
                    message: error.localizedDescription
                ))
            }
        }
        return PlanValidation(issues: issues, result: tree)
    }

    private func apply(_ operation: PlanOperation, to tree: inout [String: Bool]) throws {
        switch operation.kind {
        case .mkdir:
            let path = try checked(operation.destination, field: "path")
            if let existing = tree[path] {
                throw ButlerError.message(existing
                    ? "\(path) already exists. Remove this mkdir and move files into it directly."
                    : "\(path) already exists as a file. Choose another folder name.")
            }
            try makeFolders(path, in: &tree)
        case .move, .rename:
            let from = try checked(operation.source, field: "from")
            let to = try checked(operation.destination, field: "to")
            if operation.kind == .rename,
               (from as NSString).deletingLastPathComponent != (to as NSString).deletingLastPathComponent {
                throw ButlerError.message("\(from): a rename keeps the item in its folder. Use a move instead.")
            }
            guard let isDirectory = tree[from] else {
                throw ButlerError.message("\(from) does not exist at this point in the plan.")
            }
            if tree[to] != nil {
                throw ButlerError.message("\(to) already exists. Butler never overwrites an item.")
            }
            if isDirectory && (to == from || to.hasPrefix(from + "/")) {
                throw ButlerError.message("\(to) is inside \(from). A folder cannot move into itself.")
            }
            let parent = (to as NSString).deletingLastPathComponent
            if !parent.isEmpty && tree[parent] != true {
                throw ButlerError.message("\(parent) does not exist yet. Add a mkdir for it before this move.")
            }
            if operation.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ButlerError.message("\(from): give a short reason for this change.")
            }
            relocate(from: from, to: to, in: &tree)
        case .trash:
            let path = try checked(operation.source, field: "path")
            guard tree[path] != nil else {
                throw ButlerError.message("\(path) does not exist at this point in the plan.")
            }
            if operation.reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 12 {
                throw ButlerError.message("\(path): a trash operation needs a strong written reason.")
            }
            remove(path, in: &tree)
        }
    }

    private func checked(_ raw: String, field: String) throws -> String {
        let url = try guardrail.resolve(raw)
        guard let relative = guardrail.relativePath(for: url), !relative.isEmpty else {
            throw ButlerError.message("\(field): the managed folder itself cannot be the target.")
        }
        let depth = relative.split(separator: "/").count
        guard depth <= Self.maximumDepth else {
            throw ButlerError.message("\(relative) is \(depth) levels deep. Keep the folder tree at most \(Self.maximumDepth) levels.")
        }
        return relative
    }

    private func makeFolders(_ path: String, in tree: inout [String: Bool]) throws {
        var built = ""
        for component in path.split(separator: "/") {
            built = built.isEmpty ? String(component) : "\(built)/\(component)"
            if let isDirectory = tree[built] {
                if !isDirectory {
                    throw ButlerError.message("\(built) is a file, so \(path) cannot be created.")
                }
                continue
            }
            tree[built] = true
        }
    }

    private func relocate(from: String, to: String, in tree: inout [String: Bool]) {
        for (path, isDirectory) in tree where path == from || path.hasPrefix(from + "/") {
            tree.removeValue(forKey: path)
            tree[to + path.dropFirst(from.count)] = isDirectory
        }
    }

    private func remove(_ path: String, in tree: inout [String: Bool]) {
        for key in tree.keys where key == path || key.hasPrefix(path + "/") {
            tree.removeValue(forKey: key)
        }
    }
}
