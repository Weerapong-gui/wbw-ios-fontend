import XCTest
@testable import WBW

/// ตัวเลขความคืบหน้าชั่วคราวบน Home — ของแทนต้นไม้ในฉาก 3D ที่ถูกปิดไป
/// (ดู docs/superpowers/specs/2026-08-07-forest-3d-off-design.md ข้อ 4)
final class CheckinProgressLabelTests: XCTestCase {

    func testShowsStageOverTotal() {
        XCTAssertEqual(CheckinProgressLabel.text(stage: 3, total: 8), "เช็คอินแล้ว 3/8 ฐาน")
    }

    func testShowsZeroStageWhenNothingCheckedInYet() {
        XCTAssertEqual(CheckinProgressLabel.text(stage: 0, total: 8), "เช็คอินแล้ว 0/8 ฐาน")
    }

    func testHidesWhenTotalUnknown() {
        // total 0 = ยังโหลดความคืบหน้าไม่เสร็จ หรือไม่มีฐานเลย — "x/0 ฐาน" ไม่มีความหมาย
        XCTAssertNil(CheckinProgressLabel.text(stage: 3, total: 0))
    }

    func testHidesWhenBothZero() {
        XCTAssertNil(CheckinProgressLabel.text(stage: 0, total: 0))
    }
}
