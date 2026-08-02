import XCTest
import simd
@testable import WBW

/// ค่าอ้างอิงทั้งหมดอ่านจาก components/landing/trail.ts และ lib/dayCycle.ts ของเว็บ
/// (~/su-wbw-website) — ฉากในแอปต้องให้แสงชุดเดียวกับเว็บที่เวลาเดียวกัน
final class ForestMathTests: XCTestCase {

    // MARK: - ความสูงต้นไม้

    func testTreeHeightEndsMatchTheWebsiteTable() {
        // เว็บใช้ตาราง [0.7, 1.3, 2.2, 3.4, 5.0] · เราใช้สูตรที่ปลายทั้งสองตรงกัน
        XCTAssertEqual(ForestMath.treeHeight(stage: 0, total: 8), 0.7, accuracy: 0.001)
        XCTAssertEqual(ForestMath.treeHeight(stage: 8, total: 8), 5.0, accuracy: 0.001)
    }

    func testTreeHeightIsMonotonic() {
        var last = Float(0)
        for stage in 0...8 {
            let h = ForestMath.treeHeight(stage: stage, total: 8)
            XCTAssertGreaterThan(h, last, "ขั้น \(stage) ต้องสูงกว่าขั้นก่อน")
            last = h
        }
    }

    func testTreeHeightConstantRatio() {
        // อัตราส่วนคงที่ทุกขั้น = ต้นไม้โต "เท่าๆ กัน" ทุกฐาน ไม่กระโดดตอนท้าย
        let r1 = ForestMath.treeHeight(stage: 1, total: 8) / ForestMath.treeHeight(stage: 0, total: 8)
        let r7 = ForestMath.treeHeight(stage: 8, total: 8) / ForestMath.treeHeight(stage: 7, total: 8)
        XCTAssertEqual(r1, r7, accuracy: 0.001)
    }

    func testTreeHeightAdaptsToDifferentTotals() {
        // แอดมินลบฐานเหลือ 5 — ขั้นสุดท้ายยังต้องเป็นต้นโตเต็มที่
        XCTAssertEqual(ForestMath.treeHeight(stage: 5, total: 5), 5.0, accuracy: 0.001)
        XCTAssertEqual(ForestMath.treeHeight(stage: 12, total: 12), 5.0, accuracy: 0.001)
    }

    func testTreeHeightClampsOutOfRange() {
        XCTAssertEqual(ForestMath.treeHeight(stage: -3, total: 8), 0.7, accuracy: 0.001)
        XCTAssertEqual(ForestMath.treeHeight(stage: 99, total: 8), 5.0, accuracy: 0.001)
    }

    func testTreeHeightSurvivesZeroTotal() {
        // total = 0 เกิดได้ถ้าแอดมินลบฐานหมด — ห้ามหาร 0 แล้ว NaN ไปทั้งฉาก
        let h = ForestMath.treeHeight(stage: 0, total: 0)
        XCTAssertFalse(h.isNaN)
        XCTAssertEqual(h, 0.7, accuracy: 0.001)
    }

    // MARK: - เวลาของวัน

    func testDayRangeMatchesWebsiteBounds() {
        XCTAssertEqual(ForestMath.day(stage: 0, total: 8), 0.14, accuracy: 0.001)
        XCTAssertEqual(ForestMath.day(stage: 8, total: 8), 0.78, accuracy: 0.001)
        XCTAssertEqual(ForestMath.day(stage: 4, total: 8), 0.46, accuracy: 0.001)
    }

    func testDaySurvivesZeroTotal() {
        XCTAssertEqual(ForestMath.day(stage: 0, total: 0), 0.14, accuracy: 0.001)
    }

    // MARK: - สถานะดวงอาทิตย์

    func testSunStateAtKeyframesMatchesTheWebsite() {
        // p = 0.0 ก่อนฟ้าสาง
        let dawn = SunCycle.state(at: 0.0)
        XCTAssertEqual(dawn.elevation, -8, accuracy: 0.01)
        XCTAssertEqual(dawn.sunIntensity, 0.18, accuracy: 0.001)
        XCTAssertEqual(dawn.stars, 1.0, accuracy: 0.001)

        // p = 0.56 เที่ยง
        let noon = SunCycle.state(at: 0.56)
        XCTAssertEqual(noon.elevation, 58, accuracy: 0.01)
        XCTAssertEqual(noon.sunIntensity, 2.85, accuracy: 0.001)
        XCTAssertEqual(noon.stars, 0.0, accuracy: 0.001)
        XCTAssertEqual(noon.fog.x, 0.85, accuracy: 0.001)

        // p = 1.0 ตะวันลับดอย
        let dusk = SunCycle.state(at: 1.0)
        XCTAssertEqual(dusk.elevation, 2, accuracy: 0.01)
        XCTAssertEqual(dusk.sun.y, 0.46, accuracy: 0.001)
    }

