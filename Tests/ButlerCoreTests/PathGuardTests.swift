import XCTest
@testable import ButlerCore

final class PathGuardTests: XCTestCase {
    func testResolvesAPlainRelativePath() throws {
        let demo = try DemoFolder()
        let guardrail = PathGuard(root: demo.root)
        let url = try guardrail.resolve("Invoices/2024/bill.pdf")
        XCTAssertEqual(guardrail.relativePath(for: url), "Invoices/2024/bill.pdf")
    }

    func testRefusesAnAbsolutePath() throws {
        let demo = try DemoFolder()
        let guardrail = PathGuard(root: demo.root)
        XCTAssertThrowsError(try guardrail.resolve("/etc/passwd")) { error in
            XCTAssertTrue("\(error)".contains("relative"))
        }
    }

    func testRefusesAParentEscape() throws {
        let demo = try DemoFolder()
        let guardrail = PathGuard(root: demo.root)
        XCTAssertThrowsError(try guardrail.resolve("../secrets.txt"))
        XCTAssertThrowsError(try guardrail.resolve("a/../../b"))
    }

    func testRefusesHiddenItems() throws {
        let demo = try DemoFolder()
        let guardrail = PathGuard(root: demo.root)
        XCTAssertThrowsError(try guardrail.resolve(".ssh/id_rsa"))
        XCTAssertThrowsError(try guardrail.resolve("notes/.hidden"))
    }

    func testRefusesPathsInsideAnApplicationPackage() throws {
        let demo = try DemoFolder()
        try demo.folder("Mail.app/Contents")
        let guardrail = PathGuard(root: demo.root)
        XCTAssertThrowsError(try guardrail.resolve("Mail.app/Contents/Info.plist"))
        XCTAssertNoThrow(try guardrail.resolve("Mail.app"))
    }

    func testRefusesASymbolicLinkThatLeavesTheRoot() throws {
        let demo = try DemoFolder()
        let outside = try DemoFolder()
        try outside.file("target.txt")
        try FileManager.default.createSymbolicLink(
            at: demo.root.appendingPathComponent("away"),
            withDestinationURL: outside.root
        )
        let guardrail = PathGuard(root: demo.root)
        XCTAssertThrowsError(try guardrail.resolve("away/target.txt")) { error in
            XCTAssertTrue("\(error)".contains("link"))
        }
    }
}
