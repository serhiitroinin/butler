import Foundation

struct SidecarLaunch: Sendable {
    let sidecarDirectory: URL
    let storeDirectory: URL
    let dataDirectory: URL
    let offline: Bool
    let environment: ToolEnvironment

    public init(
        sidecarDirectory: URL,
        storeDirectory: URL,
        dataDirectory: URL,
        offline: Bool,
        environment: ToolEnvironment
    ) {
        self.sidecarDirectory = sidecarDirectory
        self.storeDirectory = storeDirectory
        self.dataDirectory = dataDirectory
        self.offline = offline
        self.environment = environment
    }

    var hostModule: URL { sidecarDirectory.appendingPathComponent("host.mjs") }
    var executable: URL {
        sidecarDirectory.appendingPathComponent("node_modules/.bin/fold-harness-sidecar")
    }
}

/// Owns the sidecar child process, its newline framing, and its lifetime.
final class SidecarProcess: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var buffer = Data()
    private let writeLock = NSLock()

    init(
        launch: SidecarLaunch,
        onLine: @escaping @Sendable (Data) -> Void,
        onDiagnostic: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws {
        guard let node = launch.environment.node else {
            throw ButlerError.message("Butler could not find node on this Mac.")
        }
        for directory in [launch.storeDirectory, launch.dataDirectory] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        guard FileManager.default.isReadableFile(atPath: launch.hostModule.path) else {
            throw ButlerError.message("The sidecar host module is missing: \(launch.hostModule.path)")
        }

        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [
            launch.executable.path,
            "--host", launch.hostModule.path,
            "--store", launch.storeDirectory.path,
        ]
        process.currentDirectoryURL = launch.sidecarDirectory
        process.environment = launch.environment.childEnvironment(extra: [
            "BUTLER_DATA_DIR": launch.dataDirectory.path,
            "BUTLER_OFFLINE": launch.offline ? "1" : "0",
            "NO_COLOR": "1",
            "BUTLER_OFFLINE_DELAY_MS": ProcessInfo.processInfo.environment["BUTLER_OFFLINE_DELAY_MS"] ?? "0",
        ])
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty { return }
            self.buffer.append(data)
            while let index = self.buffer.firstIndex(of: 0x0A) {
                let line = self.buffer.subdata(in: self.buffer.startIndex..<index)
                self.buffer.removeSubrange(self.buffer.startIndex...index)
                if !line.isEmpty { onLine(line) }
            }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            onDiagnostic(text)
        }
        process.terminationHandler = { finished in onExit(finished.terminationStatus) }
        try process.run()
    }

    func write(_ data: Data) {
        writeLock.lock()
        defer { writeLock.unlock() }
        var frame = data
        frame.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: frame)
    }

    func terminate() {
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}
