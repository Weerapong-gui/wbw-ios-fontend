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
}
