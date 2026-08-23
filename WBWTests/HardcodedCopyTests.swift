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
    private static let screens = ["WBW/LoginView.swift", "WBW/IntroView.swift"]

    /// จอ SOS ทั้งชุด — เขียนบนสาขา `feat/wbw-sos` **ก่อน**โหมดเดโม่จะกลายเป็นทางเข้าของผู้รีวิว
    /// จึงฮาร์ดโค้ดภาษาไทยไว้ 36 จุดโดยไม่มีอะไรจับได้ · ผู้รีวิวที่ใช้เครื่องภาษาอังกฤษกดปุ่ม SOS
    /// ในโหมดเดโม่แล้วเจอจอเต็มจอที่อ่านไม่ออกทั้งใบ
    private static let sosScreens = [
        "WBW/SOS/SOSStatusView.swift",
        "WBW/SOS/StaffSOSView.swift",
        "WBW/SOS/SOSFriendView.swift",
    ]

    /// `Text("...")` โดยเนื้อในไม่มี escape และไม่มี interpolation
    private static let literal = try! NSRegularExpression(pattern: #"Text\("([^"\\()]*)"\)"#)

    /// **อาร์กิวเมนต์แรก**ของตัวรับข้อความทุกตัวที่จอ SOS ใช้ · หยุดที่ `,` ด้วย ไม่ใช่แค่ `)`
    /// เพราะ `Label("คีย์", systemImage: "phone.fill")` มีสตริงตัวที่สองเป็นชื่อ SF Symbol
    /// ซึ่งไม่ใช่คีย์และต้องไม่ถูกตรวจ
    private static let firstArgument = try! NSRegularExpression(
        pattern: #"(?:Text|Button|Label|TextField|confirmationDialog|navigationTitle|alert)\("([^"\\()]*)"\s*[,)]"#)

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

    /// กันไม่ให้ 36 จุดที่เพิ่งยกออกไปไหลกลับเข้ามา · ตรวจกว้างกว่าตัวบนเพราะจอ SOS ใช้
    /// `Button(...)` / `Label(...)` / `TextField(...)` / `confirmationDialog(...)` มากกว่า `Text(...)`
    func testSOSScreensPassEveryStringThroughTheCatalogue() throws {
        for path in Self.sosScreens {
            let url = Self.repoRoot.appendingPathComponent(path)
            let text = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                // คอมเมนต์อธิบายเหตุผลในไฟล์เหล่านี้ยกตัวอย่างโค้ดที่ผิดไว้ด้วย ต้องไม่ถูกนับ
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("///") { continue }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                for m in Self.firstArgument.matches(in: line, range: range) {
                    guard let r = Range(m.range(at: 1), in: line) else { continue }
                    let value = String(line[r])
                    XCTAssertTrue(isKeyShaped(value), """
                        \(path):\(index + 1) มีข้อความ "\(value)" ฮาร์ดโค้ด
                        จอ SOS ต้องผ่านชุดคีย์ทั้งหมด — ผู้รีวิว App Store เข้าทางโหมดเดโม่บนเครื่อง
                        ภาษาอังกฤษ กดปุ่ม SOS แล้วจอเต็มจอนี้เปิดขึ้นมา อ่านไม่ออกทั้งใบ
                        """)
                }
            }
        }
    }
}
