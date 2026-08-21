import XCTest
@testable import WBW

/// จอที่ผู้รีวิว App Store เห็นก่อนอย่างอื่นต้องไม่มีข้อความอังกฤษฮาร์ดโค้ด
///
/// `CFBundleDevelopmentRegion` ของแอปคือ `th` และทุกจออื่นเป็นไทย · จอล็อกอินมี
/// `Text("Hey,\nWelcome back")`, `Text("Sign In")`, `Text("Password")` ฮาร์ดโค้ดอยู่
/// ทั้งที่คีย์ `login_greeting` / `login_action_submit` / `login_field_password`
/// มีครบทั้งสองภาษามาตลอด — คนไทยเปิดแอปมาเจอจอแรกเป็นอังกฤษครึ่งจอ
///
/// **`scripts/check-localization.sh` จับไม่ได้** regex ของมันมองหา `Text("...")` แล้วเอา
/// ข้างในไปเทียบกับชุดคีย์ · `Text("Password")` จึงถูกอ่านเป็น "คีย์ชื่อ Password" ที่หายไป
/// ซึ่งมันรายงานรวมกับคีย์ที่หายจริง ๆ แล้วกลบกันไปเอง · เทสนี้ตรวจคนละอย่าง: **รูปร่าง**
/// ของสิ่งที่ส่งเข้า `Text(` ต้องเป็นคีย์ ไม่ใช่ประโยค
final class HardcodedCopyTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// จอที่อยู่ก่อนการล็อกอิน = จอที่ผู้รีวิวเห็นแน่นอน
    private static let screens = ["WBW/LoginView.swift", "WBW/WelcomeView.swift"]

    /// `Text("...")` โดยเนื้อในไม่มี escape และไม่มี interpolation
    private static let literal = try! NSRegularExpression(pattern: #"Text\("([^"\\()]*)"\)"#)

    /// คีย์ในชุดข้อความเป็น snake_case ตัวเล็กล้วน — อะไรที่ไม่ใช่รูปนี้คือประโยคที่พิมพ์ทิ้งไว้
    private func isKeyShaped(_ s: String) -> Bool {
        !s.isEmpty && s.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression) != nil
    }

    func testPreLoginScreensPassEveryStringThroughTheCatalogue() throws {
        for path in Self.screens {
            let url = Self.repoRoot.appendingPathComponent(path)
            let text = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                for m in Self.literal.matches(in: line, range: range) {
                    guard let r = Range(m.range(at: 1), in: line) else { continue }
                    let value = String(line[r])
                    XCTAssertTrue(isKeyShaped(value), """
                        \(path):\(index + 1) มี Text("\(value)") ฮาร์ดโค้ด
                        จอก่อนล็อกอินต้องผ่านชุดคีย์ทั้งหมด — แอปตั้ง CFBundleDevelopmentRegion = th
                        ผู้ใช้ไทยจะเห็นจอแรกเป็นอังกฤษ และผู้รีวิว App Store เห็นจอนี้ก่อนอย่างอื่น
                        """)
                }
            }
        }
    }
}
