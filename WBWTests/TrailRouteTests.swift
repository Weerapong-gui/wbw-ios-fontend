import XCTest
import CoreLocation
@testable import WBW

/// เส้นทางเดินที่อบมากับแอป — ~5.0 กม. หลังตัดที่ทางแยกถนน 3303 (ดู `TrailRoute`)
/// ต้นทางคือ `app/src/main/res/raw/route_wbw.json` ของ repo Student-Union-WBW-Andriod
///
/// ทำไมต้องเทส: polyline ที่ถอดผิดไม่ทำให้แอปพัง มันวาดเส้นที่ **ไปโผล่กลางมหาสมุทร** แทน
/// แล้วกล้องก็ตามไปด้วย · ตัวถอดรหัสของ Google เป็นเลขฐานหกที่ต้องเลื่อนบิตทีละ 5 บิตแล้วกลับ
/// เครื่องหมายด้วย zigzag — พลาดขั้นใดขั้นหนึ่งได้ค่าที่ยัง "ดูเหมือนพิกัด" อยู่ ไม่ใช่ค่าที่พังชัด ๆ
final class TrailRouteTests: XCTestCase {

    /// ตัวอย่างมาตรฐานจากเอกสาร Encoded Polyline Algorithm ของ Google — ค่าที่ถูกต้องรู้กันอยู่แล้ว
    /// ทั้งสามจุด ใช้เป็นหมุดยึดว่าตัวถอดรหัสของเราคือของจริง ไม่ใช่ของที่บังเอิญได้ค่าสวย
    func testDecodesTheReferencePolylineFromGooglesOwnDocumentation() {
        let points = TrailRoute.decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")

        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].latitude, 38.5, accuracy: 1e-5)
        XCTAssertEqual(points[0].longitude, -120.2, accuracy: 1e-5)
        XCTAssertEqual(points[1].latitude, 40.7, accuracy: 1e-5)
        XCTAssertEqual(points[1].longitude, -120.95, accuracy: 1e-5)
        XCTAssertEqual(points[2].latitude, 43.252, accuracy: 1e-5)
        XCTAssertEqual(points[2].longitude, -126.453, accuracy: 1e-5)
    }

    /// สตริงว่างต้องได้ลิสต์ว่าง ไม่ใช่ crash — ไฟล์ที่พังจะถูกจับที่ `decode` ไม่ใช่ที่นี่
    func testEmptyPolylineDecodesToNoPoints() {
        XCTAssertTrue(TrailRoute.decodePolyline("").isEmpty)
    }

    // MARK: - ไฟล์จริงที่ไปกับแอป

    /// ไฟล์ต้องอยู่ใน bundle จริง ไม่ใช่แค่มีใน repo — ทรงเดียวกับ `Map3DConfigFileTests`
    /// ลืม `xcodegen generate` แล้วไฟล์จะไม่ถูกแพ็กเข้า .app โดยที่ build ยังผ่านปกติ
    func testShippedRouteIsInTheAppBundle() throws {
        let route = try XCTUnwrap(TrailRoute.bundled,
                                  "ไม่เจอ route_wbw.json ใน bundle — แผนที่ 2D จะไม่มีเส้นทางเลย")
        XCTAssertGreaterThan(route.coordinates.count, 100,
                             "เส้นทางที่เหลือไม่กี่จุดแปลว่าถอดรหัสหลุดกลางทาง")
        XCTAssertEqual(route.distanceMetres, 5126,
                       "ระยะทางในไฟล์เปลี่ยนไป — ถ้าอบเส้นทางใหม่จริงต้องแก้เลขนี้พร้อมกัน")
    }

    /// ทุกจุดต้องอยู่ในกรอบพื้นที่งานที่ `Map3DConfig.Anchor` กำหนด
    ///
    /// นี่คือเทสที่จับ "ไฟล์ผิดใบ" กับ "ถอดรหัสผิด" ได้พร้อมกัน — เส้นทางของงานอื่นหรือพิกัดที่
    /// เพี้ยนจะหลุดกรอบทันที ขณะที่การเทียบจำนวนจุดอย่างเดียวมองไม่เห็นอะไรเลย
    func testEveryPointFallsInsideTheEventArea() throws {
        let route = try XCTUnwrap(TrailRoute.bundled)
        let anchor = Map3DConfig.current.anchor

        let outside = route.coordinates.filter {
            Map3DGeo.modelUnits(latitude: $0.latitude, longitude: $0.longitude, in: anchor) == nil
        }
        XCTAssertTrue(outside.isEmpty,
                      "มี \(outside.count) จุดอยู่นอกพื้นที่งาน — จุดแรกคือ \(outside.first as Any)")
    }

    /// **เส้นทางต้องจบที่ทางแยก ชร.3303 ไม่ใช่วิ่งต่อไปทางตะวันตก**
    ///
    /// แทร็กเต็มชุดเก่าของผู้จัดงานมี 750 จุดและไปจบหลัง มฟล. (20.04570, 99.89137) · ชุดที่ส่งไป
    /// กับแอปจบที่ทางแยกตามที่ Park ชี้บนแผนที่เมื่อ 2026-08-24 · เทสนี้คือตัวกันไม่ให้ใครเอา
    /// ไฟล์เส้นเต็มมาทับแล้วหางกลับมาเงียบ ๆ — เทสจำนวนจุด "> 100" ผ่านทั้งสองแบบ จับไม่ได้
    ///
    /// **อัปเดต 2026-08-25:** ยกไฟล์ชุดใหม่จาก branch `work` ของ Android (`newroute.gpx` ของ
    /// ผู้จัดงาน คนละลิงก์ Google Maps กับ `route.gpx` เดิม) — หัวท้ายตรงกับชุดเดิมพอดี
    /// ต่างกันที่ทางช่วงกลาง จึงเป็น 504 จุด 5,126 ม. · หมุดฐานทั้งแปดยังห่างจากเส้นเท่าเดิมทุกหมุด
    func testRouteEndsAtTheJunctionNotAtTheOldWesternTail() throws {
        let route = try XCTUnwrap(TrailRoute.bundled)
        XCTAssertEqual(route.end.latitude, 20.05671, accuracy: 1e-5)
        XCTAssertEqual(route.end.longitude, 99.90875, accuracy: 1e-5)
        XCTAssertEqual(route.coordinates.count, 504,
                       "จำนวนจุดเปลี่ยน — ถ้าอบเส้นใหม่จริงต้องแก้เลขนี้กับ distanceMetres พร้อมกัน")
    }

    /// จุดเริ่ม/จุดจบคือหัวกับท้ายของเส้น ไม่ใช่จุดที่ใครมาเลือกทีหลัง — หมุด START/FINISH
    /// บนแผนที่อ่านจากสองค่านี้
    func testStartAndEndAreTheFirstAndLastPointsOfThePath() throws {
        let route = try XCTUnwrap(TrailRoute.bundled)
        XCTAssertEqual(route.start.latitude, route.coordinates.first?.latitude)
        XCTAssertEqual(route.start.longitude, route.coordinates.first?.longitude)
        XCTAssertEqual(route.end.latitude, route.coordinates.last?.latitude)
        XCTAssertEqual(route.end.longitude, route.coordinates.last?.longitude)
    }

    /// กรอบกล้องตอนเปิดแผนที่ต้องครอบเส้นทั้งเส้น — กรอบที่แคบไปคือเปิดมาแล้วเห็นเส้นครึ่งเดียว
    /// โดยไม่มีอะไรบอกว่าที่เหลืออยู่นอกจอ
    func testRegionCoversEveryPointOnThePath() throws {
        let route = try XCTUnwrap(TrailRoute.bundled)
        let region = route.region

        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2

        for point in route.coordinates {
            XCTAssertTrue((minLat...maxLat).contains(point.latitude), "จุด \(point) หลุดกรอบแนวเหนือใต้")
            XCTAssertTrue((minLon...maxLon).contains(point.longitude), "จุด \(point) หลุดกรอบแนวออกตก")
        }
    }
}
