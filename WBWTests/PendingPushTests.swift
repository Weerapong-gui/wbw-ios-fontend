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
        XCTAssertEqual(PendingPush.consume(), .openGroupChat)
        XCTAssertNil(PendingPush.consume(), "ต้องเป็น one-shot — ดึงซ้ำรอบสองต้องได้ nil ไม่ใช่ค่าเดิมซ้ำ")
    }

    func testHoldOverwritesAnyPreviouslyHeldValue() {
        PendingPush.hold(.openNotificationsTab)
        PendingPush.hold(.openGroupChat)   // แตะ push อันใหม่ก่อนอันเก่าจะถูก consume
        XCTAssertEqual(PendingPush.consume(), .openGroupChat, "ค่าล่าสุดต้องชนะ ไม่ใช่คิวสะสมหลายอัน")
    }
}
