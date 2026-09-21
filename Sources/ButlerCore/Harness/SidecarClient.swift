import Foundation
import FoldHarnessV1

enum SidecarSignal: Sendable {
    case event(FHEvent)
    case settled(runId: String, turnId: String, status: String)
    case diagnostic(String)
    case toolCancelled(callId: String)
    case stopped(code: Int32)
}

struct RunIdentity: Sendable, Equatable {
    let runId: String
    let turnId: String
}

typealias ToolHandler = @Sendable (FHSidecarToolCallParamsClass) async -> Harness.ToolResult

/// A JSON-RPC client for one sidecar process. Incoming frames are dispatched on
/// `method` first: the sidecar owns an id sequence of its own.
actor SidecarClient {
    private let launch: SidecarLaunch
    private var process: SidecarProcess?
    private var nextId = 0
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var toolHandler: ToolHandler?
    private var isClosed = false

    private let lines: AsyncStream<Data>
    private let lineSink: AsyncStream<Data>.Continuation
    private let signalSink: AsyncStream<SidecarSignal>.Continuation
    nonisolated let signals: AsyncStream<SidecarSignal>

    public init(launch: SidecarLaunch) {
        self.launch = launch
        var lineSink: AsyncStream<Data>.Continuation!
        lines = AsyncStream { lineSink = $0 }
        self.lineSink = lineSink
        var signalSink: AsyncStream<SidecarSignal>.Continuation!
        signals = AsyncStream { signalSink = $0 }
        self.signalSink = signalSink
    }

    func setToolHandler(_ handler: @escaping ToolHandler) {
        toolHandler = handler
    }

    func start(client: Harness.ClientInfo) async throws -> FHSidecarInitializeResultClass {
        let sink = lineSink
        let signals = signalSink
        process = try SidecarProcess(
            launch: launch,
            onLine: { sink.yield($0) },
            onDiagnostic: { signals.yield(.diagnostic($0)) },
            onExit: { code in
                signals.yield(.stopped(code: code))
                sink.finish()
            }
        )
        Task { await self.readLoop() }
        let result = try await send("harness/initialize", Harness.InitializeParams(client: client))
        return try decode(FHSidecarInitializeResultClass.self, from: result)
    }

    func profile(_ adapterId: String) async throws -> FHEngineProfileDiscovery {
        try decode(FHEngineProfileDiscovery.self, from:
            try await send("harness/profile", Harness.DiscoveryParams(adapterId: adapterId)))
    }

    func models(_ adapterId: String) async throws -> FHModelCatalogDiscovery {
        try decode(FHModelCatalogDiscovery.self, from:
            try await send("harness/models", Harness.DiscoveryParams(adapterId: adapterId)))
    }

    func limits(_ adapterId: String) async throws -> FHLimitSnapshotDiscovery {
        try decode(FHLimitSnapshotDiscovery.self, from:
            try await send("harness/limits", Harness.DiscoveryParams(adapterId: adapterId)))
    }

    func startRun(_ params: Harness.RunStartParams) async throws -> RunIdentity {
        let result = try await send("harness/run/start", params)
        guard let runId = result["runId"]?.stringValue, let turnId = result["turnId"]?.stringValue else {
            throw ButlerError.message("The sidecar started a run without an identity.")
        }
        return RunIdentity(runId: runId, turnId: turnId)
    }

    func cancel(runId: String) async throws {
        _ = try await send("harness/run/cancel", Harness.RunParams(runId: runId))
    }

    func shutdown() async {
        guard !isClosed else { return }
        _ = try? await send("harness/shutdown", Harness.Empty())
        close()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        process?.terminate()
        process = nil
        for continuation in pending.values {
            continuation.resume(throwing: ButlerError.message("The sidecar stopped."))
        }
        pending.removeAll()
        lineSink.finish()
        signalSink.finish()
    }

    private func send<Params: Encodable>(_ method: String, _ params: Params) async throws -> JSONValue {
        guard let process, !isClosed else { throw ButlerError.message("The sidecar is not running.") }
        nextId += 1
        let id = nextId
        let data = try JSONEncoder().encode(Harness.Request(id: id, method: method, params: params))
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            process.write(data)
        }
    }

    private func readLoop() async {
        for await line in lines {
            guard let frame = try? JSONDecoder().decode(JSONValue.self, from: line) else { continue }
            if let method = frame["method"]?.stringValue {
                await handle(method: method, frame: frame, line: line)
            } else if let id = frame["id"]?.intValue {
                resume(id: id, frame: frame)
            }
        }
    }

    private func handle(method: String, frame: JSONValue, line: Data) async {
        switch method {
        case "host/tool/call":
            await answerToolCall(frame: frame, line: line)
        case "harness/event":
            guard let event = try? decodeNested(FHEvent.self, from: line, key: "event") else { return }
            signalSink.yield(.event(event))
        case "harness/run/settled":
            guard let params = frame["params"],
                  let runId = params["runId"]?.stringValue,
                  let turnId = params["turnId"]?.stringValue,
                  let status = params["status"]?.stringValue else { return }
            signalSink.yield(.settled(runId: runId, turnId: turnId, status: status))
        case "harness/diagnostic":
            let message = frame["params"]?["diagnostic"]?["message"]?.stringValue ?? "diagnostic"
            signalSink.yield(.diagnostic(message))
        case "host/tool/cancel":
            guard let callId = frame["params"]?["callId"]?.stringValue else { return }
            signalSink.yield(.toolCancelled(callId: callId))
        default:
            break
        }
    }

    private func answerToolCall(frame: JSONValue, line: Data) async {
        guard let id = frame["id"]?.intValue else { return }
        guard let call = try? decodeNested(FHSidecarToolCallParamsClass.self, from: line, key: "params") else {
            reply(id: id, result: .failure("The tool call could not be read.", code: "TOOL_INPUT_INVALID"))
            return
        }
        guard let toolHandler else {
            reply(id: id, result: .failure("No tool is available in this turn.", code: "TOOL_NOT_FOUND"))
            return
        }
        let result = await toolHandler(call)
        reply(id: id, result: result)
    }

    private func reply(id: Int, result: Harness.ToolResult) {
        guard let process, let data = try? JSONEncoder().encode(Harness.Response(id: id, result: result)) else { return }
        process.write(data)
    }

    private func resume(id: Int, frame: JSONValue) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        if let error = frame["error"] {
            continuation.resume(throwing: ButlerError.message(Self.describe(error)))
        } else {
            continuation.resume(returning: frame["result"] ?? .null)
        }
    }

    private static func describe(_ error: JSONValue) -> String {
        let message = error["message"]?.stringValue ?? "The sidecar reported an error."
        let issues = error["data"]?["issues"]?.arrayValue?.compactMap { $0["message"]?.stringValue } ?? []
        return issues.isEmpty ? message : "\(message) \(issues.joined(separator: " "))"
    }

    private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        try JSONDecoder().decode(type, from: try JSONEncoder().encode(value))
    }

    private func decodeNested<T: Decodable>(_ type: T.Type, from line: Data, key: String) throws -> T {
        let frame = try JSONDecoder().decode(JSONValue.self, from: line)
        guard let params = frame["params"] else {
            throw ButlerError.message("The sidecar frame has no parameters.")
        }
        let target = key == "params" ? params : params[key]
        guard let target else { throw ButlerError.message("The sidecar frame has no \(key).") }
        return try decode(type, from: target)
    }
}
