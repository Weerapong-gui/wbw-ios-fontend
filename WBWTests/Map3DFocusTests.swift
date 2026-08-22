import XCTest
import simd
@testable import WBW

/// กล้องบินเข้าไปจ้องหมุดแล้วหมุนวนรอบฐาน — เส้นโค้งล้วน ไม่ผูกกับ View
///
/// ข้อที่ต้องคุมเหมือน `Map3DIntroTests`: **ทุกเฟรมต้องอยู่ในช่วงที่ `Map3DCamera.clamp*` ยอมรับ**
/// ถ้าเส้นโค้งพาออกนอกช่วง clamp จะไปตัดกลางแอนิเมชัน บนจอเห็นเป็นภาพค้างแป๊บนึงแล้วกระตุก
/// ซึ่งหาสาเหตุยากมากเพราะไม่มี error และโค้ดแอนิเมชันเองดูถูกต้องทุกบรรทัด
final class Map3DFocusTests: XCTestCase {

    private let pin = SIMD3<Float>(0.3, 0.05, -0.4)

    private var start: Map3DPose {
        Map3DPose(yaw: Map3DCamera.defaultYaw, pitch: Map3DCamera.defaultPitch,
                  distance: Map3DCamera.defaultDistance, target: .zero)
    }

    // MARK: - ท่าปลายทาง

    func testFocusPoseLooksAtThePinItself() {
        let pose = Map3DFocus.pose(forPinAt: pin, currentYaw: 0.4)
        XCTAssertEqual(pose.target, pin, "กล้องต้องหมุนรอบหมุด ไม่ใช่รอบจุดกลางแผนที่เหมือนเดิม")
        XCTAssertEqual(pose.distance, Map3DCamera.focusDistance, accuracy: 1e-6)
        XCTAssertEqual(pose.pitch, Map3DCamera.focusPitch, accuracy: 1e-6)
    }

    /// คงมุมกวาดที่ผู้ใช้มองอยู่ ไม่เหวี่ยงข้ามฝั่งจอ — เหวี่ยงเมื่อไหร่ผู้ใช้จะไม่รู้ว่าตัวเองอยู่ทิศไหน
    /// ของแผนที่แล้ว ทั้งที่เพิ่งกดหมุดที่เห็นตรงหน้าเฉย ๆ
    func testFocusPoseKeepsTheDirectionTheUserWasAlreadyLookingFrom() {
        XCTAssertEqual(Map3DFocus.pose(forPinAt: pin, currentYaw: 0.9).yaw, 0.9, accuracy: 1e-6)
    }

    func testFocusPoseNormalisesAYawThatHasSpunPastFullCircles() {
        let pose = Map3DFocus.pose(forPinAt: pin, currentYaw: 2 * .pi + 0.5)
        XCTAssertEqual(pose.yaw, 0.5, accuracy: 1e-5)
    }

    // MARK: - ช่วงบิน

    func testFrameStartsAtTheOldPoseAndEndsAtTheNewOne() {
        let target = Map3DFocus.pose(forPinAt: pin, currentYaw: start.yaw)
        XCTAssertEqual(Map3DFocus.frame(at: 0, from: start, to: target), start)
        XCTAssertEqual(Map3DFocus.frame(at: 1, from: start, to: target), target)
    }

    func testProgressOutsideZeroToOneIsPinnedToTheEnds() {
        let target = Map3DFocus.pose(forPinAt: pin, currentYaw: start.yaw)
        XCTAssertEqual(Map3DFocus.frame(at: -0.4, from: start, to: target), start)
        XCTAssertEqual(Map3DFocus.frame(at: 1.6, from: start, to: target), target)
    }

    /// หัวใจของไฟล์นี้ — ไม่มีเฟรมไหนหลุดช่วงที่กล้องยอมรับ
    func testEveryFrameStaysInsideWhatTheCameraAccepts() {
        let target = Map3DFocus.pose(forPinAt: pin, currentYaw: start.yaw)
        for step in 0...100 {
            let progress = Float(step) / 100
            let frame = Map3DFocus.frame(at: progress, from: start, to: target)
            XCTAssertEqual(Map3DCamera.clampPitch(frame.pitch), frame.pitch, accuracy: 1e-5,
                           "pitch หลุดช่วงที่ progress \(progress)")
            // ระยะต้องอยู่ระหว่างสองปลายทาง ไม่ใช่ในช่วงของท่าทางผู้ใช้ — ระยะโฟกัสใกล้กว่า
            // minDistance โดยตั้งใจ (ดู Map3DCamera.clampDistance)
            XCTAssertGreaterThanOrEqual(frame.distance, Map3DCamera.focusDistance - 1e-5,
                                        "distance ใกล้เกินปลายทางที่ progress \(progress)")
            XCTAssertLessThanOrEqual(frame.distance, Map3DCamera.defaultDistance + 1e-5,
                                     "distance ไกลเกินจุดเริ่มที่ progress \(progress)")
            XCTAssertEqual(Map3DCamera.wrapYaw(frame.yaw), frame.yaw, accuracy: 1e-5,
                           "yaw ไม่ได้ถูก wrap ที่ progress \(progress)")
        }
    }

