import XCTest
import UserNotifications
@testable import WBW

/// **ทำไม push ไม่เด้งเลยบนเครื่องจริง** — สองสาเหตุซ้อนกัน ทั้งคู่พังแบบไม่มี error ให้เห็น
///
/// 1. `GoogleService-Info.plist` ที่วางอยู่เป็นของ bundle อื่น (`th.ac.mfu.su.clubfair` ค้างจาก
///    รอบที่เกือบย้ายไปรายการ Club Fair) แต่แอปเป็น `th.ac.mfu.wbwSwift` — FCM ลงทะเบียนกับ
///    app คนละใบใน Firebase token ที่ได้จึงไม่มีทางตรงกับที่เซิร์ฟเวอร์ยิงไปหา
/// 2. เครื่องที่ **ล็อกอินค้างมาจาก build ก่อน** ไม่เคยถูกเรียก `registerForRemoteNotifications()`
///    เลย เพราะบรรทัดนั้นอยู่ในเส้นทางขอสิทธิ์ซึ่งวิ่งเฉพาะตอนล็อกอินสำเร็จ · ไม่มี APNs token
///    = FCM ไม่ออก token = ไม่มี device token ฝั่งเซิร์ฟเวอร์ ทั้งที่ผู้ใช้เคยกดอนุญาตไปนานแล้ว
final class PushDeliveryTests: XCTestCase {

    // MARK: - ไฟล์ Firebase ต้องเป็นของ bundle นี้

    func testFirebaseConfigMustBelongToThisApp() {
        XCTAssertTrue(PushManager.bundleMatches(optionsBundleID: "th.ac.mfu.wbwSwift",
                                                appBundleID: "th.ac.mfu.wbwSwift"))
        XCTAssertFalse(PushManager.bundleMatches(optionsBundleID: "th.ac.mfu.su.clubfair",
                                                 appBundleID: "th.ac.mfu.wbwSwift"),
                       "ไฟล์ของแอปอื่นต้องไม่ถูกใช้ configure — push จะตายเงียบทั้งงาน")
    }

    /// อ่านค่าไม่ได้เลยก็ถือว่าไม่ตรง — เดาว่า "น่าจะใช่" แล้วปล่อยผ่านคือสิ่งที่ทำให้เรื่องนี้
    /// ใช้เวลาไล่หาสองรอบโดยเห็นแค่ `device_token` ค้างที่ 0
    func testMissingValuesCountAsAMismatch() {
        XCTAssertFalse(PushManager.bundleMatches(optionsBundleID: nil, appBundleID: "th.ac.mfu.wbwSwift"))
        XCTAssertFalse(PushManager.bundleMatches(optionsBundleID: "th.ac.mfu.wbwSwift", appBundleID: nil))
    }

    // MARK: - ขอ APNs token ใหม่ทุกครั้งที่เปิดแอป

    /// **เคยกดอนุญาตไว้แล้วก็ยังต้องเรียก `registerForRemoteNotifications()` ใหม่ทุก launch**
    /// APNs token ไม่ใช่ของที่แอปเก็บไว้เองได้ · นี่คือเคสของเครื่องที่ล็อกอินค้างข้ามเวอร์ชัน
    func testAlreadyGrantedDevicesStillNeedToRegisterOnEveryLaunch() {
        for status: UNAuthorizationStatus in [.authorized, .provisional, .ephemeral] {
            XCTAssertTrue(PushManager.shouldRegisterForRemoteNotifications(authorization: status),
                          "สถานะ \(status.rawValue) อนุญาตแล้ว ต้องขอ APNs token ใหม่ทุกครั้ง")
        }
    }

    /// ยังไม่เคยถูกถาม หรือปฏิเสธไปแล้ว — ห้ามเรียก เพราะไม่มีอะไรให้ลงทะเบียน และการไปแตะ
    /// เส้นทางขอสิทธิ์เองคือสิ่งที่เพิ่งโดน 5.1.1(iv) ตีกลับมาสองรอบ
    func testUndecidedOrDeniedDevicesAreLeftAlone() {
        XCTAssertFalse(PushManager.shouldRegisterForRemoteNotifications(authorization: .notDetermined))
        XCTAssertFalse(PushManager.shouldRegisterForRemoteNotifications(authorization: .denied))
    }

    // MARK: - บอกให้รู้ว่าพังตรงไหน

    /// สรุปสถานะสี่อย่างเป็นบรรทัดเดียวสำหรับ log — ที่ผ่านมาอาการ "ไม่มี push" ไม่มีอะไรให้ดูเลย
    /// นอกจากเลข 0 ในฐานข้อมูล บรรทัดนี้ต้องชี้ได้ว่าตกที่ด่านไหน
    func testTheDiagnosticLineNamesEveryGate() {
        let line = PushManager.diagnosticLine(bundleMatches: false, firebaseEnabled: false,
                                              authorization: .authorized, hasFcmToken: false)
        for fragment in ["bundle", "firebase", "สิทธิ์", "fcm"] {
            XCTAssertTrue(line.lowercased().contains(fragment.lowercased()),
                          "บรรทัดวินิจฉัยไม่ได้บอกด่าน '\(fragment)': \(line)")
        }
    }
}
