import XCTest
@testable import WBW

/// PendingPush คือกลไก one-shot กันแจ้งเตือน push ตกหล่นตอน cold launch (didReceive อาจโพสต์ก่อน
/// MainTabView.task จะติดตั้ง .onReceive ทัน เพราะมีหน้าสแปลชคั่นอยู่) — เทสนี้คุมแค่สัญญาแบบ one-shot ของ
/// ตัวเก็บเอง ไม่รวมเส้นทางเต็ม AppDelegate → MainTabView ซึ่งต้องมี push จริงและ UI tap ที่ไม่มีเครื่องมือ
/// รันแบบ headless ให้ทำ (ดูรายงานฉบับเต็มสำหรับเหตุผล)
final class PendingPushTests: XCTestCase {
    override func tearDown() {
        _ = PendingPush.consume()   // กันค่าตกค้างข้ามเทส เผื่อเทสก่อนหน้าล้มเหลวกลางทางก่อนถึง consume()
        super.tearDown()
    }

    func testConsumeReturnsNilWhenNothingHeld() {
        XCTAssertNil(PendingPush.consume())
    }

    func testConsumeReturnsHeldValueThenNilOnSecondCall() {
        PendingPush.hold(.openGroupChat)
        XCTAssertEqual(PendingPush.consume()?.name, .openGroupChat)
        XCTAssertNil(PendingPush.consume(), "ต้องเป็น one-shot — ดึงซ้ำรอบสองต้องได้ nil ไม่ใช่ค่าเดิมซ้ำ")
    }

    func testHoldOverwritesAnyPreviouslyHeldValue() {
        PendingPush.hold(.openNotificationsTab)
        PendingPush.hold(.openGroupChat)   // แตะ push อันใหม่ก่อนอันเก่าจะถูก consume
        XCTAssertEqual(PendingPush.consume()?.name, .openGroupChat, "ค่าล่าสุดต้องชนะ ไม่ใช่คิวสะสมหลายอัน")
    }

    /// clear() คือส่วนที่ปิดช่องโหว่ warm-app: MainTabView.onReceive รับสดแล้วต้องล้างของที่ hold() พักไว้
    /// เอง ไม่งั้น mount ถัดไป (login บัญชีอื่นหลัง logout) จะ consume() เจอของเก่าที่ไม่เกี่ยวกับบัญชีนั้น
    func testClearRemovesHeldValueEvenIfNeverConsumed() {
        PendingPush.hold(.openGroupChat)
        PendingPush.clear()
        XCTAssertNil(PendingPush.consume(), "clear() ต้องล้างของที่ hold() พักไว้ ไม่ให้ mount ถัดไปดึงไปเล่นซ้ำ")
    }

    func testHoldCarriesUserInfo() {
        PendingPush.clear()
        PendingPush.hold(.openCheckinFeedback, info: ["checkpoint_id": "7"])
        let taken = PendingPush.consume()
        XCTAssertEqual(taken?.name, .openCheckinFeedback)
        XCTAssertEqual(taken?.info?["checkpoint_id"] as? String, "7")
    }

    func testConsumeStillClearsInOneStep() {
        PendingPush.clear()
        PendingPush.hold(.openCheckinFeedback, info: ["checkpoint_id": "3"])
        _ = PendingPush.consume()
        XCTAssertNil(PendingPush.consume(), "consume ต้องอ่านแล้วเคลียร์ในตาเดียวเหมือนเดิม")
    }

    func testHoldWithoutInfoStillWorks() {
        PendingPush.clear()
        PendingPush.hold(.openGroupChat)
        let taken = PendingPush.consume()
        XCTAssertEqual(taken?.name, .openGroupChat)
        XCTAssertNil(taken?.info)
    }

    func testClearDiscardsInfoToo() {
        PendingPush.hold(.openCheckinFeedback, info: ["checkpoint_id": "1"])
        PendingPush.clear()
        XCTAssertNil(PendingPush.consume())
    }
}
