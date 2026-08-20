import XCTest
@testable import WBW

/// ข้อความพวกนี้คือสิ่งเดียวที่บอกผู้ใช้ว่า "กดแล้วจะเสียอะไร" — ถ้าเลขเพี้ยนไปหนึ่ง ผู้ใช้ตัดสินใจผิด
/// แล้วแก้กลับเองไม่ได้ (สิทธิ์หักไปแล้ว) จึงตรึงทุกกรณีไว้ด้วยเทส
///
/// **เทสไม่จับคำ จับตัวเลขกับความต่างของประโยค** — ข้อความชุดนี้ผ่าน `Localizable.strings` แล้ว
/// การจับ "หมดแล้ว" จะกลายเป็นการตรึงว่าเครื่องที่รันเทสต้องตั้งภาษาไทย ซึ่งไม่จริงบน CI
/// สิ่งที่ต้องไม่พังคือตัวเลขที่คำนวณให้ กับการที่แต่ละกรณีพูดคนละเรื่อง ไม่ใช่ถ้อยคำที่ใช้พูด
final class GroupQuotaTextTests: XCTestCase {

    func testJoinWarningWithQuotaLeft() {
        let s = GroupQuotaText.joinWarning(groupNumber: 7, quota: 1)
        XCTAssertTrue(s.contains("7"), s)
        XCTAssertTrue(s.contains("1"), s)
    }

    /// เข้ากลุ่มไม่หักสิทธิ์ — quota 0 จึงต้องบอก "ผลที่ตามมา" ไม่ใช่บอกว่าเหลือ 0
    func testJoinWarningWhenQuotaExhausted() {
        let exhausted = GroupQuotaText.joinWarning(groupNumber: 12, quota: 0)
        let hasQuota = GroupQuotaText.joinWarning(groupNumber: 12, quota: 1)
        XCTAssertNotEqual(exhausted, hasQuota,
                          "สิทธิ์หมดกับสิทธิ์เหลือต้องไม่ใช่ประโยคเดียวกัน")
        XCTAssertFalse(exhausted.contains("0"),
                       "ห้ามบอกว่าเหลือ 0 ครั้ง — ต้องบอกผลที่ตามมาแทน: \(exhausted)")
        XCTAssertTrue(exhausted.contains("12"), exhausted)
    }

    /// ผู้เรียกส่ง quota **ก่อน** ออกมาให้ ตัวข้อความหักเอง — เหลือ 2 ก่อนออก = พูดถึงเลข 1
    func testLeaveWarningWithMoreThanOneLeft() {
        let s = GroupQuotaText.leaveWarning(groupNumber: 3, quota: 2)
        XCTAssertTrue(s.contains("1"), "เหลือ 2 ก่อนออก = เหลือ 1 หลังออก: \(s)")
        XCTAssertFalse(s.contains("2 "), "ต้องไม่พูดเลขก่อนหัก: \(s)")
    }

    /// สามกรณีของการออก (ยังเหลือหลายครั้ง · ครั้งสุดท้าย · หมดแล้ว) ต้องเป็นคนละประโยคทั้งหมด
    ///
    /// เคยมีบั๊กที่ `max(quota - 1, 0)` ทำให้ quota=0 กับ quota=1 clamp มาชนกัน แล้วคนที่สิทธิ์
    /// หมดแล้วได้ประโยค "เลือกกลุ่มใหม่ได้อีกครั้งเดียว" ซึ่งเป็นคนละความจริง
    func testTheThreeLeaveCasesAreAllDifferentSentences() {
        let many = GroupQuotaText.leaveWarning(groupNumber: 3, quota: 2)
        let last = GroupQuotaText.leaveWarning(groupNumber: 3, quota: 1)
        let none = GroupQuotaText.leaveWarning(groupNumber: 3, quota: 0)
        XCTAssertEqual(Set([many, last, none]).count, 3,
                       "สามกรณีนี้พูดคนละความจริง ต้องไม่ใช้ประโยคซ้ำกัน:\n\(many)\n\(last)\n\(none)")
        for s in [many, last, none] { XCTAssertTrue(s.contains("3"), s) }
    }

    func testRemaining() {
        XCTAssertTrue(GroupQuotaText.remaining(quota: 2).contains("2"))
        XCTAssertNotEqual(GroupQuotaText.remaining(quota: 0), GroupQuotaText.remaining(quota: 1))
        XCTAssertFalse(GroupQuotaText.remaining(quota: 0).contains("0"),
                       "สิทธิ์หมดต้องพูดว่าหมด ไม่ใช่พูดว่าเหลือศูนย์")
    }
}
