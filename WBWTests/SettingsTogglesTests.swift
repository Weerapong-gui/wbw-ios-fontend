import XCTest
@testable import WBW

/// **สวิตช์ในหน้าตั้งค่าต้องมีของจริงอยู่ปลายทาง**
///
/// Guideline 2.1 — หน้าตั้งค่าเคยมีสวิตช์แจ้งเตือน 4 ตัว แต่ 3 ตัว ("ใกล้ฐาน" · "แชท" ·
/// "สรุปรายวัน") เขียนค่าลง `UserDefaults` แล้วจบตรงนั้น ไม่มีใครอ่านต่อเลยสักที่
/// คอมเมนต์ในไฟล์เขียนไว้เองว่า "สามตัวล่างเก็บค่าไว้เฉย ๆ" — เป็นปุ่มหลอกแบบเดียวกับ
/// "Don't have an account? Sign up" ที่เคยทำให้โดนตีกลับ 2.1 มาแล้ว (ดู `FakeAffordanceTests`)
///
/// ทางแก้ที่เลือก: ถอดสองตัวที่ไม่มี push ชนิดนั้นจริง (`nearby`/`daily`) แล้ว **ต่อตัวแชท
/// ให้ทำงานจริง** กับแบนเนอร์ในแอป · เทสนี้กันทั้งสองฝั่งไม่ให้ย้อนกลับ
final class SettingsTogglesTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private func table(_ language: String) throws -> [String: String] {
        let url = Self.repoRoot.appendingPathComponent("WBW/\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil)
                             as? [String: String])
    }

    /// คีย์ของสวิตช์ที่ถอดไปต้องหายจากทั้งจอ **และ**จากชุดคีย์ — เหลือไว้ในชุดคีย์แปลว่า
    /// วันหลังมีคนวางแถวกลับเข้าไปได้โดยที่ `check-localization.sh` ไม่ฟ้องอะไรเลย
    func testTheDecorativeTogglesAreGoneEverywhere() throws {
        let removed = ["settings_noti_nearby", "settings_noti_nearby_desc",
                       "settings_noti_daily", "settings_noti_daily_desc"]
        let settings = try source("WBW/SettingsView.swift")
        let model = try source("WBW/AppSettings.swift")
        for key in removed {
            XCTAssertFalse(settings.contains(key), "หน้าตั้งค่ายังมีสวิตช์หลอก \(key)")
            for language in ["th", "en"] {
                XCTAssertNil(try table(language)[key], "\(language) ยังมีคีย์ \(key) ค้างอยู่")
            }
        }
        for property in ["notiNearby", "notiDaily"] {
            XCTAssertFalse(model.contains(property), "AppSettings ยังเก็บค่าที่ไม่มีใครอ่าน \(property)")
        }
    }

    /// สวิตช์ที่เหลือสองตัวต้องมีคนอ่านค่าไปใช้จริง
    ///
    /// `notiEnabled` คุมการลงทะเบียน device token (`PushManager`) ส่วน `notiChat` คุมแบนเนอร์
    /// ในแอปที่ `MainTabView` วาด — ปลายทางอยู่คนละไฟล์กับหน้าตั้งค่าทั้งคู่ ถ้าวันหลังมีคนถอด
    /// ปลายทางออกไป สวิตช์จะกลายเป็นปุ่มหลอกทันทีโดยไม่มีอะไรฟ้อง
    func testEveryRemainingToggleIsReadSomewhereThatMatters() throws {
        XCTAssertTrue(try source("WBW/MainTabView.swift").contains("notiChat"),
                      "ไม่มีใครอ่านสวิตช์แจ้งเตือนแชท — กลายเป็นปุ่มหลอก")
        XCTAssertTrue(try source("WBW/AppDelegate.swift").contains("notiEnabledKey"),
                      "ไม่มีใครอ่านสวิตช์ประกาศ — กลายเป็นปุ่มหลอก")
    }

    /// **คำอธิบายใต้สวิตช์แชทต้องพูดความจริงว่าคุมอะไร**
    ///
    /// สิ่งที่แอปคุมได้คือแบนเนอร์ที่วาดเองตอนแอปเปิดอยู่ ไม่ใช่ push ที่ระบบขึ้นตอนแอปปิด
    /// (payload ประกอบขึ้นฝั่ง SUS แอปไม่มีสิทธิ์ห้าม) · เขียนกว้างกว่านั้นคือคำโฆษณาที่ผู้ใช้
    /// พิสูจน์ได้เองว่าไม่จริงภายในสิบวินาที
    func testTheChatToggleDescriptionOnlyClaimsWhatTheAppCanDo() throws {
        for language in ["th", "en"] {
            let copy = try XCTUnwrap(try table(language)["settings_noti_chat_desc"])
            XCTAssertFalse(copy.isEmpty)
            let inAppWording = ["ขณะเปิดแอป", "while the app is open"]
            XCTAssertTrue(inAppWording.contains(where: { copy.localizedCaseInsensitiveContains($0) }),
                          "\(language) ไม่ได้บอกว่าคุมเฉพาะตอนเปิดแอป: \(copy)")
        }
    }
}
