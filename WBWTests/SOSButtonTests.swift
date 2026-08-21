import XCTest
@testable import WBW

final class SOSButtonTests: XCTestCase {

    func testReleasingBeforeThreeSecondsSendsNothing() {
        var model = SOSHoldProgress(duration: 3.0)
        model.start(at: 0)
        model.tick(at: 2.9)
        XCTAssertFalse(model.didComplete)
        model.release(at: 2.9)
        XCTAssertFalse(model.didComplete, "ปล่อยก่อนครบต้องไม่ส่ง")
        XCTAssertEqual(model.progress, 0, "วงแหวนต้องหดกลับ")
    }

    func testHoldingTheFullDurationCompletesExactlyOnce() {
        var model = SOSHoldProgress(duration: 3.0)
        model.start(at: 0)
        model.tick(at: 3.0)
        XCTAssertTrue(model.didComplete)
        model.tick(at: 4.0)
        XCTAssertTrue(model.didComplete)
        XCTAssertEqual(model.completionCount, 1, "กดค้างต่อไม่ควรส่งซ้ำ")
    }

    func testProgressIsLinearAcrossTheHold() {
        var model = SOSHoldProgress(duration: 3.0)
        model.start(at: 10)
        model.tick(at: 11.5)
        XCTAssertEqual(model.progress, 0.5, accuracy: 0.01)
    }

    func testProgressNeverExceedsOne() {
        var model = SOSHoldProgress(duration: 3.0)
        model.start(at: 0)
        model.tick(at: 99)
        XCTAssertEqual(model.progress, 1.0, accuracy: 0.001)
    }

    /// SOSStore.raise() เองไม่มีการ์ดกันเรียกซ้ำ (พบจากรีวิว Task 12 — ตั้งใจปล่อยให้ชั้น UI กันแทน)
    /// SOSButton จึงต้องอ่านค่านี้ก่อนเรียก raise() ทุกครั้ง: มีเคสเปิดอยู่แล้ว (queued/received/onTheWay)
    /// ต้องกันไว้ ปิดไปแล้ว (closed) หรือไม่มีเคสเลย (nil) ต้องกดใหม่ได้เสมอ — เทสนี้ตรึงตารางค่านั้นไว้
    /// เป็นหน่วยที่เทสได้จริงแยกจากท่าทางกด ตามเจตนาเดียวกับ SOSHoldProgress ด้านบน
    func testOnlyQueuedReceivedOnTheWayCountAsAnOpenCase() {
        XCTAssertTrue(SOSStatus.queued.isActive)
        XCTAssertTrue(SOSStatus.received.isActive)
        XCTAssertTrue(SOSStatus.onTheWay.isActive)
        XCTAssertFalse(SOSStatus.closed(reason: nil).isActive, "เคสที่ปิดแล้วต้องกดใหม่ได้")
        XCTAssertFalse(SOSStatus.closed(reason: "canceled_by_user").isActive, "ยกเลิกไปแล้วต้องกดใหม่ได้")
    }
}
