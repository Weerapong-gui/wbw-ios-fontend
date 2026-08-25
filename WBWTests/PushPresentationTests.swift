import XCTest
import UserNotifications
@testable import WBW

/// สิ่งที่แอปทำกับ push ที่มาถึง **ตอนแอปเปิดอยู่**
///
/// ตรรกะนี้เคยฝังอยู่ใน `AppDelegate.userNotificationCenter(_:willPresent:)` ซึ่งเรียกจากเทส
/// ไม่ได้เลย (ต้องมี `UNNotification` จริงซึ่งสร้างเองไม่ได้) — ย้ายออกมาเป็นฟังก์ชันบริสุทธิ์
/// ตอนต่อสวิตช์ "แจ้งเตือนแชท" ในหน้าตั้งค่าให้ทำงานจริง (Guideline 2.1: สวิตช์ที่กดแล้วไม่มี
/// อะไรเกิดขึ้นคือปุ่มหลอก ซึ่ง repo นี้เคยโดนตีกลับมาแล้วจากปุ่ม "Sign up")
final class PushPresentationTests: XCTestCase {

    /// แชทกับความเห็นต่อฐานมี "ของแทน" ในแอปอยู่แล้ว (ChatToast / การรีเฟรชรายการ)
    /// banner ของระบบซ้อนทับจึงเป็นการบอกเรื่องเดียวกันสองครั้ง
    func testChatAndFeedbackPushDoNotAlsoRaiseASystemBanner() {
        XCTAssertFalse(PushPresentation.foreground(type: "chat", sosId: nil).showsSystemBanner)
        XCTAssertFalse(PushPresentation.foreground(type: "checkin_feedback", sosId: nil).showsSystemBanner)
    }

    /// ฐานที่เพิ่งเช็คอินต้องส่งสัญญาณให้จอโหลดของใหม่ ไม่งั้นเงียบไปจนกว่า poll รอบถัดไป (60 วิ)
    func testFeedbackPushSignalsTheScreenToRefresh() {
        XCTAssertEqual(PushPresentation.foreground(type: "checkin_feedback", sosId: nil).signal,
                       .checkinFeedbackArrived)
        XCTAssertNil(PushPresentation.foreground(type: "chat", sosId: nil).signal)
    }

    /// เคส SOS ของเพื่อนตัดสินจาก `sos_id` ที่อ่านได้จริง ไม่ใช่ `type == "sos"` เฉย ๆ
    func testSOSPushIsRecognisedByItsIdNotItsType() {
        let ok = PushPresentation.foreground(type: "sos", sosId: 42)
        XCTAssertFalse(ok.showsSystemBanner)
        XCTAssertEqual(ok.signal, .sosArrived)
    }

    /// payload ที่พังกลางทาง (ไม่มี sos_id) ต้องได้ banner ของระบบตามเดิม — เงียบหายไปเฉย ๆ
    /// โดยไม่มีอะไรแทนที่ แย่กว่า banner ที่ซ้ำซ้อน
    func testBrokenSOSPayloadFallsBackToTheSystemBanner() {
        let broken = PushPresentation.foreground(type: "sos", sosId: nil)
        XCTAssertTrue(broken.showsSystemBanner)
        XCTAssertNil(broken.signal)
    }

    func testUnknownTypesKeepTheSystemBanner() {
        XCTAssertTrue(PushPresentation.foreground(type: nil, sosId: nil).showsSystemBanner)
        XCTAssertTrue(PushPresentation.foreground(type: "announcement", sosId: nil).showsSystemBanner)
    }
}

/// ลำดับกล่องขอสิทธิ์หลังล็อกอิน
///
/// **มีเพราะย้ายการขอสิทธิ์แจ้งเตือนจาก `didFinishLaunching` มาไว้หลังล็อกอิน** (ของเดิมกล่อง
/// เด้งใส่คนที่ยังไม่ได้ล็อกอินบนจอ splash ที่ไม่มีบริบทอะไรเลย — รูปแบบเดียวกับที่
/// `LocationPrimer` ถูกสร้างขึ้นมาแก้) · ถ้าปล่อยให้ทั้งสองอย่างเกิดพร้อมกัน กล่องแจ้งเตือน
/// ของระบบจะซ้อนทับชีตอธิบายตำแหน่งที่เพิ่งแก้ไปตาม 5.1.1(iv) พอดี
final class PermissionSequenceTests: XCTestCase {

    func testLocationPrimerWaitsUntilTheNotificationPromptIsAnswered() {
        XCTAssertFalse(PermissionSequence.mayShowLocationPrimer(pushAuthorization: .notDetermined))
    }

    func testLocationPrimerProceedsOnceTheNotificationPromptIsOutOfTheWay() {
        for status: UNAuthorizationStatus in [.authorized, .denied, .provisional, .ephemeral] {
            XCTAssertTrue(PermissionSequence.mayShowLocationPrimer(pushAuthorization: status),
                          "สถานะ \(status.rawValue) ตอบไปแล้ว ชีตอธิบายตำแหน่งไม่ควรรอต่อ")
        }
    }
}
