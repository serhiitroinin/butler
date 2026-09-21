import XCTest
import FoldHarnessV1
@testable import ButlerCore

final class EventDecodingTests: XCTestCase {
    private let frame = """
    {"jsonrpc":"2.0","method":"harness/event","params":{"event":{"schemaVersion":1,\
    "eventId":"e1","sequence":7,"timestamp":"2026-09-17T16:15:00.000Z",\
    "session":{"tenantId":"local","actorId":"owner","threadId":"t"},\
    "runId":"run-1","turnId":"turn-1","adapterId":"kit:claude",\
    "payload":{"kind":"usage","usage":{"inputTokens":21203,"outputTokens":6567,\
    "cachedInputTokens":9767,"totalTokens":27770,"durationMs":51348}}}}}
    """

    func testAUsageEventKeepsItsTokenCounts() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(frame.utf8))
        let payload = try XCTUnwrap(value["params"]?["event"])
        let event = try JSONDecoder().decode(FHEvent.self, from: JSONEncoder().encode(payload))
        XCTAssertEqual(event.payload.kind, "usage")
        XCTAssertEqual(event.payload.usage?.totalTokens, 27770)
        XCTAssertEqual(event.payload.usage?.inputTokens, 21203)
    }
}
