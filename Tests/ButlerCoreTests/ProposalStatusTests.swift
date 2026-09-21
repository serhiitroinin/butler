import XCTest
@testable import ButlerCore

final class ProposalStatusTests: XCTestCase {
    func testTheStatusFollowsTheRun() {
        var machine = ProposalStatusMachine()
        XCTAssertEqual(machine.status, .proposed)
        machine.apply(.runStarted)
        XCTAssertEqual(machine.status, .working)
        machine.apply(.planArrived)
        XCTAssertEqual(machine.status, .proposed)
    }

    func testOnlyAFinishedApplyReadsApproved() {
        var machine = ProposalStatusMachine()
        machine.apply(.applyStarted)
        XCTAssertEqual(machine.status, .working)
        machine.apply(.applyFinished)
        XCTAssertEqual(machine.status, .approved)
    }

    func testAFailedApplyLeavesThePlanProposed() {
        var machine = ProposalStatusMachine()
        machine.apply(.applyStarted)
        machine.apply(.applyFailed)
        XCTAssertEqual(machine.status, .proposed, "the label must not claim an approval")
    }

    func testAFailedRunLeavesThePlanProposed() {
        var machine = ProposalStatusMachine(status: .approved)
        machine.apply(.runStarted)
        machine.apply(.runFailed)
        XCTAssertEqual(machine.status, .proposed)
    }

    func testRejectAndUndoHaveTheirOwnLabels() {
        var machine = ProposalStatusMachine()
        XCTAssertEqual(machine.next(.rejected), .rejected)
        machine.apply(.applyFinished)
        machine.apply(.undone)
        XCTAssertEqual(machine.status, .undone)
    }

    func testTheConversationPairsARequestWithItsRevisionNote() {
        let first = Plan(revision: 1, summary: "Sorted by kind.", operations: [], engineId: "e")
        let second = Plan(
            revision: 2,
            summary: "Archives stay.",
            operations: [],
            engineId: "e",
            changeRequest: "Keep the archives."
        )
        let turns = ProposalConversation.turns(revisions: [first, second])
        XCTAssertEqual(turns.count, 1, "the first proposal answers no request")
        XCTAssertEqual(turns.first?.request, "Keep the archives.")
        XCTAssertEqual(turns.first?.reply, "Archives stay.")
        XCTAssertEqual(turns.first?.revision, 2)
    }

    func testAPendingRequestHasNoReplyYet() {
        let first = Plan(revision: 1, summary: "Sorted.", operations: [], engineId: "e")
        let turns = ProposalConversation.turns(revisions: [first], pending: "Keep the archives.")
        XCTAssertEqual(turns.count, 1)
        XCTAssertNil(turns.first?.reply)
        XCTAssertEqual(turns.first?.revision, 2)
    }

    func testTheTraceMarksOnlyWhatTheApplierFinished() {
        let operations = (0..<4).map { PlanOperation(kind: .move, source: "a\($0)", destination: "b/a\($0)") }
        var trace = ApplyTrace(operations: operations)
        XCTAssertEqual(trace.state(of: [operations[0].id]), .pending)
        trace.reached(2)
        XCTAssertEqual(trace.state(of: [operations[0].id]), .done)
        XCTAssertEqual(trace.state(of: [operations[1].id]), .done)
        XCTAssertEqual(trace.state(of: [operations[2].id]), .pending)
        XCTAssertEqual(trace.state(of: operations.prefix(3).map(\.id)), .pending, "a group waits for its last row")
        trace.finish(failure: false)
        XCTAssertEqual(trace.state(of: operations.map(\.id)), .done)
    }

    func testTheTraceIgnoresExcludedOperationsAndStopsAtAFailure() {
        let operations = (0..<3).map { PlanOperation(kind: .move, source: "a\($0)", destination: "b/a\($0)") }
        let excluded = PlanOperation(kind: .trash, source: "junk")
        var trace = ApplyTrace(operations: operations)
        XCTAssertEqual(trace.state(of: [excluded.id]), .pending, "an excluded row is never done")
        trace.reached(1)
        trace.finish(failure: true)
        XCTAssertEqual(trace.state(of: [operations[0].id, excluded.id]), .done)
        XCTAssertEqual(trace.state(of: [operations[1].id]), .failed)
        XCTAssertEqual(trace.state(of: [operations[2].id]), .pending)
        XCTAssertEqual(trace.state(of: operations.map(\.id)), .failed)
    }
}
