import XCTest
@testable import WBW

/// รายชื่อคนที่บล็อกไว้ต้องไม่ตกทอดข้ามบัญชีบนเครื่องเดียวกัน
///
/// `BlockedUsers.storageKey` ขึ้นต้นด้วย `wbw.` จึง **รอดจากการกวาด `hasPrefix("chat.")`
/// ของ `ChatSession.purgeForLogout()` มาตลอด** บัญชีที่ 2 ที่ login เครื่องเดียวกันจึงสืบทอด
/// รายการบล็อกของบัญชีก่อน — และเปิดหน้าตั้งค่า "ผู้ใช้ที่บล็อกไว้" **เห็นชื่อ** คนที่บัญชีก่อน
/// บล็อกไว้ด้วย (คลาสเก็บชื่อคู่กับ id เพื่อให้จอนั้นแสดงได้ ดูคอมเมนต์หัวคลาส)
///
/// เป็นการรั่วข้อมูลข้ามบัญชี ไม่ใช่แค่ของค้าง — เรื่องเดียวกับที่ `purgeForLogout` กับ
/// `Session.logout()` ไล่ล้างข้อความ/cursor/คิวความเห็นไปแล้วทุกก้อน ก้อนนี้ตกหล่น
@MainActor
final class BlockedUsersLogoutTests: XCTestCase {

    private func wipe() {
        let d = UserDefaults.standard
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("wbw.chat.blocked") {
            d.removeObject(forKey: key)
        }
    }

    override func setUp() {
        super.setUp()
        DemoMode.forcedActive = false   // คีย์ไม่ต่อ .demo — เหตุผลเต็มที่ FeedbackTransportTests.setUp
        wipe()
    }

    override func tearDown() {
        wipe()
        DemoMode.forcedActive = nil
        super.tearDown()
    }

    /// หัวใจของบั๊ก
    func testBlockListDoesNotSurviveLogout() {
        BlockedUsers().block("u1", name: "คนก่อกวน")
        XCTAssertTrue(BlockedUsers().isBlocked("u1"), "ตั้งต้นต้องบล็อกติดจริงก่อน")

        let chat = ChatSession()
        chat.testSetup(groupId: 1, myId: "me")
        chat.purgeForLogout()

        XCTAssertFalse(BlockedUsers().isBlocked("u1"),
                       "บัญชีถัดไปบนเครื่องเดียวกันต้องไม่สืบทอดรายการบล็อก และต้องไม่เห็นชื่อคนที่บัญชีก่อนบล็อก")
        XCTAssertTrue(BlockedUsers().entries.isEmpty)
    }

    /// ล้างทุก scope — ของโหมดเดโม่ที่ผู้รีวิวบล็อกทิ้งไว้ก็ต้องไปด้วย
    func testClearAllRemovesEveryScope() {
        let d = UserDefaults.standard
        d.set(["u1": "จริง"], forKey: "wbw.chat.blocked")
        d.set(["u2": "เดโม่"], forKey: "wbw.chat.blocked" + CacheScope.demoSuffix)

        BlockedUsers.clearAll()

        XCTAssertNil(d.object(forKey: "wbw.chat.blocked"))
        XCTAssertNil(d.object(forKey: "wbw.chat.blocked" + CacheScope.demoSuffix))
    }

    /// อีกทิศ — ไม่ logout ต้องยังอยู่ · กันการแก้เกินมือเป็น "ล้างทุกครั้งที่สร้าง instance ใหม่"
    /// ซึ่งจะทำให้การบล็อกไม่มีผลข้ามจอเลย (จอแชท จอสมาชิก จอตั้งค่า ถือคนละ instance)
    func testBlockPersistsAcrossInstancesWithoutLogout() {
        BlockedUsers().block("u1", name: "คนก่อกวน")
        XCTAssertTrue(BlockedUsers().isBlocked("u1"))
        XCTAssertEqual(BlockedUsers().entries.first?.name, "คนก่อกวน")
    }
}
