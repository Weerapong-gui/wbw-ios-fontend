import XCTest
@testable import WBW

/// ตรึงกติกาการนับระยะของแท็บ SU RUN
///
/// ตัวเลขเกณฑ์ทั้งชุดยกมาจากแอป Android (`walk/WalkTrackingService.kt`) ซึ่งผ่านการเดินจริงมาแล้ว
/// ไม่ใช่ค่าที่คิดขึ้นใหม่ · ที่ต้องมีเทสเพราะอาการเวลาตั้งผิดจะไม่ฟ้องอะไรเลยตอนรัน: ระยะจะไหลขึ้น
/// เองตอนยืนนิ่ง (GPS แกว่งอยู่กับที่) หรือไม่ขยับเลยตอนเดินช้า แล้วกว่าจะรู้ก็ต่อเมื่อมีคนเดินจริงทั้งเส้น
final class SURunMathTests: XCTestCase {

    // MARK: - ทิ้ง fix ที่ไม่แม่นพอ

    func testRejectsInaccurateFix() {
        XCTAssertFalse(SURunMath.accepts(accuracy: 26),
                       "fix ที่คลาดเกิน 25 ม. ต้องถูกทิ้ง ไม่งั้นระยะจะกระโดดทีละสิบเมตรใต้ร่มไม้")
    }

    func testAcceptsAccurateFix() {
        XCTAssertTrue(SURunMath.accepts(accuracy: 25),
                      "25 ม. พอดีต้องผ่าน — ขอบเขตเป็นแบบรวมปลาย ไม่ใช่ตัดทิ้ง")
    }

    func testRejectsUnknownAccuracy() {
        XCTAssertFalse(SURunMath.accepts(accuracy: -1),
                       "CoreLocation ใช้ค่าติดลบแทน 'ไม่รู้ความแม่น' ต้องทิ้ง ไม่ใช่ตีความว่าแม่นมาก")
    }

    // MARK: - สะสมระยะเมื่อขยับพอเท่านั้น

    func testDoesNotAdvanceOnJitter() {
        XCTAssertEqual(SURunMath.advance(movedFromAnchor: 2.4), 0,
                       "ขยับไม่ถึง 2.5 ม. คือ GPS แกว่ง ไม่ใช่คนเดิน ห้ามบวกเข้าระยะรวม")
    }

    func testAdvancesOnRealMovement() {
        XCTAssertEqual(SURunMath.advance(movedFromAnchor: 3.0), 3.0,
                       "ขยับเกินเกณฑ์ต้องบวกระยะเต็มที่ขยับจริง ไม่ใช่ส่วนที่เกินเกณฑ์")
    }

    // MARK: - ปรับความเร็วให้นิ่ง

    func testFirstSpeedSampleIsTakenWhole() {
        XCTAssertEqual(SURunMath.smooth(speed: 1.4, previous: nil), 1.4, accuracy: 0.0001,
                       "ตัวอย่างแรกไม่มีของเก่าให้ผสม ต้องใช้ค่าดิบ ไม่ใช่ผสมกับศูนย์แล้วได้ต่ำเกินจริง")
    }

    func testSpeedIsSmoothedTowardsNewSample() {
        // alpha 0.3 → 0.3*2.0 + 0.7*1.0 = 1.3
        XCTAssertEqual(SURunMath.smooth(speed: 2.0, previous: 1.0), 1.3, accuracy: 0.0001,
                       "ค่าใหม่ต้องมีน้ำหนัก 0.3 เท่านั้น ไม่งั้น pace บนจอจะกระตุกทุกวินาที")
    }

    // MARK: - ข้อความบนจอ

    func testPaceHiddenWhenTooSlow() {
        XCTAssertEqual(SURunMath.paceText(metresPerSecond: 0.34), "—",
                       "ยืนนิ่ง/เดินช้ามากได้ pace เป็นเลขมหาศาลที่ไม่มีความหมาย ต้องซ่อนแทน")
    }

    func testPaceFormatted() {
        // 2.5 m/s → 1000/2.5 = 400 วิ/กม. = 6:40
        XCTAssertEqual(SURunMath.paceText(metresPerSecond: 2.5), "6:40",
                       "pace คือ นาที:วินาที ต่อกิโลเมตร ไม่ใช่ความเร็ว")
    }

    func testDistanceUnderOneKilometreIsMetres() {
        XCTAssertEqual(SURunMath.distanceText(metres: 850), "850 ม.")
    }

    func testDistanceOverOneKilometreIsKilometres() {
        XCTAssertEqual(SURunMath.distanceText(metres: 1240), "1.24 กม.",
                       "ทศนิยม 2 ตำแหน่ง — 1 ตำแหน่งทำให้เลขนิ่งนานเกินไปจนดูเหมือนแอปค้าง")
    }

    func testElapsedUnderAnHour() {
        XCTAssertEqual(SURunMath.elapsedText(seconds: 754), "12:34")
    }

    func testElapsedOverAnHour() {
        XCTAssertEqual(SURunMath.elapsedText(seconds: 3754), "1:02:34")
    }

    func testStepsUnavailableShowsDash() {
        XCTAssertEqual(SURunMath.stepsText(nil), "—",
                       "เครื่องที่ไม่มีตัวนับก้าวต้องบอกว่า 'ไม่รู้' ไม่ใช่ 0 ซึ่งอ่านว่า 'เดินแล้วศูนย์ก้าว'")
    }

    func testStepsFormatted() {
        XCTAssertEqual(SURunMath.stepsText(1234), "1,234")
    }
}
