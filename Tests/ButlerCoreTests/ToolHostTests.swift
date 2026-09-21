import XCTest
import FoldHarnessV1
@testable import ButlerCore

final class ToolHostTests: XCTestCase {
    private func call(_ host: ButlerToolHost, _ name: String, _ input: JSONValue) async -> Harness.ToolResult {
        await host.call(FHSidecarToolCallParamsClass(
            adapterID: "kit:offline",
            callID: "call-1",
            input: input,
            name: name,
            protocolVersion: 1,
            runID: "run-1",
            session: FHSession(actorID: "owner", tenantID: "local", threadID: "thread"),
            turnID: "turn-1"
        ))
    }

    private func text(_ result: Harness.ToolResult) -> String {
        result.content.map(\.text).joined()
    }

    func testListFolderHidesHiddenItems() async throws {
        let demo = try DemoFolder()
        try demo.file("visible.pdf")
        try demo.file(".secret")
        let host = ButlerToolHost(root: demo.root)
        let result = await call(host, "list_folder", .object(["path": .string(".")]))
        XCTAssertNil(result.isError)
        XCTAssertTrue(text(result).contains("visible.pdf"))
        XCTAssertFalse(text(result).contains("secret"))
    }

    func testListFolderRefusesAnEscape() async throws {
        let demo = try DemoFolder()
        let host = ButlerToolHost(root: demo.root)
        let result = await call(host, "list_folder", .object(["path": .string("../")]))
        XCTAssertEqual(result.isError, true)
    }

    func testInspectFileReturnsBoundedMetadata() async throws {
        let demo = try DemoFolder()
        try demo.file("notes.txt", contents: String(repeating: "a", count: 9000))
        let host = ButlerToolHost(root: demo.root)
        let result = await call(host, "inspect_file", .object(["path": .string("notes.txt")]))
        XCTAssertNil(result.isError)
        XCTAssertTrue(text(result).count < 6000)
        XCTAssertTrue(text(result).contains("sizeBytes"))
    }

    func testProposePlanRefusesAnInvalidPlanAndRecordsNothing() async throws {
        let demo = try DemoFolder()
        try demo.file("a.pdf")
        let host = ButlerToolHost(root: demo.root)
        let result = await call(host, "propose_plan", .object([
            "summary": .string("tidy"),
            "operations": .array([
                .object([
                    "op": .string("move"),
                    "from": .string("a.pdf"),
                    "to": .string("Docs/a.pdf"),
                    "reason": .string("doc"),
                ]),
            ]),
        ]))
        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(text(result).contains("mkdir"))
        let recorded = await host.takeProposal()
        XCTAssertNil(recorded)
    }

    func testProposePlanRecordsAValidPlan() async throws {
        let demo = try DemoFolder()
        try demo.file("a.pdf")
        let host = ButlerToolHost(root: demo.root)
        let result = await call(host, "propose_plan", .object([
            "summary": .string("tidy"),
            "operations": .array([
                .object(["op": .string("mkdir"), "path": .string("Docs")]),
                .object([
                    "op": .string("move"),
                    "from": .string("a.pdf"),
                    "to": .string("Docs/a.pdf"),
                    "reason": .string("It is a document."),
                ]),
            ]),
        ]))
        XCTAssertNil(result.isError)
        XCTAssertTrue(text(result).contains("End your turn now."))
        let recorded = await host.takeProposal()
        XCTAssertEqual(recorded?.operations.count, 2)
        XCTAssertTrue(demo.exists("a.pdf"), "the tools never change a file")
        XCTAssertFalse(demo.exists("Docs"))
    }

    func testAnUnknownToolIsRefused() async throws {
        let demo = try DemoFolder()
        let host = ButlerToolHost(root: demo.root)
        let result = await call(host, "write_file", .object(["path": .string("a.pdf")]))
        XCTAssertEqual(result.isError, true)
        XCTAssertEqual(result.code, "TOOL_NOT_FOUND")
    }
}
