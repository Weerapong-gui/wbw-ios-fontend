import XCTest
import CoreLocation
@testable import WBW

/// ประตูของจออธิบายก่อนขอสิทธิ์ตำแหน่ง
///
/// ของเดิม `Session.save(_:)` เรียก `SOSLocator.shared.requestPermission()` ตรง ๆ ทันทีที่
/// ล็อกอินสำเร็จ — กล่องของระบบเด้งใส่ผู้ใช้ที่กำลังมองหน้า Home อยู่ โดยไม่มีอะไรบนจอบอกว่า
/// ทำไม · Guideline 5.1.1 เขียนเรื่องนี้ตรง ๆ ว่าต้องขอพร้อมบริบท และโปรเจกต์นี้เพิ่งแก้อาการ
/// หน้าตาเหมือนกันเป๊ะไปรอบหนึ่งแล้ว (แท็บ SU RUN ขอสิทธิ์เองตอน mount)
///
/// **ธงเปลี่ยนความหมายเมื่อ 2026-08-25** จาก "กดไว้ทีหลังไปแล้ว" เป็น "พาไปถึงกล่องของระบบ
/// ไปแล้ว" — ปุ่ม "ไว้ทีหลัง" ถูกถอดทิ้งตามใบตีกลับ 1.0 (12) (ดู `PermissionCopyTests`)
final class LocationPrimerTests: XCTestCase {

    func testShowsWhenNobodyHasBeenAskedYet() {
        XCTAssertTrue(LocationPrimer.shouldShow(authorization: .notDetermined,
                                                isDemo: false, asked: false))
    }

    /// ตอบไปแล้วไม่ว่าทางไหนก็จบ — กล่องของระบบไม่เด้งซ้ำอยู่แล้ว จออธิบายก็ไม่ควรเด้งซ้ำ
    func testDoesNotShowOnceTheSystemPromptHasBeenAnswered() {
        for status in [CLAuthorizationStatus.authorizedWhenInUse, .authorizedAlways,
                       .denied, .restricted] {
            XCTAssertFalse(LocationPrimer.shouldShow(authorization: status,
                                                     isDemo: false, asked: false),
                           "สถานะ \(status.rawValue) ไม่ควรเห็นจออธิบายอีก")
        }
    }

    /// โหมดเดโม่ไม่แตะพิกัดจริงเลยสักครั้ง — ผู้รีวิวไม่ควรเจอทั้งจออธิบายและกล่องของระบบ
    func testNeverShowsInDemoMode() {
        XCTAssertFalse(LocationPrimer.shouldShow(authorization: .notDetermined,
                                                 isDemo: true, asked: false))
    }

    /// **เคสเดียวที่ทำให้สถานะยังเป็น `.notDetermined` ทั้งที่พาไปถึงกล่องของระบบแล้ว:**
    /// ปิด Location Services ทั้งเครื่อง — `requestPermission()` ได้แค่กล่องชวนไปเปิดใน
    /// Settings สถานะไม่ขยับ · ไม่มีธงนี้จออธิบายที่ปัดทิ้งไม่ได้แล้วจะขึ้นทุกครั้งที่เปิดแอป
    func testDoesNotNagAfterTheUserWasAlreadyTakenToTheSystemPrompt() {
        XCTAssertFalse(LocationPrimer.shouldShow(authorization: .notDetermined,
                                                 isDemo: false, asked: true))
    }

    /// ธงต้องแยกตาม backend เหมือน cache ตัวอื่นทั้งแอป (กติกา `cacheNamespace`)
    ///
    /// เขียนรายชื่อ backend ตรง ๆ ไม่ใช่ `allCases` — แบบเดียวกับ `FeedbackOutboxTests` และ
    /// `CheckinProgressStoreTests` ซึ่งเป็นสิ่งที่กัน `case susLan` ไม่ให้ถูกลบทิ้ง
    func testAskedFlagIsNamespacedPerBackend() {
        let all: [Backend] = [.prodNode, .nodeLocal, .susLocal, .susProd, .susLan]
        let keys = Set(all.map { LocationPrimer.askedKey(for: $0) })
        XCTAssertEqual(keys.count, all.count, "คีย์ซ้ำกันระหว่าง backend")
    }

    /// **ต้องเป็นคีย์คนละใบกับธง "กดไว้ทีหลัง" ของเดิม** — คนที่เคยกด "ไว้ทีหลัง" ใน 1.0 (12)
    /// มีธงเก่าค้างเป็น true อยู่ ใช้ชื่อเดิมต่อแปลว่าคนกลุ่มนั้นไม่มีวันถูกถามอีกเลย
    /// ทั้งที่ยังไม่เคยเห็นกล่องของระบบสักครั้ง ซึ่งตรงข้ามกับสิ่งที่ใบตีกลับสั่งไว้
    func testAskedFlagDoesNotInheritTheOldPutItOffFlag() {
        for backend: Backend in [.prodNode, .nodeLocal, .susLocal, .susProd, .susLan] {
            XCTAssertFalse(LocationPrimer.askedKey(for: backend).contains("Dismissed"),
                           "ยังใช้คีย์เดิมของปุ่ม 'ไว้ทีหลัง' อยู่")
        }
    }
}
