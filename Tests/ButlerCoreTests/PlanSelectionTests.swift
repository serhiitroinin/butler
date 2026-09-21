import XCTest
@testable import ButlerCore

final class PlanSelectionTests: XCTestCase {
    private func plan(_ operations: [PlanOperation]) -> Plan {
        Plan(revision: 1, summary: "test", operations: operations, engineId: "kit:offline")
    }

    func testTrashOperationsStartExcluded() throws {
        let demo = try DemoFolder()
        try demo.file("junk.zip")
        let trash = PlanOperation(kind: .trash, source: "junk.zip", reason: "The archive is a duplicate.")
        let selection = PlanSelection(
            plan: plan([trash]),
            validator: try PlanValidator(scanner: FolderScanner(root: demo.root))
        )
        XCTAssertFalse(selection.isIncluded(trash))
        XCTAssertEqual(selection.includedCount, 0)
    }

    func testExcludingAFolderBlocksTheMovesIntoIt() throws {
        let demo = try DemoFolder()
        try demo.file("a.pdf")
        try demo.file("b.png")
        let mkdir = PlanOperation(kind: .mkdir, destination: "Docs")
        let move = PlanOperation(kind: .move, source: "a.pdf", destination: "Docs/a.pdf", reason: "doc")
        let other = PlanOperation(kind: .rename, source: "b.png", destination: "shot.png", reason: "clearer")
        var selection = PlanSelection(
            plan: plan([mkdir, move, other]),
            validator: try PlanValidator(scanner: FolderScanner(root: demo.root))
        )
        XCTAssertEqual(selection.includedCount, 3)

        selection.toggle(mkdir)
        XCTAssertFalse(selection.isIncluded(move))
        XCTAssertEqual(selection.blockReason(move), "The folder Docs is not included.")
        XCTAssertTrue(selection.isIncluded(other))

        selection.toggle(mkdir)
        XCTAssertEqual(selection.includedCount, 3)
        XCTAssertNil(selection.blockReason(move))
    }

    func testTheRestStaysValidWhenAMoveIsExcluded() throws {
        let demo = try DemoFolder()
        try demo.file("a.pdf")
        try demo.file("b.pdf")
        let mkdir = PlanOperation(kind: .mkdir, destination: "Docs")
        let first = PlanOperation(kind: .move, source: "a.pdf", destination: "Docs/a.pdf", reason: "doc")
        let second = PlanOperation(kind: .move, source: "b.pdf", destination: "Docs/b.pdf", reason: "doc")
        var selection = PlanSelection(
            plan: plan([mkdir, first, second]),
            validator: try PlanValidator(scanner: FolderScanner(root: demo.root))
        )
        selection.toggle(first)
        XCTAssertEqual(selection.includedCount, 2)
        XCTAssertTrue(selection.isIncluded(second))
    }
}
