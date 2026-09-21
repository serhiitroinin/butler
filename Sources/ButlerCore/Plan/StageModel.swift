import Foundation

public enum OperationKindMark: Sendable, Equatable {
    case newFolder
    case moved
    case renamed
    case trashed
    case unchanged
}

public enum StageMode: String, CaseIterable, Identifiable {
    public static let allCases: [StageMode] = [.changes, .before, .after]
    case changes = "Changes"
    case before = "Before"
    case after = "After"

    public var id: String { rawValue }
}

public struct StageRow: Identifiable, Equatable, Sendable {
    /// The identity of the FILE, not of the row, so a file keeps its row when
    /// the stage changes and visibly travels to its new folder.
    public let id: String
    public let group: String
    public let name: String
    public let previousName: String?
    public let iconPath: String
    public let mark: OperationKindMark
    public let reason: String
    public let sourcePath: String
    public let operationId: UUID?
}

public struct StageGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let folder: String
    public let isNew: Bool
    public let isTrash: Bool
    /// The mkdir operations that create this folder.
    public var creationIds: [UUID] = []
    public var rows: [StageRow]
}

public enum StageBuilder {
    public static func groups(mode: StageMode, plan: Plan, included: [PlanOperation], root: URL) -> [StageGroup] {
        switch mode {
        case .changes: return changes(plan: plan, root: root)
        case .before: return before(included: included, root: root)
        case .after: return after(included: included, root: root)
        }
    }

    private static func changes(plan: Plan, root: URL) -> [StageGroup] {
        var created: Set<String> = []
        var creationIds: [String: [UUID]] = [:]
        var rows: [String: [StageRow]] = [:]
        var trash: [StageRow] = []
        let origins = origins(of: plan.operations)
        for operation in plan.operations {
            switch operation.kind {
            case .mkdir:
                created.insert(operation.destination)
                creationIds[operation.destination, default: []].append(operation.id)
                rows[operation.destination] = rows[operation.destination] ?? []
            case .move, .rename:
                rows[operation.destinationFolder, default: []].append(StageRow(
                    id: operation.source,
                    group: operation.destinationFolder,
                    name: operation.displayName,
                    previousName: operation.kind == .rename ? operation.previousName : nil,
                    iconPath: root.appendingPathComponent(origins.byOperation[operation.id] ?? operation.source).path,
                    mark: operation.kind == .rename ? .renamed : .moved,
                    reason: operation.reason,
                    sourcePath: operation.source,
                    operationId: operation.id
                ))
            case .trash:
                trash.append(StageRow(
                    id: operation.source,
                    group: "Trash",
                    name: operation.displayName,
                    previousName: nil,
                    iconPath: root.appendingPathComponent(operation.source).path,
                    mark: .trashed,
                    reason: operation.reason,
                    sourcePath: operation.source,
                    operationId: operation.id
                ))
            }
        }
        var result = rows.keys.sorted(by: order).map { folder in
            StageGroup(
                id: folder.isEmpty ? "." : folder,
                folder: folder,
                isNew: created.contains(folder),
                isTrash: false,
                creationIds: creationIds[folder] ?? [],
                rows: rows[folder] ?? []
            )
        }
        if !trash.isEmpty {
            result.append(StageGroup(id: "«trash»", folder: "Trash", isNew: false, isTrash: true, rows: trash))
        }
        return result
    }

    private static func before(included: [PlanOperation], root: URL) -> [StageGroup] {
        guard let paths = try? FolderScanner(root: root).allPaths() else { return [] }
        var marks: [String: OperationKindMark] = [:]
        for operation in included {
            switch operation.kind {
            case .move: marks[operation.source] = .moved
            case .rename: marks[operation.source] = .renamed
            case .trash: marks[operation.source] = .trashed
            case .mkdir: break
            }
        }
        return tree(paths: paths, root: root, identity: { $0 }, marks: marks, created: [])
    }

    private static func after(included: [PlanOperation], root: URL) -> [StageGroup] {
        guard let validator = try? PlanValidator(scanner: FolderScanner(root: root)) else { return [] }
        let paths = validator.validate(included).result
        var marks: [String: OperationKindMark] = [:]
        var identity: [String: String] = [:]
        var created: Set<String> = []
        for operation in included {
            switch operation.kind {
            case .move, .rename:
                marks[operation.destination] = operation.kind == .rename ? .renamed : .moved
                identity[operation.destination] = operation.source
            case .mkdir:
                created.insert(operation.destination)
            case .trash:
                break
            }
        }
        return tree(
            paths: paths,
            root: root,
            identity: { identity[$0] ?? $0 },
            onDisk: origins(of: included).byResult,
            marks: marks,
            created: created
        )
    }

    /// Where each item is on disk now. A plan may move a file and then rename
    /// it, so the second operation's source does not exist yet; the file's
    /// kind, size and icon are read from where the chain started.
    static func origins(of operations: [PlanOperation]) -> (byOperation: [UUID: String], byResult: [String: String]) {
        var byOperation: [UUID: String] = [:]
        var current: [String: String] = [:]
        for operation in operations where operation.kind == .move || operation.kind == .rename {
            let origin = current.removeValue(forKey: operation.source) ?? operation.source
            byOperation[operation.id] = origin
            current[operation.destination] = origin
        }
        return (byOperation, current)
    }

    private static func tree(
        paths: [String: Bool],
        root: URL,
        identity: (String) -> String,
        onDisk: [String: String] = [:],
        marks: [String: OperationKindMark],
        created: Set<String>
    ) -> [StageGroup] {
        var rows: [String: [StageRow]] = [:]
        for (path, isDirectory) in paths {
            let folder = (path as NSString).deletingLastPathComponent
            if isDirectory {
                rows[path] = rows[path] ?? []
                continue
            }
            rows[folder, default: []].append(StageRow(
                id: identity(path),
                group: folder,
                name: (path as NSString).lastPathComponent,
                previousName: nil,
                iconPath: root.appendingPathComponent(onDisk[path] ?? path).path,
                mark: marks[path] ?? .unchanged,
                reason: "",
                sourcePath: path,
                operationId: nil
            ))
        }
        rows[""] = rows[""] ?? []
        return rows.keys.sorted(by: order).map { folder in
            StageGroup(
                id: folder.isEmpty ? "." : folder,
                folder: folder,
                isNew: created.contains(folder),
                isTrash: false,
                rows: (rows[folder] ?? []).sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            )
        }
        .filter { !$0.rows.isEmpty || $0.folder.isEmpty || $0.isNew }
    }

    private static func order(_ left: String, _ right: String) -> Bool {
        if left.isEmpty != right.isEmpty { return left.isEmpty }
        return left.localizedStandardCompare(right) == .orderedAscending
    }
}
