import XCTest
@testable import ButlerCore

final class PlanValidatorTests: XCTestCase {
    private func validator(for demo: DemoFolder) throws -> PlanValidator {
        try PlanValidator(scanner: FolderScanner(root: demo.root))
    }

    func testAcceptsAFolderThenAMoveIntoIt() throws {
        let demo = try DemoFolder()
        try demo.file("bill.pdf")
        let validation = try validator(for: demo).validate([
            PlanOperation(kind: .mkdir, destination: "Invoices"),
            PlanOperation(kind: .move, source: "bill.pdf", destination: "Invoices/bill.pdf", reason: "It is a bill."),
        ])
        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.result["Invoices/bill.pdf"], false)
        XCTAssertNil(validation.result["bill.pdf"])
    }

    func testRefusesAMoveIntoAFolderThatIsNeverCreated() throws {
        let demo = try DemoFolder()
        try demo.file("bill.pdf")
        let validation = try validator(for: demo).validate([
            PlanOperation(kind: .move, source: "bill.pdf", destination: "Invoices/bill.pdf", reason: "It is a bill."),
        ])
        XCTAssertEqual(validation.issues.count, 1)
        XCTAssertTrue(validation.issues[0].message.contains("mkdir"))
    }

    func testRefusesAnOverwrite() throws {
        let demo = try DemoFolder()
        try demo.file("a.pdf")
        try demo.file("Invoices/a.pdf")
        let validation = try validator(for: demo).validate([
            PlanOperation(kind: .move, source: "a.pdf", destination: "Invoices/a.pdf", reason: "It is a bill."),
        ])
        XCTAssertTrue(validation.issues[0].message.contains("never overwrites"))
    }

    func testRefusesTwoMovesToTheSameDestination() throws {
        let demo = try DemoFolder()
        try demo.file("a.pdf")
        try demo.file("b.pdf")
        let validation = try validator(for: demo).validate([
            PlanOperation(kind: .mkdir, destination: "Docs"),
            PlanOperation(kind: .move, source: "a.pdf", destination: "Docs/one.pdf", reason: "first"),
            PlanOperation(kind: .move, source: "b.pdf", destination: "Docs/one.pdf", reason: "second"),
        ])
        XCTAssertEqual(validation.issues.count, 1)
        XCTAssertTrue(validation.issues[0].message.contains("already exists"))
    }

    func testRefusesAMissingSource() throws {
        let demo = try DemoFolder()
        let validation = try validator(for: demo).validate([
            PlanOperation(kind: .mkdir, destination: "Docs"),
            PlanOperation(kind: .move, source: "ghost.pdf", destination: "Docs/ghost.pdf", reason: "why not"),
        ])
        XCTAssertTrue(validation.issues[0].message.contains("does not exist"))
    }

    func testRefusesAFolderMovingIntoItself() throws {
        let demo = try DemoFolder()
        try demo.folder("Archive")
        let validation = try validator(for: demo).validate([
            PlanOperation(kind: .move, source: "Archive", destination: "Archive/Old", reason: "tidy"),
        ])
        XCTAssertTrue(validation.issues[0].message.contains("cannot move into itself"))
    }

    func testRefusesAnEscapeAndAHiddenItem() throws {
        let demo = try DemoFolder()
        try demo.file("a.pdf")
        let validation = try validator(for: demo).validate([
            PlanOperation(kind: .move, source: "a.pdf", destination: "../a.pdf", reason: "away"),
            PlanOperation(kind: .trash, source: ".config", reason: "It is not needed any more."),
        ])
        XCTAssertEqual(validation.issues.count, 2)
    }

    func testRefusesATrashWithoutAStrongReason() throws {
        let demo = try DemoFolder()
        try demo.file("junk.zip")
        let validation = try validator(for: demo).validate([
            PlanOperation(kind: .trash, source: "junk.zip", reason: "old"),
        ])
        XCTAssertTrue(validation.issues[0].message.contains("strong written reason"))
    }

    func testRefusesATreeThatIsTooDeep() throws {
        let demo = try DemoFolder()
        let validation = try validator(for: demo).validate([
            PlanOperation(kind: .mkdir, destination: "a/b/c/d/e"),
        ])
        XCTAssertTrue(validation.issues[0].message.contains("levels"))
    }

    func testRefusesARenameThatChangesFolder() throws {
        let demo = try DemoFolder()
        try demo.file("a.pdf")
        try demo.folder("Docs")
        let validation = try validator(for: demo).validate([
            PlanOperation(kind: .rename, source: "a.pdf", destination: "Docs/a.pdf", reason: "tidy"),
        ])
        XCTAssertTrue(validation.issues[0].message.contains("keeps the item in its folder"))
    }

    func testReportsEveryProblemAtOnce() throws {
        let demo = try DemoFolder()
        let validation = try validator(for: demo).validate([
            PlanOperation(kind: .move, source: "one.pdf", destination: "X/one.pdf", reason: "a"),
            PlanOperation(kind: .move, source: "two.pdf", destination: "X/two.pdf", reason: "b"),
        ])
        XCTAssertEqual(validation.issues.count, 2)
    }
}
