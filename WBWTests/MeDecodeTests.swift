import XCTest
@testable import WBW

/// backend ที่ยังไม่ได้ deploy โควตา (หรือ backend ทดสอบตัวอื่น) ไม่ส่ง leave_quota มา —
/// ถ้า field นี้ไม่เป็น optional โปรไฟล์จะ decode ไม่ผ่านทั้งก้อน = แอปเปิดมาแล้วว่างทั้งจอ
/// โดยไม่มี error ให้เห็น เทสนี้ตรึงไว้ว่าต้องรอด
final class MeDecodeTests: XCTestCase {

    private func decode(_ json: String) throws -> Me {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(Me.self, from: Data(json.utf8))
    }

    func testDecodesWithoutLeaveQuota() throws {
        let me = try decode(#"{"user_id":"u1","username":"6931900011","role":"participant"}"#)
        XCTAssertNil(me.leaveQuota)
    }

    func testDecodesLeaveQuota() throws {
        let me = try decode(#"{"user_id":"u1","username":"x","role":"participant","leave_quota":2}"#)
        XCTAssertEqual(me.leaveQuota, 2)
    }
}
