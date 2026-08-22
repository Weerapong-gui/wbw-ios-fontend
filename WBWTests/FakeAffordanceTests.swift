import XCTest

/// จอที่ **ดูเหมือนกดได้แต่กดไม่ได้** — รูปแบบที่ repo นี้โดน App Review ตีกลับมาแล้วจริง
///
/// หน้าล็อกอินเคยมี `Text("Don't have an account? Sign up")` กับ `Text("Forget password?")`
/// วางอยู่เฉย ๆ ไม่มี action · Guideline 2.1 ตีกลับเพราะผู้ตรวจกดทุกอย่างบนจอแล้วไม่มีอะไร
/// เกิดขึ้น (ดูคอมเมนต์ยาวที่ `WBW/LoginView.swift` ซึ่งห้ามใส่กลับ)
///
/// รอบนี้เจอตัวที่สองที่แท็บกิจกรรม: การ์ดอีเวนต์มีแถว "ดูรายละเอียด ›" พร้อม `chevron.right`
/// เต็มความกว้าง สูง 52pt — อ่านเป็นปุ่มทุกประการ แต่ทั้งไฟล์ไม่มี `Button` หรือ
/// `NavigationLink` สักตัว
///
/// **ตรวจแบบต่อไฟล์ ไม่ใช่ต่อบรรทัด** — เจตนาคือจับ "ไฟล์ที่วาดลูกศรพาไปต่อ ทั้งที่ไม่มีอะไร
/// ในไฟล์นั้นกดได้เลย" · ตรวจละเอียดกว่านี้ (หา ancestor ของ chevron แต่ละตัว) ทำไม่ได้จริง
/// เพราะแพทเทิร์นที่ใช้อยู่คือ `NavigationLink { ... } label: { navRow(...) }` ซึ่งตัว chevron
/// อยู่คนละฟังก์ชันกับ `NavigationLink` (ดู `WBW/SettingsView.swift`)
final class FakeAffordanceTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// ลูกศร "พาไปต่อ" ที่ผู้ใช้อ่านเป็นปุ่มเสมอ
    private static let forwardChevrons = ["chevron.right", "chevron.forward"]

    /// อะไรก็ได้ที่ทำให้ของบนจอกดได้จริง
    private static let interactive = ["Button", "NavigationLink", "Link(", "onTapGesture",
                                      "navigationDestination"]

    func testNoScreenDrawsAForwardChevronWithNothingTappableInIt() throws {
        let files = try FileManager.default
            .subpathsOfDirectory(atPath: Self.repoRoot.appendingPathComponent("WBW").path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()

        var checked = 0
        for file in files {
            let text = try String(
                contentsOf: Self.repoRoot.appendingPathComponent("WBW/\(file)"), encoding: .utf8)
            // ตัดคอมเมนต์ออกก่อน — ไฟล์ใน repo นี้เล่าเหตุผลยาวและอ้างชื่อสัญลักษณ์ในคอมเมนต์บ่อย
            let code = text.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")

            guard Self.forwardChevrons.contains(where: code.contains) else { continue }
            checked += 1
            XCTAssertTrue(Self.interactive.contains(where: code.contains), """
                WBW/\(file) วาดลูกศร "พาไปต่อ" ทั้งที่ไม่มีอะไรในไฟล์กดได้เลย
                ผู้ตรวจ App Store กดทุกอย่างบนจอ — แถวที่ดูเหมือนปุ่มแต่ไม่มี action คือ
                Guideline 2.1 ซึ่ง repo นี้โดนมาแล้วรอบหนึ่งที่หน้าล็อกอิน
                ถ้ายังไม่มีปลายทาง ให้ถอดลูกศรออก ไม่ใช่ปล่อยไว้รอทำทีหลัง
                """)
        }
        XCTAssertGreaterThan(checked, 1, "ตัวกวาดหาไฟล์ที่มีลูกศรไม่เจอ — เงื่อนไขเน่าแล้ว")
    }
}
