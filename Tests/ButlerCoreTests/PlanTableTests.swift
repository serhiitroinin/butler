import XCTest
@testable import ButlerCore

final class PlanTableTests: XCTestCase {
    private func plan(_ operations: [PlanOperation]) -> Plan {
        Plan(revision: 1, summary: "test", operations: operations, engineId: "kit:offline")
    }

    private func fixture() throws -> (DemoFolder, Plan) {
        let demo = try DemoFolder()
        try demo.file("bill.pdf", contents: "0123456789")
        try demo.file("note.txt")
        try demo.file("junk.zip")
        let operations = [
            PlanOperation(kind: .mkdir, destination: "Invoices"),
            PlanOperation(kind: .move, source: "bill.pdf", destination: "Invoices/bill.pdf", reason: "It is a bill."),
            PlanOperation(kind: .trash, source: "junk.zip", reason: "It is an exact duplicate."),
        ]
        return (demo, plan(operations))
    }

    func testTheChangesTableNestsFilesUnderTheirDestination() throws {
        let (demo, plan) = try fixture()
        let nodes = PlanTable.nodes(mode: .changes, plan: plan, included: plan.operations, root: demo.root)
        let invoices = try XCTUnwrap(nodes.first { $0.name == "Invoices" })
        XCTAssertTrue(invoices.isNewFolder)
        XCTAssertEqual(invoices.kindLabel, "New Folder")
        XCTAssertEqual(invoices.children?.count, 1)
        let bill = try XCTUnwrap(invoices.children?.first)
        XCTAssertEqual(bill.name, "bill.pdf")
        XCTAssertEqual(bill.destination, "Top Level", "the column says where the file comes from")
        XCTAssertEqual(bill.size, 10)
        XCTAssertEqual(bill.reason, "It is a bill.")
    }

    func testARenameAfterAMoveReadsItsKindAndSizeFromTheFileOnDisk() throws {
        let demo = try DemoFolder()
        try demo.file("report (1).pdf", contents: "0123456789")
        let operations = [
            PlanOperation(kind: .mkdir, destination: "Docs"),
            PlanOperation(kind: .move, source: "report (1).pdf", destination: "Docs/report (1).pdf", reason: "A report."),
            PlanOperation(kind: .rename, source: "Docs/report (1).pdf", destination: "Docs/report-copy-1.pdf", reason: "A clearer name."),
        ]
        let value = plan(operations)
        for mode in [StageMode.changes, .after] {
            let nodes = PlanTable.nodes(mode: mode, plan: value, included: operations, root: demo.root)
            let files = try XCTUnwrap(nodes.first { $0.name == "Docs" }?.children)
            XCTAssertFalse(files.isEmpty)
            for file in files {
                XCTAssertEqual(file.size, 10, "\(mode): \(file.name) is the file that is on disk now")
                XCTAssertEqual(file.kindLabel, files[0].kindLabel)
                XCTAssertEqual(file.kindLabel, PlanTable.kind(of: "x.pdf", contentType: nil))
            }
        }
    }

    func testAYearFolderIsNestedInsideItsParent() throws {
        let demo = try DemoFolder()
        try demo.file("a.pdf")
        try demo.file("b.pdf")
        try demo.folder("Invoices")
        let operations = [
            PlanOperation(kind: .mkdir, destination: "Invoices/2023"),
            PlanOperation(kind: .mkdir, destination: "Invoices/2024"),
            PlanOperation(kind: .move, source: "a.pdf", destination: "Invoices/2023/a.pdf", reason: "2023"),
            PlanOperation(kind: .move, source: "b.pdf", destination: "Invoices/2024/b.pdf", reason: "2024"),
        ]
        let value = plan(operations)
        let nodes = PlanTable.nodes(mode: .changes, plan: value, included: operations, root: demo.root)
        XCTAssertEqual(nodes.map(\.name), ["Invoices"])
        let invoices = try XCTUnwrap(nodes.first)
        XCTAssertEqual(invoices.kindLabel, "Folder", "Invoices already exists")
        XCTAssertEqual(invoices.children?.map(\.name), ["2023", "2024"])
        let year = try XCTUnwrap(invoices.children?.first)
        XCTAssertEqual(year.kindLabel, "New Folder")
        XCTAssertEqual(year.children?.map(\.name), ["a.pdf"])

        /// The parent carries every operation below it, so its checkbox drives
        /// the whole subtree and reports the mixed state.
        XCTAssertEqual(invoices.operationIds.count, 4)
        var selection = PlanSelection(
            plan: value,
            validator: try PlanValidator(scanner: FolderScanner(root: demo.root))
        )
        XCTAssertEqual(selection.state(of: invoices.operationIds, in: value), .included)
        selection.setIncluded(year.operationIds, to: false, in: value)
        XCTAssertEqual(selection.state(of: invoices.operationIds, in: value), .mixed)
        XCTAssertEqual(selection.state(of: year.operationIds, in: value), .excluded)
        selection.setIncluded(invoices.operationIds, to: false, in: value)
        XCTAssertEqual(selection.state(of: invoices.operationIds, in: value), .excluded)
    }

