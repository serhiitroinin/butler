import Foundation
import FoldHarnessV1

public struct RecordedProposal: Sendable {
    public let summary: String
    public let operations: [PlanOperation]
}

public enum ToolActivity: Sendable {
    case listed(path: String, count: Int)
    case inspected(path: String)
    case proposed(count: Int)
    case refused(tool: String, message: String)
}

/// Every tool the agent can reach. The host reads metadata and records one
/// proposal. It never changes a file.
public actor ButlerToolHost {
    public let root: URL
    private let scanner: FolderScanner
    private let inspector: FileInspector
    private var recorded: RecordedProposal?
    private let onActivity: @Sendable (ToolActivity) -> Void

    public init(root: URL, onActivity: @escaping @Sendable (ToolActivity) -> Void = { _ in }) {
        self.root = root
        scanner = FolderScanner(root: root)
        inspector = FileInspector(guardrail: PathGuard(root: root))
        self.onActivity = onActivity
    }

    nonisolated var descriptors: [Harness.ToolDescriptor] { ToolCatalog.descriptors }

    public func takeProposal() -> RecordedProposal? {
        defer { recorded = nil }
        return recorded
    }

    func call(_ params: FHSidecarToolCallParamsClass) -> Harness.ToolResult {
        do {
            switch params.name {
            case ToolCatalog.listFolder:
                return .text(try listFolder(params.input))
            case ToolCatalog.inspectFile:
                return .text(try inspectFile(params.input))
            case ToolCatalog.proposePlan:
                return .text(try proposePlan(params.input))
            default:
                return .failure("Butler has no tool named \(params.name).", code: "TOOL_NOT_FOUND")
            }
        } catch {
            onActivity(.refused(tool: params.name, message: error.localizedDescription))
            return .failure(error.localizedDescription, code: "TOOL_INPUT_INVALID")
        }
    }

    private func listFolder(_ input: JSONValue) throws -> String {
        let path = input["path"]?.stringValue ?? "."
        let listing = try scanner.list(path: path, depth: input["depth"]?.intValue ?? 1)
        onActivity(.listed(path: path, count: listing.entries.count))
        return try JSONValue.object([
            "path": .string(path),
            "truncated": .bool(listing.truncated),
            "entries": .array(listing.entries.map(Self.describe)),
        ]).encodedString()
    }

    private func inspectFile(_ input: JSONValue) throws -> String {
        guard let path = input["path"]?.stringValue else {
            throw ButlerError.message("inspect_file needs a 'path'.")
        }
        let details = try inspector.inspect(path: path)
        onActivity(.inspected(path: path))
        return try JSONValue.object(details).encodedString()
    }

    private func proposePlan(_ input: JSONValue) throws -> String {
        let decoded = try PlanDecoder.decode(input)
        let validator = try PlanValidator(scanner: scanner)
        let validation = validator.validate(decoded.operations)
        guard validation.isValid else {
            throw ButlerError.message("The plan is not valid yet. Fix every problem and call propose_plan again:\n- "
                + validation.issues.map(\.message).joined(separator: "\n- "))
        }
        recorded = RecordedProposal(summary: decoded.summary, operations: decoded.operations)
        onActivity(.proposed(count: decoded.operations.count))
        return "The plan is recorded and shown to the user. End your turn now."
    }

    static func describe(_ entry: FolderEntry) -> JSONValue {
        var value: [String: JSONValue] = [
            "name": .string(entry.name),
            "path": .string(entry.path),
            "kind": .string(entry.isDirectory ? "folder" : "file"),
        ]
        if !entry.fileExtension.isEmpty { value["ext"] = .string(entry.fileExtension) }
        if let type = entry.typeIdentifier { value["type"] = .string(type) }
        if let size = entry.size { value["sizeBytes"] = .double(Double(size)) }
        if let created = entry.created { value["created"] = .string(FileInspector.stamp(created)) }
        if let modified = entry.modified { value["modified"] = .string(FileInspector.stamp(modified)) }
        if let children = entry.childCount { value["itemCount"] = .number(children) }
        return .object(value)
    }
}