    /// กวาดทางสั้นเสมอ — 170° ไป -170° ห่างกันแค่ 20° ต้องผ่าน 180° ไม่ใช่วิ่งย้อน 340° ผ่าน 0°
    func testYawTakesTheShortWayRoundNotAllTheWayBack() {
        let from = Map3DPose(yaw: 170 * .pi / 180, pitch: Map3DCamera.defaultPitch,
                             distance: Map3DCamera.defaultDistance, target: .zero)
        let to = Map3DPose(yaw: -170 * .pi / 180, pitch: Map3DCamera.focusPitch,
                           distance: Map3DCamera.focusDistance, target: pin)
        for step in 0...20 {
            let frame = Map3DFocus.frame(at: Float(step) / 20, from: from, to: to)
            let degrees = abs(frame.yaw) * 180 / .pi
            XCTAssertGreaterThan(degrees, 169.9,
                                 "ที่ progress \(Float(step) / 20) กวาดย้อนกลับผ่าน 0° แทนที่จะผ่าน 180°")
        }
    }

    func testTargetSlidesFromTheOldOneToThePin() {
        let target = Map3DFocus.pose(forPinAt: pin, currentYaw: start.yaw)
        let middle = Map3DFocus.frame(at: 0.5, from: start, to: target)
        XCTAssertGreaterThan(simd_length(middle.target), 0, "เป้าต้องขยับออกจากจุดกลางแล้ว")
        XCTAssertLessThan(simd_distance(middle.target, pin), simd_length(pin),
                          "เป้าต้องเข้าใกล้หมุดขึ้น ไม่ใช่ไถลออกไปทางอื่น")
    }

    // MARK: - ช่วงหมุนวน

    func testOrbitKeepsTurningOneWay() {
        let base: Float = 0
        let early = Map3DFocus.orbitYaw(base: base, elapsed: 1)
        let later = Map3DFocus.orbitYaw(base: base, elapsed: 2)
        XCTAssertEqual(early, Map3DCamera.orbitSpeed, accuracy: 1e-5)
        XCTAssertEqual(later, Map3DCamera.orbitSpeed * 2, accuracy: 1e-5)
    }

    /// หมุนค้างไว้เป็นนาที ๆ ได้ — ค่าต้องไม่โตขึ้นเรื่อย ๆ จนเสียความละเอียดของ Float
    func testOrbitWrapsInsteadOfGrowingForever() {
        for seconds in [60.0, 600.0, 3600.0] {
            let yaw = Map3DFocus.orbitYaw(base: 0, elapsed: seconds)
            XCTAssertEqual(Map3DCamera.wrapYaw(yaw), yaw, accuracy: 1e-5,
                           "หมุนมา \(seconds) วิแล้ว yaw ยังต้องอยู่ในหนึ่งรอบ")
        }
    }

    func testDurationsAreLongEnoughToReadAsMovementButNotAWait() {
        XCTAssertGreaterThan(Map3DFocus.flyDuration, 0.8)
        XCTAssertLessThan(Map3DFocus.flyDuration, 2.5, "นานกว่านี้คนกดหมุดแล้วรู้สึกว่าถูกขัง")
        XCTAssertLessThan(Map3DFocus.returnDuration, Map3DFocus.flyDuration,
                          "ขากลับต้องเร็วกว่าขาไป — ผู้ใช้กดปิดแล้วอยากได้จอคืนทันที")
    }

    // MARK: - ม่านมืดตอนโฟกัสหมุด

    /// ปลายทั้งสองต้องคืนค่าเป๊ะ ไม่ผ่านการคำนวณ — เหตุผลเดียวกับ `frame(at:from:to:)`:
    /// `a + (b - a) * 1` ใน floating point ไม่ได้เท่ากับ `b` เสมอไป เศษที่เหลือแปลว่าม่าน
    /// ไม่เคยมืดเต็มที่จริงหรือไม่เคยใสสนิทจริง ซึ่งบนจอคือคราบจาง ๆ ที่ไม่มีวันหายไป
    func testDimReturnsItsEndpointsExactly() {
        XCTAssertEqual(Map3DFocus.dim(at: 0, from: 0, to: 1), 0)
        XCTAssertEqual(Map3DFocus.dim(at: 1, from: 0, to: 1), 1)
        XCTAssertEqual(Map3DFocus.dim(at: 1, from: 1, to: 0), 0)
    }

