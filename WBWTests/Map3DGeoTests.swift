import XCTest
@testable import WBW

/// แปลง lat/lng → พิกัดในหน่วยของโมเดล (เมตร Web Mercator) · ผูกกับ `Map3DConfig.Anchor`
/// ไม่ผูกกับขนาด bbox ของโมเดลอีกแล้ว — ใส่เมฆหรือต้นไม้เพิ่มในโมเดลก็ไม่ขยับจุด
final class Map3DGeoTests: XCTestCase {

    // MARK: - anchor: lat/lng → หน่วยของโมเดลตรง ๆ

    /// ค่าชุดเดียวกับ `map_config.json` — ที่มาอยู่ใน docs/superpowers/specs/2026-08-20-map-2-0-design.md §3.1
    private let anchor = Map3DConfig.Anchor(
        originLatitude: 20.04549, originLongitude: 99.90280,
        unitsPerDegreeLatitude: 118498.01, unitsPerDegreeLongitude: 111319.49,
        halfSpanUnitsEastWest: 2230, halfSpanUnitsNorthSouth: 2230,
        userDotHeightUnits: 320)

    func testOriginLandsAtModelZero() {
        let p = Map3DGeo.modelUnits(latitude: 20.04549, longitude: 99.90280, in: anchor)
        XCTAssertEqual(p?.x ?? .nan, 0, accuracy: 0.01)
        XCTAssertEqual(p?.y ?? .nan, 0, accuracy: 0.01)
    }

    /// ไปทางตะวันออกได้ x บวก ไปทางเหนือได้ y บวก — สลับเครื่องหมายเมื่อไหร่จุดจะไปโผล่
    /// ฝั่งตรงข้ามของแผนที่ ซึ่งดูเหมือน "GPS เพี้ยน" มากกว่าดูเหมือนบั๊กเรื่องแกน
    func testEastIsPositiveXAndNorthIsPositiveY() {
        let east = Map3DGeo.modelUnits(latitude: 20.04549, longitude: 99.91280, in: anchor)
        XCTAssertEqual(east?.x ?? .nan, 1113.19, accuracy: 1)
        XCTAssertEqual(east?.y ?? .nan, 0, accuracy: 1)

        let north = Map3DGeo.modelUnits(latitude: 20.05549, longitude: 99.90280, in: anchor)
        XCTAssertEqual(north?.x ?? .nan, 0, accuracy: 1)
        XCTAssertEqual(north?.y ?? .nan, 1184.98, accuracy: 1)
    }

    /// หมุดฐานที่ 5 อยู่ที่ (751.2, −112) ในไฟล์โมเดล (ตรวจด้วย usdcat) · พิกัดจริงที่ถอดได้
    /// ต้องแปลงกลับมาลงที่เดิม ไม่งั้นแปลว่าค่า anchor ชุดนี้ผิด
    func testKnownMarkerRoundTripsToItsModelPosition() {
        let p = Map3DGeo.modelUnits(latitude: 20.04454, longitude: 99.90955, in: anchor)
        XCTAssertEqual(p?.x ?? .nan, 751.2, accuracy: 6)
        XCTAssertEqual(p?.y ?? .nan, -112.0, accuracy: 6)
    }

    func testOutsideTheEventAreaReturnsNil() {
        XCTAssertNil(Map3DGeo.modelUnits(latitude: 13.7, longitude: 100.5, in: anchor),
                     "กรุงเทพอยู่นอกพื้นที่งาน — ต้องไม่มีจุดบนโมเดล")
        // เลยขอบภูมิประเทศไปหนึ่งหน่วยพอดี (2231 > halfSpan 2230) — เนื้อแผ่นตอไม้ ไม่ใช่พื้นที่งาน
        XCTAssertNil(Map3DGeo.modelUnits(latitude: 20.04549, longitude: 99.922841, in: anchor))
    }
}
