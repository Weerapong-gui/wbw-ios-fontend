import XCTest

/// ทางอัปโหลดรูปโปรไฟล์ถูกถอดออก — **ห้ามกลับมาโดยไม่มีเพดานขนาด**
///
/// `APIClient.updatePhoto` กับ `ProfileStore.updatePhoto` ไม่มีใครเรียกเลยทั้งแอป (ไม่มี
/// `PhotosPicker` ไม่มี `loadTransferable` ไม่มีปุ่มไหนพาไปถึง) รูปที่แอปแสดงมาจากเซิร์ฟเวอร์
/// ทางเดียว · แต่ตัวฟังก์ชันยังเปิดทาง `PATCH /me` ที่รับสตริง base64 **ไม่จำกัดขนาด** ค้างไว้
///
/// โค้ดที่ไม่มีใครเรียกแต่ยิงเน็ตได้ = พื้นที่โจมตีที่ไม่มีใครเฝ้า และเป็นรอยเดียวกับที่
/// `SURunRemovalTests` เฝ้าอยู่: ของที่ถอดฟีเจอร์ไปแล้วแต่ร่องรอยยังอยู่
///
/// วันไหนจะทำฟีเจอร์เปลี่ยนรูปจริง ให้เอากลับมาพร้อม **เพดานขนาดและการบีบอัดฝั่งเครื่อง**
/// แล้วแก้เทสนี้ให้ตรวจเพดานนั้นแทนที่จะลบเทสทิ้ง — `ProfileAvatar.decode` วิ่งบน main thread
/// รูปใหญ่เกินไปคือ jank บนจอแชทโดยตรง
final class PhotoUploadRemovalTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func swiftSources() throws -> [(path: String, text: String)] {
        let root = Self.repoRoot.appendingPathComponent("WBW")
        return try FileManager.default
            .subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
            .map { ($0, try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8)) }
    }

    /// ตัดบรรทัดคอมเมนต์ทิ้งก่อนตรวจ — คอมเมนต์ที่อธิบายว่า "เคยมีและทำไมถึงถอด" ต้องเขียนได้
    private func code(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    func testNoUpdatePhotoFunctionRemains() throws {
        for (path, text) in try swiftSources() {
            XCTAssertFalse(code(text).contains("updatePhoto"),
                           "\(path) ยังมี updatePhoto — ทางอัปโหลดรูปถูกถอดไปแล้ว")
        }
    }

    /// ตรวจรูปร่างด้วย ไม่ใช่แค่ชื่อฟังก์ชัน — เอากลับมาใต้ชื่ออื่นก็ยังโดนจับ
    ///
    /// ข้าม `Demo/` เพราะที่นั่น `photo_url` เป็น **fixture ขาเข้า** (รูปร่างของสิ่งที่เซิร์ฟเวอร์
    /// ส่งกลับมาในรายชื่อสมาชิก) ไม่ใช่ payload ที่แอปยิงออกไป · แอปยังต้อง *อ่าน* คีย์นี้ได้ตลอด
    /// สิ่งที่ถูกถอดคือทางเขียน ไม่ใช่ทางอ่าน
    func testNoRequestSendsAnUnboundedPhotoPayload() throws {
        for (path, text) in try swiftSources() where !path.hasPrefix("Demo/") {
            XCTAssertFalse(code(text).contains("\"photo_url\""),
                           "\(path) ยังส่ง photo_url ขึ้นเซิร์ฟเวอร์ — ถ้าจะเอากลับมาต้องมีเพดานขนาดก่อน")
        }
    }
}
