import Foundation

/// A GUI process does not inherit the terminal PATH, so the tools are resolved
/// through a login shell exactly once and reused for every child process.
public struct ToolEnvironment: Sendable {
    public let path: String
    public let node: String?
    public let claude: String?
    public let codex: String?

    public var isReady: Bool { node != nil }

    public static func resolve() -> ToolEnvironment {
        let path = loginShellPath() ?? ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        return ToolEnvironment(
            path: path,
            node: locate("node", in: path),
            claude: locate("claude", in: path),
            codex: locate("codex", in: path)
        )
    }

    public func childEnvironment(extra: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = path
        for (key, value) in extra { environment[key] = value }
        return environment
    }

    static func loginShellPath() -> String? {
        guard let output = run("/bin/zsh", ["-lc", "printf %s \"$PATH\""]) else { return nil }
        return output.isEmpty ? nil : output
    }

    static func locate(_ name: String, in path: String) -> String? {
        for directory in path.split(separator: ":") {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private static func run(_ launchPath: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
