import XCTest
import MapKit
@testable import WBW

/// กรอบแผนที่ในการ์ดเคส — ส่วนเดียวของงานนี้ที่มีตรรกะจริง
///
/// เจ้าหน้าที่อ่านแผนที่นี้ตอนกำลังจะวิ่งไปหาผู้บาดเจ็บ · ซูมผิดทางไหนก็ใช้ไม่ได้ทั้งคู่:
/// แน่นเกินไปเห็นแค่ทางเท้าไม่รู้ว่าอยู่ตรงไหนของเขา กว้างเกินไปหมุดกลายเป็นจุดเดียวไร้ความหมาย
final class SOSCaseMapTests: XCTestCase {

    /// ระยะที่ span หนึ่งองศาละติจูดกินจริง — ใช้แปลงกลับเป็นเมตรเพื่อตรวจ
    private let metresPerDegreeLat = 111_320.0
    private let lat = 20.04549
    private let lng = 99.90280

    private func spanMetres(_ r: MKCoordinateRegion) -> (ns: Double, ew: Double) {
        (r.span.latitudeDelta * metresPerDegreeLat,
         r.span.longitudeDelta * metresPerDegreeLat * cos(lat * .pi / 180))
    }

    /// พิกัดแม่นมากต้องไม่ซูมจนเห็นแค่ทางเท้า — เจ้าหน้าที่ต้องเห็นบริบทรอบตัวว่าอยู่ตรงไหนของเส้นทาง
    func testAVeryAccurateFixStillShowsTheSurroundings() {
        let r = SOSCaseMap.region(lat: lat, lng: lng, accuracyM: 3)
        let m = spanMetres(r)
        // ขอบล่างวัดจากจอจริง — ต่ำกว่านี้พื้นที่งานเป็นป่าเปล่าไม่มีที่หมายให้เทียบเลย
        // (ดูคอมเมนต์ที่ `SOSCaseMap.minSpanMetres`)
        XCTAssertGreaterThan(m.ns, 300, "แน่นเกินไป (\(Int(m.ns)) ม.) — ป่าเปล่าไม่มีที่หมาย")
        XCTAssertLessThan(m.ns, 900)
    }

    /// ไม่รู้ความแม่นเลย (`accuracyM` เป็น nil) ต้องได้กรอบพื้นล่าง ไม่ใช่กรอบศูนย์หรือค่า NaN
    func testUnknownAccuracyFallsBackToTheFloorNotToZero() {
        let r = SOSCaseMap.region(lat: lat, lng: lng, accuracyM: nil)
        let m = spanMetres(r)
        XCTAssertGreaterThan(m.ns, 300)
        XCTAssertFalse(m.ns.isNaN)
    }

    /// **กรอบต้องครอบวงความคลาดเคลื่อนได้จริง** ไม่งั้นวงที่วาดจะล้นออกนอกจอแล้วเจ้าหน้าที่
    /// เห็นแค่ส่วนหนึ่งของมัน ซึ่งอ่านผิดเป็น "อยู่ในบริเวณนี้" ทั้งที่จริงกว้างกว่าที่เห็น
    func testTheFrameContainsTheWholeAccuracyCircle() {
        for accuracy in [250.0, 500.0, 900.0] {
            let m = spanMetres(SOSCaseMap.region(lat: lat, lng: lng, accuracyM: accuracy))
            XCTAssertGreaterThan(m.ns, accuracy * 2,
                                 "±\(Int(accuracy)) ม. วงกว้าง \(Int(accuracy * 2)) ม. แต่กรอบแค่ \(Int(m.ns)) ม.")
            XCTAssertGreaterThan(m.ew, accuracy * 2)
        }
    }

    /// พิกัดหยาบมากต้องไม่ซูมออกจนเห็นทั้งจังหวัด — เลยจุดหนึ่งแผนที่ก็ไม่ช่วยอะไรแล้ว
    /// ข้อความ "พิกัดหยาบ อย่าเชื่อฐานที่ระบบเดา" บนการ์ดต่างหากที่ทำหน้าที่นั้น
    func testAHopelesslyCoarseFixIsCappedNotZoomedToTheProvince() {
        let m = spanMetres(SOSCaseMap.region(lat: lat, lng: lng, accuracyM: 20_000))
        XCTAssertLessThan(m.ns, 4_000, "กว้างเกินไป (\(Int(m.ns)) ม.) หมุดไร้ความหมายไปแล้ว")
    }

    /// ความแม่นแย่ลง กรอบต้องไม่เล็กลง — ไล่ทีละขั้นไม่ใช่เช็คแค่สองปลาย
    func testTheFrameNeverShrinksAsAccuracyGetsWorse() {
        var previous = 0.0
        for accuracy in stride(from: 0.0, through: 2_000.0, by: 50.0) {
            let ns = spanMetres(SOSCaseMap.region(lat: lat, lng: lng, accuracyM: accuracy)).ns
            XCTAssertGreaterThanOrEqual(ns, previous - 0.001, "±\(Int(accuracy)) ม. กรอบเล็กลง")
            previous = ns
        }
    }

    /// กรอบต้องอยู่ตรงกลางที่จุดเกิดเหตุจริง
    func testTheFrameIsCentredOnTheCase() {
        let r = SOSCaseMap.region(lat: lat, lng: lng, accuracyM: 40)
        XCTAssertEqual(r.center.latitude, lat, accuracy: 0.000001)
        XCTAssertEqual(r.center.longitude, lng, accuracy: 0.000001)
    }

    /// **หนึ่งองศาลองจิจูดสั้นกว่าหนึ่งองศาละติจูด** ที่ 20°N ราว 6% — ลืมหารด้วย cos(lat)
    /// แล้วกรอบจะแคบไปตามแนวตะวันออก-ตะวันตก และวงความคลาดเคลื่อนจะล้นออกสองข้าง
    /// (หลักการเดียวกับที่ `Map3DGeo` ใช้)
    func testLongitudeSpanIsWidenedForTheLatitude() {
        let r = SOSCaseMap.region(lat: lat, lng: lng, accuracyM: 300)
        XCTAssertGreaterThan(r.span.longitudeDelta, r.span.latitudeDelta,
                             "องศาลองจิจูดต้องมากกว่าละติจูดเพื่อให้ระยะจริงเท่ากัน")
    }

    // MARK: - ลิงก์ Apple Maps

    /// สตริงนี้เคยถูกเขียนซ้ำสองที่ (`StaffSOSView`, `SOSFriendView`) — รวมมาที่เดียวแล้ว
    /// ต้องยังคืน URL ที่ใช้ได้จริง ไม่ใช่ nil เงียบ ๆ ซึ่งจะทำให้ปุ่ม "เปิดแผนที่" หายไปทั้งปุ่ม
    func testAppleMapsLinkCarriesTheCoordinates() throws {
        let url = try XCTUnwrap(SOSMapLink.appleMaps(lat: lat, lng: lng))
        XCTAssertEqual(url.scheme, "maps")
        XCTAssertTrue(url.absoluteString.contains("20.04549"))
        XCTAssertTrue(url.absoluteString.contains("99.9028"))
    }
}
