import XCTest
@testable import WBW

/// ขั้นการบานต้องตรงกับแอป Android เป๊ะ (`stageFor` ใน `ui/home/Bloom.kt`) — คนละเกณฑ์แปลว่า
/// เพื่อนสองคนที่เช็คอินเท่ากันเปิดแอปคนละเครื่องแล้วเห็นดอกไม้คนละขั้น ซึ่งอ่านว่าแอปพัง
/// ไม่ใช่ว่าดีไซน์ต่างกัน · ไม่มีอะไรใน build จับได้ถ้าเกณฑ์เพี้ยน
final class BloomStagesTests: XCTestCase {

    func testNoCheckinIsSeedNotBlank() {
        XCTAssertEqual(BloomStages.stage(checkedIn: 0, total: 12), 0,
                       "คนที่ยังไม่เช็คอินที่ไหนเลยต้องเห็นเมล็ด ไม่ใช่จอว่าง")
    }

    func testUnknownTotalFallsBackToSeed() {
        XCTAssertEqual(BloomStages.stage(checkedIn: 3, total: 0), 0,
                       "ยังไม่รู้จำนวนฐานทั้งหมด (โปรไฟล์ยังไม่มา) ต้องไม่หารด้วยศูนย์")
    }

    func testThresholdsMatchAndroid() {
        // 12 ฐาน: 1/12=8% → 1, 3/12=25% → 2, 6/12=50% → 3, 9/12=75% → 4, 11/12=92% → 5
        XCTAssertEqual(BloomStages.stage(checkedIn: 1, total: 12), 1)
        XCTAssertEqual(BloomStages.stage(checkedIn: 3, total: 12), 2)
        XCTAssertEqual(BloomStages.stage(checkedIn: 6, total: 12), 3)
        XCTAssertEqual(BloomStages.stage(checkedIn: 9, total: 12), 4)
        XCTAssertEqual(BloomStages.stage(checkedIn: 11, total: 12), 5)
    }

    func testFullProgressIsFullBloom() {
        XCTAssertEqual(BloomStages.stage(checkedIn: 12, total: 12), 5)
    }

    func testOverCountedProgressStillClamps() {
        XCTAssertEqual(BloomStages.stage(checkedIn: 99, total: 12), 5,
                       "backend เคยส่งเกินมาแล้วตอนแอดมินย้ายกลุ่ม — ห้ามหลุดออกนอกช่วง 0-5")
    }

    func testEveryStageHasALabel() {
        for s in 0..<BloomStages.count {
            XCTAssertFalse(BloomStages.label(s).isEmpty, "ขั้น \(s) ไม่มีชื่อ")
        }
        XCTAssertEqual(BloomStages.label(99), BloomStages.label(5),
                       "ขั้นที่หลุดช่วงต้องหนีบเข้าขั้นสุดท้าย ไม่ใช่คืนสตริงว่าง")
    }
}

/// เรขาคณิตของดอกไม้ถูกพอร์ตมาทั้งชุด — เทสจับเฉพาะข้อตกลงที่พังแล้วเห็นเป็นจอว่าง
/// ไม่ได้พยายามล็อกทุกพิกัด (รูปทรงถูกปรับได้ ความว่างเปล่าไม่ได้)
final class BloomGeometryTests: XCTestCase {

    private let size = CGSize(width: 220, height: 260)

    func testEveryStageDrawsSomething() {
        for s in 0..<BloomStages.count {
            let dots = BloomGeometry.build(size: size, stage: CGFloat(s), step: 6,
                                           centreYFraction: 0.38, kind: .plant)
            XCTAssertGreaterThan(dots.count, 20,
                                 "ขั้น \(s) วาดออกมาแทบไม่มีจุด — จอ Home จะดูเหมือนแอปพัง")
        }
    }

    func testSeedStageStillDrawsAHead() {
        // ขั้น 0 ไม่มีกลีบเลย เหลือแต่แกนกลาง — ถ้ากันแกนกลางไว้ที่ขั้น 1 ชิปแรกของแถบจะว่างสนิท
        // ใต้ป้ายที่เขียนว่า "เมล็ด"
        let dots = BloomGeometry.build(size: CGSize(width: 44, height: 44), stage: 0, step: 3,
                                       centreYFraction: 0.5, kind: .head)
        XCTAssertGreaterThan(dots.count, 3, "ชิปขั้นเมล็ดต้องมีอะไรให้เห็น ไม่ใช่กรอบเปล่า")
    }

    func testBloomGrowsWithStage() {
        let small = BloomGeometry.build(size: size, stage: 1, step: 6,
                                        centreYFraction: 0.38, kind: .plant).count
        let large = BloomGeometry.build(size: size, stage: 5, step: 6,
                                        centreYFraction: 0.38, kind: .plant).count
        XCTAssertGreaterThan(large, small,
                             "ดอกบานเต็มที่ต้องมีเนื้อมากกว่าดอกตูม ไม่งั้นแถบขั้นไม่ได้แสดงการเติบโต")
    }

    func testDotsStayInsideTheCanvas() {
        let dots = BloomGeometry.build(size: size, stage: 5, step: 6,
                                       centreYFraction: 0.38, kind: .plant)
        for d in dots {
            XCTAssertTrue(d.x >= -8 && d.x <= size.width + 8 && d.y >= -8 && d.y <= size.height + 8,
                          "จุดที่ (\(d.x),\(d.y)) หลุดกรอบ canvas — ดอกไม้จะล้นไปทับจอส่วนอื่น")
        }
    }

    func testEmptySizeDrawsNothingInsteadOfCrashing() {
        XCTAssertTrue(BloomGeometry.build(size: .zero, stage: 3, step: 6,
                                          centreYFraction: 0.38, kind: .plant).isEmpty,
                      "ตอน layout ยังไม่วัดขนาด canvas เป็นศูนย์ ต้องคืนลิสต์ว่าง ไม่ใช่หารด้วยศูนย์")
    }

    func testHashIsDeterministic() {
        XCTAssertEqual(BloomGeometry.hash(12.5), BloomGeometry.hash(12.5),
                       "ความไม่เท่ากันของจุดต้องมาจาก hash ไม่ใช่ตัวสุ่ม ไม่งั้นดอกไม้จะระยิบทุกเฟรม")
    }
}
