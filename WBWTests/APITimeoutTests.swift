import XCTest
@testable import WBW

/// เพดานเวลารอของทุกคำขอที่ไม่ได้ตั้งเอง
///
/// `APIClient.send` ใช้ `URLSession.shared` ตรง ๆ ซึ่งค่าปริยายคือ **60 วินาที** ต่อคำขอ ·
/// มีแค่ SOS / แชท / Open-Meteo ที่ตั้ง `timeoutInterval` ของตัวเอง (เพราะสามตัวนั้นเป็น
/// long-poll ที่ต้องรอนานกว่าปกติจริง ๆ) ที่เหลือทั้งหมด — ล็อกอิน โปรไฟล์ ฐาน ความคืบหน้า
/// ประกาศ กลุ่ม ความเห็น — ตกอยู่ที่ 60
///
/// อาการจริงตอนเน็ตหลุด: กด "เข้าสู่ระบบ" แล้วเห็นตัวหมุนนิ่ง ๆ **หนึ่งนาที** ก่อนจะขึ้นข้อความ
/// error ซึ่งอ่านเหมือนแอปค้าง ไม่ใช่เหมือนแอปกำลังรอ
final class APITimeoutTests: XCTestCase {

    /// long-poll ที่ตั้งเวลาเองต้องยังทับค่านี้ได้ ไม่ใช่ถูกตัดที่เพดานกลาง
    func testLongPollRequestsKeepTheirOwnLongerTimeout() {
        var req = URLRequest(url: URL(string: "https://example.invalid")!)
        req.timeoutInterval = 45
        XCTAssertEqual(APIClient.timeout(for: req), 45)
    }

    /// คำขอธรรมดาที่ไม่ตั้งอะไรเลยต้องได้เพดานกลาง ไม่ใช่ 60 ของระบบ
    func testOrdinaryRequestsGetTheSharedCeiling() {
        let req = URLRequest(url: URL(string: "https://example.invalid")!)
        XCTAssertEqual(APIClient.timeout(for: req), APIClient.defaultTimeout)
        XCTAssertLessThanOrEqual(APIClient.defaultTimeout, 20,
                                 "เพดานกลางยาวเกินกว่าที่คนจะรอโดยไม่คิดว่าแอปค้าง")
    }

    /// **กับดักของวิธีนี้**: คำขอที่ตั้งใจตั้ง 60 พอดีจะถูกอ่านว่า "ไม่ได้ตั้ง" แล้วโดนหั่นเหลือ 15
    ///
    /// ตอนเขียนไม่มีใครตั้ง 60 (long-poll ใช้ `wait + 10` โดย `wait` = 25 → 35 และ SOS raise = 20)
    /// เทสนี้กันไม่ให้มีคนเพิ่มเข้ามาแล้วโดนหั่นเงียบ ๆ — long-poll ที่ถูกตัดที่ 15 จะดูเหมือน
    /// "เน็ตหลุด" ทุก 15 วินาทีทั้งที่เซิร์ฟเวอร์ทำงานปกติ
    func testNothingInTheAppSetsExactlySixtySeconds() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let files = try FileManager.default
            .subpathsOfDirectory(atPath: root.appendingPathComponent("WBW").path)
            .filter { $0.hasSuffix(".swift") }
        for file in files {
            let text = try String(
                contentsOf: root.appendingPathComponent("WBW/\(file)"), encoding: .utf8)
            XCTAssertFalse(text.contains("timeoutInterval = 60"), """
                WBW/\(file) ตั้ง timeoutInterval = 60 ซึ่ง APIClient.timeout(for:) อ่านว่า "ไม่ได้ตั้ง"
                แล้วหั่นเหลือ \(APIClient.defaultTimeout) — ใช้ 59 หรือ 61 แทนถ้าตั้งใจจริง
                """)
        }
    }

    /// ค่าปริยาย 60 ของ `URLRequest` ต้องถูกมองว่า "ไม่ได้ตั้ง" ไม่ใช่ "ตั้งไว้ที่ 60"
    func testTheSystemDefaultCountsAsUnsetRatherThanAChoice() {
        var req = URLRequest(url: URL(string: "https://example.invalid")!)
        req.timeoutInterval = 60
        XCTAssertEqual(APIClient.timeout(for: req), APIClient.defaultTimeout)
    }
}
