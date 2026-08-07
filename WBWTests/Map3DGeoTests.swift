import XCTest
@testable import WBW

/// แปลง lat/lng → พิกัดบนโมเดล · โมเดลกินพื้นที่ -1…1 ทั้งสองแกนหลังถูกย่อให้พอดีกรอบ
final class Map3DGeoTests: XCTestCase {

    private let bounds = Map3DGeo.Bounds(south: 20.0, west: 99.0, north: 21.0, east: 100.0)

    func testCenterLandsAtOrigin() {
        let p = Map3DGeo.modelPoint(latitude: 20.5, longitude: 99.5, in: bounds)
        XCTAssertEqual(p?.x ?? .nan, 0, accuracy: 0.01)
        XCTAssertEqual(p?.y ?? .nan, 0, accuracy: 0.01)
    }

    func testSouthWestCornerLandsAtMinusOne() {
        let p = Map3DGeo.modelPoint(latitude: 20.0, longitude: 99.0, in: bounds)
        XCTAssertEqual(p?.x ?? .nan, -1, accuracy: 0.01)
        XCTAssertEqual(p?.y ?? .nan, -1, accuracy: 0.01)
    }

    func testNorthEastCornerLandsAtPlusOne() {
        let p = Map3DGeo.modelPoint(latitude: 21.0, longitude: 100.0, in: bounds)
        XCTAssertEqual(p?.x ?? .nan, 1, accuracy: 0.01)
        XCTAssertEqual(p?.y ?? .nan, 1, accuracy: 0.01)
    }

    func testOutsideBoundsReturnsNil() {
        XCTAssertNil(Map3DGeo.modelPoint(latitude: 13.7, longitude: 100.5, in: bounds),
                     "กรุงเทพอยู่นอกพื้นที่งาน — ต้องไม่มีจุดบนโมเดล")
        XCTAssertNil(Map3DGeo.modelPoint(latitude: 20.5, longitude: 98.9, in: bounds))
    }

    func testEventAreaIsAWellFormedBox() {
        XCTAssertLessThan(Map3DGeo.eventArea.south, Map3DGeo.eventArea.north)
        XCTAssertLessThan(Map3DGeo.eventArea.west, Map3DGeo.eventArea.east)
    }
}
