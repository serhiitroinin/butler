import Foundation
import UniformTypeIdentifiers

public enum InclusionState: Sendable, Hashable {
    case included
    case excluded
    case mixed
}

/// One row of the proposal table. A folder row holds the folders and files
/// inside it, as Finder's list view does.
public struct PlanTableNode: Identifiable, Sendable, Hashable {
    public enum Role: Sendable, Hashable {
        case destination(isNew: Bool)
        case trash
        case file(OperationKindMark)
    }

    public var id: String
    public var role: Role
    public var name: String
    public var previousName: String?
    /// The source of a file in the Changes and After views, and where it goes
    /// in the Before view.
    public var destination: String
    public var kindLabel: String
    public var size: Int64?
    /// An absolute path, for the icon, Quick Look, and Finder.
    public var path: String
    public var reason: String
    public var operationIds: [UUID]
    public var children: [PlanTableNode]?

    public var isFolder: Bool {
        if case .file = role { return false }
        return true
    }

    public var isNewFolder: Bool {
        if case let .destination(isNew) = role { return isNew }
        return false
    }

    public var sortableSize: Int64 { size ?? -1 }
}

public enum PlanTable {
    /// Every file row, wherever it sits in the outline.
    public static func files(in nodes: [PlanTableNode]) -> [PlanTableNode] {
        nodes.flatMap { node -> [PlanTableNode] in
            node.isFolder ? files(in: node.children ?? []) : [node]
        }
    }

