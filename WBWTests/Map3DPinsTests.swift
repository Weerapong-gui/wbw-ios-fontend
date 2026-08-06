import XCTest
@testable import WBW

/// หมุดฐานบนโมเดลแผนที่ — ตารางจับคู่ prim กับลำดับฐาน และข้อความบนการ์ด
final class Map3DPinsTests: XCTestCase {

    func testTableCoversEightPinsWithNoDuplicates() {
        XCTAssertEqual(Map3DPins.entityNames.count, 8, "โมเดลมีแท่งแดง 8 แท่ง")
        XCTAssertEqual(Set(Map3DPins.entityNames).count, 8, "ชื่อ prim ห้ามซ้ำ")
    }

    func testSequenceLookupMatchesTableOrder() {
        XCTAssertEqual(Map3DPins.sequence(forEntityNamed: Map3DPins.entityNames[0]), 1)
        XCTAssertEqual(Map3DPins.sequence(forEntityNamed: Map3DPins.entityNames[7]), 8)
    }

    func testUnknownEntityHasNoSequence() {
        XCTAssertNil(Map3DPins.sequence(forEntityNamed: "Buildings"))
    }

    func testLabelUsesRealNameWhenCheckedIn() {
        let item = CheckinProgressItem(checkpointId: 12, name: "ฐานผาหมี", activityName: nil,
                                       sequence: 3, at: "2026-08-07T01:00:00Z",
                                       answered: false, rating: nil, comment: nil)
        XCTAssertEqual(Map3DPins.label(sequence: 3, checkedIn: [item]), "ฐานผาหมี")
    }

    func testLabelFallsBackToNumberWhenNotCheckedInYet() {
        // ชื่อฐานที่ยังไม่เช็คอิน backend ไม่ได้ส่งมาให้ participant เลย — ห้ามเดาชื่อ
        XCTAssertEqual(Map3DPins.label(sequence: 5, checkedIn: []), "ฐานที่ 5")
    }

    func testLabelFallsBackWhenCheckedInRowHasNoSequence() {
        let item = CheckinProgressItem(checkpointId: 12, name: "ฐานผาหมี", activityName: nil,
                                       sequence: nil, at: "2026-08-07T01:00:00Z",
                                       answered: false, rating: nil, comment: nil)
        XCTAssertEqual(Map3DPins.label(sequence: 3, checkedIn: [item]), "ฐานที่ 3")
    }
}