    func testSunStateClampsOutsideZeroOne() {
        XCTAssertEqual(SunCycle.state(at: -5).elevation, SunCycle.state(at: 0).elevation, accuracy: 0.001)
        XCTAssertEqual(SunCycle.state(at: 7).elevation, SunCycle.state(at: 1).elevation, accuracy: 0.001)
    }

    func testSunStateInterpolatesBetweenKeys() {
        // กึ่งกลางระหว่าง p=0.36 (elev 24) และ p=0.56 (elev 58) ด้วย smoothstep(0.5) = 0.5
        let mid = SunCycle.state(at: 0.46)
        XCTAssertEqual(mid.elevation, 41, accuracy: 0.01)
    }

    func testSunDirectionIsUnitLengthAndRisesWithElevation() {
        let low = SunCycle.direction(SunCycle.state(at: 0.18))
        let high = SunCycle.direction(SunCycle.state(at: 0.56))
        XCTAssertEqual(simd_length(low), 1.0, accuracy: 0.001)
        XCTAssertEqual(simd_length(high), 1.0, accuracy: 0.001)
        XCTAssertGreaterThan(high.y, low.y, "ตอนเที่ยงดวงอาทิตย์ต้องสูงกว่าตอนเช้า")
    }

    // ทดสอบทุกฟิลด์ของทั้ง 6 keyframe เพื่อจับการแก้ไขค่าที่ผิดพลาด
    func testSunStateKeyframesAllFieldsMatchExactly() {
        let keyframes: [(p: Float, expected: SunState)] = [
            (0.00, SunState(elevation: -8, azimuth: 104,
                sun: [0.35, 0.45, 0.72], sunIntensity: 0.18,
                skyColor: [0.13, 0.18, 0.30], groundColor: [0.05, 0.09, 0.07],
                ambientIntensity: 0.40, fog: [0.07, 0.11, 0.15], fogDensity: 0.0090, stars: 1.00)),
            (0.18, SunState(elevation: 3, azimuth: 100,
                sun: [1.00, 0.55, 0.26], sunIntensity: 2.20,
                skyColor: [0.56, 0.50, 0.50], groundColor: [0.15, 0.20, 0.15],
                ambientIntensity: 0.85, fog: [0.76, 0.60, 0.45], fogDensity: 0.0072, stars: 0.22)),
            (0.36, SunState(elevation: 24, azimuth: 94,
                sun: [1.00, 0.86, 0.66], sunIntensity: 2.60,
                skyColor: [0.70, 0.80, 0.92], groundColor: [0.20, 0.30, 0.22],
                ambientIntensity: 1.15, fog: [0.80, 0.83, 0.79], fogDensity: 0.0055, stars: 0.00)),
            (0.56, SunState(elevation: 58, azimuth: 78,
                sun: [1.00, 0.98, 0.93], sunIntensity: 2.85,
                skyColor: [0.76, 0.86, 1.00], groundColor: [0.25, 0.35, 0.25],
                ambientIntensity: 1.35, fog: [0.85, 0.88, 0.86], fogDensity: 0.0045, stars: 0.00)),
            (0.79, SunState(elevation: 25, azimuth: 58,
                sun: [1.00, 0.86, 0.60], sunIntensity: 2.50,
                skyColor: [0.72, 0.78, 0.86], groundColor: [0.22, 0.30, 0.22],
                ambientIntensity: 1.05, fog: [0.86, 0.80, 0.70], fogDensity: 0.0055, stars: 0.00)),
            (1.00, SunState(elevation: 2, azimuth: 48,
                sun: [1.00, 0.46, 0.20], sunIntensity: 2.00,
                skyColor: [0.50, 0.40, 0.43], groundColor: [0.14, 0.16, 0.14],
                ambientIntensity: 0.72, fog: [0.73, 0.50, 0.38], fogDensity: 0.00725, stars: 0.18)),
        ]

        for (p, expected) in keyframes {
            let actual = SunCycle.state(at: p)
            XCTAssertEqual(actual.elevation, expected.elevation, accuracy: 0.0001, "p=\(p) field=elevation")
            XCTAssertEqual(actual.azimuth, expected.azimuth, accuracy: 0.0001, "p=\(p) field=azimuth")
            XCTAssertEqual(actual.sun.x, expected.sun.x, accuracy: 0.0001, "p=\(p) field=sun.x")
            XCTAssertEqual(actual.sun.y, expected.sun.y, accuracy: 0.0001, "p=\(p) field=sun.y")
            XCTAssertEqual(actual.sun.z, expected.sun.z, accuracy: 0.0001, "p=\(p) field=sun.z")
            XCTAssertEqual(actual.sunIntensity, expected.sunIntensity, accuracy: 0.0001, "p=\(p) field=sunIntensity")
            XCTAssertEqual(actual.skyColor.x, expected.skyColor.x, accuracy: 0.0001, "p=\(p) field=skyColor.x")
            XCTAssertEqual(actual.skyColor.y, expected.skyColor.y, accuracy: 0.0001, "p=\(p) field=skyColor.y")
            XCTAssertEqual(actual.skyColor.z, expected.skyColor.z, accuracy: 0.0001, "p=\(p) field=skyColor.z")
            XCTAssertEqual(actual.groundColor.x, expected.groundColor.x, accuracy: 0.0001, "p=\(p) field=groundColor.x")
            XCTAssertEqual(actual.groundColor.y, expected.groundColor.y, accuracy: 0.0001, "p=\(p) field=groundColor.y")
            XCTAssertEqual(actual.groundColor.z, expected.groundColor.z, accuracy: 0.0001, "p=\(p) field=groundColor.z")
            XCTAssertEqual(actual.ambientIntensity, expected.ambientIntensity, accuracy: 0.0001, "p=\(p) field=ambientIntensity")
            XCTAssertEqual(actual.fog.x, expected.fog.x, accuracy: 0.0001, "p=\(p) field=fog.x")
            XCTAssertEqual(actual.fog.y, expected.fog.y, accuracy: 0.0001, "p=\(p) field=fog.y")
            XCTAssertEqual(actual.fog.z, expected.fog.z, accuracy: 0.0001, "p=\(p) field=fog.z")
            XCTAssertEqual(actual.fogDensity, expected.fogDensity, accuracy: 0.0001, "p=\(p) field=fogDensity")
            XCTAssertEqual(actual.stars, expected.stars, accuracy: 0.0001, "p=\(p) field=stars")
        }
    }