    func testTheFromColumnCollapsesWhenEveryFileSharesOneSource() throws {
        let (demo, plan) = try fixture()
        let nodes = PlanTable.nodes(mode: .changes, plan: plan, included: plan.operations, root: demo.root)
        XCTAssertEqual(PlanTable.files(in: nodes).count, 2)
        XCTAssertNil(PlanTable.commonSource(in: nodes), "the trashed file reports the Trash")

        let moves = plan.operations.filter { $0.kind != .trash }
        let onlyMoves = Plan(revision: 1, summary: "m", operations: moves, engineId: "kit:offline")
        let quiet = PlanTable.nodes(mode: .changes, plan: onlyMoves, included: moves, root: demo.root)
        XCTAssertEqual(PlanTable.commonSource(in: quiet), "Top Level")
    }

    func testTheTrashGroupIsLastAndNamesTheTrash() throws {
        let (demo, plan) = try fixture()
        let nodes = PlanTable.nodes(mode: .changes, plan: plan, included: plan.operations, root: demo.root)
        let last = try XCTUnwrap(nodes.last)
        XCTAssertEqual(last.name, "Trash")
        XCTAssertEqual(last.children?.first?.destination, "Trash")
    }

    func testTheBeforeAndAfterTablesShowTheFolderTree() throws {
        let (demo, plan) = try fixture()
        let before = PlanTable.nodes(mode: .before, plan: plan, included: plan.operations, root: demo.root)
        XCTAssertEqual(PlanTable.files(in: before).count, 3, "the root files sit at the top level")
        XCTAssertEqual(before.first { $0.name == "bill.pdf" }?.role, .file(.moved))
        XCTAssertEqual(before.first { $0.name == "note.txt" }?.role, .file(.unchanged))

        let after = PlanTable.nodes(mode: .after, plan: plan, included: plan.operations, root: demo.root)
        let invoices = try XCTUnwrap(after.first { $0.name == "Invoices" })
        XCTAssertEqual(invoices.children?.first?.name, "bill.pdf")
        XCTAssertNil(after.first { $0.name == "junk.zip" })
    }

    func testAFolderReportsTheMixedStateOfItsSubtree() throws {
        let demo = try DemoFolder()
        try demo.file("a.pdf")
        try demo.file("b.pdf")
        let mkdir = PlanOperation(kind: .mkdir, destination: "Docs")
        let first = PlanOperation(kind: .move, source: "a.pdf", destination: "Docs/a.pdf", reason: "doc")
        let second = PlanOperation(kind: .move, source: "b.pdf", destination: "Docs/b.pdf", reason: "doc")
        let value = plan([mkdir, first, second])
        var selection = PlanSelection(
            plan: value,
            validator: try PlanValidator(scanner: FolderScanner(root: demo.root))
        )
        let subtree = [first.id, second.id]
        XCTAssertEqual(selection.state(of: subtree, in: value), .included)

        selection.toggle(first)
        XCTAssertEqual(selection.state(of: subtree, in: value), .mixed)

        selection.setIncluded(subtree, to: false, in: value)
        XCTAssertEqual(selection.state(of: subtree, in: value), .excluded)
        XCTAssertEqual(selection.includedCount, 1, "only the folder is left")

        selection.setIncluded(subtree, to: true, in: value)
        XCTAssertEqual(selection.state(of: subtree, in: value), .included)
    }

    func testTheColumnsSortWithKeyPathComparators() throws {
        let (demo, plan) = try fixture()
        let nodes = PlanTable.nodes(mode: .changes, plan: plan, included: plan.operations, root: demo.root)
        let byName = nodes.sorted(using: KeyPathComparator(\PlanTableNode.name, order: .reverse))
        XCTAssertEqual(byName.first?.name, "Trash")
        let files = PlanTable.files(in: nodes)
            .sorted(using: KeyPathComparator(\PlanTableNode.sortableSize, order: .forward))
        XCTAssertEqual(files.first?.name, "junk.zip")
    }
}

extension PlanTableTests {
    func testTheProposalKeepsOneGroupPerDestinationPath() throws {
        let demo = try DemoFolder()
        try demo.file("a.pdf", contents: "0123456789")
        try demo.file("b.pdf")
        let operations = [
            PlanOperation(kind: .mkdir, destination: "Invoices/2023"),
            PlanOperation(kind: .mkdir, destination: "Invoices/2024"),
            PlanOperation(kind: .move, source: "a.pdf", destination: "Invoices/2023/a.pdf", reason: "2023"),
            PlanOperation(kind: .move, source: "b.pdf", destination: "Invoices/2024/b.pdf", reason: "2024"),
        ]
        let value = Plan(revision: 1, summary: "t", operations: operations, engineId: "kit:offline")
        let groups = PlanTable.destinations(mode: .changes, plan: value, included: operations, root: demo.root)
        XCTAssertEqual(groups.map(\.name), ["Invoices/2023", "Invoices/2024"])
        XCTAssertEqual(groups.first?.children?.count, 1)
        XCTAssertEqual(groups.first?.size, 10, "the header shows the group's bytes")
        XCTAssertTrue(groups.allSatisfy(\.isNewFolder))
        XCTAssertEqual(groups.first?.operationIds.count, 2, "the mkdir and the move")
    }
}
