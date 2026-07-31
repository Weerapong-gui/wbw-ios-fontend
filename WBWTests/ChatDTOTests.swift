import XCTest
@testable import WBW

final class ChatDTOTests: XCTestCase {
    private func decode(_ json: String) throws -> ChatSyncResponse {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(ChatSyncResponse.self, from: json.data(using: .utf8)!)
    }

    func testDecodesFullResponse() throws {
        let r = try decode("""
        {"since_id": 42, "member_count": 7,
         "messages": [{"id": 43, "group_id": 3, "sender_id": "u1", "client_id": "c1",
                       "body": "ไง", "device_time": "2026-07-31T10:00:00.000Z",
                       "created_at": "2026-07-31T10:00:01.000Z",
                       "first_name": "ปาร์ค", "last_name": "ก"}],
         "cursors": [{"user_id": "u2", "last_read_id": 43}]}
        """)
        XCTAssertEqual(r.sinceId, 42)
        XCTAssertEqual(r.memberCount, 7)
        XCTAssertEqual(r.messages.first?.id, "43")
        XCTAssertEqual(r.messages.first?.senderName, "ปาร์ค ก")
        XCTAssertEqual(r.cursors.first?.userId, "u2")
        XCTAssertEqual(r.cursors.first?.lastReadId, 43)
    }

    func testDecodesEmptyTimeoutResponse() throws {
        let r = try decode("""
        {"since_id": 0, "member_count": 2, "messages": [], "cursors": []}
        """)
        XCTAssertTrue(r.messages.isEmpty)
        XCTAssertTrue(r.cursors.isEmpty)
        XCTAssertEqual(r.sinceId, 0)
    }
}
