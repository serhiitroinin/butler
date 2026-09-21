import Foundation

/// Turns an untrusted relative path into a URL inside the managed root, or
/// explains the refusal in words written for the model.
public struct PathGuard: Sendable {
    public let root: URL

    private static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "xcodeproj", "xcworkspace", "photoslibrary",
        "rtfd", "sparsebundle", "download", "fcpbundle", "logicx", "band",
    ]

    public init(root: URL) {
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
    }

    public func resolve(_ relative: String) throws -> URL {
        let trimmed = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." { return root }
        guard !trimmed.hasPrefix("/") else {
            throw ButlerError.message("\(relative): use a path relative to the folder, not an absolute path.")
        }
        guard !trimmed.contains("\0") else {
            throw ButlerError.message("\(relative): the path contains an invalid character.")
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.contains("") else {
            throw ButlerError.message("\(relative): remove the empty path segment.")
        }
        guard !components.contains("..") && !components.contains(".") else {
            throw ButlerError.message("\(relative): '.' and '..' are not allowed. Give a plain path inside the folder.")
        }
        for component in components where component.hasPrefix(".") {
            throw ButlerError.message("\(relative): hidden items are out of scope.")
        }
        for component in components.dropLast() where Self.isPackageName(component) {
            throw ButlerError.message("\(relative): '\(component)' is an application package. Never look inside one.")
        }
        let url = root.appendingPathComponent(components.joined(separator: "/")).standardizedFileURL
        try checkEscape(url, relative: relative)
        return url
    }

    /// A destination may not exist yet, so the nearest existing ancestor is the
    /// one that can hide a symbolic link out of the root.
    private func checkEscape(_ url: URL, relative: String) throws {
        guard url.path.hasPrefix(root.path + "/") else {
            throw ButlerError.message("\(relative): that path is outside the folder.")
        }
        var probe = url
        while probe.path.count > root.path.count, !FileManager.default.fileExists(atPath: probe.path) {
            probe = probe.deletingLastPathComponent()
        }
        let resolved = probe.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
            throw ButlerError.message("\(relative): that path leaves the folder through a link.")
        }
    }

    public func relativePath(for url: URL) -> String? {
        let standard = url.standardizedFileURL.path
        if standard == root.path { return "" }
        guard standard.hasPrefix(root.path + "/") else { return nil }
        return String(standard.dropFirst(root.path.count + 1))
    }

    public static func isPackageName(_ name: String) -> Bool {
        let suffix = (name as NSString).pathExtension.lowercased()
        return !suffix.isEmpty && packageExtensions.contains(suffix)
    }

    public static func isHidden(_ name: String) -> Bool {
        name.hasPrefix(".")
    }
}
