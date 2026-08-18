import XCTest
import CoreLocation
@testable import WBW

/// เส้นทางเดินถูก bake ไว้เป็นไฟล์ในแอป ไม่ได้ยิงขอจาก routing service ตอนรัน — ทั้งเพื่อไม่ต้องมีเน็ต
/// บนดอย และเพื่อไม่ให้เปลืองโควตา API · ไฟล์ `WBW/Resources/route_wbw.json` เป็นไฟล์เดียวกับที่แอป
/// Android ใช้ (`app/src/main/res/raw/route_wbw.json`) สองแอปจะได้ลากเส้นเดียวกันเป๊ะ
///
/// เทสตัวถอดรหัสเป็นหลัก เพราะ polyline ของ Google เป็นรูปแบบที่ผิดนิดเดียวแล้วได้เส้นที่ยังลากได้
/// แต่ไปโผล่คนละซีกโลก — ไม่มี error ให้เห็น มีแต่แผนที่ที่ว่างเปล่าเพราะกล้องไปจ่ออยู่กลางทะเล
final class TrailRouteTests: XCTestCase {

    /// ตัวอย่างมาตรฐานจากเอกสาร Encoded Polyline Algorithm ของ Google
    func testDecodesGoogleReferenceVector() {
        let points = TrailRoute.decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].latitude, 38.5, accuracy: 0.00001)
        XCTAssertEqual(points[0].longitude, -120.2, accuracy: 0.00001)
        XCTAssertEqual(points[2].latitude, 43.252, accuracy: 0.00001)
        XCTAssertEqual(points[2].longitude, -126.453, accuracy: 0.00001)
    }

    func testEmptyStringDecodesToNothing() {
        XCTAssertTrue(TrailRoute.decodePolyline("").isEmpty,
                      "สตริงว่างต้องได้ลิสต์ว่าง ไม่ใช่ค้างในลูปหรือคืนจุด (0,0)")
    }

    // MARK: - ไฟล์จริงในแอป

    func testBundledRouteLoads() throws {
        let route = try XCTUnwrap(TrailRoute.bundled,
                                  "โหลด route_wbw.json ไม่ได้ — เช็คว่าไฟล์อยู่ใน sources ของ target หลัง xcodegen generate")
        XCTAssertEqual(route.distanceMetres, 8358,
                       "ระยะรวมของเส้นทางต้องตรงกับที่ Android โชว์ ไม่งั้นสองแอปบอกคนละตัวเลข")
        XCTAssertEqual(route.points.count, 750)
    }

    func testBundledRouteStaysInsideEventArea() throws {
        let route = try XCTUnwrap(TrailRoute.bundled)
        let area = Map3DGeo.eventArea
        for p in route.points {
            XCTAssertTrue(p.latitude >= area.south && p.latitude <= area.north
                          && p.longitude >= area.west && p.longitude <= area.east,
                          "จุด \(p.latitude),\(p.longitude) หลุดกรอบพื้นที่งาน — เส้นทางกับแผนที่ 3D คนละที่กันแล้ว")
        }
    }

    func testStartAndFinishAreDistinct() throws {
        let route = try XCTUnwrap(TrailRoute.bundled)
        let start = try XCTUnwrap(route.start)
        let finish = try XCTUnwrap(route.finish)
        XCTAssertGreaterThan(
            CLLocation(latitude: start.latitude, longitude: start.longitude)
                .distance(from: CLLocation(latitude: finish.latitude, longitude: finish.longitude)),
            50,
            "หมุดเริ่มกับหมุดจบต้องห่างกันพอให้เห็นเป็นสองหมุด ไม่ใช่ทับกันจนดูเหมือนมีหมุดเดียว")
    }
}
