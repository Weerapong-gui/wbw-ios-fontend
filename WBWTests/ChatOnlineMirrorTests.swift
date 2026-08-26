import XCTest
@testable import WBW

/// แบนเนอร์ "ออฟไลน์อยู่ ข้อความจะส่งเมื่อกลับมามีสัญญาณ" ต้องขึ้น/หายเองจริง
///
/// เดิมจอแชทอ่าน `store.connectivity.online` ตรง ๆ · `Connectivity` เป็น `ObservableObject`
/// **คนละตัว** กับ `ChatSession` และ `@ObservedObject var store` ไม่ observe nested object ให้
/// แบนเนอร์เลยขยับเฉพาะตอนมีอย่างอื่นบังเอิญมา invalidate body (เช่น sync ได้ข้อความใหม่)
/// เน็ตหลุดตอนไม่มีข้อความไหลเข้าเลย = ไม่ขึ้นสักที คนพิมพ์ไปเรื่อยโดยไม่รู้ว่ากำลังเข้าคิว
@MainActor
final class ChatOnlineMirrorTests: XCTestCase {

    // ปิด NWPathMonitor จริงตลอดคลาสนี้ — เทสยิง apply(online:) เอง monitor จริงที่วิ่งอยู่
    // เบื้องหลังเขียนค่าทับกลางเทสได้ (path เครื่องเปลี่ยนจริงตอนรัน) ทำให้ assertion แกว่ง
    override func setUp() {
        super.setUp()
        Connectivity.monitoringDisabledForTests = true
    }

    override func tearDown() {
        Connectivity.monitoringDisabledForTests = false
        super.tearDown()
    }

    func testSessionMirrorsConnectivityBothDirections() {
        let s = ChatSession()
        XCTAssertTrue(s.online, "เริ่มต้นต้องถือว่ามีเน็ต ไม่ใช่ขึ้นแบนเนอร์ค้างตอนเปิดแอป")

        s.connectivity.apply(online: false)
        XCTAssertFalse(s.online)

        s.connectivity.apply(online: true)
        XCTAssertTrue(s.online)
    }

    /// `apply` เป็นประตูเดียวที่เขียน `online` แล้ว — onReconnect ต้องยังยิงเฉพาะขา offline→online
    /// เหมือนเดิม ไม่ใช่ยิงทุกครั้งที่มีค่าเข้ามา (NWPathMonitor ยิงค่าเดิมซ้ำได้)
    func testReconnectFiresOnlyOnOfflineToOnlineEdge() {
        let net = Connectivity()
        var fired = 0
        net.onReconnect = { fired += 1 }

        net.apply(online: true)    // ค่าเดิม — ไม่ใช่ขอบ
        XCTAssertEqual(fired, 0)

        net.apply(online: false)
        XCTAssertEqual(fired, 0)

        net.apply(online: true)    // ขอบจริง
        XCTAssertEqual(fired, 1)

        net.apply(online: true)    // ซ้ำ — ห้ามยิงอีก
        XCTAssertEqual(fired, 1)
    }
}
