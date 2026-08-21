import XCTest
@testable import WBW

/// ขีดยาวคั่นประโยคถูกเอาออกทั้งแอปแล้ว (2026-08-21) — เทสนี้คือด่านเดียวที่กันไม่ให้มันกลับมา
///
/// `scripts/check-localization.sh` ตรวจสองอย่าง: คีย์มีครบทั้งสองภาษาไหม กับตัวระบุรูปแบบ
/// ตรงกันไหม **มันไม่รู้จักเครื่องหมายวรรคตอนเลย** ใครเติม `—` กลับเข้ามาในอีกหกเดือน
/// จะผ่านทั้ง build ทั้งสคริปต์ และผ่านสายตาคนรีวิวที่ไม่ได้รู้ว่าเคยมีการตัดสินใจนี้
///
/// อ่านไฟล์จาก source tree ผ่าน `#filePath` ไม่ใช่ผ่าน `Loc.t` เพราะต้องกวาด**ทุกคีย์**
/// ไม่ใช่คีย์ที่บังเอิญรู้ชื่ออยู่แล้ว (แพตเทิร์นเดียวกับ `AppAssetsTests`)
final class LocalizationDashTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // WBWTests
        .deletingLastPathComponent()   // repo root

    /// `"key" = "value";` โดยยอมให้มี escape (`\"`, `\n`) อยู่ในค่าได้
    private static let entry = try! NSRegularExpression(
        pattern: "^\\s*\"([A-Za-z0-9_]+)\"\\s*=\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\s*;")

    private func entries(_ language: String) throws -> [(key: String, value: String)] {
        let url = Self.repoRoot.appendingPathComponent("WBW/\(language).lproj/Localizable.strings")
        let text = try String(contentsOf: url, encoding: .utf8)
        var found: [(String, String)] = []
        for line in text.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let m = Self.entry.firstMatch(in: line, range: range),
                  let k = Range(m.range(at: 1), in: line),
                  let v = Range(m.range(at: 2), in: line) else { continue }
            found.append((String(line[k]), String(line[v])))
        }
        return found
    }

    /// ตัวกวาดต้องเจอคีย์จริง ไม่ใช่ผ่านเพราะ regex ไม่แมตช์อะไรเลย
    ///
    /// ถ้าข้อนี้พัง แปลว่าเทสข้างล่างกำลังตรวจลิสต์ว่าง = ผ่านตลอดกาลโดยไม่ได้ตรวจอะไร
    func testTheSweepActuallyReadsBothCatalogues() throws {
        for language in ["en", "th"] {
            let rows = try entries(language)
            XCTAssertGreaterThan(rows.count, 250,
                                 "\(language): อ่านได้แค่ \(rows.count) คีย์ — regex ไม่แมตช์ไฟล์จริงแล้ว")
            XCTAssertTrue(rows.contains { $0.key == "group_join" },
                          "\(language): ไม่เจอคีย์ที่รู้ว่ามีอยู่แน่ ๆ")
        }
    }

    /// `—` ที่มีเว้นวรรคขนาบ = ขีดคั่นประโยค · ห้ามมี
    ///
    /// เงื่อนไขนี้ปล่อยผ่าน `"walk_unavailable" = "—"` เองโดยไม่ต้องมีข้อยกเว้นรายคีย์ เพราะ
    /// ขีดที่แปลว่า "ไม่มีข้อมูล" ยืนเดี่ยวไม่มีเว้นวรรคขนาบ · ช่วงตัวเลข `1–14` ก็ผ่าน
    /// เพราะเป็น en dash คนละตัวและไม่มีเว้นวรรคเช่นกัน
    func testNoEmDashSeparatesClausesInEitherLanguage() throws {
        for language in ["en", "th"] {
            for (key, value) in try entries(language) {
                let offending = value.contains(" — ")
                    || value.hasPrefix("— ") || value.hasSuffix(" —")
                    || value.contains("\\n— ") || value.contains(" —\\n")
                XCTAssertFalse(offending, """
                    \(language) · \(key) = "\(value)"
                    มีขีดยาวคั่นประโยคอยู่ — ทั้งแอปเลิกใช้ไปแล้ว (2026-08-21) ให้ใช้จุด
                    หรือขึ้นบรรทัดใหม่แทน โดยดูตามบริบททีละประโยค ไม่ใช่ลบขีดทิ้งเฉย ๆ
                    · `—` เดี่ยว ๆ ที่แปลว่า "ไม่มีข้อมูล" ยังใช้ได้ (เช่น walk_unavailable)
                    """)
            }
        }
    }
}
