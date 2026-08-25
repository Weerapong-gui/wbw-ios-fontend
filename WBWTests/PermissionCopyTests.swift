import XCTest
@testable import WBW

/// **ปุ่มที่อยู่ก่อนกล่องขอสิทธิ์ของระบบ ห้ามใช้คำที่ชี้นำให้กดอนุญาต**
///
/// Guideline 5.1.1(iv) — App Review ตีกลับ 1.0 (11) เมื่อ 2026-08-24 ด้วยข้อความว่า:
/// *"A custom message appears before the permission request, and to proceed users press a
/// 'Allow Location' button. Use words like 'Continue' or 'Next' on the button instead."*
///
/// ตอนนั้นปุ่มบนจออธิบายใช้คีย์ `sos_status_loc_allow` = "อนุญาตตำแหน่ง" / "Allow location"
/// และมีอีกจุดที่ใช้คีย์เดียวกันแบบเดียวกันเป๊ะ (แบนเนอร์ในจอสถานะ SOS) ซึ่งผู้ตรวจยังไม่ทันเห็น
/// — แก้ทั้งสองที่พร้อมกันเป็น `action_continue`
///
/// เทสนี้กวาดซอร์สแทนที่จะเรียกฟังก์ชัน ด้วยเหตุผลเดียวกับ `HardcodedCopyTests`: สิ่งที่ต้องคุม
/// คือ **คำบนปุ่ม** ซึ่งไม่มีทางหลุดออกมาทาง API ไหนให้ assert ได้ และผิดแล้วไม่มีอะไรฟ้อง
/// นอกจากใบตีกลับรอบถัดไป ซึ่งเสียไปหนึ่งรอบรีวิวเต็ม ๆ
final class PermissionCopyTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// จอที่คั่นก่อนกล่องของระบบ — ทั้งสองใบเรียก `requestPermission()` ตรง ๆ จากปุ่มของตัวเอง
    private static let screensThatPrecedeTheSystemPrompt = [
        "WBW/SOS/LocationPrimerSheet.swift",
        "WBW/SOS/SOSStatusView.swift",
    ]

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private func table(_ language: String) throws -> [String: String] {
        let url = Self.repoRoot.appendingPathComponent("WBW/\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil)
                             as? [String: String])
    }

    /// คีย์เดิมต้องหายไปจากโค้ด **และ**จากชุดคีย์ ไม่ใช่แค่เลิกใช้
    ///
    /// ปล่อยไว้ในชุดคีย์แปลว่าวันหลังมีคนพิมพ์ `Text("sos_status_loc_allow")` แล้วได้ข้อความที่
    /// โดนตีกลับกลับมาบนจอ โดยที่ `check-localization.sh` ไม่ฟ้องอะไรเลยเพราะคีย์นั้นมีอยู่จริง
    func testTheRejectedAllowLocationKeyIsGoneEverywhere() throws {
        for path in Self.screensThatPrecedeTheSystemPrompt {
            XCTAssertFalse(try source(path).contains("sos_status_loc_allow"),
                           "\(path) ยังใช้คีย์ที่โดนตีกลับตาม 5.1.1(iv)")
        }
        for language in ["th", "en"] {
            XCTAssertNil(try table(language)["sos_status_loc_allow"],
                         "\(language) ยังมีคีย์ 'อนุญาตตำแหน่ง' ค้างอยู่ในชุดคีย์")
        }
    }

    /// ปุ่มที่พาไปสู่กล่องของระบบต้องเป็นคำกลาง — คำที่ Apple ยกมาเองคือ "Continue" / "Next"
    func testScreensBeforeThePromptUseTheNeutralContinueKey() throws {
        for path in Self.screensThatPrecedeTheSystemPrompt {
            XCTAssertTrue(try source(path).contains("action_continue"),
                          "\(path) ไม่ได้ใช้ปุ่มคำกลาง — ดู 5.1.1(iv)")
        }
    }

    /// คำบนปุ่มต้องไม่ชี้นำ **ทั้งสองภาษา** — ผู้ตรวจรอบนี้อ่านฉบับอังกฤษ ส่วนผู้ใช้จริงอ่านไทย
    func testTheNeutralButtonCopyDoesNotTellPeopleToAllowAnything() throws {
        let directives = ["อนุญาต", "ยินยอม", "เปิดสิทธิ์", "allow", "enable", "grant", "permit"]
        for language in ["th", "en"] {
            let copy = try XCTUnwrap(table(language)["action_continue"],
                                     "\(language) ไม่มีคีย์ action_continue")
            XCTAssertFalse(copy.isEmpty)
            for word in directives {
                XCTAssertFalse(copy.lowercased().contains(word.lowercased()),
                               "ปุ่มภาษา \(language) มีคำชี้นำ '\(word)' อยู่: \(copy)")
            }
        }
    }

    /// **จออธิบายต้องไม่มีทางออกอื่นนอกจากปุ่มที่พาไปสู่กล่องของระบบ**
    ///
    /// Guideline 5.1.1(iv) — App Review ตีกลับ **1.0 (12)** เมื่อ 2026-08-25 ด้วยข้อความว่า:
    /// *"A custom message appears before the permission request, and the user can close the
    /// message and delay the permission request with the Not now button. The user should
    /// always proceed to the permission request after the message."*
    ///
    /// รอบก่อน (1.0 (11)) โดนข้อเดียวกันเรื่อง **คำบนปุ่ม** จอนี้จึงโดนสองรอบติดกัน — รอบนี้
    /// เป็นตัวปุ่มที่สองเอง ไม่ใช่คำ · คีย์ต้องหายจากชุดคีย์ด้วย ไม่ใช่แค่เลิกใช้ ด้วยเหตุผล
    /// เดียวกับ `sos_status_loc_allow` ข้างบน
    func testThePrimerHasNoOptOutButton() throws {
        let code = try source("WBW/SOS/LocationPrimerSheet.swift")
        XCTAssertFalse(code.contains("location_primer_later"),
                       "จออธิบายยังมีปุ่มเลื่อนไปทีหลัง — ตรงกับที่ 5.1.1(iv) ตีกลับ 1.0 (12)")
        for language in ["th", "en"] {
            XCTAssertNil(try table(language)["location_primer_later"],
                         "\(language) ยังมีคีย์ปุ่ม 'ไว้ทีหลัง' ค้างอยู่ในชุดคีย์")
        }
    }

    /// **ปัดชีตทิ้งก็คือ "ไว้ทีหลัง" อีกทาง** — ถอดแต่ปุ่มไม่พอ
    ///
    /// ใบตีกลับเขียนว่า *"the user can **close the message** and delay"* ซึ่งกินความถึงการปัด
    /// ด้วย · รอบนี้ผู้ตรวจใช้ **iPad Air 11-inch (M3)** ด้วย ซึ่ง `.sheet` เป็นกรอบลอยกลางจอ
    /// ที่ **แตะนอกกรอบแล้วปิดได้** — `interactiveDismissDisabled` ปิดทั้งสองทางพร้อมกัน
    /// ส่วนแถบลากคือคำเชิญให้ปัด ที่ยังค้างอยู่บนสกรีนช็อตในใบตีกลับ
    func testThePrimerCannotBeClosedByGesture() throws {
        let code = try source("WBW/SOS/LocationPrimerSheet.swift")
        XCTAssertTrue(code.contains("interactiveDismissDisabled(true)"),
                      "จออธิบายยังปัดทิ้ง/แตะนอกกรอบปิดได้ — ทางออกที่ 5.1.1(iv) ห้ามไว้")
        XCTAssertTrue(code.contains("presentationDragIndicator(.hidden)"),
                      "ยังมีแถบลากชวนให้ปัดทิ้ง ทั้งที่ปัดไม่ได้แล้ว")
    }
}