    /// The one source every file comes from, when they all come from one place.
    public static func commonSource(in nodes: [PlanTableNode]) -> String? {
        let sources = files(in: nodes).map(\.destination)
        guard let first = sources.first, sources.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// The flat grouping the proposal page draws: one node per destination folder,
    /// named by its whole path, with its files as children.
    public static func destinations(
        mode: StageMode,
        plan: Plan,
        included: [PlanOperation],
        root: URL
    ) -> [PlanTableNode] {
        let counterpart = counterparts(mode: mode, plan: plan)
        let all = StageBuilder.groups(mode: mode, plan: plan, included: included, root: root)
        var adopted: [String: [UUID]] = [:]
        for parent in all where parent.rows.isEmpty && !parent.isTrash {
            let child = all.first {
                !$0.rows.isEmpty && $0.folder.hasPrefix(parent.folder.isEmpty ? "" : parent.folder + "/")
            }
            guard let child else { continue }
            adopted[child.id, default: []] += parent.creationIds
        }
        return all.filter { !$0.rows.isEmpty || $0.isTrash }.map { group in
            let rows = group.rows.map { row in
                file(row, in: group, mode: mode, root: root, counterpart: counterpart)
            }
            return PlanTableNode(
                id: "folder:\(group.id)",
                role: group.isTrash ? .trash : .destination(isNew: group.isNew),
                name: group.isTrash ? "Trash" : (group.folder.isEmpty ? "Top Level" : group.folder),
                destination: "",
                kindLabel: group.isTrash ? "" : (group.isNew ? "New Folder" : "Folder"),
                size: rows.compactMap(\.size).reduce(0, +),
                path: root.appendingPathComponent(group.folder).path,
                reason: "",
                operationIds: group.creationIds + rows.flatMap(\.operationIds) + (adopted[group.id] ?? []),
                children: rows
            )
        }
    }

    public static func nodes(
        mode: StageMode,
        plan: Plan,
        included: [PlanOperation],
        root: URL
    ) -> [PlanTableNode] {
        let groups = StageBuilder.groups(mode: mode, plan: plan, included: included, root: root)
        let counterpart = counterparts(mode: mode, plan: plan)
        var tree = Branch()
        var trash: PlanTableNode?

        for group in groups {
            let rows = group.rows.map { row in
                file(row, in: group, mode: mode, root: root, counterpart: counterpart)
            }
            if group.isTrash {
                trash = PlanTableNode(
                    id: "folder:«trash»",
                    role: .trash,
                    name: "Trash",
                    destination: "",
                    kindLabel: "",
                    path: root.path,
                    reason: "",
                    operationIds: group.rows.compactMap(\.operationId),
                    children: rows
                )
                continue
            }
            tree.insert(
                components: group.folder.isEmpty ? [] : group.folder.components(separatedBy: "/"),
                files: rows,
                creationIds: group.creationIds,
                isNew: group.isNew
            )
        }

        var result = tree.nodes(prefix: "", root: root)
        if let trash { result.append(trash) }
        return result
    }

    /// A node of the folder outline while it is being built from path parts.
    private struct Branch {
        var order: [String] = []
        var children: [String: Branch] = [:]
        var files: [PlanTableNode] = []
        var creationIds: [UUID] = []
        var isNew = false

        mutating func insert(
            components: [String],
            files rows: [PlanTableNode],
            creationIds ids: [UUID],
            isNew new: Bool
        ) {
            guard let first = components.first else {
                files += rows
                creationIds += ids
                isNew = isNew || new
                return
            }
            if children[first] == nil {
                order.append(first)
                children[first] = Branch()
            }
            children[first]?.insert(
                components: Array(components.dropFirst()),
                files: rows,
                creationIds: ids,
                isNew: new
            )
        }

        func nodes(prefix: String, root: URL) -> [PlanTableNode] {
            let folders = order.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .compactMap { name -> PlanTableNode? in
                    guard let branch = children[name] else { return nil }
                    let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
                    let inside = branch.nodes(prefix: path, root: root)
                    return PlanTableNode(
                        id: "folder:\(path)",
                        role: .destination(isNew: branch.isNew),
                        name: name,
                        destination: "",
                        kindLabel: branch.isNew ? "New Folder" : "Folder",
                        size: nil,
                        path: root.appendingPathComponent(path).path,
                        reason: "",
                        operationIds: branch.creationIds + inside.flatMap(\.operationIds),
                        children: inside
                    )
                }
            return folders + files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    private static func file(
        _ row: StageRow,
        in group: StageGroup,
        mode: StageMode,
        root: URL,
        counterpart: [String: String]
    ) -> PlanTableNode {
        let url = URL(fileURLWithPath: row.iconPath)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        return PlanTableNode(
            id: "file:\(group.id):\(row.id)",
            role: .file(row.mark),
            name: row.name,
            previousName: row.previousName,
            destination: destination(row, group: group, counterpart: counterpart),
            kindLabel: kind(of: row.name, contentType: values?.contentType),
            size: values?.fileSize.map(Int64.init),
            path: row.iconPath,
            reason: row.reason,
            operationIds: row.operationId.map { [$0] } ?? [],
            children: nil
        )
    }

    /// The other end of a move, so the table can say where a file comes from in
    /// the Changes and After views and where it goes in the Before view.
    private static func counterparts(mode: StageMode, plan: Plan) -> [String: String] {
        var result: [String: String] = [:]
        for operation in plan.operations where operation.kind == .move || operation.kind == .rename {
            switch mode {
            case .changes, .after: result[operation.source] = operation.sourceFolder
            case .before: result[operation.source] = operation.destinationFolder
            }
        }
        if mode == .before {
            for operation in plan.operations where operation.kind == .trash {
                result[operation.source] = "Trash"
            }
        }
        return result
    }

    private static func destination(
        _ row: StageRow,
        group: StageGroup,
        counterpart: [String: String]
    ) -> String {
        if group.isTrash { return "Trash" }
        guard let other = counterpart[row.id] else { return "" }
        return other.isEmpty ? "Top Level" : other
    }

    /// One source for the Kind column: the system's description of the type,
    /// from the file when it can be read and from the extension when not, so
    /// every row reads the same way ("PDF document").
    static func kind(of name: String, contentType: UTType?) -> String {
        let suffix = (name as NSString).pathExtension
        if let described = (contentType ?? UTType(filenameExtension: suffix))?.localizedDescription {
            return described
        }
        return suffix.isEmpty ? "Document" : suffix.uppercased() + " document"
    }
}

extension PlanSelection {
    /// The state of a whole subtree, so a folder row can show a mixed checkbox.
    public func state(of operationIds: [UUID], in plan: Plan) -> InclusionState {
        let operations = plan.operations.filter { operationIds.contains($0.id) }
        guard !operations.isEmpty else { return .included }
        let on = operations.filter(isIncluded).count
        if on == operations.count { return .included }
        return on == 0 ? .excluded : .mixed
    }

    public mutating func setIncluded(_ operationIds: [UUID], to included: Bool, in plan: Plan) {
        for operation in plan.operations where operationIds.contains(operation.id) {
            if isIncluded(operation) != included { toggle(operation) }
        }
    }
}