    // ทดสอบส่วนประกอบที่มีเครื่องหมายของเวกเตอร์ทิศทาง โดยเฉพาะเครื่องหมายลบของ z
    func testSunDirectionSignedComponentsAreCorrect() {
        // p = 0.0: elevation = -8°, azimuth = 104°
        let state0 = SunCycle.state(at: 0.0)
        let dir0 = SunCycle.direction(state0)
        let e0Rad = Float(-8) * .pi / 180
        let a0Rad = Float(104) * .pi / 180
        let x0Expected = cos(e0Rad) * sin(a0Rad)
        let y0Expected = sin(e0Rad)
        let z0Expected = -cos(e0Rad) * cos(a0Rad)
        XCTAssertEqual(dir0.x, x0Expected, accuracy: 0.0001, "p=0.0 field=x (azimuth sign)")
        XCTAssertEqual(dir0.y, y0Expected, accuracy: 0.0001, "p=0.0 field=y")
        XCTAssertEqual(dir0.z, z0Expected, accuracy: 0.0001, "p=0.0 field=z (leading minus)")

        // p = 1.0: elevation = 2°, azimuth = 48°
        let state1 = SunCycle.state(at: 1.0)
        let dir1 = SunCycle.direction(state1)
        let e1Rad = Float(2) * .pi / 180
        let a1Rad = Float(48) * .pi / 180
        let x1Expected = cos(e1Rad) * sin(a1Rad)
        let y1Expected = sin(e1Rad)
        let z1Expected = -cos(e1Rad) * cos(a1Rad)
        XCTAssertEqual(dir1.x, x1Expected, accuracy: 0.0001, "p=1.0 field=x (azimuth sign)")
        XCTAssertEqual(dir1.y, y1Expected, accuracy: 0.0001, "p=1.0 field=y")
        XCTAssertEqual(dir1.z, z1Expected, accuracy: 0.0001, "p=1.0 field=z (leading minus)")
    }
}
