import XCTest
@testable import WBW

/// คำตอบของ `/chat/sync` ที่มีแถวเสียปนมา ต้องไม่ฆ่าแชททั้งห้อง
///
/// เดิม `MessageDTO` เป็น non-optional ทุกฟิลด์ และ `messages` decode เป็นก้อนเดียว —
/// **แถวเดียวที่ `client_id` เป็น null (แอดมิน insert เอง / migration) ทำให้ `chatSync` throw
/// แล้ว syncLoop เข้า backoff วนตลอดไป** ไม่มี error บนจอ ไม่มี toast แคชเก่ายังโชว์อยู่ครบ
/// อาการที่ผู้ใช้เห็นคือ "แชทเงียบไปเฉย ๆ" ซึ่งเป็นทรงเดียวกับกับดัก 200-พร้อมลิสต์ว่าง
/// ที่ `docs/sus-test-backend.md` บันทึกไว้ — พังเงียบสนิท ไม่มีอะไรให้ไล่
///
/// ถ้าเป็น `""` แทน `null` แย่กว่า: `@Attribute(.unique)` ของ `ChatMessage.clientId` จะยุบ
/// ทุกแถวแบบนั้นรวมเป็นแถวเดียว และ `ForEach` ในจอแชทจะมี id ซ้ำ
final class ChatSyncResilienceTests: XCTestCase {
    private func decode(_ json: String) throws -> ChatSyncResponse {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(ChatSyncResponse.self, from: Data(json.utf8))
    }

    private func row(id: Int, clientId: String?) -> String {
        let cid = clientId.map { "\"\($0)\"" } ?? "null"
        return """
        {"id": \(id), "group_id": 1, "sender_id": "u1", "client_id": \(cid),
         "body": "ข้อความ \(id)", "device_time": "2026-08-24T10:00:00.000Z",
         "created_at": "2026-08-24T10:00:01.000Z", "first_name": "ดิน", "last_name": "ก"}
        """
    }

    /// หัวใจของบั๊ก — แถวกลางไม่มี client_id แต่อีกสองแถวต้องรอด
    func testRowWithNullClientIdDoesNotKillTheBatch() throws {
        let r = try decode("""
        {"since_id": 0, "member_count": 3,
         "messages": [\(row(id: 1, clientId: "c1")), \(row(id: 2, clientId: nil)), \(row(id: 3, clientId: "c3"))],
         "cursors": []}
        """)
        XCTAssertEqual(r.messages.count, 3, "แถวที่ไม่มี client_id ต้องได้คีย์แทน ไม่ใช่หายไปทั้งก้อน")
        XCTAssertEqual(r.messages.map(\.id), ["1", "2", "3"])
    }

    /// client_id ที่หายหรือว่าง ต้องได้คีย์แทนที่ **ไม่ซ้ำกัน** ไม่งั้น @Attribute(.unique) ยุบรวม
    func testMissingClientIdFallsBackToDistinctKeyPerMessage() throws {
        let r = try decode("""
        {"since_id": 0, "member_count": 3,
         "messages": [\(row(id: 7, clientId: nil)), \(row(id: 8, clientId: "")), \(row(id: 9, clientId: nil))],
         "cursors": []}
        """)
        let ids = r.messages.map(\.clientId)
        XCTAssertEqual(Set(ids).count, 3, "คีย์ต้องไม่ซ้ำกัน ไม่งั้นสามแถวจะยุบเหลือแถวเดียวใน SwiftData")
        XCTAssertFalse(ids.contains(where: \.isEmpty))
    }

    /// แถวที่พังจริง ๆ (ไม่มี id เลย — ไม่มีอะไรตั้งคีย์ให้ได้) ทิ้งได้ แต่ที่เหลือต้องรอด
    func testUnrecoverableRowIsDroppedAndTheRestSurvive() throws {
        let r = try decode("""
        {"since_id": 0, "member_count": 3,
         "messages": [\(row(id: 1, clientId: "c1")),
                      {"group_id": 1, "sender_id": "u1", "body": "ไม่มี id"},
                      \(row(id: 3, clientId: "c3"))],
         "cursors": []}
        """)
        XCTAssertEqual(r.messages.map(\.id), ["1", "3"])
    }

    /// backend เก่า/ตัวกลางที่ตัดคีย์ทิ้ง ต้องไม่ทำให้ทั้งก้อนล่ม — ค่าที่ขาดอ่านเป็นค่าที่ปลอดภัยสุด
    /// (sinceId 0 = ไม่ purge อะไรเลย · cursors ว่าง = ยังไม่มีใครอ่าน)
    func testMissingOptionalTopLevelKeysDoNotThrow() throws {
        let r = try decode("""
        {"messages": [\(row(id: 5, clientId: "c5"))]}
        """)
        XCTAssertEqual(r.sinceId, 0)
        XCTAssertEqual(r.memberCount, 0)
        XCTAssertTrue(r.cursors.isEmpty)
        XCTAssertEqual(r.messages.count, 1)
    }

    /// คำตอบปกติต้องไม่เปลี่ยนพฤติกรรม — ตัวกันการแก้เกินมือ
    func testNormalResponseStillDecodesUnchanged() throws {
        let r = try decode("""
        {"since_id": 42, "member_count": 7,
         "messages": [\(row(id: 43, clientId: "c43"))],
         "cursors": [{"user_id": "u2", "last_read_id": 43}]}
        """)
        XCTAssertEqual(r.sinceId, 42)
        XCTAssertEqual(r.memberCount, 7)
        XCTAssertEqual(r.messages.first?.clientId, "c43")
        XCTAssertEqual(r.messages.first?.senderName, "ดิน ก")
        XCTAssertEqual(r.cursors.first?.lastReadId, 43)
    }
}
