import XCTest
@testable import WBW

/// หมุดฐานบนโมเดลแผนที่ — ตารางจับคู่ prim กับลำดับฐาน และข้อความบนการ์ด
final class Map3DPinsTests: XCTestCase {

    func testTableCoversEightPinsWithNoDuplicates() {
        XCTAssertEqual(Map3DConfig.current.pins.count, 8, "งานมีแปดฐาน")
        XCTAssertEqual(Map3DPins.entityNames.count, 16,
                       "ฐานละสองชื่อ — ตัวแท่งกับเลขที่ปั้นติดหมุด")
        XCTAssertEqual(Set(Map3DPins.entityNames).count, 16,
                       "ชื่อซ้ำข้ามฐาน แปลว่าสองฐานชี้ prim เดียวกัน")
    }

    /// เลขที่ปั้นติดหมุดเป็น prim **พี่น้อง** ของแท่ง ไม่ใช่ลูก — ตัวไต่หาพ่อใน Map3DScreen
    /// ไต่จากเลขแล้วจะไปสุดที่ root ไม่เจอฐาน คนแตะเลขที่เห็นชัดที่สุดบนจอแล้วเงียบสนิท
    func testBothTheMarkerAndItsNumberResolveToTheSameBase() {
        XCTAssertEqual(Map3DPins.sequence(forEntityNamed: "marker_5"), 5)
        XCTAssertEqual(Map3DPins.sequence(forEntityNamed: "markerNum_5"), 5)
    }

    /// กล้องต้องบินไปจ้องตัวแท่ง ไม่ใช่เลขที่ลอยอยู่สูงกว่า ไม่งั้นเฟรมสุดท้ายเป็นภาพกลางอากาศ
    func testPrimaryEntityIsTheMarkerNotTheNumber() {
        XCTAssertEqual(Map3DPins.primaryEntityName(for: 5), "marker_5")
        XCTAssertNil(Map3DPins.primaryEntityName(for: 99))
    }

    func testUnknownEntityHasNoSequence() {
        XCTAssertNil(Map3DPins.sequence(forEntityNamed: "Buildings"))
        XCTAssertNil(Map3DPins.sequence(forEntityNamed: "stumpBase"))
    }

    // MARK: - แหล่งชื่อฐาน

    /// ชื่อมาจากรายการฐาน ไม่ใช่จาก progress — **นี่คือจุดประสงค์ทั้งหมดของ GET /wbw/checkpoints**
    /// ฐานที่ยังไม่ได้ไปก็ต้องมีชื่อจริง ไม่ใช่ "ฐานที่ N"
    func testLabelUsesTheCheckpointListEvenWhenNotCheckedIn() {
        defer { Loc.use(.system) }
        Loc.use(.th)
        let list = [Checkpoint(id: 7, sequence: 7, name: "ฐานผ้าใบ", nameEn: "Canvas Base",
                               activityName: "ผ้าใบเขียนความรู้สึก", activityNameEn: "Feelings canvas",
                               type: "activity", requiresCheckin: true)]
        XCTAssertEqual(Map3DPins.label(sequence: 7, checkedIn: [], checkpoints: list), "ฐานผ้าใบ")
        XCTAssertEqual(Map3DPins.activity(sequence: 7, checkedIn: [], checkpoints: list),
                       "ผ้าใบเขียนความรู้สึก")
    }

    /// ตั้งแอปเป็นอังกฤษแล้วต้องได้ชื่ออังกฤษ — เดิมเห็นชื่อไทยทั้งหมดเพราะ /me/progress ไม่มีฟิลด์ _en
    func testLabelFollowsTheInAppLanguage() {
        defer { Loc.use(.system) }
        Loc.use(.en)
        let list = [Checkpoint(id: 5, sequence: 5, name: "จุดปลูก", nameEn: "Planting Point",
                               activityName: "ปลูกป่า", activityNameEn: "Tree planting",
                               type: "activity", requiresCheckin: true)]
        XCTAssertEqual(Map3DPins.label(sequence: 5, checkedIn: [], checkpoints: list), "Planting Point")
    }

    /// ยังไม่เคยดึงรายการฐานสำเร็จและไม่มีแคช = **ไม่รู้จริง ๆ** ต้องขึ้น "ฐานที่ N" ไม่ใช่เดาชื่อ
    func testLabelFallsBackToNumberWhenNothingIsKnownYet() {
        XCTAssertEqual(Map3DPins.label(sequence: 6, checkedIn: [], checkpoints: []),
                       String(format: Loc.t("map_base_number"), 6))
        XCTAssertNil(Map3DPins.activity(sequence: 6, checkedIn: [], checkpoints: []))
    }

    /// เครื่องที่เพิ่งอัปเดตแอปแล้วยังไม่ได้ต่อเน็ตเลยสักครั้งมีแต่แคชเก่าของ progress —
    /// ยังต้องได้ชื่อฐานที่เคยไปมาแล้ว ไม่ใช่ถอยไปเป็นเลขทั้งแผนที่
    func testLabelStillFallsBackToProgressWhenTheListIsEmpty() {
        let item = CheckinProgressItem(checkpointId: 12, name: "ฐานผาหมี", activityName: nil,
                                       sequence: 3, at: "2026-08-07T01:00:00Z",
                                       answered: false, rating: nil, comment: nil)
        XCTAssertEqual(Map3DPins.label(sequence: 3, checkedIn: [item], checkpoints: []), "ฐานผาหมี")
    }

    func testLabelUsesRealNameWhenCheckedIn() {
        let item = CheckinProgressItem(checkpointId: 12, name: "ฐานผาหมี", activityName: nil,
                                       sequence: 3, at: "2026-08-07T01:00:00Z",
                                       answered: false, rating: nil, comment: nil)
        XCTAssertEqual(Map3DPins.label(sequence: 3, checkedIn: [item]), "ฐานผาหมี")
    }

    func testLabelFallsBackToNumberWhenNotCheckedInYet() {
        // ชื่อฐานที่ยังไม่เช็คอิน backend ไม่ได้ส่งมาให้ participant เลย — ห้ามเดาชื่อ
        XCTAssertEqual(Map3DPins.label(sequence: 5, checkedIn: []),
                       String(format: Loc.t("map_base_number"), 5))
    }

    func testLabelFallsBackWhenCheckedInRowHasNoSequence() {
        let item = CheckinProgressItem(checkpointId: 12, name: "ฐานผาหมี", activityName: nil,
                                       sequence: nil, at: "2026-08-07T01:00:00Z",
                                       answered: false, rating: nil, comment: nil)
        XCTAssertEqual(Map3DPins.label(sequence: 3, checkedIn: [item]),
                       String(format: Loc.t("map_base_number"), 3))
    }
}
