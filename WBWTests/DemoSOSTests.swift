import XCTest
@testable import WBW

/// โหมดเดโม่ต้องไม่แตะเน็ตเลยแม้แต่ครั้งเดียว — **รวมถึงเส้นทาง SOS**
///
/// `APIClient.swift` มี `if DemoMode.active { return DemoData... }` อยู่ 18 จุด แต่
/// `APIClient+SOS.swift` ที่ merge เข้ามาจากสาขา `feat/wbw-sos` ไม่มีเลยสักจุด — ไฟล์นั้นเขียน
/// ก่อนโหมดเดโม่จะกลายเป็นทางเข้าหลักของผู้รีวิว App Store
///
/// อาการจริงที่เจอบนซิม (2026-08-21): เปิดโหมดเดโม่แล้ว `SOSStore` poll `/me/sos/active`
/// ด้วย token ปลอมของเดโม่ → backend จริงตอบ 401 → `APIClient.send` แปลงเป็น `.wbwUnauthorized`
/// → `Session.logout(automatic:)` → **ผู้รีวิวถูกเตะออกจากโหมดเดโม่กลับไปหน้าล็อกอิน**
/// ซึ่งคือ Guideline 2.1 เต็ม ๆ เพราะโหมดเดโม่คือทางเดียวที่เขาเข้าแอปได้
final class DemoSOSTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()

    /// ทุกฟังก์ชันที่ยิงเน็ตในไฟล์ SOS ต้องมีทางลัดของโหมดเดโม่ก่อนถึงบรรทัดที่สร้าง `URLRequest`
    func testEverySOSNetworkCallHasADemoShortCircuit() throws {
        let url = Self.repoRoot.appendingPathComponent("WBW/APIClient+SOS.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        // ชื่อฟังก์ชันที่ยิงเน็ตจริง — `postSOSAction`/`getSOSDecoded` เป็นตัวช่วยภายในที่ถูก
        // เรียกต่อจากตัวข้างบน ดักที่ตัวข้างบนพอ
        let networkCalls = ["raiseSOS", "cancelSOS", "activeSOS", "sosCase",
                            "staffSOSFeed", "ackSOS", "resolveSOS"]
        for name in networkCalls {
            guard let range = text.range(of: "func \(name)(") else {
                return XCTFail("ไม่เจอ func \(name) — ชื่อเปลี่ยนไปแล้วหรือเทสนี้เน่า")
            }
            // ตัดเอาเฉพาะ ~40 บรรทัดแรกของฟังก์ชัน พอให้เห็นว่า guard อยู่ก่อนงานจริง
            let body = text[range.lowerBound...].prefix(2000)
            XCTAssertTrue(body.contains("DemoMode.active"), """
                \(name) ไม่มี guard ของโหมดเดโม่ — โหมดเดโม่จะยิง backend จริงด้วย token ปลอม
                แล้วได้ 401 ซึ่งเตะผู้ใช้ออกจากโหมดเดโม่ทั้งเซสชัน
                """)
        }
    }

    // MARK: - พฤติกรรมของเคสจำลอง

    @MainActor
    func testRaiseThenActiveReturnsTheSameCase() {
        DemoSOS.clear()
        defer { DemoSOS.clear() }
        let draft = SOSDraft(clientId: "c1", deviceTime: "2026-08-21T10:00:00Z",
                             forOther: false, lat: 20.045, lng: 99.903,
                             accuracyM: 12, message: "ทดสอบ", serverId: nil, ownerId: "demo")
        let raised = DemoSOS.raise(draft)
        XCTAssertEqual(DemoSOS.active()?.id, raised.id)
        XCTAssertEqual(DemoSOS.active()?.lat, 20.045)
        XCTAssertFalse(raised.resolved)
    }

    /// ยิงซ้ำด้วย clientId เดิมต้องได้เคสเดิม ไม่ใช่เคสใหม่ — เหมือน backend จริงที่ idempotent
    /// ด้วย clientId ไม่งั้น `SOSStore` ที่ retry อยู่จะสร้างเคสใหม่ทุกครั้งที่ยิงซ้ำ
    @MainActor
    func testRaiseIsIdempotentOnClientId() {
        DemoSOS.clear()
        defer { DemoSOS.clear() }
        let draft = SOSDraft(clientId: "same", deviceTime: "2026-08-21T10:00:00Z",
                             forOther: false, lat: nil, lng: nil, accuracyM: nil,
                             message: nil, serverId: nil, ownerId: "demo")
        let first = DemoSOS.raise(draft)
        let second = DemoSOS.raise(draft)
        XCTAssertEqual(first.id, second.id)
    }

    @MainActor
    func testCancelClearsTheCase() {
        DemoSOS.clear()
        defer { DemoSOS.clear() }
        let draft = SOSDraft(clientId: "c2", deviceTime: "2026-08-21T10:00:00Z",
                             forOther: false, lat: nil, lng: nil, accuracyM: nil,
                             message: nil, serverId: nil, ownerId: "demo")
        _ = DemoSOS.raise(draft)
        XCTAssertEqual(DemoSOS.cancel(), .canceled)
        XCTAssertNil(DemoSOS.active())
    }

    /// ไม่มีเคสเปิดอยู่ = ยกเลิกไม่ได้ ต้องไม่ตอบว่า "ยกเลิกแล้ว" ทั้งที่ไม่มีอะไรให้ยกเลิก
    @MainActor
    func testCancelWithNoOpenCaseIsTooLateNotSuccess() {
        DemoSOS.clear()
        XCTAssertEqual(DemoSOS.cancel(), .tooLate)
    }
}
