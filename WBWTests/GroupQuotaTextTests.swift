import XCTest
@testable import WBW

/// ข้อความพวกนี้คือสิ่งเดียวที่บอกผู้ใช้ว่า "กดแล้วจะเสียอะไร" — ถ้าเลขเพี้ยนไปหนึ่ง ผู้ใช้ตัดสินใจผิด
/// แล้วแก้กลับเองไม่ได้ (สิทธิ์หักไปแล้ว) จึงตรึงทุกกรณีไว้ด้วยเทส
final class GroupQuotaTextTests: XCTestCase {

    func testJoinWarningWithQuotaLeft() {
        let s = GroupQuotaText.joinWarning(groupNumber: 7, quota: 1)
        XCTAssertTrue(s.contains("กลุ่ม 7"), s)
        XCTAssertTrue(s.contains("1 ครั้ง"), s)
    }

    func testJoinWarningWhenQuotaExhausted() {
        let s = GroupQuotaText.joinWarning(groupNumber: 12, quota: 0)
        XCTAssertTrue(s.contains("หมดแล้ว"), s)
        XCTAssertTrue(s.contains("เปลี่ยนกลุ่มไม่ได้อีก"), s)
        XCTAssertFalse(s.contains("0 ครั้ง"), "ห้ามบอกว่าเหลือ 0 ครั้ง — ต้องบอกผลที่ตามมาแทน: \(s)")
    }

    func testLeaveWarningWithMoreThanOneLeft() {
        let s = GroupQuotaText.leaveWarning(groupNumber: 3, quota: 2)
        XCTAssertTrue(s.contains("1 ครั้ง"), "เหลือ 2 ก่อนออก = เหลือ 1 หลังออก: \(s)")
    }

    func testLeaveWarningOnLastChance() {
        let s = GroupQuotaText.leaveWarning(groupNumber: 3, quota: 1)
        XCTAssertTrue(s.contains("อีกครั้งเดียว"), s)
    }

    func testRemaining() {
        XCTAssertTrue(GroupQuotaText.remaining(quota: 2).contains("2 ครั้ง"))
        XCTAssertTrue(GroupQuotaText.remaining(quota: 0).contains("ครบแล้ว"))
    }
}
