import XCTest
@testable import ButlerCore

final class StageBuilderTests: XCTestCase {
    private func plan(_ operations: [PlanOperation]) -> Plan {
        Plan(revision: 1, summary: "test", operations: operations, engineId: "kit:offline")
    }

    func testTheBeforeStageMarksEveryItemThatLeaves() throws {
        let demo = try DemoFolder()
        try demo.file("bill.pdf")
        try demo.file("keep.txt")
        let move = PlanOperation(kind: .move, source: "bill.pdf", destination: "Docs/bill.pdf", reason: "doc")
        let groups = StageBuilder.groups(
            mode: .before,
            plan: plan([PlanOperation(kind: .mkdir, destination: "Docs"), move]),
            included: [PlanOperation(kind: .mkdir, destination: "Docs"), move],
            root: demo.root
        )
        let rows = groups.flatMap(\.rows)
        XCTAssertEqual(rows.first { $0.name == "bill.pdf" }?.mark, .moved)
        XCTAssertEqual(rows.first { $0.name == "keep.txt" }?.mark, .unchanged)
    }

    func testTheAfterStageMarksArrivalsAndNewFolders() throws {
        let demo = try DemoFolder()
        try demo.file("bill.pdf")
        let mkdir = PlanOperation(kind: .mkdir, destination: "Docs")
        let move = PlanOperation(kind: .move, source: "bill.pdf", destination: "Docs/bill.pdf", reason: "doc")
        let groups = StageBuilder.groups(
            mode: .after,
            plan: plan([mkdir, move]),
            included: [mkdir, move],
            root: demo.root
        )
        let docs = try XCTUnwrap(groups.first { $0.folder == "Docs" })
        XCTAssertTrue(docs.isNew)
        XCTAssertEqual(docs.rows.first?.mark, .moved)
        /// The row keeps the identity of the file it was before the move.
        XCTAssertEqual(docs.rows.first?.id, "bill.pdf")
    }

    func testTheChangesStageGroupsByDestination() throws {
        let demo = try DemoFolder()
        try demo.file("bill.pdf")
        try demo.file("junk.zip")
        let operations = [
            PlanOperation(kind: .mkdir, destination: "Docs"),
            PlanOperation(kind: .move, source: "bill.pdf", destination: "Docs/bill.pdf", reason: "doc"),
            PlanOperation(kind: .trash, source: "junk.zip", reason: "It is an exact duplicate."),
        ]
        let groups = StageBuilder.groups(mode: .changes, plan: plan(operations), included: operations, root: demo.root)
        XCTAssertEqual(groups.first { $0.folder == "Docs" }?.rows.count, 1)
        XCTAssertTrue(groups.first { $0.folder == "Docs" }?.isNew ?? false)
        XCTAssertEqual(groups.last?.isTrash, true)
        XCTAssertEqual(groups.last?.rows.first?.mark, .trashed)
    }
}
