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
}
