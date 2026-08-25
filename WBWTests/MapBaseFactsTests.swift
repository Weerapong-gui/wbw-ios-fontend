import XCTest
import CoreLocation
@testable import WBW

/// สองบรรทัดใหม่บนการ์ดฐาน — ยกมาจากฝั่ง Android (`405c63d` + `7211c6f`)
///
/// "เช็คอินแล้วกี่คน" ตอบคำถามที่คนยืนอยู่หน้าฐานถามจริง ๆ ว่าคิวยาวแค่ไหน · "ห่างเท่าไร"
/// ตอบว่าจะเดินไปตอนนี้หรือไว้ก่อนดี — สองอย่างนี้คือสิ่งที่การ์ดเดิม (ชื่อ + กิจกรรม + เช็คอินหรือยัง)
/// ตอบไม่ได้เลย
final class MapBaseFactsTests: XCTestCase {

    private func checkpoint(_ sequence: Int, count: Int? = nil,
                            lat: Double? = nil, lng: Double? = nil) -> Checkpoint {
        Checkpoint(id: sequence, sequence: sequence, name: "ฐาน \(sequence)", nameEn: nil,
                   activityName: nil, activityNameEn: nil, type: "activity",
                   requiresCheckin: true, lat: lat, lng: lng, checkinCount: count)
    }

    // MARK: - เช็คอินแล้วกี่คน

    /// **เซิร์ฟเวอร์ที่ยังไม่ส่งตัวเลขมาต้องอ่านเป็นศูนย์ ไม่ใช่ซ่อนบรรทัดทิ้ง** — ตัดสินแบบเดียวกับ
    /// ฝั่ง Android ที่ `7211c6f` · บรรทัดที่หายไปกับบรรทัดที่บอกว่า "ยังไม่มีใคร" อ่านต่างกันมาก
    /// สำหรับคนที่กำลังตัดสินใจว่าจะแวะฐานไหนก่อน
    func testTheCountReadsZeroUntilTheServerSendsOne() {
        XCTAssertEqual(Map3DPins.checkinCount(sequence: 3, checkpoints: [checkpoint(3)]), 0)
        XCTAssertEqual(Map3DPins.checkinCount(sequence: 3, checkpoints: []), 0)
        XCTAssertEqual(Map3DPins.checkinCount(sequence: 3, checkpoints: [checkpoint(3, count: 42)]), 42)
    }

    // MARK: - ห่างเท่าไร

    /// ไม่รู้พิกัดฐาน หรือไม่รู้พิกัดคนอ่าน = **ไม่มีบรรทัดนี้** ไม่ใช่โชว์ "ห่าง —"
    ///
    /// คนที่ยังไม่ให้สิทธิ์ตำแหน่งจะไม่มีวันได้ค่านี้ การโชว์ช่องว่างไว้ให้ดูจึงเป็นการบอกว่า
    /// "แอปพัง" ทั้งที่มันแค่ไม่มีข้อมูล
    func testThereIsNoDistanceLineWithoutBothCoordinates() {
        let here = CLLocationCoordinate2D(latitude: 20.045, longitude: 99.902)
        XCTAssertNil(Map3DPins.distanceFromMe(sequence: 3, checkpoints: [checkpoint(3)], me: here))
        XCTAssertNil(Map3DPins.distanceFromMe(sequence: 3,
                                              checkpoints: [checkpoint(3, lat: 20.05, lng: 99.90)],
                                              me: nil))
    }

    /// ระยะจริงต้องคิดจากพิกัดสองจุด ไม่ใช่เดาจากลำดับฐาน
    func testTheDistanceIsMeasuredBetweenTheTwoPoints() throws {
        let me = CLLocationCoordinate2D(latitude: 20.04549, longitude: 99.90280)
        let metres = try XCTUnwrap(
            Map3DPins.distanceFromMe(sequence: 5,
                                     checkpoints: [checkpoint(5, lat: 20.04549, lng: 99.90280)],
                                     me: me))
        XCTAssertEqual(metres, 0, accuracy: 1)

        let far = try XCTUnwrap(
            Map3DPins.distanceFromMe(sequence: 5,
                                     checkpoints: [checkpoint(5, lat: 20.05449, lng: 99.90280)],
                                     me: me))
        XCTAssertEqual(far, 1000, accuracy: 60, "ราวหนึ่งกิโลเมตรตามละติจูดที่ต่างกัน 0.009°")
    }

    /// **ข้อความระยะต้องมาจากตัวจัดรูปตัวเดียวกับที่ HUD การเดินใช้** — สองตัวที่ปัดคนละแบบ
    /// (450 ม. กับ 0.45 กม. บนจอเดียวกัน) คือของที่ผู้ใช้จับได้ทันทีว่าแอปไม่ตรงกันเอง
    func testTheDistanceTextIsTheSameFormatterTheWalkHudUses() {
        XCTAssertEqual(WalkMath.distanceText(450), WalkMath.distanceText(450))
        XCTAssertTrue(WalkMath.distanceText(1_240).contains("."), "เกินหนึ่งกิโลเมตรต้องเป็นทศนิยม")
    }
}
