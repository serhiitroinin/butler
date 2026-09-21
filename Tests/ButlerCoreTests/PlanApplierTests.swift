import XCTest
@testable import ButlerCore

final class PlanApplierTests: XCTestCase {
    func testAppliesAPlanAndUndoesIt() throws {
        let demo = try DemoFolder()
        try demo.file("bill.pdf", contents: "invoice")
        let applier = PlanApplier(guardrail: PathGuard(root: demo.root))
        let outcome = applier.apply([
            PlanOperation(kind: .mkdir, destination: "Invoices/2024"),
            PlanOperation(kind: .move, source: "bill.pdf", destination: "Invoices/2024/bill.pdf", reason: "bill"),
        ])
        XCTAssertTrue(outcome.succeeded)
        XCTAssertTrue(demo.exists("Invoices/2024/bill.pdf"))
        XCTAssertEqual(try demo.read("Invoices/2024/bill.pdf"), "invoice")

        let undo = applier.undo(outcome.actions)
        XCTAssertTrue(undo.succeeded)
        XCTAssertTrue(demo.exists("bill.pdf"))
        XCTAssertFalse(demo.exists("Invoices"))
    }

    func testRenameKeepsTheContents() throws {
        let demo = try DemoFolder()
        try demo.file("scan.pdf", contents: "scan")
        let applier = PlanApplier(guardrail: PathGuard(root: demo.root))
        let outcome = applier.apply([
            PlanOperation(kind: .rename, source: "scan.pdf", destination: "receipt.pdf", reason: "clearer"),
        ])
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(try demo.read("receipt.pdf"), "scan")
        XCTAssertTrue(applier.undo(outcome.actions).succeeded)
        XCTAssertTrue(demo.exists("scan.pdf"))
    }

    func testATrashOperationGoesToTheTrashAndComesBack() throws {
        let demo = try DemoFolder()
        try demo.file("junk.zip", contents: "junk")
        let applier = PlanApplier(guardrail: PathGuard(root: demo.root))
        let outcome = applier.apply([
            PlanOperation(kind: .trash, source: "junk.zip", reason: "The archive is a duplicate."),
        ])
        XCTAssertTrue(outcome.succeeded)
        XCTAssertFalse(demo.exists("junk.zip"))
        let trashPath = try XCTUnwrap(outcome.actions.first?.trashPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashPath))

        XCTAssertTrue(applier.undo(outcome.actions).succeeded)
        XCTAssertEqual(try demo.read("junk.zip"), "junk")
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashPath))
    }

    func testAPartialFailureStopsAndKeepsWhatItDid() throws {
        let demo = try DemoFolder()
        try demo.file("one.pdf")
        try demo.file("Docs/two.pdf")
        let applier = PlanApplier(guardrail: PathGuard(root: demo.root))
        let outcome = applier.apply([
            PlanOperation(kind: .move, source: "one.pdf", destination: "Docs/one.pdf", reason: "tidy"),
            PlanOperation(kind: .move, source: "missing.pdf", destination: "Docs/missing.pdf", reason: "tidy"),
            PlanOperation(kind: .move, source: "Docs/two.pdf", destination: "three.pdf", reason: "tidy"),
        ])
        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.actions.count, 1)
        XCTAssertTrue(demo.exists("Docs/one.pdf"))
        XCTAssertFalse(demo.exists("three.pdf"))

        XCTAssertTrue(applier.undo(outcome.actions).succeeded)
        XCTAssertTrue(demo.exists("one.pdf"))
    }

    func testAnUndoKeepsAFolderThatHoldsOtherItems() throws {
        let demo = try DemoFolder()
        try demo.file("one.pdf")
        let applier = PlanApplier(guardrail: PathGuard(root: demo.root))
        let outcome = applier.apply([
            PlanOperation(kind: .mkdir, destination: "Docs"),
            PlanOperation(kind: .move, source: "one.pdf", destination: "Docs/one.pdf", reason: "tidy"),
        ])
        try demo.file("Docs/added-by-the-user.txt")

        XCTAssertTrue(applier.undo(outcome.actions).succeeded)
        XCTAssertTrue(demo.exists("one.pdf"))
        XCTAssertTrue(demo.exists("Docs/added-by-the-user.txt"))
    }

    func testTheApplierRefusesAnOverwrite() throws {
        let demo = try DemoFolder()
        try demo.file("one.pdf", contents: "first")
        try demo.file("Docs/one.pdf", contents: "second")
        let applier = PlanApplier(guardrail: PathGuard(root: demo.root))
        let outcome = applier.apply([
            PlanOperation(kind: .move, source: "one.pdf", destination: "Docs/one.pdf", reason: "tidy"),
        ])
        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(try demo.read("Docs/one.pdf"), "second")
        XCTAssertEqual(try demo.read("one.pdf"), "first")
    }

    func testTheApplierRefusesAPathOutsideTheRoot() throws {
        let demo = try DemoFolder()
        try demo.file("one.pdf")
        let applier = PlanApplier(guardrail: PathGuard(root: demo.root))
        let outcome = applier.apply([
            PlanOperation(kind: .move, source: "one.pdf", destination: "../one.pdf", reason: "away"),
        ])
        XCTAssertFalse(outcome.succeeded)
        XCTAssertTrue(demo.exists("one.pdf"))
    }
}
