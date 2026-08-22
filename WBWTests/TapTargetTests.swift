import XCTest

/// กวาดซอร์สหาปุ่มไอคอนล้วนที่ยังไม่มีพื้นที่รับนิ้ว 44pt หรือยังไม่มีป้ายให้ VoiceOver
///
/// **ตรวจจากซอร์สเพราะไม่มีทางวัดจากที่อื่นได้** — ขนาดพื้นที่รับนิ้วของ SwiftUI รู้ได้ตอน
/// layout เท่านั้น ซึ่งเทสหน่วยเข้าไม่ถึง และรูปที่ถ่ายออกมาก็บอกได้แค่ขนาดที่ *ตาเห็น*
/// ไม่ใช่ขนาดที่ *นิ้วโดน* — สองอย่างนี้ต่างกันคือหัวใจของกติกาข้อนี้ทั้งข้อ
///
/// `Config.Tap.minTarget` มีมาตั้งแต่ 2026-08 พร้อมคอมเมนต์อ้าง HIG แต่ถูกใช้จริงแค่ 6 จุด
/// จากปุ่มไอคอนทั้งแอป — ค่าคงที่ที่ไม่มีอะไรบังคับให้ใช้ก็เป็นแค่คอมเมนต์
final class TapTargetTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// `Button { ... } label: { Image(systemName: ...) }` แบบไอคอนล้วน — ไม่มี `Text`/`Label` ข้างใน
    ///
    /// ตัดขอบเขตด้วย **ย่อหน้า** ไม่ใช่จำนวนบรรทัดตายตัว: บล็อกของปุ่มหนึ่งตัวคือบรรทัดที่ย่อ
    /// ลึกกว่าบรรทัด `Button` บวกกับ modifier ที่ห้อยท้าย (บรรทัดย่อหน้าเท่ากันที่ขึ้นต้นด้วย `.`)
    /// — หน้าต่างแบบ N บรรทัดตายตัวที่เขียนไว้ตอนแรกกินของเพื่อนบ้านบ้าง ตัดกลางปุ่มบ้าง
    /// แล้วเจอปุ่มจริงแค่ 2 ตัวจากทั้งแอป ซึ่งอันตรายกว่าไม่มีเทสเลย เพราะมันเขียว
    private func iconOnlyButtons(in text: String) -> [(line: Int, block: String, inToolbar: Bool)] {
        let lines = text.components(separatedBy: .newlines)
        func indent(_ s: String) -> Int { s.prefix { $0 == " " }.count }

        var found: [(Int, String, Bool)] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Button ") || trimmed.hasPrefix("Button(")
                    || trimmed.contains("= Button ") || trimmed.contains("return Button ")
            else { i += 1; continue }

            // ขอบเขตของปุ่มหนึ่งตัว = นับปีกกาจนกลับมาสมดุล แล้วค่อยกวาด modifier ที่ห้อยต่อ
            //
            // ลองใช้ย่อหน้าอย่างเดียวมาก่อนแล้วพังสองทาง: หยุดที่ `}` ของตัวเองทำให้
            // `.accessibilityLabel` ที่ห้อยอยู่บรรทัดถัดไปไม่เคยถูกอ่าน ส่วนการไล่ข้าม `}` ไปเรื่อย ๆ
            // ก็กลืนปุ่มเพื่อนบ้านเข้ามาจนบล็อกมี `Text(` ของคนอื่นแล้วถูกข้ามทิ้งทั้งก้อน
            let base = indent(line)
            var depth = 0
            var end = i
            var closed = false
            while end < lines.count {
                let current = lines[end]
                for ch in current {
                    if ch == "{" { depth += 1 }
                    if ch == "}" { depth -= 1 }
                }
                end += 1
                if depth == 0 { closed = true; break }
            }
            guard closed else { i += 1; continue }
            // modifier ที่ห้อยท้าย: ย่อหน้าเท่าตัว `Button` หรือลึกกว่า และขึ้นต้นด้วยจุด
            while end < lines.count {
                let t = lines[end].trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("."), indent(lines[end]) >= base else { break }
                end += 1
            }

            let start = i
            let block = lines[start..<end].joined(separator: "\n")
            i = end

            guard block.contains("Image(systemName:") else { continue }
            // มีตัวหนังสืออยู่ในปุ่มแล้ว = VoiceOver อ่านออกและพื้นที่กดโตตามตัวอักษรอยู่แล้ว
            //
            // **ต้องตัด `accessibilityLabel` ออกก่อนเทียบ** — สตริง "Label(" อยู่ในชื่อ modifier
            // นั้นด้วย ปุ่มที่ติดป้ายถูกต้องแล้วจึงถูกอ่านว่า "มี Label อยู่ในปุ่ม" แล้วข้ามทิ้ง
            // ผลคือเทสเขียวโดยตรวจได้จริงปุ่มเดียวจากทั้งแอป (เจอตอนเทียบจำนวนที่กวาดได้)
            let body = block.replacingOccurrences(of: "accessibilityLabel", with: "")
            guard !body.contains("Text(") && !body.contains("Label(") else { continue }

            // ปุ่มใน `ToolbarItem` ได้พื้นที่กด 44pt มาจากระบบเองอยู่แล้ว — ใส่ `.frame(44)`
            // ทับเข้าไปมีแต่จะดันเลย์เอาต์ของแถบเครื่องมือเพี้ยน · ยังตรวจเรื่องป้าย VoiceOver
            // ตามปกติ เพราะอันนั้นระบบไม่ได้ให้มาด้วย
            let context = lines[max(0, start - 3)..<start].joined(separator: "\n")
            found.append((start + 1, block, context.contains("ToolbarItem")))
        }
        return found
    }

    private func swiftFiles() throws -> [String] {
        try FileManager.default
            .subpathsOfDirectory(atPath: Self.repoRoot.appendingPathComponent("WBW").path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
    }

    func testIconOnlyButtonsDeclareATapTargetAndAVoiceOverLabel() throws {
        for file in try swiftFiles() {
            let text = try String(
                contentsOf: Self.repoRoot.appendingPathComponent("WBW/\(file)"), encoding: .utf8)
            for (line, block, inToolbar) in iconOnlyButtons(in: text) {
                // ปุ่มใน ToolbarItem ได้พื้นที่กด 44pt มาจากระบบเองอยู่แล้ว — ใส่ `.frame(44)`
                // ทับเข้าไปมีแต่จะดันเลย์เอาต์ของแถบเครื่องมือเพี้ยน · ป้าย VoiceOver ยังต้องมี
                // เพราะอันนั้นระบบไม่ได้ให้มาด้วย
                let hasTarget = inToolbar
                    || block.contains("Config.Tap.minTarget")
                    || block.contains("frame(width: 44")
                    || block.contains("frame(height: 44")
                    || block.contains("frame(width: 46")
                XCTAssertTrue(hasTarget, """
                    WBW/\(file):\(line) เป็นปุ่มไอคอนล้วนที่ไม่ได้ประกาศพื้นที่รับนิ้ว
                    ครอบด้วย .frame(minWidth: Config.Tap.minTarget, minHeight: Config.Tap.minTarget)
                    + .contentShape(Rectangle()) ชั้นนอกของ label — ไม่ใช่ทำไอคอนให้ใหญ่ขึ้น
                    """)

                XCTAssertTrue(block.contains("accessibilityLabel"), """
                    WBW/\(file):\(line) เป็นปุ่มไอคอนล้วนที่ไม่มีป้ายให้ VoiceOver
                    ไอคอนอย่างเดียว VoiceOver อ่านได้แค่ชื่อ SF Symbol หรือ "ปุ่ม" เฉย ๆ
                    """)
            }
        }
    }

    /// ค้ำอีกทาง — ถ้าตัวกวาดข้างบนหาไม่เจอสักปุ่ม แปลว่า regex เน่าไปแล้วไม่ใช่แอปสะอาด
    func testTheSweepActuallyFindsIconOnlyButtons() throws {
        var total = 0
        for file in try swiftFiles() {
            let text = try String(
                contentsOf: Self.repoRoot.appendingPathComponent("WBW/\(file)"), encoding: .utf8)
            total += iconOnlyButtons(in: text).count
        }
        XCTAssertGreaterThan(total, 5, "ตัวกวาดหาปุ่มไอคอนไม่เจอ — regex เน่าแล้ว")
    }
}
