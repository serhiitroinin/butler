import XCTest
@testable import ButlerCore

/// Drives the real sidecar with the offline engine, the real Swift tools, and
/// the real applier. It needs `bun install` and `Sidecar/scripts/build.sh`.
@MainActor
final class OfflineRunTests: XCTestCase {
    private var temporaryData: URL?

    override func setUp() async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sidecar = repository.appendingPathComponent("Sidecar")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: sidecar.appendingPathComponent("host.mjs").path),
            "run Sidecar/scripts/build.sh first"
        )
        let data = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("butler-run-\(UUID().uuidString)")
        temporaryData = data
        setenv("BUTLER_SIDECAR_DIR", sidecar.path, 1)
        setenv("BUTLER_DATA_DIR", data.path, 1)
    }

    override func tearDown() async throws {
        if let temporaryData { try? FileManager.default.removeItem(at: temporaryData) }
        unsetenv("BUTLER_SIDECAR_DIR")
        unsetenv("BUTLER_DATA_DIR")
    }

    func testTheOfflineEngineProposesAPlanThatTheApplierCanApplyAndUndo() async throws {
        let demo = try DemoFolder()
        try demo.file("invoice-2024.pdf")
        try demo.file("holiday.jpg")
        try demo.file("installer.dmg")
        try demo.file("report (1).pdf")
        try demo.folder("Empty folder")

        let service = HarnessService(offline: true)
        await service.start()
        guard service.status.isReady else {
            return XCTFail("the sidecar did not start: \(service.status)")
        }
        defer { Task { await service.shutdown() } }

        let offline = try XCTUnwrap(service.engines.first { $0.id == "kit:offline" })
        XCTAssertNotNil(offline.catalog.value)

        let run = RunController(service: service)
        let folderId = UUID()
        await run.start(RunRequestOptions(
            folderId: folderId,
            root: demo.root,
            rules: "Sort by kind and year.",
            choice: EngineChoice(engineId: offline.id, modelId: "scripted"),
            revision: 1
        ))
        try await waitForProposal(run)

        let plan = try XCTUnwrap(run.plan)
        // The offline engine also proposes one rename and one trash, so the
        // interface has every row kind to show.
        XCTAssertEqual(plan.count(of: .move), 4)
        XCTAssertEqual(plan.count(of: .rename), 1)
        XCTAssertEqual(plan.count(of: .trash), 1)
        XCTAssertTrue(plan.count(of: .mkdir) > 0)
        XCTAssertEqual(plan.usage?.totalTokens, 1290)

        let validation = try PlanValidator(scanner: FolderScanner(root: demo.root)).validate(plan.operations)
        XCTAssertTrue(validation.isValid, "\(validation.issues)")

        let applier = PlanApplier(guardrail: PathGuard(root: demo.root))
        let outcome = applier.apply(plan.operations)
        XCTAssertTrue(outcome.succeeded, outcome.failure ?? "")
        XCTAssertFalse(demo.exists("invoice-2024.pdf"))
        XCTAssertFalse(demo.exists("Empty folder"))

        XCTAssertTrue(applier.undo(outcome.actions).succeeded)
        XCTAssertTrue(demo.exists("invoice-2024.pdf"))
        XCTAssertTrue(demo.exists("holiday.jpg"))
        XCTAssertTrue(demo.exists("installer.dmg"))
        XCTAssertTrue(demo.exists("report (1).pdf"))
        XCTAssertTrue(demo.exists("Empty folder"), "the Trash gave the folder back")
    }

    private func waitForProposal(_ run: RunController) async throws {
        for _ in 0..<600 {
            if run.phase == .proposed { return }
            if case let .failed(message) = run.phase { return XCTFail(message) }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("the run did not finish in time: \(run.phase)")
    }
}
