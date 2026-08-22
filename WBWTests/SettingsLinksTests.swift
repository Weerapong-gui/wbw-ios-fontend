import XCTest
@testable import WBW

/// ลิงก์ออกเว็บในหมวด "ทั่วไป" ของหน้าตั้งค่า — นโยบายความเป็นส่วนตัวกับหน้าช่วยเหลือ
///
/// **สอง URL นี้คือค่าเดียวกับที่กรอกใน App Store Connect** (Privacy Policy URL กับ
/// Support URL) · พิมพ์ผิดแล้วไม่มีอะไรฟ้อง: แอปคอมไพล์ผ่าน ปุ่มกดได้ Safari เปิดขึ้นมา
/// แล้วโชว์ 404 — คนแรกที่เจอคือผู้ตรวจของ Apple ซึ่งเป็นรอบที่แพงที่สุดที่จะเจอ
///
/// ต้องเป็น **ลิงก์ออกเว็บ ไม่ใช่ `DocView` ที่ฝังข้อความไว้ในแอป** — ฝังไว้แล้วแก้นโยบาย
/// ทีไรต้องส่งแอปเวอร์ชันใหม่ให้ Apple ตรวจทุกครั้ง
final class SettingsLinksTests: XCTestCase {

    func testPrivacyRowOpensThePublishedPolicy() {
        XCTAssertEqual(SettingsWebLink.privacy.absoluteString,
                       "https://walkbeyondthewild.studentunion.social/privacy",
                       "ต้องเป็น URL เดียวกับที่กรอกช่อง Privacy Policy URL ใน ASC")
    }

    func testSupportRowOpensThePublishedSupportPage() {
        XCTAssertEqual(SettingsWebLink.support.absoluteString,
                       "https://walkbeyondthewild.studentunion.social/support",
                       "ต้องเป็น URL เดียวกับที่กรอกช่อง Support URL ใน ASC")
    }

    /// http ธรรมดาจะโดน ATS บล็อก — ปุ่มกดแล้วเงียบ ไม่มี error ให้ผู้ใช้เห็นว่าเกิดอะไรขึ้น
    func testLinksUseHttps() {
        for url in [SettingsWebLink.privacy, SettingsWebLink.support] {
            XCTAssertEqual(url.scheme, "https", "\(url) ต้องเป็น https ไม่งั้น ATS บล็อกเงียบ ๆ")
        }
    }

    /// คีย์ที่หายไม่ทำให้ build พัง ผู้ใช้จะเห็นคำว่า "settings_privacy" เป็นชื่อแถวแทน
    func testRowTitlesExistInBothLanguages() {
        defer { Loc.use(.system) }
        for language in [AppLanguage.th, .en] {
            Loc.use(language)
            for key in [SettingsWebLink.privacyTitleKey, SettingsWebLink.supportTitleKey] {
                XCTAssertNotEqual(Loc.t(key), key,
                                  "ไม่มีคีย์ \(key) ในภาษา \(language) — ผู้ใช้จะเห็นชื่อคีย์บนแถว")
            }
        }
    }
}
