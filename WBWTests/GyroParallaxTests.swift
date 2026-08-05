import XCTest
import simd
@testable import WBW

/// การ map การเอียงเครื่องเป็นการเลื่อนกล้อง — เทสเฉพาะส่วนที่เป็นคณิตศาสตร์ล้วน
/// (ตัวเซนเซอร์เทสไม่ได้ในซิม ต้องเครื่องจริง)
final class GyroParallaxTests: XCTestCase {

    func testLevelDeviceIsCentred() {
        let o = GyroParallax.mapAttitude(roll: 0, pitch: 0)
        XCTAssertEqual(o.x, 0, accuracy: 0.0001)
        XCTAssertEqual(o.y, 0, accuracy: 0.0001)
    }

    func testTiltingRightMovesCameraRight() {
        let o = GyroParallax.mapAttitude(roll: 0.3, pitch: 0)
        XCTAssertGreaterThan(o.x, 0)
    }

    func testTiltingLeftMovesCameraLeft() {
        let o = GyroParallax.mapAttitude(roll: -0.3, pitch: 0)
        XCTAssertLessThan(o.x, 0)
    }

    func testOffsetIsClampedToTheBakedMargin() {
        // สคริปต์ bake เผื่อขอบไว้ 25% ของกรวยกล้อง = ±1.1 หน่วย
        // ถ้าปล่อยให้เกินนี้ เอียงแรงๆ จะเห็นขอบฉากว่างเปล่า
        for roll in stride(from: -3.0, through: 3.0, by: 0.25) {
            let o = GyroParallax.mapAttitude(roll: roll, pitch: 0)
            XCTAssertLessThanOrEqual(abs(o.x), GyroParallax.maxOffsetX + 0.0001,
                                     "roll \(roll) ให้ offset เกินขอบที่ bake ไว้")
        }
    }

    func testPitchOffsetIsClamped() {
        for pitch in stride(from: -3.0, through: 3.0, by: 0.25) {
            let o = GyroParallax.mapAttitude(roll: 0, pitch: pitch)
            XCTAssertLessThanOrEqual(abs(o.y), GyroParallax.maxOffsetY + 0.0001)
        }
    }

    func testResponseIsMonotonicWithinRange() {
        let a = GyroParallax.mapAttitude(roll: 0.1, pitch: 0).x
        let b = GyroParallax.mapAttitude(roll: 0.2, pitch: 0).x
        XCTAssertGreaterThan(b, a)
    }
}
