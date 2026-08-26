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

    /// ค่าปริยายคือ **มืด** ไม่ใช่ `auto` — ต่างจาก `ThemeMode.AUTO` ของ Android โดยตั้งใจ
    ///
    /// `WBWApp` ส่งค่านี้ต่อเป็น `.preferredColorScheme` ซึ่งคุมสีนาฬิกา/แบตของ status bar ด้วย
    /// `auto` บนเครื่องที่ตั้งโหมดสว่างจะได้ status bar ตัวดำทับพื้นภาพที่มืดอยู่ดี
    func testDefaultsToDarkWhenTheUserHasNeverTouchedTheSwitch() {
        let keys = [AppSettings.themeModeKey, AppSettings.darkModeKey]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { UserDefaults.standard.set(v, forKey: k) } }

        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        XCTAssertEqual(AppSettings.themeModePreference(), .dark,
                       "ยังไม่เคยตั้งค่า = โหมดมืด ไม่งั้น status bar เป็นตัวดำบนพื้นภาพที่มืด")
    }

    /// **ย้ายค่าของคนที่เคยตั้งสวิตช์สองสถานะไว้** — สวิตช์เดิมเป็น Bool ตัวเดียว (`wbw.darkmode`)
    /// ตอนนี้เป็นสามสถานะคนละคีย์ · ไม่อ่านคีย์เก่าเลยแปลว่าคนที่เคยเลือกโหมดสว่างไว้เองจะถูก
    /// ดีดกลับเป็นมืดเงียบ ๆ ตอนอัปเดตแอป
    func testMigratesTheOldTwoStateDarkSwitch() {
        let keys = [AppSettings.themeModeKey, AppSettings.darkModeKey]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { UserDefaults.standard.set(v, forKey: k) } }

        UserDefaults.standard.removeObject(forKey: AppSettings.themeModeKey)
        UserDefaults.standard.set(false, forKey: AppSettings.darkModeKey)
        XCTAssertEqual(AppSettings.themeModePreference(), .light,
                       "เคยเลือกสว่างไว้ ต้องได้สว่าง ไม่ใช่ค่าปริยาย")

        UserDefaults.standard.set(true, forKey: AppSettings.darkModeKey)
        XCTAssertEqual(AppSettings.themeModePreference(), .dark)
    }

    /// คีย์ใหม่ชนะคีย์เก่าเสมอ — คนที่เข้าหน้าตั้งค่าแล้วเลือกใหม่ต้องไม่ถูกค่าเก่าดึงกลับ
    func testTheNewKeyWinsOverTheMigratedOne() {
        let keys = [AppSettings.themeModeKey, AppSettings.darkModeKey]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { UserDefaults.standard.set(v, forKey: k) } }

        UserDefaults.standard.set(true, forKey: AppSettings.darkModeKey)
        UserDefaults.standard.set(ThemeMode.auto.rawValue, forKey: AppSettings.themeModeKey)
        XCTAssertEqual(AppSettings.themeModePreference(), .auto)
    }

    /// ยังไม่เคยเลือกภาษา = เดินตามเครื่อง ไม่ใช่บังคับไทย
    func testLanguageDefaultsToFollowingTheDevice() {
        let key = AppSettings.languageKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(AppSettings.languagePreference(), .system)

        UserDefaults.standard.set("en", forKey: key)
        XCTAssertEqual(AppSettings.languagePreference(), .en)
    }

    /// ค่าขยะใน UserDefaults ต้องไม่ทำให้แอปพัง — ตกกลับไปเดินตามเครื่อง
    func testUnknownLanguageValueFallsBackToTheDevice() {
        let key = AppSettings.languageKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        UserDefaults.standard.set("klingon", forKey: key)
        XCTAssertEqual(AppSettings.languagePreference(), .system)
    }

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

    /// **กฎข้อที่สำคัญที่สุดของ palette ที่ยกมาจาก Android** — พื้นหลังเป็นภาพเดียวและมืดเสมอ
    /// ไม่ว่าผู้ใช้เลือกธีมไหน ตัวอักษรที่วางลงบนภาพจึงตามธีมไม่ได้
    ///
    /// ต้นทางเขียนว่า *"Using [textPrimary] here is what makes a title vanish in light mode"* —
    /// อาการคือคำทักทายบน Home หายไปเฉย ๆ ตอนสลับเป็นโหมดสว่าง โดยไม่มี error ให้เห็น
    func testBackdropInkStaysLightInBothSchemes() {
        for (color, name) in [(Color.wbwOnBackdrop, "wbwOnBackdrop"),
                              (Color.wbwOnBackdropMuted, "wbwOnBackdropMuted")] {
            XCTAssertEqual(resolved(color, .light), resolved(color, .dark),
                           "\(name) วางอยู่บนภาพพื้นหลัง ห้ามเปลี่ยนตามธีม")
            var white: CGFloat = 0
            resolved(color, .light).getWhite(&white, alpha: nil)
            XCTAssertGreaterThan(white, 0.55,
                                 "\(name) ต้องสว่างพอจะอ่านออกบนภาพที่ความสว่างเฉลี่ย 0.25")
        }
    }

    /// ของที่เป็นดีไซน์ตายตัว ไม่ใช่พื้นผิวที่เดินตามการตั้งค่ารูปลักษณ์
    ///
    /// บัตรผู้เข้าร่วมคือของที่ยกให้เจ้าหน้าที่ดู · สีสภาพอากาศนั่งบนภาพพื้นหลังโดยตรง
    /// (เหตุผลเดียวกับ `wbwOnBackdrop`) · `wbwForestVoid` เป็นพื้นฉาก ไม่ใช่พื้นจอ
    func testFixedDesignColoursDoNotFollowTheTheme() {
        for (color, name) in [(Color.wbwForestVoid, "wbwForestVoid"),
                              (Color.wbwMedical, "wbwMedical"),
                              (Color.wbwSolid, "wbwSolid"),
                              (Color.wbwOnBackdropDanger, "wbwOnBackdropDanger"),
                              (Color.ticketDeep, "ticketDeep"),
                              (Color.ticketGreen, "ticketGreen"),
                              (Color.ticketCreamPaper, "ticketCreamPaper"),
                              (Color.skySunTint, "skySunTint"),
                              (Color.skyRainTint, "skyRainTint"),
                              (Color.airGoodTint, "airGoodTint")] {
            XCTAssertEqual(resolved(color, .light), resolved(color, .dark),
                           "\(name) เป็นดีไซน์ตายตัว ต้องเหมือนกันทั้งสองธีม")
        }
    }

    /// **ไม่มีสีเน้นแล้ว** — accent คือ ink ตัวเดียวกัน ไม่ใช่เฉดอื่น
    ///
    /// `Color.kt` ของ Android: *"There is no accent hue. Gold, then leaf green, were both tried
    /// and both lost"* · โทเคนยังอยู่เพื่อให้จุดเรียกคงความหมาย แต่ค่าต้องเท่ากับ `wbwInk` เป๊ะ
    /// ทั้งสองธีม ไม่งั้นชื่อโทเคนจะโกหกอีกรอบเหมือนตอนที่ `wbwGold` ไม่ได้เป็นสีทองแล้ว
    func testAccentIsTheInkNotAHue() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            XCTAssertEqual(resolved(.wbwAccent, style), resolved(.wbwInk, style),
                           "accent ต้องเป็นสีเดียวกับ ink")
            XCTAssertEqual(resolved(.wbwGold, style), resolved(.wbwAccent, style),
                           "wbwGold เป็น alias ของ accent แล้ว — ห้ามมีสีทองเหลืออยู่")
        }
    }

    /// เขียวสถานะปรับตามธีม (ต่างจากของเดิมที่ตายตัว) เพราะมันวางบน **การ์ด** ไม่ใช่บนภาพ
    func testStatusGreenAdaptsBecauseItSitsOnCards() {
        assertAdapts(.wbwGreen, "wbwGreen")
    }

    /// โหมดสว่างต้องได้ค่าตามชุดที่ยกมาจาก Android เป๊ะ — ออฟไวท์อุ่นที่ยังมีเขียวปน
    /// ไม่ใช่ขาวล้วน (`"Pure white on a forest ground reads as a hole punched in the page"`)
    func testLightModeMatchesTheAndroidPalette() {
        XCTAssertEqual(resolved(.wbwInk, .light), UIColor(red: 0x1B / 255, green: 0x2A / 255, blue: 0x1B / 255, alpha: 1),
                       "wbwInk โหมดสว่าง = #1B2A1B")
        XCTAssertEqual(resolved(.wbwBg, .light), UIColor(red: 0xED / 255, green: 0xF0 / 255, blue: 0xE5 / 255, alpha: 1),
                       "wbwBg โหมดสว่าง = #EDF0E5")
        XCTAssertEqual(resolved(.wbwSurface, .light), UIColor(red: 0xF5 / 255, green: 0xF4 / 255, blue: 0xE9 / 255, alpha: 1),
                       "wbwSurface โหมดสว่าง = #F5F4E9 ไม่ใช่ขาวล้วน")
    }

    // MARK: - คู่สีของแท็บแชท

    /// ความสว่างเชิงเส้นตามสูตร WCAG — ไม่ใช่ `getWhite` ซึ่งเป็นค่าที่ผ่าน gamma มาแล้ว
    private func luminance(_ color: Color, _ style: UIUserInterfaceStyle) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved(color, style).getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private func contrast(_ a: Color, _ b: Color, _ style: UIUserInterfaceStyle) -> Double {
        let (x, y) = (luminance(a, style), luminance(b, style))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func assertContrast(_ a: Color, _ aName: String, on b: Color, _ bName: String,
                                atLeast floor: Double,
                                file: StaticString = #filePath, line: UInt = #line) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let ratio = contrast(a, b, style)
            let mode = style == .light ? "สว่าง" : "มืด"
            XCTAssertGreaterThan(ratio, floor,
                                 "โหมด\(mode): \(aName) บน \(bName) ได้ \(String(format: "%.2f", ratio)):1 "
                                 + "ต่ำกว่าเกณฑ์ \(floor):1",
                                 file: file, line: line)
        }
    }

    /// `wbwOnGreen` ต้องพลิกตามธีม เพราะ `wbwGreen` เองพลิก (เข้มในโหมดสว่าง อ่อนในโหมดมืด)
    /// ตัวอักษรสีเดียวตายตัวบนมันจะอ่านออกได้แค่ธีมเดียว
    func testOnGreenFlipsWithTheThemeBecauseGreenDoes() {
        assertAdapts(.wbwOnGreen, "wbwOnGreen")
    }

    /// **นี่คือเทสที่จับบั๊กจริงของแท็บแชท** — ฟองข้อความฝั่งเรา ปุ่มส่ง pill "ข้อความใหม่"
    /// และปุ่มเข้ากลุ่ม ใช้ `wbwGold` (= `wbwAccent` = #E9EEE0 ในโหมดมืด) คู่กับตัวอักษร `.white`
    /// ตายตัว จากยุคที่ `wbwGold` ยังเป็นสีทองจริง ผลคือ **ขาวบนขาว** ในโหมดมืดซึ่งเป็นค่าปริยาย
    /// ของแอป · คอมไพเลอร์ไม่เห็น เทสสีเดิมก็ไม่เห็น เพราะทุกตัวตรวจ "โทเคนคืออะไร" ไม่ใช่
    /// "โทเคนคู่ไหนถูกวางทับกัน"
    func testChatColourPairsClearTheContrastFloor() {
        assertContrast(.wbwOnGreen, "wbwOnGreen", on: .wbwGreen, "wbwGreen", atLeast: 4.5)
        assertContrast(.wbwOnBackdrop, "wbwOnBackdrop", on: .wbwSolid, "wbwSolid", atLeast: 4.5)
    }

    /// ปุ่มทึบต้องแยกออกจากการ์ดที่มันวางอยู่ — ไม่ใช่เรื่องตัวอักษร แต่เป็นเรื่อง "เห็นว่ามีปุ่มไหม"
    ///
    /// โหมดมืดคือฝั่งที่คับ: `wbwSolid` (#2F3B2B) บน `wbwSurface` (#1A2318) ได้ราว 1.3:1
    /// ตัวปุ่มจึงต้องมีเส้นขอบผมของตัวเองเป็นสิ่งที่กำหนดรูปทรง (ท่าเดียวกับ `GlassSurface`)
    /// เกณฑ์ 1.2:1 คือ "พื้นต่างกันพอให้เส้นขอบไม่ใช่สิ่งเดียวที่มองเห็น" ไม่ใช่เกณฑ์ตัวอักษร
    func testSolidButtonSeparatesFromTheCardItSitsOn() {
        assertContrast(.wbwSolid, "wbwSolid", on: .wbwSurface, "wbwSurface", atLeast: 1.2)
    }

    /// **ปุ่มเข้าสู่ระบบต้องใช้โทเคน ไม่ใช่ hex ดิบ** — และนี่คือเหตุผลที่เทสสีตัวอื่นมองไม่เห็นบั๊กนี้
    ///
    /// ของเดิมเป็นพื้น `wbwCream` (ชื่อเก่าของ `wbwBg` = #0F1610 เกือบดำในโหมดมืด) คู่กับตัวอักษร
    /// `Color(red: 0.23, green: 0.17, blue: 0.07)` ที่พิมพ์ไว้กลางไฟล์จอ ได้ราว 1.35:1 —
    /// อ่านไม่ออกและดันไปตรงกับสำนวน "ปุ่มปิดใช้งาน" ที่จออื่นใช้ (`wbwSolid` พื้นเข้ม = กดไม่ได้)
    /// เจ้าของงานจึงรายงานว่าปุ่มเป็นสีเทาทั้งที่ยังไม่ได้กด (2026-08-26)
    ///
    /// เทสคู่สีอย่างเดียวจับไม่ได้เพราะ hex ดิบไม่ใช่โทเคนที่เทสรู้จัก — ต้องห้ามที่ระดับซอร์สด้วย
    func testLoginButtonUsesThemeTokensNotRawHex() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("WBW/LoginView.swift")
        // ตัดบรรทัดคอมเมนต์ทิ้งก่อนสแกน — คอมเมนต์ในไฟล์นั้นพูดถึงชื่อสีเก่าโดยตั้งใจ เพื่อบอกว่า
        // ของเดิมคืออะไรและทำไมถึงเลิกใช้ · ห้ามทั้งคำเท่ากับห้ามอธิบายเหตุผลไว้ให้คนอ่านรอบหน้า
        let source = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")

        XCTAssertFalse(source.contains("Color(red:"), """
            สีดิบกลางไฟล์จอ = สีที่ไม่พลิกตามธีมและไม่มีเทสไหนมองเห็น
            (กติกา ui-conventions: เพิ่มเป็น static let ใน Config.swift ก่อน)
            """)
        for legacy in ["wbwCream", "wbwGold"] {
            XCTAssertFalse(source.contains(legacy), """
                `\(legacy)` เป็นชื่อเก่าที่ Config.swift เขียนไว้เองว่าโค้ดใหม่ห้ามใช้ —
                มันชี้ไปที่ค่าที่ความหมายกลับด้านในโหมดมืด
                """)
        }
    }
}
