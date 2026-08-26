import CoreLocation
import XCTest
@testable import WBW

/// คณิตของการเดิน — สองข้อที่สำคัญที่สุดคือ "ยืนอยู่กับที่แล้วระยะต้องไม่วิ่ง"
/// กับ "เดินช้ามากแล้วเพซต้องไม่เป็นเลขบ้า ๆ"
///
/// ทั้งสองอย่างทดสอบด้วยตาบนเครื่องจริงยากมาก (ต้องออกไปยืนกลางแดดรอ GPS สั่นเอง) แต่เป็น
/// อาการที่ผู้ใช้เห็นแล้วเลิกเชื่อตัวเลขทั้งจอทันที — จึงต้องถูกจับตรงนี้
///
/// เทสได้เพราะ `WalkMath` เป็น `static func` บริสุทธิ์ล้วน ไม่ต้อง mount View ไม่ต้องรอ GPS จริง
/// (ทรงเดียวกับ `Map3DCameraTests` ที่เรียก `Map3DCamera.clampPitch` ตรง ๆ)
final class WalkMathTests: XCTestCase {

    private func fix(lat: Double, lng: Double, accuracy: Double = 5, speed: Double = 1) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                   altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5,
                   course: 0, speed: speed, timestamp: Date())
    }

    // MARK: - ความน่าเชื่อถือของ fix

    func testFixesWithPoorAccuracyAreThrownAway() {
        XCTAssertTrue(WalkMath.isTrustworthy(fix(lat: 20, lng: 99, accuracy: 24)))
        XCTAssertFalse(WalkMath.isTrustworthy(fix(lat: 20, lng: 99, accuracy: 30)),
                       "ใต้ร่มไม้หนา GPS ให้ค่าที่กระโดดเป็นสิบเมตร ต้องทิ้ง ไม่ใช่เอามาบวกระยะ")
    }

    func testNegativeAccuracyMeansTheFixIsUnusable() {
        XCTAssertFalse(WalkMath.isTrustworthy(fix(lat: 20, lng: 99, accuracy: -1)),
                       "ค่าติดลบแปลว่าพิกัดใช้ไม่ได้เลย ไม่ใช่แปลว่าแม่นมาก")
    }

    // MARK: - ระยะสะสม (ข้อที่สำคัญที่สุด)

    /// ~1.1 เมตรต่อ 0.00001 องศาละติจูด
    func testStandingStillNeverAddsDistance() {
        let anchor = fix(lat: 20.0000000, lng: 99)
        let jitter = fix(lat: 20.0000180, lng: 99)   // ~2.0 ม. — ต่ำกว่าเกณฑ์ 2.5
        XCTAssertNil(WalkMath.advance(from: anchor, to: jitter), """
            การสั่นของ GPS ตอนยืนนิ่งต้องไม่ถูกนับเป็นระยะ — คืน nil แปลว่า **ห้ามขยับหมุด
            อ้างอิงด้วย** ถ้าเลื่อนหมุดตามทุก fix ระยะจะสะสมทีละ 1-2 เมตรจนได้กิโลเมตร
            จากการยืนอยู่กับที่
            """)
    }

    func testRealMovementIsCounted() {
        let anchor = fix(lat: 20.0000000, lng: 99)
        let moved = fix(lat: 20.0000450, lng: 99)   // ~5 ม.
        let advance = WalkMath.advance(from: anchor, to: moved)
        XCTAssertNotNil(advance)
        XCTAssertEqual(advance ?? 0, 5, accuracy: 1.0)
    }

    // MARK: - ความเร็ว

    func testSpeedIsSmoothedTowardsTheSampleNotSnappedToIt() {
        let smoothed = WalkMath.smoothSpeed(previous: 0, sample: 1.0)
        XCTAssertEqual(smoothed, WalkMath.speedAlpha, accuracy: 1e-9,
                       "ค่าดิบจาก GPS กระโดดจนอ่านไม่ทัน ต้องไล่เข้าหา ไม่ใช่กระโดดตาม")
        XCTAssertLessThan(smoothed, 1.0)
    }

    func testUnknownSpeedIsTreatedAsZeroNotAsMinusOne() {
        // CoreLocation คืน -1 ตอนวัดความเร็วไม่ได้ ปล่อยผ่านแล้วค่าเฉลี่ยจะติดลบ
        XCTAssertGreaterThanOrEqual(WalkMath.smoothSpeed(previous: 0, sample: -1), 0)
    }

    // MARK: - ข้อความที่ผู้ใช้อ่าน

    func testDistanceSwitchesToKilometresAtExactlyOneThousand() {
        XCTAssertTrue(WalkMath.distanceText(999).contains("999"))
        XCTAssertTrue(WalkMath.distanceText(1000).contains("1.00"),
                      "ตั้งแต่ 1 กม. ขึ้นไปต้องเป็นกิโลเมตรสองตำแหน่ง ไม่ใช่ '1000 ม.'")
        XCTAssertTrue(WalkMath.distanceText(1240).contains("1.24"))
    }

    func testPaceIsBlankedOutWhenTooSlowToBeWalking() {
        XCTAssertEqual(WalkMath.paceText(speedMps: 0), "—")
        XCTAssertEqual(WalkMath.paceText(speedMps: WalkMath.minPaceSpeedMps - 0.01), "—", """
            ไม่มีเพดานนี้ เพซตอนยืนนิ่งจะพุ่งเป็นหลักชั่วโมงต่อกิโลเมตร ซึ่งถูกทางคณิต
            แต่ไร้ความหมายกับคนอ่าน
            """)
    }

    func testPaceReadsAsMinutesAndSecondsPerKilometre() {
        // 1.32 m/s → 1000/1.32 = 757.6 วิ = 12 นาที 37 วิ
        XCTAssertEqual(WalkMath.paceText(speedMps: 1.32), "12'37\"")
        // วินาทีต้องเติมศูนย์หน้าเสมอ ไม่งั้น 8 นาที 5 วิ จะพิมพ์เป็น 8'5" ซึ่งอ่านกำกวม
        XCTAssertEqual(WalkMath.paceText(speedMps: 2.0), "8'20\"")
    }

    func testStepsShowADashWhenTheDeviceCannotCountThem() {
        XCTAssertEqual(WalkMath.stepsText(nil), "—",
                       "nil = นับไม่ได้ ไม่ใช่ศูนย์ก้าว — สองอย่างนี้ผู้ใช้ต้องแยกออก")
        XCTAssertEqual(WalkMath.stepsText(0), "0")
        XCTAssertEqual(WalkMath.stepsText(1683), "1683")
    }

    // MARK: - ความคืบหน้าบนเส้นทาง (เส้น fill บนแผนที่ — port จาก 2c760c6 ของ Android)

    private func straightRoute(_ metres: Double) -> TrailRoute {
        let mPerDeg = 111_320.0
        let points = (0...Int(metres / 10)).map {
            CLLocationCoordinate2D(latitude: Double($0) * 10 / mPerDeg, longitude: 0)
        }
        return TrailRoute(coordinates: points, distanceMetres: Int(metres))
    }

    /// ตัวห่อที่ tracker เรียกจริง — กติกา "ถือค่าเดิมไว้เสมอเมื่อตอบไม่ได้" อยู่ตรงนี้
    /// (progressFrom คืน nil ตอน off-route · ไม่มีเส้น = ไม่มีอะไรให้วัด)
    func testRouteProgressKeepsThePreviousValueWhenOffRoute() {
        let route = straightRoute(1_000)
        let off = CLLocationCoordinate2D(latitude: 400 / 111_320.0, longitude: 300 / 111_320.0)
        XCTAssertEqual(WalkMath.routeProgress(previous: 400, route: route, at: off), 400,
                       "หลุดเส้น = ถือค่าเดิม ไม่ใช่รีเซ็ตหรือเดามั่ว")
    }

    func testRouteProgressIsNilWithoutARouteOrAFix() {
        let off = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        XCTAssertNil(WalkMath.routeProgress(previous: nil, route: nil, at: off),
                     "ไม่มีเส้นให้วัด = ไม่มีความคืบหน้า ไม่ใช่ศูนย์")
        XCTAssertEqual(WalkMath.routeProgress(previous: 250, route: nil, at: off), 250)
    }

    func testRouteProgressAcquiresOnFirstFixThenAdvances() {
        let route = straightRoute(1_000)
        let mPerDeg = 111_320.0
        let first = WalkMath.routeProgress(
            previous: nil, route: route,
            at: CLLocationCoordinate2D(latitude: 300 / mPerDeg, longitude: 0))
        XCTAssertNotNil(first)
        XCTAssertEqual(first!, 300, accuracy: 15)

        let second = WalkMath.routeProgress(
            previous: first, route: route,
            at: CLLocationCoordinate2D(latitude: 450 / mPerDeg, longitude: 0))
        XCTAssertEqual(second!, 450, accuracy: 15)
    }
}
