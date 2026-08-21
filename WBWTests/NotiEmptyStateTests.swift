import XCTest
@testable import WBW

/// จอว่างต้องบอกความจริงว่าว่างเพราะอะไร
///
/// `NotiStore.load` กลืน error ด้วย `try?` แล้วตั้ง `loaded = true` ไม่ว่าจะสำเร็จหรือไม่ ·
/// จอจึงขึ้น "ยังไม่มีประกาศ" ทั้งที่ความจริงคือยิงไม่ถึงเซิร์ฟเวอร์ — ผู้ใช้ที่เน็ตหลุดบนดอย
/// อ่านว่า "ทีมงานยังไม่ประกาศอะไร" แล้วเลิกลองใหม่ ทั้งที่ประกาศอาจมีอยู่แล้วก็ได้
///
/// คีย์ `error_load_announcements` กับ `action_retry` มีอยู่ครบสองภาษามาตลอด แต่ไม่เคยมี
/// View ไหนเรียกใช้เลยสักตัว
final class NotiEmptyStateTests: XCTestCase {

    func testStillLoadingShowsNeitherMessage() {
        XCTAssertEqual(NotiStore.emptyState(loaded: false, failed: false, isEmpty: true), .loading)
    }

    func testLoadedAndGenuinelyEmptySaysThereIsNothingYet() {
        XCTAssertEqual(NotiStore.emptyState(loaded: true, failed: false, isEmpty: true), .empty)
    }

    /// อาการที่แก้: ยิงไม่ถึงแล้วยังบอกว่า "ยังไม่มีประกาศ"
    func testAFailedLoadSaysItCouldNotReachTheServer() {
        XCTAssertEqual(NotiStore.emptyState(loaded: true, failed: true, isEmpty: true), .failed)
    }

    /// ยิงไม่ถึงแต่ยังมีของเก่าค้างอยู่ = โชว์ของเก่าไป ไม่ต้องทับด้วยจอ error
    func testAFailedRefreshKeepsShowingWhatIsAlreadyThere() {
        XCTAssertEqual(NotiStore.emptyState(loaded: true, failed: true, isEmpty: false), .none)
    }

    func testLoadedWithItemsShowsNothingOverlaid() {
        XCTAssertEqual(NotiStore.emptyState(loaded: true, failed: false, isEmpty: false), .none)
    }
}
