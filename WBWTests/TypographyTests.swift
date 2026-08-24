import XCTest
import SwiftUI
import UIKit
@testable import WBW

/// ฟอนต์ที่ลงทะเบียนไม่ติดคือบั๊กที่เงียบที่สุดในแอปนี้
///
/// `Font.custom(_:size:)` ที่หาชื่อ PostScript ไม่เจอ **ไม่ throw ไม่ log ไม่ทำให้ build พัง** —
/// มันตกกลับไปใช้ San Francisco เงียบ ๆ ผลคือทั้งแอปดูเหมือน "ยังไม่ได้ทำงานฟอนต์" แทนที่จะดู
/// เหมือนพัง · เคสที่ทำให้พังได้จริงมีสามทาง และไม่มีทางไหนที่คอมไพเลอร์เห็น:
/// - `UIAppFonts` ใน `Info.plist` เขียนเป็น `Fonts/Sarabun-Regular.ttf` ทั้งที่ XcodeGen แบน
///   resource ลง bundle ราก (เคยเขียนผิดแบบนี้มาแล้วตอนเพิ่มฟอนต์)
/// - ชื่อไฟล์ไม่ตรงกับชื่อ PostScript ข้างในไฟล์ (`Sarabun-SemiBold.ttf` ที่ข้างในชื่อ
///   `Sarabun-Semibold` — ต่างกันตัวเดียว)
/// - ลืมรัน `xcodegen generate` หลังวางไฟล์ ฟอนต์จึงไม่ถูก copy เข้า bundle เลย
///
/// เทสนี้รันในโปรเซสของแอป (app target เป็น test host) จึงเห็น bundle จริงที่เครื่องจะได้
final class TypographyTests: XCTestCase {

    func testEveryFontTheAppAsksForIsActuallyRegistered() {
        XCTAssertTrue(FontAudit.missing.isEmpty,
                      "ฟอนต์ลงทะเบียนไม่ติด: \(FontAudit.missing.joined(separator: ", ")) — " +
                      "แอปจะตกกลับไปใช้ฟอนต์ระบบเงียบ ๆ ทั้งแอปโดยไม่มี error ให้เห็น")
    }

    /// กันรายชื่อที่ตรวจว่างเปล่า — `missing` ของลิสต์ว่างก็ว่าง เทสข้างบนจึงผ่านฟรี
    func testAuditListActuallyCoversTheAppFont() {
        XCTAssertFalse(FontAudit.expected.isEmpty, "ลิสต์ตรวจว่าง เทสข้างบนจะผ่านฟรีทุกครั้ง")
        XCTAssertTrue(FontAudit.expected.allSatisfy { $0.hasPrefix("Anuphan") },
                      "แอปใช้ Anuphan หน้าเดียวทั้งแอป (เปลี่ยนจาก Sarabun + Kanit 2026-08-25)")
    }

    /// **น้ำหนักทุกตัวที่ enum ประกอบชื่อขึ้นมาได้ ต้องมีของจริงรองรับ**
    ///
    /// Anuphan เป็น variable font ไฟล์เดียวที่ iOS กาง instance ออกมาให้ตามชื่อใน `fvar`
    /// เพิ่ม case ใหม่ใน enum โดยที่ไฟล์ไม่มี instance นั้น ฟอนต์จะหายเฉพาะจุดที่เรียก
    /// น้ำหนักนั้น ซึ่งหายากกว่าหายทั้งแอปมาก
    ///
    /// เรียก `Font.face(_:)` ตัวเดียวกับที่โค้ดจริงใช้ ไม่ใช่ประกอบชื่อเองในเทส —
    /// ประกอบเองแล้ววันที่กฎตั้งชื่อเปลี่ยน เทสจะยังเขียวทั้งที่แอปพัง
    func testEveryWeightTheCodeCanAskForIsRegistered() {
        for weight in [Font.NumeralWeight.medium, .semibold, .bold] {
            let name = Font.face(weight.rawValue)
            XCTAssertNotNil(UIFont(name: name, size: 12), "ไม่มี instance ฟอนต์สำหรับ \(name)")
        }
        for weight in [Font.TextWeight.regular, .semibold, .bold] {
            let name = Font.face(weight.rawValue)
            XCTAssertNotNil(UIFont(name: name, size: 12), "ไม่มี instance ฟอนต์สำหรับ \(name)")
        }
    }

    /// สัญญาอนุญาต OFL ต้องเดินทางไปกับฟอนต์เสมอ
    ///
    /// SIL Open Font License ข้อ 2 บังคับให้แนบสำเนาสัญญาไปกับไฟล์ฟอนต์ทุกชุดที่แจกจ่าย —
    /// แอปที่ส่งขึ้น store คือการแจกจ่าย · ลบไฟล์นี้ทิ้งคือผิดสัญญาอนุญาต ไม่ใช่แค่เสียมารยาท
    func testTheOpenFontLicenseShipsWithTheFont() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let license = root.appendingPathComponent("WBW/Resources/Fonts/Anuphan-OFL.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: license.path),
                      "ไฟล์สัญญาอนุญาตหายไป — OFL บังคับให้แนบไปกับฟอนต์ที่แจกจ่าย")
        let text = try String(contentsOf: license, encoding: .utf8)
        XCTAssertTrue(text.contains("SIL OPEN FONT LICENSE"), "เนื้อไฟล์ไม่ใช่สัญญาอนุญาต OFL")
    }
}
