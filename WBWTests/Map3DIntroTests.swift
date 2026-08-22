import XCTest
import simd
@testable import WBW

/// แอนิเมชันบินทะลุเมฆตอนเข้าแท็บแผนที่ครั้งแรก
///
/// **2026-08-21: ปลายทางเปลี่ยนจาก "กลางแผนที่" เป็น "ฐานที่ 1"** ตัวเส้นโค้งจึงย้ายไปใช้
/// `Map3DFocus.frame(at:from:to:)` ซึ่ง interpolate ท่าเต็มสี่แกน (yaw/pitch/distance/target)
/// ด้วย ease-out กำลังสามเส้นเดียวกับที่ `Map3DIntro.frame(at:)` เดิมใช้ · ของเดิมคำนวณได้
/// แค่สองแกนจึงพาไปหาหมุดไม่ได้
///
/// เทสสองตัวที่เคยอยู่ที่นี่ (ระยะลดทางเดียว, progress นอกช่วงถูกบีบ) **ย้ายไปอยู่ใน
/// `Map3DFocusTests`** แล้ว — `testFrameStartsAtTheOldPoseAndEndsAtTheNewOne` กับ
/// `testProgressOutsideZeroToOneIsPinnedToTheEnds` คุมเรื่องเดียวกันบนเส้นโค้งตัวจริง
/// ไม่ได้หายไปเฉย ๆ
final class Map3DIntroTests: XCTestCase {

    /// ตำแหน่งหมุดสมมติ — ค่าจริงมาจากโมเดลตอนรัน เทสสนใจแค่ว่ามันถูกใช้เป็นปลายทาง
    private let pin = SIMD3<Float>(0.42, 0.06, -0.31)

    private var destination: Map3DPose {
        Map3DFocus.pose(forPinAt: pin, currentYaw: Map3DCamera.defaultYaw)
    }

    func testStartsAboveTheCloudsAndFarAway() {
        let start = Map3DIntro.startPose
        XCTAssertEqual(start.pitch, Map3DIntro.startPitch, accuracy: 1e-5)
        XCTAssertEqual(start.distance, Map3DIntro.startDistance, accuracy: 1e-5)
        XCTAssertGreaterThan(Map3DIntro.startDistance, Map3DCamera.defaultDistance,
                             "ต้องเริ่มจากไกลกว่าปกติ ไม่งั้นไม่มีระยะให้ไต่ลงมาทะลุเมฆ")
    }

    /// เริ่มที่กลางแผนที่ จบที่หมุด — `target` คือแกนที่ของเดิมขยับไม่ได้เลย และเป็นทั้งหมด
    /// ของสิ่งที่งานนี้เปลี่ยน
    func testStartsLookingAtTheCentreAndEndsLookingAtThePin() {
        XCTAssertEqual(Map3DIntro.startPose.target, .zero)
        XCTAssertEqual(destination.target, pin)
    }

    /// ปลายทางต้องเป็นท่าเดียวกับตอนแตะหมุดเป๊ะ ไม่ใช่ท่าที่คำนวณแยกอีกชุด — ไม่งั้นเปิดแอปมา
    /// อยู่ท่าหนึ่ง พอกดหมุดเดิมซ้ำกล้องจะขยับไปอีกท่าโดยไม่มีเหตุผลที่ผู้ใช้เห็น
    func testTheDestinationIsTheSamePoseTappingThePinWouldGive() {
        let tapped = Map3DFocus.pose(forPinAt: pin, currentYaw: Map3DCamera.defaultYaw)
        XCTAssertEqual(destination.pitch, tapped.pitch, accuracy: 1e-6)
        XCTAssertEqual(destination.distance, tapped.distance, accuracy: 1e-6)
        XCTAssertEqual(destination.target, tapped.target)
    }

    /// ทุกเฟรมต้องอยู่ในช่วงที่กล้องยอมรับ ไม่งั้น clamp จะไปตัดกลางแอนิเมชัน บนจอเห็นเป็น
    /// ภาพค้างแป๊บนึงแล้วกระตุก
    ///
    /// **ระยะต้อง clamp ด้วยพื้น `focusDistance` ไม่ใช่ค่าปริยาย** — ปลายทางคือ 0.55 ซึ่ง
    /// ต่ำกว่า `minDistance` 0.8 · `clampDistance` แบบไม่ส่ง floor จะดีดเฟรมท้าย ๆ ขึ้นไป 0.8
    /// ซึ่งคือกล้องถอยออกเองตอนใกล้ถึงหมุด · `Map3DFocus.pose` ก็ส่ง floor ตัวเดียวกันนี้
    func testEveryFrameSurvivesCameraClampUnchanged() {
        for step in 0...40 {
            let p = Float(step) / 40
            let f = Map3DFocus.frame(at: p, from: Map3DIntro.startPose, to: destination)
            XCTAssertEqual(Map3DCamera.clampPitch(f.pitch), f.pitch, accuracy: 1e-5,
                           "pitch โดน clamp ที่ progress \(p)")
            XCTAssertEqual(Map3DCamera.clampDistance(f.distance, floor: Map3DCamera.focusDistance),
                           f.distance, accuracy: 1e-5,
                           "distance โดน clamp ที่ progress \(p)")
        }
    }

    /// ระยะต้องเข้าใกล้อย่างเดียว ไม่แกว่งกลับ — แกว่งกลับบนจอคือกล้องถอยออกกลางทาง ดูเหมือนพลาด
    func testDistanceOnlyDecreases() {
        var previous = Map3DIntro.startPose.distance
        for step in 1...40 {
            let p = Float(step) / 40
            let d = Map3DFocus.frame(at: p, from: Map3DIntro.startPose, to: destination).distance
            XCTAssertLessThanOrEqual(d, previous + 1e-5, "ระยะเพิ่มขึ้นที่ progress \(p)")
            previous = d
        }
    }

    /// ชั้นเมฆต้องอยู่ระหว่างระยะเริ่มกับความสูงที่กล้องไปจบ ไม่งั้นกล้องไม่ได้ทะลุอะไรเลย
    ///
    /// เกณฑ์ล่างยังเทียบกับ `defaultDistance` ตัวเดิม ไม่ใช่ปลายทางใหม่ — และยังจริงกว่าเดิม
    /// เพราะกล้องไปจบต่ำลงกว่าเดิมมาก (0.55·sin34° ≈ 0.31 เทียบกับของเดิม 1.15·sin68° ≈ 1.07)
    func testCloudLayersSitBetweenStartAndEndDistance() {
        XCTAssertFalse(Map3DSky.cloudLayerHeights.isEmpty)
        for h in Map3DSky.cloudLayerHeights {
            XCTAssertGreaterThan(h, Map3DCamera.defaultDistance * 0.3,
                                 "ชั้นเมฆต่ำเกินไป กล้องจบแล้วยังอยู่เหนือมัน จะไม่เห็นเมฆเลย")
            XCTAssertLessThan(h, Map3DIntro.startDistance,
                              "ชั้นเมฆสูงกว่าจุดเริ่ม กล้องเริ่มใต้เมฆแล้ว ไม่ได้ทะลุลงมา")
        }
    }
}
