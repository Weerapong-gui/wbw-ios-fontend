import XCTest
import SwiftUI
@testable import WBW

/// หน้าตั้งค่า — ปุ่มต้องเปลี่ยนอะไรจริง ไม่ใช่แค่จำค่าไว้เฉย ๆ
///
/// สองเรื่องที่ผู้ใช้เจอ: ปิดแจ้งเตือนแล้วกลับมาเปิดเองหลัง login, และสลับโหมดมืดแล้วพื้นยังขาว
final class SettingsBehaviorTests: XCTestCase {

    // MARK: - แจ้งเตือน

    /// ปิดสวิตช์แล้วต้องปิดจริง — เดิม registerCurrent() ไม่เคยอ่านค่านี้เลย ทำให้ Session.save()
    /// ตอน login และ updateFcmToken() ตอน FCM หมุน token ลงทะเบียนเครื่องกลับเข้าไปเงียบ ๆ
    /// ทั้งที่สวิตช์ยังโชว์ปิดอยู่
    func testDoesNotRegisterWhenNotificationsTurnedOff() {
        XCTAssertFalse(
            PushManager.shouldRegister(pushEnabled: true, notiEnabled: false, fcmToken: "fcm", jwt: "jwt"),
            "ผู้ใช้ปิดแจ้งเตือนไว้ — ห้ามลงทะเบียน device token กลับเข้าไปไม่ว่าจะถูกเรียกจากทางไหน")
    }

    func testRegistersWhenEverythingReady() {
        XCTAssertTrue(
            PushManager.shouldRegister(pushEnabled: true, notiEnabled: true, fcmToken: "fcm", jwt: "jwt"))
    }

    /// ค่าปริยายของ AppSettings คือ "เปิด" เมื่อยังไม่เคยแตะสวิตช์ (kNoti ยังไม่มีใน UserDefaults)
    /// ฝั่งนี้ต้องตีความเหมือนกัน ไม่งั้นเครื่องที่ไม่เคยเข้าหน้าตั้งค่าจะไม่ได้รับ push เลยสักครั้ง
    func testTreatsMissingPreferenceAsEnabled() {
        let key = "wbw.noti.enabled"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(PushManager.notificationsEnabledPreference(),
                      "ไม่เคยตั้งค่า = เปิด ต้องตรงกับ AppSettings.init")
    }

    func testReadsDisabledPreference() {
        let key = "wbw.noti.enabled"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(PushManager.notificationsEnabledPreference())
    }

    /// ขาดของอย่างใดอย่างหนึ่งก็ลงทะเบียนไม่ได้ — เงื่อนไขเดิมที่ต้องไม่หายไปตอนเพิ่ม notiEnabled
    func testStillRequiresPushEnabledAndTokens() {
        XCTAssertFalse(PushManager.shouldRegister(pushEnabled: false, notiEnabled: true, fcmToken: "fcm", jwt: "jwt"),
                       "Firebase ยังไม่พร้อม")
        XCTAssertFalse(PushManager.shouldRegister(pushEnabled: true, notiEnabled: true, fcmToken: nil, jwt: "jwt"),
                       "ยังไม่ได้ FCM token")
        XCTAssertFalse(PushManager.shouldRegister(pushEnabled: true, notiEnabled: true, fcmToken: "fcm", jwt: ""),
                       "ยังไม่ได้ login — JWT ว่าง")
    }

    // MARK: - โหมดมืด

    private func resolved(_ color: Color, _ style: UIUserInterfaceStyle) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    private func assertAdapts(_ color: Color, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotEqual(resolved(color, .light), resolved(color, .dark),
                          "\(name) ต้องเปลี่ยนตามธีม ไม่งั้นสลับโหมดมืดแล้วจอยังหน้าตาเดิม",
                          file: file, line: line)
    }

    /// สามตัวนี้คือพื้น/การ์ด/ตัวหนังสือ ถ้าไม่ปรับตามธีม สลับโหมดมืดแล้วแทบไม่มีอะไรเปลี่ยน
    func testCoreTokensAdaptToColorScheme() {
        assertAdapts(.wbwBg, "wbwBg")
        assertAdapts(.wbwSurface, "wbwSurface")
        assertAdapts(.wbwInk, "wbwInk")
        assertAdapts(.wbwMuted, "wbwMuted")
        assertAdapts(.wbwLine, "wbwLine")
    }

    /// สีแบรนด์ห้ามพลิกตามธีม — ทองกับเขียวเป็นเอกลักษณ์ของงาน ไม่ใช่สีพื้นผิว
    func testBrandColorsStayFixedAcrossSchemes() {
        for (color, name) in [(Color.wbwGold, "wbwGold"), (Color.wbwGreen, "wbwGreen"),
                              (Color.wbwCream, "wbwCream"), (Color.wbwForestVoid, "wbwForestVoid")] {
            XCTAssertEqual(resolved(color, .light), resolved(color, .dark),
                           "\(name) เป็นสีแบรนด์/สีฉาก ต้องเหมือนกันทั้งสองธีม")
        }
    }

    /// โหมดสว่างต้องได้ค่าเดิมเป๊ะ งานนี้เพิ่มโหมดมืด ไม่ใช่เปลี่ยนหน้าตาของโหมดสว่าง
    func testLightModeKeepsOriginalValues() {
        XCTAssertEqual(resolved(.wbwInk, .light), UIColor(red: 43 / 255, green: 43 / 255, blue: 43 / 255, alpha: 1),
                       "wbwInk โหมดสว่างต้องยังเป็น #2B2B2B เท่าเดิม")
        XCTAssertEqual(resolved(.wbwBg, .light), UIColor(red: 250 / 255, green: 247 / 255, blue: 240 / 255, alpha: 1),
                       "wbwBg โหมดสว่างต้องเป็นครีม #FAF7F0 สีเดียวกับที่แต่ละจอเคยประกาศเอง")
        XCTAssertEqual(resolved(.wbwSurface, .light), UIColor.white,
                       "wbwSurface โหมดสว่างต้องเป็นขาวล้วนเหมือน Color.white เดิม")
    }
}
