import XCTest
@testable import WBW

/// ตัวเลขความคืบหน้าชั่วคราวบน Home — ของแทนต้นไม้ในฉาก 3D ที่ถูกปิดไป
/// (ดู docs/superpowers/specs/2026-08-07-forest-3d-off-design.md ข้อ 4)
final class CheckinProgressLabelTests: XCTestCase {

    func testShowsStageOverTotal() {
        XCTAssertEqual(CheckinProgressLabel.text(stage: 3, total: 8),
                       String(format: Loc.t("home_checked_in"), 3, 8))
    }

    func testShowsZeroStageWhenNothingCheckedInYet() {
        XCTAssertEqual(CheckinProgressLabel.text(stage: 0, total: 8),
                       String(format: Loc.t("home_checked_in"), 0, 8))
    }

    func testHidesWhenTotalUnknown() {
        // total 0 = ยังโหลดความคืบหน้าไม่เสร็จ หรือไม่มีฐานเลย — "x/0 ฐาน" ไม่มีความหมาย
        XCTAssertNil(CheckinProgressLabel.text(stage: 3, total: 0))
    }

    func testHidesWhenBothZero() {
        XCTAssertNil(CheckinProgressLabel.text(stage: 0, total: 0))
    }

    /// **ตัวเศษห้ามเกินตัวส่วน** — เช็คอินเกินจำนวนฐานเกิดได้จริงเมื่อเจ้าหน้าที่สแกนที่จุดบริการ
    /// ซึ่งไม่ถูกนับใน `total` (ของจริง: `ฐาน Zero Waste` ถูกตัดออกจากการนับ 2026-08-27)
    /// · "เช็คอินแล้ว 9 / 8 ฐาน" อ่านว่าแอปพัง ทั้งที่ความจริงคือเขาเดินครบแล้ว
    func testTheNumeratorNeverExceedsTheDenominator() {
        let text = CheckinProgressLabel.text(stage: 9, total: 8)
        XCTAssertNotNil(text)
        XCTAssertFalse(text!.contains("9"), "โชว์ 9 / 8 ไม่ได้ — ต้องหยุดที่ 8 / 8: \(text!)")
        XCTAssertEqual(text, CheckinProgressLabel.text(stage: 8, total: 8))
    }
}
