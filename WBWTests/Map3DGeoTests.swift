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
        // เลยขอบภูมิประเทศไปนิดเดียว (x = 2230.95 เทียบ halfSpan 2230) — เนื้อแผ่นตอไม้
        // ไม่ใช่พื้นที่งาน · จงใจให้เฉียดขอบ จะได้จับได้ถ้ามีใครเผลอเปลี่ยนเส้นแบ่งไปไกลกว่านี้
        XCTAssertNil(Map3DGeo.modelUnits(latitude: 20.04549, longitude: 99.922841, in: anchor))
    }

    /// ขอบพอดีเป๊ะต้องนับว่า "อยู่ใน" — เงื่อนไขเป็น `<=` ไม่ใช่ `<`
    ///
    /// ไม่มีอะไรบนจอฟ้องว่าเส้นแบ่งเป็นแบบไหน คนที่ยืนริมพื้นที่งานพอดีจะเห็นจุดตัวเองหายไปเฉย ๆ
    /// ถ้าวันหลังมีคนแก้เป็น `<` · ตรึงค่าขอบ (halfSpan 2230.0) ไว้ด้วยเทส แทนที่จะปล่อยให้เป็น
    /// ผลพลอยได้ของเครื่องหมายที่บังเอิญพิมพ์ไว้
    func testTheExactHalfSpanBoundaryIsInside() throws {
        let onTheEdge = anchor.originLongitude
            + anchor.halfSpanUnitsEastWest / anchor.unitsPerDegreeLongitude
        let p = try XCTUnwrap(
            Map3DGeo.modelUnits(latitude: anchor.originLatitude, longitude: onTheEdge, in: anchor),
            "ลองจิจูดที่ให้ x = halfSpan (2230.0) พอดีต้องยังอยู่ในพื้นที่งาน")
        XCTAssertEqual(p.x, 2230, accuracy: 0.01)
        XCTAssertEqual(p.y, 0, accuracy: 0.01)
    }

    // MARK: - ผกผัน: หน่วยของโมเดล → lat/lng

    /// ใช้ตอนเอาตำแหน่งหมุดที่ปักไว้ในโมเดลไปวางบนแผนที่ 2 มิติ — ทิศทางกลับของทั้งไฟล์นี้
    ///
    /// ต้องเป็นผกผันของ `modelUnits` เป๊ะ ไม่ใช่สูตรที่เขียนแยกกันแล้วบังเอิญใกล้เคียง: หมุดที่
    /// เพี้ยนไป 100 ม.บนแผนที่ดาวเทียมคือหมุดที่ไปตกอยู่คนละฝั่งถนน ซึ่งดูเหมือนข้อมูลผิด
    /// มากกว่าดูเหมือนเลขคณิตผิด
    func testModelUnitsInvertBackToTheSameCoordinate() {
        let base5 = Map3DGeo.coordinate(x: 751.2, y: -112.0, in: anchor)
        XCTAssertEqual(base5.latitude, 20.04454, accuracy: 1e-4)
        XCTAssertEqual(base5.longitude, 99.90955, accuracy: 1e-4)
    }

    func testOriginInvertsToTheAnchorCoordinate() {
        let origin = Map3DGeo.coordinate(x: 0, y: 0, in: anchor)
        XCTAssertEqual(origin.latitude, anchor.originLatitude, accuracy: 1e-9)
        XCTAssertEqual(origin.longitude, anchor.originLongitude, accuracy: 1e-9)
    }

    /// ไป-กลับแล้วต้องได้ที่เดิม — จับกรณีที่คนแก้ตัวหนึ่งแล้วลืมแก้อีกตัว
    func testRoundTripThroughBothDirectionsLandsWhereItStarted() throws {
        for (latitude, longitude) in [(20.04155, 99.89656), (20.05533, 99.90914), (20.03498, 99.90004)] {
            let point = try XCTUnwrap(
                Map3DGeo.modelUnits(latitude: latitude, longitude: longitude, in: anchor))
            let back = Map3DGeo.coordinate(x: point.x, y: point.y, in: anchor)
            XCTAssertEqual(back.latitude, latitude, accuracy: 1e-4)
            XCTAssertEqual(back.longitude, longitude, accuracy: 1e-4)
        }
    }
}
