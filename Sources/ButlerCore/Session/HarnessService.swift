import Foundation

public enum ServiceStatus: Sendable, Equatable {
    case idle
    case starting
    case ready
    case failed(String)

    public var isReady: Bool { self == .ready }
}

/// Owns the one sidecar process, engine discovery, and the active run.
@MainActor
public final class HarnessService: ObservableObject {
    @Published public private(set) var status: ServiceStatus = .idle
    @Published public private(set) var engines: [Engine] = []
    @Published public private(set) var diagnostics: [String] = []

    public let environment: ToolEnvironment
    public let offline: Bool
    private var client: SidecarClient?
    private weak var activeRun: RunController?
    private var refreshedAt: [String: Date] = [:]

    public init(offline: Bool = ProcessInfo.processInfo.environment["BUTLER_OFFLINE"] == "1",
                environment: ToolEnvironment = .resolve()) {
        self.offline = offline
        self.environment = environment
    }

    public func engine(_ id: String?) -> Engine? {
        guard let id else { return nil }
        return engines.first { $0.id == id }
    }

    public var defaultEngineId: String? {
        engines.first(where: \.isUsable)?.id ?? engines.first?.id
    }

    public func start() async {
        guard status == .idle || isFailed else { return }
        status = .starting
        guard environment.node != nil else {
            status = .failed("Butler needs Node.js. Install it, then open Butler again.")
            return
        }
        guard let sidecarDirectory = ButlerPaths.sidecarDirectory() else {
            status = .failed("Butler could not find its sidecar. Run Sidecar/scripts/build.sh.")
            return
        }
        let launch = SidecarLaunch(
            sidecarDirectory: sidecarDirectory,
            storeDirectory: ButlerPaths.harnessStore,
            dataDirectory: ButlerPaths.applicationSupport,
            offline: offline,
            environment: environment
        )
        let client = SidecarClient(launch: launch)
        do {
            let result = try await client.start(client: Harness.ClientInfo(name: "Butler", version: "0.1.0"))
            self.client = client
            listen(to: client)
            status = .ready
            await discover(result.adapters, client: client)
        } catch {
            status = .failed(error.localizedDescription)
            await client.shutdown()
        }
    }

    public func shutdown() async {
        await client?.shutdown()
        client = nil
        status = .idle
    }

    public func refresh() async {
        guard let client else { return }
        await discover(engines.map(\.id), client: client)
    }

    /// Asks one engine again for its models and limits: when its menu opens and
    /// after each run, since a run spends the account's allowance. The sidecar
    /// caches a snapshot briefly, and calls closer than five seconds are dropped.
    public func refresh(engine id: String?) async {
        guard let id, let client, engines.contains(where: { $0.id == id }) else { return }
        if let last = refreshedAt[id], Date().timeIntervalSince(last) < 5 { return }
        refreshedAt[id] = Date()
        let models = try? await client.models(id)
        let limits = try? await client.limits(id)
        guard let index = engines.firstIndex(where: { $0.id == id }) else { return }
        if let models, case let .available(catalog) = EngineMapper.catalog(models) {
            /// A probe that fails now does not take a good list off the screen.
            engines[index].catalog = .available(catalog)
        }
        if let limits { engines[index].limits = EngineMapper.limits(limits) }
    }

    private var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    private func discover(_ adapters: [String], client: SidecarClient) async {
        var found: [Engine] = []
        for id in adapters {
            guard let profile = try? await client.profile(id) else { continue }
            var engine = EngineMapper.engine(id: id, profile: profile)
            if let models = try? await client.models(id) {
                engine.catalog = EngineMapper.catalog(models)
            } else {
                engine.catalog = .unavailable("The engine did not answer the model list.")
            }
            if let limits = try? await client.limits(id) {
                engine.limits = EngineMapper.limits(limits)
            }
            found.append(engine)
        }
        engines = found
    }

    private func listen(to client: SidecarClient) {
        Task { [weak self] in
            for await signal in client.signals {
                guard let self else { return }
                self.receive(signal)
            }
        }
    }

    private func receive(_ signal: SidecarSignal) {
        switch signal {
        case let .diagnostic(text):
            diagnostics.append(text)
            if diagnostics.count > 80 { diagnostics.removeFirst(diagnostics.count - 80) }
        case let .stopped(code):
            status = .failed("The sidecar stopped with code \(code).")
            activeRun?.sidecarStopped()
        default:
            activeRun?.receive(signal)
        }
    }

    func begin(_ run: RunController) -> SidecarClient? {
        activeRun = run
        return client
    }
}