    /// SwiftUI ส่ง progress เลยขอบมาได้ในบางเส้นโค้ง — ต้องบีบ ไม่ใช่คำนวณต่อ
    func testDimClampsProgressOutsideZeroToOne() {
        XCTAssertEqual(Map3DFocus.dim(at: -0.5, from: 0, to: 1), 0)
        XCTAssertEqual(Map3DFocus.dim(at: 1.7, from: 0, to: 1), 1)
    }

    /// ม่านต้องมืดขึ้นทางเดียวตอนเข้าโฟกัส และใสขึ้นทางเดียวตอนออก — กระพริบกลับทางแม้เฟรมเดียว
    /// อ่านเป็นจอสั่น ไม่ใช่การเปลี่ยนโฟกัส
    func testDimMovesOneWayOnly() {
        var previous = Map3DFocus.dim(at: 0, from: 0, to: 1)
        for step in 1...40 {
            let value = Map3DFocus.dim(at: Float(step) / 40, from: 0, to: 1)
            XCTAssertGreaterThanOrEqual(value, previous, "ม่านสว่างกลับที่ก้าวที่ \(step)")
            previous = value
        }
        previous = Map3DFocus.dim(at: 0, from: 1, to: 0)
        for step in 1...40 {
            let value = Map3DFocus.dim(at: Float(step) / 40, from: 1, to: 0)
            XCTAssertLessThanOrEqual(value, previous, "ม่านมืดกลับที่ก้าวที่ \(step)")
            previous = value
        }
    }

    /// ม่านกับกล้องต้องถึงที่หมายพร้อมกัน — ใช้เส้นโค้งเดียวกันจริงหรือเปล่า
    ///
    /// เดิม `frame(at:from:to:)` คำนวณ `1 - pow(1 - t, 3)` ไว้ในตัวเอง ถ้าม่านลอกสูตรไปเขียนซ้ำ
    /// แล้ววันหลังมีคนแก้ที่เดียว ม่านกับกล้องจะเดินคนละจังหวะโดยไม่มีอะไรฟ้อง
    func testDimRidesTheSameEasingCurveAsTheCamera() {
        let from = Map3DPose(yaw: 0, pitch: Map3DCamera.defaultPitch,
                             distance: Map3DCamera.defaultDistance, target: .zero)
        let to = Map3DPose(yaw: 0, pitch: Map3DCamera.focusPitch,
                           distance: Map3DCamera.focusDistance, target: SIMD3<Float>(0.3, 0, 0.2))
        for step in 1..<10 {
            let t = Float(step) / 10
            let cameraShare = (Map3DFocus.frame(at: t, from: from, to: to).target.x - from.target.x)
                / (to.target.x - from.target.x)
            XCTAssertEqual(Map3DFocus.dim(at: t, from: 0, to: 1), cameraShare, accuracy: 0.001,
                           "ม่านกับกล้องเดินคนละเส้นโค้งที่ t = \(t)")
        }
    }

    /// ความทึบจริงบนจอต้องอยู่ใน 0…maxDim เสมอ แม้ป้อนค่านอกช่วงเข้าไป
    func testDimOpacityStaysInsideItsOwnRange() {
        XCTAssertEqual(Map3DFocus.dimOpacity(0), 0)
        XCTAssertEqual(Map3DFocus.dimOpacity(1), Map3DFocus.maxDim)
        XCTAssertEqual(Map3DFocus.dimOpacity(2), Map3DFocus.maxDim, "ค่าเกิน 1 ต้องถูกบีบ")
        XCTAssertEqual(Map3DFocus.dimOpacity(-1), 0, "ค่าติดลบต้องถูกบีบ")
    }

    /// ม่านทึบเต็มแปลว่าแผนที่หายไปทั้งจอ เหลือแต่การ์ด — ซึ่งไม่ใช่การโฟกัส แต่คือการปิดแผนที่
    func testMaxDimLeavesTheMapVisible() {
        XCTAssertGreaterThan(Map3DFocus.maxDim, 0, "ม่านที่ใสสนิทคือไม่มีม่าน")
        XCTAssertLessThan(Map3DFocus.maxDim, 1, "ม่านทึบเต็มแปลว่าแผนที่หายไปหมด")
    }
}
