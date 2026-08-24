import XCTest
import UIKit
@testable import WBW

/// รูปโปรไฟล์ต้อง decode ครั้งเดียวต่อสตริง ไม่ใช่ทุกครั้งที่ view วาดตัวเอง
///
/// `ProfileAvatar.decode` ถูกเรียก **ข้างใน `body`** ซึ่งจอแชท re-render ทุกครั้งที่
/// `store.messages` เปลี่ยน (ทุกข้อความที่เข้ามา ทุกครั้งที่ส่ง ทุกครั้งที่สถานะอ่านขยับ)
/// และทุกเฟรมที่เลื่อนลิสต์ — base64 decode + `UIImage(data:)` ต่อฟองที่มองเห็น บน main thread
/// ทั้งหมด · เฟรมตกช่วงกดส่งทำให้ช่องพิมพ์ "ดูเหมือนไม่เคลียร์" ได้เองแม้ตัวการล้างจะถูกแล้ว
final class ProfileAvatarCacheTests: XCTestCase {
    /// PNG 1×1 โปร่งใส — เล็กสุดที่ `UIImage(data:)` ยังยอมรับ
    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    func testSameDataUrlDecodesOnceAndReusesTheSameImage() {
        let url = "data:image/png;base64,\(Self.onePixelPNG)"
        let first = ProfileAvatar.decode(url)
        let second = ProfileAvatar.decode(url)

        XCTAssertNotNil(first)
        XCTAssertTrue(first === second, "สตริงเดิมต้องได้ UIImage ตัวเดิม ไม่ใช่ decode ใหม่ทุกครั้งที่ body วาด")
    }

    /// base64 ล้วน (ไม่มีหัว data:) ก็ต้องแคชเหมือนกัน — ทั้งสองรูปแบบมาจากเซิร์ฟเวอร์จริง
    func testBareBase64IsCachedToo() {
        let first = ProfileAvatar.decode(Self.onePixelPNG)
        let second = ProfileAvatar.decode(Self.onePixelPNG)

        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
    }

    /// คนละสตริงต้องได้คนละรูป — กันแคชที่ตอบรูปผิดคน ซึ่งบนจอแชทคือ avatar สลับตัวกัน
    func testDifferentStringsDoNotShareAnImage() {
        let a = ProfileAvatar.decode("data:image/png;base64,\(Self.onePixelPNG)")
        let b = ProfileAvatar.decode(Self.onePixelPNG)

        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertFalse(a === b)
    }

    func testEmptyAndGarbageInputStillReturnNil() {
        XCTAssertNil(ProfileAvatar.decode(nil))
        XCTAssertNil(ProfileAvatar.decode(""))
        XCTAssertNil(ProfileAvatar.decode("ไม่ใช่รูป"))
    }
}
