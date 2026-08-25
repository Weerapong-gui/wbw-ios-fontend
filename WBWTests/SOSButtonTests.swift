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

    // MARK: - กดครบแล้วไปไหนต่อ (กวาดซอร์ส)

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func buttonSource() throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent("WBW/SOS/SOSButton.swift"),
                   encoding: .utf8)
    }

    /// **กดค้างครบ 3 วิแล้วต้องอยู่หน้าบัตรต่อ ไม่ใช่เด้งจอสถานะมาบัง**
    ///
    /// บัตรผู้เข้าร่วมคือจอที่ออกแบบมาให้ยื่นให้คนอื่นดูอยู่แล้ว (QR · กรุ๊ปเลือด · เบอร์ญาติ
    /// อยู่บนใบเดียวกัน) · ของเดิมจอสถานะเต็มจอเด้งมาบังทันทีที่กดครบ คนที่เจ็บจึงต้องกด
    /// "ย่อลง" ก่อนถึงจะยื่นบัตรให้คนช่วยดูได้ · สิ่งที่บอกว่าส่งไปแล้วคือ haptic หนัก
    /// ขอบจอที่เรืองแดง (ดู `SOSEmergencyBackdrop`) และตัวปุ่มที่เปลี่ยนเป็น `sos_pass_active`
    func testCompletingTheHoldDoesNotCoverThePassWithTheStatusScreen() throws {
        let source = try buttonSource()
        let fireBranch = source.components(separatedBy: "UIImpactFeedbackGenerator(style: .heavy)")
            .dropFirst().first ?? ""
        let untilRaise = fireBranch.components(separatedBy: "store.raise").first ?? fireBranch
        XCTAssertFalse(untilRaise.contains("showStatus = true"),
                       "กดครบแล้วยังเด้งจอสถานะมาบังบัตรอยู่")
    }

    /// **แต่ทางกลับเข้าจอสถานะห้ามหาย** — เคสที่เปิดอยู่แล้วแตะเดียวต้องพาเข้าไปได้
    /// นั่นคือที่เดียวที่กดยกเลิก พิมพ์บอกอาการ และเห็นชื่อเจ้าหน้าที่ที่รับเรื่องได้
    /// ถอดผิดสาขาแล้วผู้ใช้จะยกเลิกเคสไม่ได้เลย ซึ่งแพงกว่าบั๊กหน้าตามาก
    func testTappingAnOpenCaseStillOpensTheStatusScreen() throws {
        let source = try buttonSource()
        let opens = source.components(separatedBy: "showStatus = true").count - 1
        XCTAssertEqual(opens, 2,
                       "ต้องเหลือทางเปิดจอสถานะเฉพาะสองสาขาของ 'เคสเปิดอยู่แล้ว' เท่านั้น")
        XCTAssertTrue(source.contains("guard !caseIsActive else"),
                      "การ์ดกันเคสซ้อนหาย — สาขาที่พากลับจอสถานะอยู่ในนั้น")
    }
}
