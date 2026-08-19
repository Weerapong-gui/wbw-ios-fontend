import XCTest
import simd
@testable import WBW

/// กล้องแท็บแผนที่ — ข้อที่สำคัญที่สุดคือผู้ใช้ต้องมองใต้โมเดลไม่ได้
final class Map3DCameraTests: XCTestCase {

    func testPitchNeverGoesBelowTheHorizon() {
        // ลากลงแรงแค่ไหนก็ต้องไม่ต่ำกว่า minPitch — ต่ำกว่านั้นเห็นก้นภูมิประเทศที่เป็นแผ่นตัดเปล่า
        XCTAssertEqual(Map3DCamera.clampPitch(-3), Map3DCamera.minPitch, accuracy: 1e-6)
        XCTAssertEqual(Map3DCamera.clampPitch(0), Map3DCamera.minPitch, accuracy: 1e-6)
        XCTAssertGreaterThan(Map3DCamera.minPitch, 0, "มุมต่ำสุดต้องอยู่เหนือเส้นขอบฟ้า")
    }

    func testPitchNeverReachesStraightDown() {
        XCTAssertEqual(Map3DCamera.clampPitch(3), Map3DCamera.maxPitch, accuracy: 1e-6)
        XCTAssertLessThan(Map3DCamera.maxPitch, .pi / 2,
                          "ตั้งฉาก 90° พอดีทำให้ทิศกวาดพลิกกะทันหัน")
    }

    func testPitchInRangePassesThrough() {
        let mid = (Map3DCamera.minPitch + Map3DCamera.maxPitch) / 2
        XCTAssertEqual(Map3DCamera.clampPitch(mid), mid, accuracy: 1e-6)
    }

    /// **หมุนได้รอบตัวแล้ว** เดิมล็อกไว้ ±55° จากมุมเริ่มต้น — เจ้าของงานสั่งให้ปลดล็อก
    ///
    /// ต้อง wrap เข้าช่วง (-π, π] ไม่ใช่ปล่อยให้ค่าสะสมโตไปเรื่อย ๆ: yaw ตัวนี้ถูกใช้เป็นจุดตั้งต้น
    /// ของท่าทางลากรอบถัดไป และเป็นปลายทางของแอนิเมชันบินเข้าหาหมุด ปล่อยให้เป็นหลักพันเรเดียน
    /// แล้วเส้นโค้ง interpolate จะวิ่งวนหลายรอบก่อนถึงที่หมาย
    func testYawWrapsAllTheWayAroundInsteadOfClamping() {
        func degrees(_ radians: Float) -> Float { radians * 180 / .pi }
        XCTAssertEqual(degrees(Map3DCamera.wrapYaw(370 * .pi / 180)), 10, accuracy: 1e-3)
        XCTAssertEqual(degrees(Map3DCamera.wrapYaw(-190 * .pi / 180)), 170, accuracy: 1e-3)
        XCTAssertEqual(degrees(Map3DCamera.wrapYaw(180 * .pi / 180)), 180, accuracy: 1e-3)
        XCTAssertEqual(degrees(Map3DCamera.wrapYaw(-180 * .pi / 180)), 180, accuracy: 1e-3)
    }

    func testYawInsideTheCircleIsLeftAlone() {
        for degrees in stride(from: -179.0, through: 180.0, by: 37.0) {
            let radians = Float(degrees) * .pi / 180
            XCTAssertEqual(Map3DCamera.wrapYaw(radians), radians, accuracy: 1e-5,
                           "\(degrees)° อยู่ในรอบอยู่แล้ว ห้ามขยับ")
        }
    }

    /// ค่าที่วนหลายรอบต้องยังชี้ทิศเดิมจริง ๆ ไม่ใช่แค่ตัวเลขสวย
    func testWrappedYawPointsTheCameraTheSameWay() {
        let target = SIMD3<Float>(0, 0, 0)
        let spun = Map3DCamera.wrapYaw(3 * 2 * .pi + 0.7)
        let plain = Map3DCamera.position(yaw: 0.7, pitch: 0.5, distance: 2, target: target)
        let wrapped = Map3DCamera.position(yaw: spun, pitch: 0.5, distance: 2, target: target)
        XCTAssertEqual(simd_distance(plain, wrapped), 0, accuracy: 1e-4)
    }

    func testDistanceClampsBothEnds() {
        XCTAssertEqual(Map3DCamera.clampDistance(0), Map3DCamera.minDistance, accuracy: 1e-6)
        XCTAssertEqual(Map3DCamera.clampDistance(99), Map3DCamera.maxDistance, accuracy: 1e-6)
        XCTAssertEqual(Map3DCamera.clampDistance(Map3DCamera.defaultDistance),
                       Map3DCamera.defaultDistance, accuracy: 1e-6)
    }

    func testDefaultsSitInsideTheirOwnLimits() {
        XCTAssertEqual(Map3DCamera.clampPitch(Map3DCamera.defaultPitch),
                       Map3DCamera.defaultPitch, accuracy: 1e-6)
        XCTAssertEqual(Map3DCamera.wrapYaw(Map3DCamera.defaultYaw),
                       Map3DCamera.defaultYaw, accuracy: 1e-6)
        XCTAssertEqual(Map3DCamera.clampDistance(Map3DCamera.defaultDistance),
                       Map3DCamera.defaultDistance, accuracy: 1e-6)
    }

    func testCameraStaysAboveWhateverItLooksAt() {
        // ทุกมุมที่ clamp แล้วต้องให้กล้องอยู่สูงกว่าเป้าเสมอ = มองลงมาที่โมเดล ไม่ใช่มองขึ้นจากใต้
        let target = SIMD3<Float>(0, 0, 0)
        for degrees in stride(from: -180.0, through: 180.0, by: 15.0) {
            let pitch = Map3DCamera.clampPitch(Float(degrees) * .pi / 180)
            let p = Map3DCamera.position(yaw: 0, pitch: pitch,
                                         distance: Map3DCamera.defaultDistance, target: target)
            XCTAssertGreaterThan(p.y, target.y, "มุม \(degrees)° ทำให้กล้องหลุดไปอยู่ใต้โมเดล")
        }
    }

    func testHigherPitchLiftsTheCameraAndPullsItIn() {
        let target = SIMD3<Float>(0, 0, 0)
        let low = Map3DCamera.position(yaw: 0, pitch: Map3DCamera.minPitch,
                                       distance: 2, target: target)
        let high = Map3DCamera.position(yaw: 0, pitch: Map3DCamera.maxPitch,
                                        distance: 2, target: target)
        XCTAssertGreaterThan(high.y, low.y, "เงยมากขึ้นต้องลอยสูงขึ้น")
        XCTAssertLessThan(high.z, low.z, "เงยมากขึ้นต้องเข้าใกล้แนวดิ่งเหนือเป้า")
    }

    func testDistanceIsPreservedRegardlessOfAngle() {
        let target = SIMD3<Float>(1, 2, 3)
        for pitchDegrees in [6.0, 30.0, 75.0] {
            for yawDegrees in [-55.0, 0.0, 55.0] {
                let p = Map3DCamera.position(yaw: Float(yawDegrees) * .pi / 180,
                                             pitch: Float(pitchDegrees) * .pi / 180,
                                             distance: 2.5, target: target)
                XCTAssertEqual(simd_distance(p, target), 2.5, accuracy: 1e-4)
            }
        }
    }
}
