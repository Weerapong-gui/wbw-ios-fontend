import XCTest
@testable import WBW

/// **SOS สองชั้น** — ยกมาจาก branch `work` ของ Android (`925895d` + `6a213ee`)
///
/// เหตุผลที่ต้นทางเขียนไว้: ของเดิมเคสถูกส่งให้เจ้าหน้าที่ชุดที่ตัดสินจาก "ฐานที่ใกล้ที่สุด"
/// ตั้งแต่วินาทีที่กด · แต่คนที่รู้ดีที่สุดว่าเกิดอะไรขึ้นจริงคือเจ้าหน้าที่ที่เดินอยู่กับกลุ่มนั้น
/// ซึ่งได้รับแจ้งพร้อมกับคนทั้งงาน — หรือถ้าเดาฐานพลาด ก็ไม่ได้รับแจ้งเลย
///
/// ชั้นแรก: เห็นเฉพาะเจ้าหน้าที่ประจำกลุ่ม + แอดมิน · ชั้นสอง: เจ้าหน้าที่กดสรุปว่าเป็นเรื่องใหญ่
/// แล้วทั้งงานถึงเห็น — **ไม่ใช่การปิดเคส** เคสที่ถูกยกระดับยังเปิดค้างอยู่จนกว่าจะมีคนกดปิด
final class StaffSOSReportTests: XCTestCase {

    // MARK: - ค่าที่ยิงขึ้นเซิร์ฟเวอร์

    func testEveryOutcomeHasTheWireValueTheServerExpects() {
        XCTAssertEqual(SOSOutcome.falseAlarm.wire, "false_alarm")
        XCTAssertEqual(SOSOutcome.minor.wire, "minor")
        XCTAssertEqual(SOSOutcome.major.wire, "major")
        XCTAssertEqual(SOSOutcome.urgent.wire, "urgent")
    }

    /// **สองแบบหลังยกระดับ อีกสองแบบไม่** — และการยกระดับกับการปิดเคสเป็นคนละเรื่อง
    /// เคสที่สรุปว่าใหญ่ต้องยังเปิดอยู่ ไม่งั้นคนที่กำลังเดินไปหาจะไม่เหลืออะไรให้ดู
    func testOnlyTheSeriousOutcomesEscalateToTheWholeEvent() {
        XCTAssertFalse(SOSOutcome.falseAlarm.escalates)
        XCTAssertFalse(SOSOutcome.minor.escalates)
        XCTAssertTrue(SOSOutcome.major.escalates)
        XCTAssertTrue(SOSOutcome.urgent.escalates)
    }

    // MARK: - เคสที่ backend รุ่นเก่ายังไม่ส่งฟิลด์ใหม่มา

    /// **`escalated` ที่หายไปต้องอ่านเป็น "ยังไม่ยกระดับ" ไม่ใช่ decode พัง**
    ///
    /// backend ที่ยังไม่ deploy รุ่นที่มีสองชั้นจะไม่ส่งคีย์นี้เลย · decode ไม่ผ่าน = ลิสต์เคสว่าง
    /// ทั้งจอในวันงาน ซึ่งแย่กว่าการไม่มีป้ายบอกชั้นเป็นไหน ๆ (ทรงเดียวกับ `leave_quota` ที่
    /// `MeDecodeTests` ค้ำไว้)
    func testACaseFromAnOlderBackendStillDecodes() throws {
        let json = #"""
        {"id":7,"for_other":false,"resolved":false,"created_at":"2026-08-25T09:00:00Z",
         "updated_at":"2026-08-25T09:00:00Z","participant_id":"u1","first_name":"ดิน",
         "last_name":"ดิน"}
        """#
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let c = try dec.decode(SOSStaffCase.self, from: Data(json.utf8))
        XCTAssertFalse(c.isEscalated)
        XCTAssertNil(c.severity)
    }

    func testAnEscalatedCaseReadsAsEscalated() throws {
        let json = #"""
        {"id":8,"for_other":false,"resolved":false,"created_at":"2026-08-25T09:00:00Z",
         "updated_at":"2026-08-25T09:00:00Z","participant_id":"u1","first_name":"ดิน",
         "last_name":"ดิน","escalated":true,"severity":"urgent"}
        """#
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let c = try dec.decode(SOSStaffCase.self, from: Data(json.utf8))
        XCTAssertTrue(c.isEscalated)
        XCTAssertEqual(c.severity, "urgent")
    }

    // MARK: - ป้ายบอกว่ายังอยู่ชั้นแรก

    /// ป้าย "ตอนนี้เห็นเฉพาะเจ้าหน้าที่ประจำกลุ่มกับผู้ดูแล" มีไว้บอกเจ้าหน้าที่ที่ถือเคสอยู่ว่า
    /// **ยังไม่มีใครอื่นเห็น** — ขึ้นผิดเวลาแปลว่าเขาจะรอคนที่ไม่มีวันมา
    func testTheStageOneBadgeOnlyShowsWhileTheCaseIsStillPrivateAndOpen() {
        XCTAssertTrue(SOSOutcome.showsStageOneBadge(escalated: false, resolved: false))
        XCTAssertFalse(SOSOutcome.showsStageOneBadge(escalated: true, resolved: false))
        XCTAssertFalse(SOSOutcome.showsStageOneBadge(escalated: false, resolved: true))
        XCTAssertFalse(SOSOutcome.showsStageOneBadge(escalated: true, resolved: true))
    }
}
