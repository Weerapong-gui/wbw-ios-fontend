import CoreLocation
import XCTest
@testable import WBW

/// เรขาคณิตของความคืบหน้าบนเส้นทาง — ส่วนเดียวของการเดินที่ตรวจด้วยตาบนจอไม่ได้
/// (ทางเลือกคือเดินจริงห้ากิโลพร้อม debugger) · ยกเคสมาจาก `TrailRouteProgressTest.kt`
/// ของ Android ทั้งชุด ให้สองแอปถือสัญญาเดียวกัน
///
/// fixture เป็นเส้นสังเคราะห์ ไม่ใช่ GPX จริง — เส้นตรงกับสี่เหลี่ยมที่รู้ขนาดทำให้คำตอบ
/// ที่คาดเป็นเลขคณิต ไม่ใช่ "แล้วแต่ track จะทำอะไรแถวจุดที่ 412" · ทุกคุณสมบัติที่เทส
/// (monotonic, ตัด off-route, แก้ความกำกวมของ loop) เป็นเรื่องของอัลกอริทึม ไม่ใช่เส้นของงาน
final class TrailRouteProgressTests: XCTestCase {

    /// เมตรต่อองศาละติจูด — ค่าเดียวกับใน TrailRoute
    private let mPerDeg = 111_320.0

    /// เส้นตรงขึ้นเหนือจากศูนย์สูตร ยาว [metres] จุดทุก 10 ม.
    private func straightRoute(_ metres: Double) -> TrailRoute {
        let step = 10.0
        let n = Int(metres / step) + 1
        let points = (0..<n).map {
            CLLocationCoordinate2D(latitude: Double($0) * step / mPerDeg, longitude: 0)
        }
        return TrailRoute(coordinates: points, distanceMetres: Int(metres))
    }

    /// ตำแหน่งเหนือขึ้นไป [north] ม. และออกข้าง [east] ม. (ใกล้ศูนย์สูตร cos(lat) ≈ 1)
    private func at(north: Double, east: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: north / mPerDeg, longitude: east / mPerDeg)
    }

    func testFirstFixAcquiresAnywhereOnTheRoute() {
        let route = straightRoute(1_000)
        // ค่าติดลบ = ไม่มีตำแหน่งก่อนหน้า — คนอาจมาเริ่มกลางเส้นก็ได้
        let p = route.progressFrom(-1, coordinate: at(north: 400, east: 0))
        XCTAssertNotNil(p)
        XCTAssertEqual(p!, 400, accuracy: 15)
    }

    func testProgressAdvancesAsTheWalkerMovesAlongTheLine() {
        let route = straightRoute(1_000)
        var m = -1.0
        for target in [100.0, 250, 600, 900] {
            m = route.progressFrom(m, coordinate: at(north: target, east: 0))!
            XCTAssertEqual(m, target, accuracy: 15)
        }
    }

    func testAPositionOffTheTrailReportsNothingRatherThanAWrongNumber() {
        let route = straightRoute(1_000)
        // ออกข้าง 300 ม. เกินเกณฑ์ 120 ม. ไปไกล — ต้องได้ nil ให้ผู้เรียกถือค่าเดิม
        // ไม่ใช่เลขผิด ๆ ที่ลากเส้นบนจอไปมั่ว
        XCTAssertNil(route.progressFrom(400, coordinate: at(north: 400, east: 300)))
    }

    func testJitterBackwardsDoesNotDragProgressDown() {
        let route = straightRoute(1_000)
        let settled = route.progressFrom(-1, coordinate: at(north: 500, east: 0))!
        // fix ถอยหลังไม่กี่เมตร — GPS สั่นตามปกติ ไม่ใช่คนหันหลังเดินกลับ
        let after = route.progressFrom(settled, coordinate: at(north: 492, east: 0))!
        XCTAssertGreaterThanOrEqual(after, settled, "เส้นบนจอห้ามกระตุกถอยเพราะ noise ระดับเมตร")
    }

    /// เคสที่หน้าต่างค้นหามีไว้แก้: ปลาย loop เฉียดจุดเริ่มของตัวเอง — nearest-point ล้วน ๆ
    /// จะรีเซ็ตคนที่เกือบจบกลับไปศูนย์
    func testNearTheEndOfALoopProgressDoesNotSnapBackToTheStart() {
        // สี่เหลี่ยมด้านละ 400 ม. วนกลับมาห่างจุดเริ่ม 20 ม.
        let side = 400.0
        var pts: [CLLocationCoordinate2D] = []
        var d = 0.0
        while d <= side { pts.append(at(north: d, east: 0)); d += 10 }          // ขึ้นเหนือ
        d = 0
        while d <= side { pts.append(at(north: side, east: d)); d += 10 }       // ไปตะวันออก
        d = side
        while d >= 0 { pts.append(at(north: d, east: side)); d -= 10 }          // ลงใต้
        d = side
        while d >= 20 { pts.append(at(north: 0, east: d)); d -= 10 }            // ย้อนตะวันตก
        let route = TrailRoute(coordinates: pts, distanceMetres: 1_580)

        let nearEnd = route.lengthMetres - 30
        let last = pts.last!
        let m = route.progressFrom(nearEnd, coordinate: last)
        XCTAssertNotNil(m)
        XCTAssertGreaterThan(m!, route.lengthMetres - 100,
                             "เกือบจบแล้วโดนดีดกลับไปจุดเริ่ม: \(m!) จาก \(route.lengthMetres)")
    }

    func testSplitAtCutsTheRouteIntoTwoHalvesThatMeet() {
        let route = straightRoute(1_000)
        let (walked, remaining) = route.splitAt(400)
        XCTAssertGreaterThanOrEqual(walked.count, 2)
        XCTAssertGreaterThanOrEqual(remaining.count, 2)
        // จุดตัดเป็นของทั้งสองท่อน — เส้นที่วาดต้องชนกันพอดี ไม่ใช่ช่องว่างที่กว้างตามความยาว segment
        XCTAssertEqual(walked.last!.latitude, remaining.first!.latitude, accuracy: 1e-9)
        XCTAssertEqual(walked.last!.longitude, remaining.first!.longitude, accuracy: 1e-9)
        XCTAssertEqual(walked.last!.latitude * mPerDeg, 400, accuracy: 15)
    }

    func testSplitAtClampsAtBothEndsInsteadOfCrashing() {
        let route = straightRoute(1_000)
        let (noneWalked, allLeft) = route.splitAt(-50)
        XCTAssertGreaterThanOrEqual(allLeft.count, 2)
        XCTAssertEqual(noneWalked.last!.latitude * mPerDeg, 0, accuracy: 1)

        let (allWalked, noneLeft) = route.splitAt(5_000)
        XCTAssertGreaterThanOrEqual(allWalked.count, 2)
        XCTAssertEqual(allWalked.last!.latitude * mPerDeg, 1_000, accuracy: 15)
        XCTAssertLessThanOrEqual(noneLeft.count, 2)
    }

    /// เส้นจริงของงานต้องมีความยาวใกล้เคียงตัวเลขในไฟล์ — ถ้าห่างกันมากแปลว่า projection ผิด
    func testBundledRouteLengthAgreesWithItsOwnFile() throws {
        let route = try XCTUnwrap(TrailRoute.bundled, "เส้นทางของงานต้องอ่านได้จาก bundle")
        XCTAssertEqual(route.lengthMetres, Double(route.distanceMetres), accuracy: 30,
                       "ความยาวจาก projection ต้องตรงกับตัวเลขใน route_wbw.json ระดับไม่กี่สิบเมตร")
    }
}
