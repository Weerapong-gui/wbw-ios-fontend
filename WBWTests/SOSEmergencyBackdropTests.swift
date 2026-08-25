import XCTest
@testable import WBW

/// พื้นหลังแดงเรืองจากขอบจอของ `SOSStatusView` ระหว่างรอเจ้าหน้าที่
///
/// จอนี้ถูกออกแบบมาให้ **ยื่นให้คนอื่นดู** อยู่แล้ว (การ์ดกรุ๊ปเลือด/เบอร์ญาติ) ขอบจอที่เรืองแดง
/// จึงอ่านออกจากระยะไกลและจากหางตาว่าเครื่องนี้กำลังรอความช่วยเหลืออยู่ ไม่ใช่เปิดค้างไว้เฉย ๆ
///
/// ตรรกะสองข้อที่ต้องคุมไว้เพราะ **มองไม่เห็นจากภาพนิ่ง** และพังเงียบ: เต้นเมื่อไหร่ กับ
/// เคารพ Reduce Motion ไหม
final class SOSEmergencyBackdropTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// เคสยังเปิดอยู่ = ยังต้องส่งสัญญาณ · รวมสถานะ "เจ้าหน้าที่กำลังมา" ด้วยตามที่เจ้าของงานสั่ง
    /// (เต้นต่อจนเคสปิด) — คนที่กำลังเดินมาหาต้องเห็นเครื่องเรืองแดงจากไกลเหมือนเดิม
    func testItPulsesWhileTheCaseIsStillOpen() {
        for status: SOSStatus in [.queued, .received, .onTheWay] {
            XCTAssertTrue(SOSPulse.pulses(status: status), "สถานะ \(status) ยังเปิดอยู่ ต้องเต้นต่อ")
        }
    }

    /// เคสจบแล้วต้องเลิกส่งสัญญาณฉุกเฉินทันที — จอที่ยังเรืองแดงหลังเคสปิดคือการบอกคนรอบตัวว่า
    /// ยังมีเหตุอยู่ทั้งที่จบไปแล้ว
    func testItStopsPulsingOnceTheCaseIsClosed() {
        XCTAssertFalse(SOSPulse.pulses(status: .closed(reason: "canceled_by_user")))
        XCTAssertFalse(SOSPulse.pulses(status: .closed(reason: nil)))
        XCTAssertFalse(SOSPulse.pulses(status: nil))
    }

    /// ช่วงความทึบต้องเป็นช่วงจริง และต่ำสุดต้องยัง **เห็นเป็นแดง** ไม่ใช่จางหายไปเป็นจอดำ
    /// ระหว่างจังหวะหนึ่งของการเต้น — คนที่เหลือบมองตอนจังหวะต่ำสุดต้องยังอ่านออกว่าเกิดอะไรขึ้น
    func testThePulseNeverFadesAllTheWayToBlack() {
        let range = SOSPulse.opacityRange(reduceMotion: false)
        XCTAssertGreaterThan(range.lowerBound, 0.3)
        XCTAssertLessThan(range.lowerBound, range.upperBound)
        XCTAssertLessThanOrEqual(range.upperBound, 1.0)
    }

    /// **เปิด Reduce Motion แล้วต้องนิ่งสนิท** — ช่วงจุดเดียว ไม่ใช่ช่วงที่แคบลง
    ///
    /// แอปนี้เคารพ Reduce Motion อยู่แล้วทุกที่ (`IntroView`, `Map3DScreen`, `GrowingTree`)
    /// และจอฉุกเฉินไม่ใช่ที่ที่จะเริ่มยกเว้น — คนที่เปิดตัวเลือกนี้มักเปิดเพราะการเคลื่อนไหว
    /// ทำให้เวียนหัวหรือกระตุ้นอาการ ซึ่งเป็นสิ่งสุดท้ายที่ควรเจอตอนกำลังเจ็บอยู่
    func testReduceMotionKeepsTheRedButStopsTheMotion() {
        let range = SOSPulse.opacityRange(reduceMotion: true)
        XCTAssertEqual(range.lowerBound, range.upperBound, "ต้องนิ่ง ไม่ใช่เต้นช้าลง")
        XCTAssertGreaterThan(range.lowerBound, 0, "นิ่งแล้วต้องยังเห็นแดงอยู่")
    }

    /// จังหวะต้องช้าพอที่จะไม่ใช่ไฟกะพริบ — เกณฑ์ที่ยอมรับกันคือต่ำกว่า 3 ครั้ง/วินาที
    /// จอฉุกเฉินต้องไม่กลายเป็นตัวกระตุ้นอาการชักของใครกลางเหตุการณ์จริง
    func testTheRhythmIsSlowEnoughNotToBeAFlash() {
        XCTAssertGreaterThanOrEqual(SOSPulse.cycleSeconds, 1.0)
    }

    /// กวาดซอร์สแบบเดียวกับ `PermissionCopyTests` — จอต้องอ่านค่า Reduce Motion จริง
    /// ถอด `@Environment(\.accessibilityReduceMotion)` ออกแล้วไม่มีอะไรฟ้องเลย จนกว่าจะมีคน
    /// ที่เปิดตัวเลือกนี้ไว้มาเจอจอเต้นระหว่างเหตุฉุกเฉิน
    func testTheScreenActuallyReadsTheReduceMotionSetting() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("WBW/SOS/SOSStatusView.swift"),
            encoding: .utf8)
        XCTAssertTrue(source.contains("accessibilityReduceMotion"),
                      "จอสถานะ SOS ไม่ได้อ่านค่า Reduce Motion — พื้นหลังจะเต้นใส่คนที่ปิดไว้")
        XCTAssertTrue(source.contains("SOSEmergencyBackdrop"),
                      "จอสถานะ SOS ยังไม่ได้ต่อพื้นหลังฉุกเฉินเข้าไป")
    }

    /// **จอบัตรคือจอที่ต้องเรืองแดง** — เจ้าของงานชี้จอนี้มาโดยตรง เพราะเป็นจอที่ยื่นให้คนอื่นดู
    /// ระหว่างรอความช่วยเหลือ (QR · กรุ๊ปเลือด · เบอร์ญาติ อยู่บนบัตรใบเดียวกัน)
    func testThePassScreenGlowsWhileACaseIsOpen() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("WBW/ParticipantPassView.swift"),
            encoding: .utf8)
        XCTAssertTrue(source.contains("SOSEmergencyBackdrop"),
                      "จอบัตรยังไม่มีขอบจอเรืองแดงตอนเคสเปิดอยู่")
        XCTAssertTrue(source.contains("accessibilityReduceMotion"),
                      "จอบัตรไม่ได้อ่านค่า Reduce Motion — พื้นหลังจะเต้นใส่คนที่ปิดไว้")
    }

    /// **ความทึบต้องคิดจากนาฬิกา ไม่ใช่จาก state ที่สลับครั้งเดียว** — ของเดิมใช้ `@State`
    /// สลับตอน `onAppear` แล้วปล่อย `.repeatForever` วิ่ง ซึ่งพังเงียบบนจอบัตร: วิวถูกสร้าง
    /// ตั้งแต่ยังไม่มีเคส พอเคสเปิดทีหลังตัวแปรไม่ได้เปลี่ยนอีก การเต้นจึงไม่เคยเริ่มเลย
    /// (จับได้จากสกรีนช็อตสองใบห่างกัน 1 วิ ที่ได้สีมุมจอเท่ากันเป๊ะ)
    func testTheOpacityMovesOverTimeWithinTheRange() {
        let range = SOSPulse.opacityRange(reduceMotion: false)
        let quarter = SOSPulse.cycleSeconds / 4
        let a = SOSPulse.opacity(at: 0, reduceMotion: false)
        let b = SOSPulse.opacity(at: quarter, reduceMotion: false)
        XCTAssertNotEqual(a, b, accuracy: 0.0001, "เวลาเดินแล้วความทึบต้องเปลี่ยน")
        for t in stride(from: 0.0, through: SOSPulse.cycleSeconds * 2, by: 0.05) {
            let v = SOSPulse.opacity(at: t, reduceMotion: false)
            XCTAssertGreaterThanOrEqual(v, range.lowerBound - 0.0001)
            XCTAssertLessThanOrEqual(v, range.upperBound + 0.0001)
        }
    }

    /// เปิด Reduce Motion แล้วเวลาเดินไปเท่าไหร่ค่าก็ต้องเท่าเดิม
    func testTheOpacityIsFrozenWhenMotionIsReduced() {
        let fixed = SOSPulse.opacityRange(reduceMotion: true).lowerBound
        for t in [0.0, 0.4, 1.0, 7.3] {
            XCTAssertEqual(SOSPulse.opacity(at: t, reduceMotion: true), fixed, accuracy: 0.0001)
        }
    }
}
