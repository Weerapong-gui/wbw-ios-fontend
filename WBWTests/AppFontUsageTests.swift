import XCTest
@testable import WBW

/// **ข้อความที่คนอ่านต้องเป็นฟอนต์ของแอป ไม่ใช่ฟอนต์ระบบ**
///
/// แอปมีฟอนต์เดียวคือ Anuphan (ไม่มีหัว) เรียกผ่าน `Font.wbwText(...)` และโทเคนใน `Typography.swift`
/// — แต่จอที่เขียน `.font(.body)` / `.font(.caption)` เฉย ๆ จะได้ฟอนต์ไทยของ **ระบบ** (มีหัว) แทน
/// ปนกันคนละจอในแอปเดียว เจ้าของงานเห็นจากจอแชทแล้วทักมาเอง (2026-08-26)
///
/// **ทำไมต้องมีเทสนี้:** `TypographyTests` ตรวจแค่ว่าฟอนต์ลงทะเบียนแล้วและชื่อ face ถูก —
/// ไม่มีอะไรตรวจว่า *จอไหนเรียกใช้มันจริง* · `Font.custom` ที่ชื่อผิดก็ตกกลับเป็นฟอนต์ระบบเงียบ ๆ
/// ไม่มี error ทั้งคู่จึงเขียวมาตลอดทั้งที่ครึ่งแอปเป็นฟอนต์ผิด
///
/// **กติกาที่เทสนี้บังคับ:** ห้ามใช้ text style เปล่า (`.font(.body)`, `.font(.caption)` …) ที่ไหนเลย
/// ใน `WBW/` · ข้อความใช้ `wbw*` · SF Symbol ใช้ฟอนต์ระบบได้แต่ต้องเขียนรูป `.font(.system(...))`
/// ให้ชัด — ไม่ใช่เพราะไอคอนต้องการ แต่เพราะรูปนั้นเป็นรูปเดียวที่แยก "ตั้งใจใช้ระบบ" ออกจาก
/// "ลืมเปลี่ยน" ได้ด้วยการ grep
final class AppFontUsageTests: XCTestCase {

    /// text style ของระบบที่ห้ามใช้เปล่า ๆ — ตัวที่ลากฟอนต์ไทยของระบบเข้ามา
    private let bannedStyles = [
        "largeTitle", "title", "title2", "title3", "headline", "subheadline",
        "body", "callout", "footnote", "caption", "caption2",
    ]

    private var appSourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WBWTests/
            .deletingLastPathComponent()   // ราก repo
            .appendingPathComponent("WBW")
    }

    func testNoScreenUsesASystemTextStyle() throws {
        let files = FileManager.default
            .enumerator(at: appSourceRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty, "หาไฟล์ซอร์สของแอปไม่เจอ — เทสนี้จะผ่านด้วยเหตุผลผิด")

        var offenders: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                // คอมเมนต์พูดถึงชื่อพวกนี้ได้ — ที่ห้ามคือการเรียกใช้จริง
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                for style in bannedStyles where line.contains(".font(.\(style))")
                    || line.contains(".font(.\(style).") {
                    offenders.append("\(file.lastPathComponent):\(index + 1)  .\(style)")
                }
            }
        }

        XCTAssertTrue(offenders.isEmpty, """
            ยังมีจุดที่ใช้ฟอนต์ระบบกับข้อความอยู่ \(offenders.count) จุด — ข้อความต้องใช้ `wbw*`
            ส่วนไอคอน SF Symbol ให้เขียน `.font(.system(...))` ให้ชัด:
            \(offenders.joined(separator: "\n"))
            """)
    }
}
