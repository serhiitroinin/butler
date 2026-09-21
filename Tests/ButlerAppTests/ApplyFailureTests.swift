import XCTest
@testable import ButlerApp
@testable import ButlerCore

/// An apply that fails half-way, through the view model the page reads. The
/// failure is a real one: the second file is locked (the user-immutable flag,
/// Finder's "Locked" checkbox), so the file system itself refuses the move.
@MainActor
final class ApplyFailureTests: XCTestCase {
    private var root: URL!
    private var store: ButlerStore!
    private var folderId: UUID!
    private var plan: Plan!

    private var manager: FileManager { .default }
    private func url(_ name: String) -> URL { root.appendingPathComponent(name) }
    private func exists(_ name: String) -> Bool { manager.fileExists(atPath: url(name).path) }

    override func setUp() async throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("butler-app-tests-\(UUID().uuidString)/Downloads")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["a.pdf", "b.pdf", "c.pdf"] {
            try "data".write(to: url(name), atomically: true, encoding: .utf8)
        }
        try manager.setAttributes([.immutable: true], ofItemAtPath: url("b.pdf").path)

        store = ButlerStore(file: root.deletingLastPathComponent().appendingPathComponent("state.json"))
        folderId = store.addFolder(at: root).id
        plan = Plan(revision: 1, summary: "test", operations: [
            PlanOperation(kind: .mkdir, destination: "Docs"),
            PlanOperation(kind: .move, source: "a.pdf", destination: "Docs/a.pdf", reason: "A document."),
            PlanOperation(kind: .move, source: "b.pdf", destination: "Docs/b.pdf", reason: "A document."),
            PlanOperation(kind: .move, source: "c.pdf", destination: "Docs/c.pdf", reason: "A document."),
        ], engineId: "kit:offline")
        store.update(folderId) { $0.revisions = [self.plan] }
    }

    override func tearDown() async throws {
        for name in ["b.pdf", "Docs/b.pdf"] where exists(name) {
            try? manager.setAttributes([.immutable: false], ofItemAtPath: url(name).path)
        }
        try? manager.removeItem(at: root.deletingLastPathComponent())
    }

    private func page() -> FolderViewModel {
        let environment = ToolEnvironment(path: "/usr/bin:/bin", node: nil, claude: nil, codex: nil)
        return FolderViewModel(
            folderId: folderId,
            store: store,
            service: HarnessService(offline: true, environment: environment)
        )
    }

    private func node(_ name: String, in page: FolderViewModel) throws -> PlanTableNode {
        try XCTUnwrap(page.groups(mode: .changes).flatMap { $0.children ?? [] }.first { $0.name == name })
    }

    private func approveAndWait(_ page: FolderViewModel) async throws {
        page.approve(undoManager: nil)
        XCTAssertEqual(page.status, .working)
        let deadline = Date().addingTimeInterval(10)
        while page.applying != nil, Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertNil(page.applying, "the applier never finished")
    }

    func testAFailingMoveStopsThereAndTheRestIsReportedTruthfullyAndUndone() async throws {
        let page = page()
        XCTAssertTrue(page.canDecide)
        try await approveAndWait(page)

        /// The folder: the first file moved, the locked one and the one after it did not.
        XCTAssertTrue(exists("Docs/a.pdf"))
        XCTAssertTrue(exists("b.pdf"))
        XCTAssertTrue(exists("c.pdf"))
        XCTAssertFalse(exists("Docs/c.pdf"), "nothing runs after the failure")

        /// The page: proposed again, the error on its own row, the rows after it untouched.
        XCTAssertEqual(page.status, .proposed)
        XCTAssertEqual(page.applyState(of: try node("a.pdf", in: page)), .done)
        XCTAssertEqual(page.applyState(of: try node("b.pdf", in: page)), .failed)
        XCTAssertEqual(page.applyState(of: try node("c.pdf", in: page)), .pending)
        let failure = try XCTUnwrap(page.applyFailure)
        XCTAssertTrue(failure.hasPrefix("b.pdf is locked"), failure)
        let line = try XCTUnwrap(page.stoppedLine)
        XCTAssertTrue(line.contains("1 item was moved"), line)

        /// The record says what really happened, and nothing can be decided
        /// until it is undone: the plan no longer matches the folder.
        let record = try XCTUnwrap(page.stoppedRun)
        XCTAssertEqual(record.itemCount, 1)
        XCTAssertEqual(record.actions.map(\.kind), [.createdFolder, .moved])
        XCTAssertEqual(record.statusWord, "Stopped")
        XCTAssertFalse(page.canDecide)
        XCTAssertEqual(page.lastUndoableRun?.id, record.id)

        /// A new session shows the same thing.
        let reopened = self.page()
        XCTAssertEqual(reopened.status, .proposed)
        XCTAssertNotNil(reopened.stoppedLine)
        XCTAssertEqual(reopened.applyState(of: try node("a.pdf", in: reopened)), .done)
        XCTAssertFalse(reopened.canDecide)

        /// Undo puts the moved file back and removes the folder Butler made.
        page.undoLastRun()
        XCTAssertNil(page.error)
        XCTAssertTrue(exists("a.pdf"))
        XCTAssertFalse(exists("Docs"))
        XCTAssertEqual(page.status, .proposed)
        XCTAssertNil(page.stoppedRun)
        XCTAssertNil(page.applyFailure)
        XCTAssertEqual(page.applyState(of: try node("a.pdf", in: page)), .pending)
        XCTAssertTrue(page.canDecide)
        XCTAssertEqual(store.folder(folderId)?.history.first?.statusWord, "Undone")

        /// With the lock gone the same plan goes through.
        try manager.setAttributes([.immutable: false], ofItemAtPath: url("b.pdf").path)
        try await approveAndWait(page)
        XCTAssertEqual(page.status, .approved)
        XCTAssertTrue(exists("Docs/b.pdf"))
        XCTAssertEqual(page.tidiedLine, "Tidied · 3 items")
    }
}
