import XCTest
@testable import WBW

/// แอนิเมชันบินทะลุเมฆตอนเข้าแท็บแผนที่ครั้งแรก
///
/// แยกเส้นโค้งออกมาเป็นค่าล้วนเพื่อให้เทสจับได้ก่อนถึงจอ — ถ้าเส้นโค้งพากล้องออกนอกช่วงที่
/// Map3DCamera ยอมรับ แอนิเมชันจะกระตุกตอนโดน clamp ซึ่งบนจอดูเหมือน "แอปค้างแป๊บนึง"
/// ไล่หาสาเหตุยากมากถ้าไม่มีเทสตรงนี้
final class Map3DIntroTests: XCTestCase {

    func testStartsAboveTheCloudsAndFarAway() {
        let f = Map3DIntro.frame(at: 0)
        XCTAssertEqual(f.pitch, Map3DIntro.startPitch, accuracy: 1e-5)
        XCTAssertEqual(f.distance, Map3DIntro.startDistance, accuracy: 1e-5)
        XCTAssertGreaterThan(Map3DIntro.startDistance, Map3DCamera.defaultDistance,
                             "ต้องเริ่มจากไกลกว่าปกติ ไม่งั้นไม่มีระยะให้ไต่ลงมาทะลุเมฆ")
    }

    func testEndsExactlyAtTheNormalCameraFraming() {
        let f = Map3DIntro.frame(at: 1)
        XCTAssertEqual(f.pitch, Map3DCamera.defaultPitch, accuracy: 1e-5,
                       "จบแล้วต้องเป็นมุมปกติเป๊ะ ไม่งั้นจะเห็นภาพกระตุกตอนสลับไปโหมดผู้ใช้คุมเอง")
        XCTAssertEqual(f.distance, Map3DCamera.defaultDistance, accuracy: 1e-5)
    }

    /// ระยะต้องเข้าใกล้อย่างเดียว ไม่แกว่งกลับ — แกว่งกลับบนจอคือกล้องถอยออกกลางทาง ดูเหมือนพลาด
    func testDistanceOnlyDecreases() {
        var previous = Map3DIntro.frame(at: 0).distance
        for step in 1...40 {
            let d = Map3DIntro.frame(at: Float(step) / 40).distance
            XCTAssertLessThanOrEqual(d, previous + 1e-5,
                                     "ระยะเพิ่มขึ้นที่ progress \(Float(step) / 40)")
            previous = d
        }
    }

    /// ทุกเฟรมต้องอยู่ในช่วงที่กล้องยอมรับอยู่แล้ว — ไม่งั้น clamp จะไปตัดกลางแอนิเมชัน
    func testEveryFrameSurvivesCameraClampUnchanged() {
        for step in 0...40 {
            let p = Float(step) / 40
            let f = Map3DIntro.frame(at: p)
            XCTAssertEqual(Map3DCamera.clampPitch(f.pitch), f.pitch, accuracy: 1e-5,
                           "pitch โดน clamp ที่ progress \(p)")
            XCTAssertEqual(Map3DCamera.clampDistance(f.distance), f.distance, accuracy: 1e-5,
                           "distance โดน clamp ที่ progress \(p)")
        }
    }

    /// SwiftUI ส่งค่าเลยขอบมาได้ตอนเฟรมแรก/สุดท้ายของ animation curve บางแบบ
    func testProgressOutsideZeroToOneIsClamped() {
        XCTAssertEqual(Map3DIntro.frame(at: -0.5).distance,
                       Map3DIntro.frame(at: 0).distance, accuracy: 1e-5)
        XCTAssertEqual(Map3DIntro.frame(at: 1.5).distance,
                       Map3DIntro.frame(at: 1).distance, accuracy: 1e-5)
    }

    /// ชั้นเมฆต้องอยู่ระหว่างระยะเริ่มกับระยะจบ ไม่งั้นกล้องไม่ได้ทะลุอะไรเลย
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
