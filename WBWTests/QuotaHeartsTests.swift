import XCTest
@testable import WBW

/// แถวหัวใจบอกสิทธิ์ออกจากกลุ่มคงเหลือ — ตรึงเฉพาะสองเคสขอบที่วาดตรง ๆ แล้วพัง
///
/// `ForEach(0..<quota)` เฉย ๆ ใช้ไม่ได้: quota = 0 จะได้แถวว่างซึ่งอ่านเหมือนแอปพัง ไม่ใช่
/// "สิทธิ์หมดแล้ว" · ส่วนค่าเยอะ ๆ เกิดได้จริงเพราะ admin เติมสิทธิ์รายคนได้ (`quota_adjust` ใน
/// migration 000016_group_leave_quota) และไม่มีเพดานอะไรกันไว้เลยทั้งใน DB และใน API
final class QuotaHeartsTests: XCTestCase {

    func testNoQuotaDrawsTheFadedHeartNotAnEmptyRow() {
        XCTAssertEqual(QuotaHearts.layout(quota: 0), .none,
                       "สิทธิ์หมดต้องยังมีอะไรให้เห็น แถวที่หายไปเฉย ๆ อ่านเหมือนจอโหลดไม่ขึ้น")
    }

    func testNegativeQuotaIsTreatedAsNone() {
        XCTAssertEqual(QuotaHearts.layout(quota: -1), .none,
                       "backend เก่าไม่ส่ง leave_quota มา ฝั่งแอปอ่านเป็น 0 อยู่แล้ว แต่ค่าติดลบต้องไม่ทำให้ ForEach ระเบิด")
    }

    func testSmallQuotaDrawsOneHeartEach() {
        XCTAssertEqual(QuotaHearts.layout(quota: 1), .hearts(1))
        XCTAssertEqual(QuotaHearts.layout(quota: 3), .hearts(3))
    }

    func testBoundaryOfWhatStillFitsOnOneLine() {
        XCTAssertEqual(QuotaHearts.layout(quota: QuotaHearts.maxDrawn), .hearts(QuotaHearts.maxDrawn),
                       "ค่าที่เท่ากับเพดานพอดีต้องยังวาดเป็นดวง ไม่ใช่ตัวเลข — ขอบเขตแบบรวมปลาย")
        XCTAssertEqual(QuotaHearts.layout(quota: QuotaHearts.maxDrawn + 1),
                       .counted(QuotaHearts.maxDrawn + 1),
                       "เกินเพดานต้องสลับเป็น '♥ ×N' ไม่งั้นแถวจะล้นบรรทัดบนจอแคบ")
    }

    func testLargeQuotaKeepsTheRealNumber() {
        XCTAssertEqual(QuotaHearts.layout(quota: 12), .counted(12),
                       "ตัวเลขที่โชว์ต้องเป็นค่าจริง ไม่ใช่ค่าที่ถูกหนีบไว้ที่เพดาน")
    }

    /// เลขบนแถวหัวใจกับประโยคใต้แถวมาจากคนละฟังก์ชัน ถ้าเพี้ยนกันจะอ่านขัดกันเองในกล่องเดียว
    func testHeartCountAgreesWithTheSentenceBelowIt() {
        for quota in 1...QuotaHearts.maxDrawn {
            guard case let .hearts(n) = QuotaHearts.layout(quota: quota) else {
                return XCTFail("quota \(quota) ควรวาดเป็นดวง")
            }
            XCTAssertTrue(GroupQuotaText.remaining(quota: quota).contains("\(n)"),
                          "จำนวนหัวใจ (\(n)) ไม่ตรงกับตัวเลขในประโยค: \(GroupQuotaText.remaining(quota: quota))")
        }
    }
}
