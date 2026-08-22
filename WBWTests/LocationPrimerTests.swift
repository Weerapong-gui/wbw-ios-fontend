import XCTest
import CoreLocation
@testable import WBW

/// ประตูของจออธิบายก่อนขอสิทธิ์ตำแหน่ง
///
/// ของเดิม `Session.save(_:)` เรียก `SOSLocator.shared.requestPermission()` ตรง ๆ ทันทีที่
/// ล็อกอินสำเร็จ — กล่องของระบบเด้งใส่ผู้ใช้ที่กำลังมองหน้า Home อยู่ โดยไม่มีอะไรบนจอบอกว่า
/// ทำไม · Guideline 5.1.1 เขียนเรื่องนี้ตรง ๆ ว่าต้องขอพร้อมบริบท และโปรเจกต์นี้เพิ่งแก้อาการ
/// หน้าตาเหมือนกันเป๊ะไปรอบหนึ่งแล้ว (แท็บ SU RUN ขอสิทธิ์เองตอน mount)
final class LocationPrimerTests: XCTestCase {

    func testShowsWhenNobodyHasBeenAskedYet() {
        XCTAssertTrue(LocationPrimer.shouldShow(authorization: .notDetermined,
                                                isDemo: false, dismissed: false))
    }

    /// ตอบไปแล้วไม่ว่าทางไหนก็จบ — กล่องของระบบไม่เด้งซ้ำอยู่แล้ว จออธิบายก็ไม่ควรเด้งซ้ำ
    func testDoesNotShowOnceTheSystemPromptHasBeenAnswered() {
        for status in [CLAuthorizationStatus.authorizedWhenInUse, .authorizedAlways,
                       .denied, .restricted] {
            XCTAssertFalse(LocationPrimer.shouldShow(authorization: status,
                                                     isDemo: false, dismissed: false),
                           "สถานะ \(status.rawValue) ไม่ควรเห็นจออธิบายอีก")
        }
    }

    /// โหมดเดโม่ไม่แตะพิกัดจริงเลยสักครั้ง — ผู้รีวิวไม่ควรเจอทั้งจออธิบายและกล่องของระบบ
    func testNeverShowsInDemoMode() {
        XCTAssertFalse(LocationPrimer.shouldShow(authorization: .notDetermined,
                                                 isDemo: true, dismissed: false))
    }

    /// กด "ไว้ทีหลัง" แล้วต้องไม่ตามตื๊อทุกครั้งที่เปิดแอป · สถานะระบบยังเป็น .notDetermined อยู่
    /// จึงกันด้วยธงของเราเองเท่านั้น
    func testDoesNotNagAfterTheUserPutItOff() {
        XCTAssertFalse(LocationPrimer.shouldShow(authorization: .notDetermined,
                                                 isDemo: false, dismissed: true))
    }

    /// ธงต้องแยกตาม backend เหมือน cache ตัวอื่นทั้งแอป (กติกา `cacheNamespace`)
    ///
    /// เขียนรายชื่อ backend ตรง ๆ ไม่ใช่ `allCases` — แบบเดียวกับ `FeedbackOutboxTests` และ
    /// `CheckinProgressStoreTests` ซึ่งเป็นสิ่งที่กัน `case susLan` ไม่ให้ถูกลบทิ้ง
    func testDismissFlagIsNamespacedPerBackend() {
        let all: [Backend] = [.prodNode, .nodeLocal, .susLocal, .susProd, .susLan]
        let keys = Set(all.map { LocationPrimer.dismissKey(for: $0) })
        XCTAssertEqual(keys.count, all.count, "คีย์ซ้ำกันระหว่าง backend")
    }
}
