import XCTest
@testable import WBW

/// ตัวตัดสินว่า "สแกนที่เพิ่งอ่านได้ ควรถูกรับไหม" — แยกออกจาก View เพื่อให้เทสได้โดยไม่ต้องมีกล้อง
///
/// **ซิมูเลเตอร์ไม่มีกล้อง** (`AVCaptureDevice.default` คืน nil) จอสแกนจึงเดินเข้าทาง
/// "เครื่องนี้ไม่มีกล้อง" เสมอ ไม่มีทางทดสอบเส้นทางการสแกนจริงบนซิมได้เลย · ตรรกะทั้งหมด
/// จึงต้องอยู่นอก View ไม่งั้นมันจะไม่มีวันถูกทดสอบ (ทรงเดียวกับ `CameraPermission.from`
/// ที่ `StaffScanPermissionTests` แยกไว้ด้วยเหตุผลเดียวกัน)
///
/// `evaluate` คืน **ทั้งคำตัดสินและ state ใหม่** ไม่ใช่คำตัดสินอย่างเดียว — เพราะตัวกันสแกนซ้ำ
/// ที่ถูกต้องต้องขยับเวลาทุกครั้งที่ *เห็น* โค้ด ไม่ใช่เฉพาะตอนรับ (ดู
/// `testHoldingTheSameCodeInFrameNeverFiresASecondRequest`) ถ้าคืนแต่คำตัดสิน ตรรกะครึ่งหนึ่ง
/// จะไปกองอยู่ใน View แล้วเทสไม่ถึงอีก
final class StaffScanGateTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func evaluate(_ code: String, busy: Bool = false, resultOpen: Bool = false,
                          hasBase: Bool = true, lastCode: String? = nil, lastAt: Date? = nil,
                          at: TimeInterval = 0) -> ScanGate.Outcome {
        ScanGate.evaluate(code: code, busy: busy, resultOpen: resultOpen, hasBase: hasBase,
                          lastCode: lastCode, lastAt: lastAt, now: t0.addingTimeInterval(at))
    }

    // MARK: - ยังไม่ได้เลือกฐาน

    /// **เดิมสแกนแล้วไม่มีอะไรเกิดขึ้นเลย** — `checkin` เจอ `selected == nil` แล้ว `return`
    /// เงียบ ๆ ไม่ตั้ง error · เกิดจริงเมื่อ `load()` พังตอนเปิดจอ (เน็ตหลุดบนดอย) และเกิดเสมอ
    /// ในโหมดเดโม่ที่ `staffCheckpoints` เป็นลิสต์ว่าง · เจ้าหน้าที่ส่องกล้องแล้วไม่มีอะไรขึ้น
    /// สรุปว่ากล้องอ่านไม่ออก ทั้งที่ปัญหาคือยังไม่มีรายชื่อฐาน
    func testNoBaseSelectedTellsTheStaffInsteadOfDoingNothing() {
        XCTAssertEqual(evaluate("abc", hasBase: false).decision, .needsBase)
    }

    /// ไม่มีฐานต้องชนะทุกเหตุผลที่จะเงียบ — เรียงผิดแล้วเจ้าหน้าที่จะไม่มีวันเห็นข้อความ
    func testTheMissingBaseMessageOutranksEveryOtherReasonToIgnore() {
        XCTAssertEqual(
            evaluate("abc", busy: true, resultOpen: true, hasBase: false,
                     lastCode: "abc", lastAt: t0).decision,
            .needsBase)
    }

    // MARK: - การ์ดผลเปิดค้างอยู่

    /// **บั๊กจริงที่ฐานที่มีคนต่อคิว**: การ์ดผลเป็น overlay กล้องข้างล่างยังวิ่งและยังรับสแกน
    /// QR ของคนถัดไปจึงทับการ์ดของคนปัจจุบันก่อนเจ้าหน้าที่อ่านจบ — รวมถึงป้ายแดง
    /// "มีข้อมูลการแพทย์ โปรดระวัง" ซึ่งเป็นบรรทัดที่แพงที่สุดบนการ์ด
    func testAResultOnScreenBlocksTheNextPersonFromOverwritingIt() {
        XCTAssertEqual(evaluate("next-person", resultOpen: true).decision, .ignore,
                       "ต้องเงียบ ไม่ใช่ขึ้น error — นี่ไม่ใช่ความผิดของใคร")
    }

    // MARK: - กันสแกนซ้ำ

    func testTheSameCodeTwiceInARowIsIgnored() {
        XCTAssertEqual(evaluate("same", lastCode: "same", lastAt: t0, at: 0.5).decision, .ignore)
    }

    /// **หัวใจของการแก้ S3** — ถือกล้องค้างที่ QR เดิมคือท่ายืนปกติของเจ้าหน้าที่ที่ฐาน
    /// ของเดิมปลดล็อกด้วย timer 2 วิที่นับจาก *ตอนเริ่มสแกน* กล้องจึงยิง `POST /staff/checkin`
    /// ของคนเดิมซ้ำทุก ~2 วิไม่รู้จบ ตราบใดที่โค้ดยังอยู่ในเฟรม
    ///
    /// ตัวกันที่ถูกต้องต้องขยับเวลาทุกครั้งที่ **เห็น** โค้ด ไม่ใช่เฉพาะตอนรับ — หน้าต่างเวลาจึง
    /// เริ่มนับก็ต่อเมื่อโค้ดหายออกจากเฟรมไปแล้วจริง ๆ
    func testHoldingTheSameCodeInFrameNeverFiresASecondRequest() {
        var lastCode: String? = nil
        var lastAt: Date? = nil
        var accepted = 0
        // กล้องส่ง metadata ถี่ ๆ ตลอด 10 วินาทีที่โค้ดยังอยู่ในเฟรม
        for tick in stride(from: 0.0, through: 10.0, by: 0.2) {
            let out = evaluate("held", lastCode: lastCode, lastAt: lastAt, at: tick)
            if out.decision == .accept { accepted += 1 }
            lastCode = out.lastCode
            lastAt = out.lastAt
        }
        XCTAssertEqual(accepted, 1, "ถือค้างไว้ต้องยิงครั้งเดียว ไม่ใช่ยิงซ้ำทุกครั้งที่หน้าต่างหมด")
    }

    /// โค้ดเดิมกลับมาได้หลังหายออกจากเฟรมนานพอ — คนเดิมเช็คอินฐานถัดไปทีหลังต้องไม่ถูกกันตลอดกาล
    func testTheSameCodeWorksAgainAfterItHasLeftTheFrame() {
        let out = evaluate("same", lastCode: "same", lastAt: t0,
                           at: ScanGate.repeatWindow + 0.01)
        XCTAssertEqual(out.decision, .accept)
    }

    /// **บั๊กเดิม**: timer ล้าง `lastScan` แบบไม่มีเงื่อนไข — สแกน A แล้วสแกน B ภายใน 2 วิ
    /// timer ของ A จะล้างตัวกันของ B ทิ้ง B จึงถูกสแกนซ้ำได้ทันที
    func testADifferentCodeIsNeverBlockedByThePreviousOne() {
        XCTAssertEqual(evaluate("person-B", lastCode: "person-A", lastAt: t0, at: 0.2).decision,
                       .accept)
    }

    /// โค้ดที่ถูกเมิน (การ์ดเปิดอยู่) ต้องไม่ไปยึดที่ของโค้ดก่อนหน้า — ยึดแล้วพอการ์ดปิด
    /// คนที่ยังไม่ได้เช็คอินจริงจะถูกกันไว้อีก 2 วิโดยไม่มีเหตุผล
    func testAnIgnoredCodeDoesNotBecomeTheOneWeAreGuardingAgainst() {
        let out = evaluate("person-B", resultOpen: true, lastCode: "person-A", lastAt: t0, at: 0.2)
        XCTAssertEqual(out.lastCode, "person-A")
    }

    // MARK: - กำลังยิง request อยู่

    func testNothingIsAcceptedWhileARequestIsInFlight() {
        XCTAssertEqual(evaluate("abc", busy: true).decision, .ignore)
    }

    // MARK: - ทางปกติ

    func testAFreshCodeWithABaseSelectedIsAccepted() {
        let out = evaluate("fresh")
        XCTAssertEqual(out.decision, .accept)
        XCTAssertEqual(out.lastCode, "fresh", "ที่รับแล้วต้องถูกจำไว้กันซ้ำ")
    }
}
