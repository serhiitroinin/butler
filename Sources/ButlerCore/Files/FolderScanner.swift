import Foundation
import UniformTypeIdentifiers

public struct FolderEntry: Sendable, Hashable, Codable, Identifiable {
    public var path: String
    public var name: String
    public var isDirectory: Bool
    public var size: Int64?
    public var created: Date?
    public var modified: Date?
    public var childCount: Int?
    public var typeIdentifier: String?

    public var id: String { path }
    public var isPackage: Bool { isDirectory && PathGuard.isPackageName(name) }
    public var fileExtension: String { (name as NSString).pathExtension.lowercased() }
}

public struct FolderListing: Sendable {
    public let path: String
    public let entries: [FolderEntry]
    public let truncated: Bool
}

/// Reads bounded folder metadata. Hidden items never appear: the agent must not
/// learn about them and the app must never move them.
public struct FolderScanner: Sendable {
    public static let maxEntriesPerFolder = 400
    public static let maxSnapshotEntries = 1200

    public let guardrail: PathGuard

    public init(root: URL) {
        guardrail = PathGuard(root: root)
    }

    public func list(path: String, depth: Int = 1) throws -> FolderListing {
        var entries: [FolderEntry] = []
        var truncated = false
        try collect(
            path: path,
            depth: max(1, min(depth, 3)),
            limit: Self.maxEntriesPerFolder,
            entries: &entries,
            truncated: &truncated
        )
        return FolderListing(path: path, entries: entries, truncated: truncated)
    }

    public func snapshot(depth: Int = 2, limit: Int = maxSnapshotEntries) throws -> [FolderEntry] {
        var entries: [FolderEntry] = []
        var truncated = false
        try collect(path: ".", depth: depth, limit: limit, entries: &entries, truncated: &truncated)
        return entries
    }

    /// Every path under the root, used to validate a plan as one transaction.
    public func allPaths() throws -> [String: Bool] {
        var result: [String: Bool] = [:]
        var queue = [""]
        while let current = queue.popLast() {
            let url = current.isEmpty ? guardrail.root : guardrail.root.appendingPathComponent(current)
            for child in try children(of: url) {
                let relative = current.isEmpty ? child.name : "\(current)/\(child.name)"
                result[relative] = child.isDirectory
                if child.isDirectory && !child.isPackage { queue.append(relative) }
            }
        }
        return result
    }

    private func collect(
        path: String,
        depth: Int,
        limit: Int,
        entries: inout [FolderEntry],
        truncated: inout Bool
    ) throws {
        let url = try guardrail.resolve(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ButlerError.message("\(path): there is no such folder.")
        }
        guard isDirectory.boolValue else {
            throw ButlerError.message("\(path): that is a file. Use inspect_file for a file.")
        }
        var queue: [(URL, String, Int)] = [(url, guardrail.relativePath(for: url) ?? "", depth)]
        while !queue.isEmpty {
            let (folder, prefix, remaining) = queue.removeFirst()
            let found = try children(of: folder)
            for child in found {
                if entries.count >= limit {
                    truncated = true
                    return
                }
                var entry = child
                entry.path = prefix.isEmpty ? child.name : "\(prefix)/\(child.name)"
                entries.append(entry)
                if remaining > 1 && entry.isDirectory && !entry.isPackage {
                    queue.append((folder.appendingPathComponent(child.name), entry.path, remaining - 1))
                }
            }
        }
    }

    private func children(of folder: URL) throws -> [FolderEntry] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey,
            .contentTypeKey, .isSymbolicLinkKey,
        ]
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        return contents.compactMap { url -> FolderEntry? in
            let name = url.lastPathComponent
            if PathGuard.isHidden(name) { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { return nil }
            let isDirectory = values?.isDirectory ?? false
            return FolderEntry(
                path: name,
                name: name,
                isDirectory: isDirectory,
                size: values?.fileSize.map(Int64.init),
                created: values?.creationDate,
                modified: values?.contentModificationDate,
                childCount: isDirectory ? countChildren(url) : nil,
                typeIdentifier: values?.contentType?.identifier
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func countChildren(_ url: URL) -> Int? {
        try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).count
    }
}
