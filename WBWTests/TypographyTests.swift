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
    func testAuditListCoversBothFamilies() {
        XCTAssertTrue(FontAudit.expected.contains { $0.hasPrefix("Sarabun-") },
                      "ลิสต์ตรวจต้องมี Sarabun (ตัวอักษรของข้อความทั้งแอป)")
        XCTAssertTrue(FontAudit.expected.contains { $0.hasPrefix("Kanit-") },
                      "ลิสต์ตรวจต้องมี Kanit (ตัวเลขบนบัตรและจำนวนเด่น)")
    }

    /// น้ำหนักทุกตัวที่ `wbwNumeral` ประกอบชื่อขึ้นมาได้ ต้องมีไฟล์รองรับจริง
    ///
    /// `NumeralWeight` เป็น enum ที่เอา rawValue ไปต่อท้าย `"Kanit-"` ตรง ๆ — เพิ่ม case ใหม่
    /// โดยไม่ได้เพิ่มไฟล์ ฟอนต์จะหายเฉพาะจุดที่เรียกน้ำหนักนั้น ซึ่งหายากกว่าหายทั้งแอป
    func testEveryNumeralWeightHasAFile() {
        for weight in [Font.NumeralWeight.medium, .semibold, .bold] {
            let name = "Kanit-\(weight.rawValue)"
            XCTAssertNotNil(UIFont(name: name, size: 12), "ไม่มีไฟล์ฟอนต์สำหรับ \(name)")
        }
    }
}
