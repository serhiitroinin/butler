import Foundation
import FoldHarnessV1

public enum RunPhase: Sendable, Equatable {
    case idle
    case running
    case proposed
    case cancelled
    case failed(String)

    public var isRunning: Bool { self == .running }
}

public struct ActivityLine: Sendable, Identifiable, Hashable {
    public enum Kind: Sendable, Hashable {
        case tool
        case thinking
        case note
        case failure
    }

    public let id = UUID()
    public let kind: Kind
    public var text: String
    /// The exact text the model received. A failed step shows all of it.
    public var detail: String?
}

public struct RunRequestOptions: Sendable {
    public let folderId: UUID
    public let root: URL
    public let rules: String
    public let choice: EngineChoice
    public let review: ReviewContext?
    public let revision: Int

    public init(
        folderId: UUID,
        root: URL,
        rules: String,
        choice: EngineChoice,
        review: ReviewContext? = nil,
        revision: Int
    ) {
        self.folderId = folderId
        self.root = root
        self.rules = rules
        self.choice = choice
        self.review = review
        self.revision = revision
    }
}

/// One turn. It streams live activity and ends with a recorded plan.
@MainActor
public final class RunController: ObservableObject {
    @Published public private(set) var phase: RunPhase = .idle
    @Published public private(set) var activity: [ActivityLine] = []
    @Published public private(set) var assistantText = ""
    @Published public private(set) var plan: Plan?

    private let service: HarnessService
    private var client: SidecarClient?
    private var toolHost: ButlerToolHost?
    private var identity: RunIdentity?
    private var usage: PlanUsage?
    private var options: RunRequestOptions?

    public init(service: HarnessService) {
        self.service = service
    }

    public func start(_ options: RunRequestOptions) async {
        guard phase != .running else { return }
        guard let engineId = options.choice.engineId else {
            phase = .failed("Choose an engine in Settings before you run Butler.")
            return
        }
        guard let client = service.begin(self) else {
            phase = .failed("Butler is not connected to its sidecar.")
            return
        }
        self.options = options
        self.client = client
        phase = .running
        activity = []
        assistantText = ""
        plan = nil
        usage = nil

        let host = ButlerToolHost(root: options.root) { [weak self] activity in
            Task { @MainActor [weak self] in self?.record(activity) }
        }
        toolHost = host
        await client.setToolHandler { call in await host.call(call) }

        do {
            let entries = try FolderScanner(root: options.root).snapshot()
            let request = Harness.RunRequest(
                session: Harness.SessionKey(
                    tenantId: "local",
                    actorId: "owner",
                    threadId: options.folderId.uuidString
                ),
                adapterId: engineId,
                input: [Harness.TextInput(text: turnText(options))],
                model: options.choice.modelId,
                effort: options.choice.effortId,
                settings: settings(for: options.choice)
            )
            identity = try await client.startRun(Harness.RunStartParams(
                request: request,
                tools: host.descriptors,
                context: ContextBuilder.context(
                    rules: options.rules,
                    entries: entries,
                    review: options.review
                )
            ))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func stop() async {
        guard let client, let identity, phase.isRunning else { return }
        try? await client.cancel(runId: identity.runId)
    }

    private func turnText(_ options: RunRequestOptions) -> String {
        options.review == nil
            ? "Organise this folder by the rules."
            : "Revise the plan as the user asks."
    }

    private func settings(for choice: EngineChoice) -> Harness.RunSettings? {
        guard !choice.controls.isEmpty else { return nil }
        var settings = Harness.RunSettings()
        settings.controls = choice.controls.mapValues { value in
            switch value {
            case let .text(text): return JSONValue.string(text)
            case let .flag(flag): return JSONValue.bool(flag)
            case let .number(number): return JSONValue.double(number)
            }
        }
        return settings
    }

    private func record(_ activity: ToolActivity) {
        switch activity {
        case let .listed(path, count):
            append(.tool, "Reading \(path == "." ? "the folder" : path) · \(count) items")
        case let .inspected(path):
            append(.tool, "Looking at \(path)")
        case let .proposed(count):
            append(.note, "Recorded a plan with \(count) operations")
        case let .refused(tool, message):
            append(.failure, "\(tool) was refused", detail: message)
        }
    }

    private func append(_ kind: ActivityLine.Kind, _ text: String, detail: String? = nil) {
        activity.append(ActivityLine(kind: kind, text: text, detail: detail))
        if activity.count > 200 { activity.removeFirst(activity.count - 200) }
    }

    func receive(_ signal: SidecarSignal) {
        switch signal {
        case let .event(event):
            apply(event.payload)
        case let .settled(runId, _, status):
            guard runId == identity?.runId else { return }
            // The terminal event carries the usage. The settled notification can
            // reach the client before the last event notifications drain.
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await finish(status: status)
            }
        default:
            break
        }
    }

    func sidecarStopped() {
        guard phase.isRunning else { return }
        phase = .failed("The sidecar stopped during the run.")
    }

    private func apply(_ payload: FHPayload) {
        switch payload.kind {
        case "assistant-text":
            assistantText += payload.text ?? ""
        case "thinking":
            if let text = payload.text, !text.isEmpty { append(.thinking, text) }
        case "usage":
            if let value = payload.usage { merge(value) }
        case "error":
            append(.failure, "The engine reported an error", detail: payload.message)
        case "tool-completed":
            guard payload.status == .failed || payload.status == .declined else { break }
            append(
                .failure,
                "\(payload.title ?? "A tool") did not finish",
                detail: payload.error ?? payload.outputAppend
            )
        case "turn-completed":
            if let value = payload.usage { merge(value) }
            Task { await finish(status: payload.status?.rawValue ?? "completed") }
        default:
            break
        }
    }

    private func finish(status: String) async {
        guard phase.isRunning else { return }
        let recorded = await toolHost?.takeProposal()
        switch status {
        case "interrupted":
            phase = .cancelled
        case "error" where recorded == nil:
            phase = .failed(lastError ?? "The engine could not finish the turn.")
        default:
            guard let recorded, let options else {
                phase = .failed("The engine ended the turn without a plan. Ask it to run again.")
                return
            }
            plan = Plan(
                revision: options.revision,
                summary: recorded.summary,
                operations: recorded.operations,
                engineId: options.choice.engineId ?? "",
                modelId: options.choice.modelId,
                usage: usage,
                changeRequest: options.review?.request
            )
            phase = .proposed
        }
    }

    private var lastError: String? {
        guard let line = activity.last(where: { $0.kind == .failure }) else { return nil }
        return [line.text, line.detail].compactMap { $0 }.joined(separator: ": ")
    }

    /// A terminal event can repeat the usage with empty fields. Keep whatever
    /// the engine reported earlier in the turn.
    private func merge(_ value: FHUsage) {
        var merged = usage ?? PlanUsage()
        merged.inputTokens = value.inputTokens ?? merged.inputTokens
        merged.outputTokens = value.outputTokens ?? merged.outputTokens
        merged.totalTokens = value.totalTokens ?? merged.totalTokens
        merged.costUsd = value.costUsd ?? merged.costUsd
        usage = merged
    }
}
