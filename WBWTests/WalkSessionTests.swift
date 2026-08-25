import XCTest
@testable import WBW

/// การเดินหนึ่งรอบที่ **ข้ามการออกจากแอปและการปิดแอปได้**
///
/// ของเดิม `WalkTracker` จับเฉพาะตอนแอปอยู่หน้าจอ (เขียนไว้เองหัวไฟล์ว่าตั้งใจไม่ยก foreground
/// service ของ Android มา เพราะ iOS ต้องขอ `UIBackgroundModes: location` ซึ่งกินแบตและต้องตอบ
/// Apple ตาม 2.5.4) · เจ้าของงานเลือกทางที่ไม่ขอ background mode: ให้ **ชิปนับก้าวของเครื่อง**
/// เป็นแหล่งความจริงของช่วงที่แอปไม่ได้อยู่หน้าจอ แล้วถามย้อนหลังตอนกลับมา
///
/// ตรรกะสองก้อนที่ต้องคุมไว้เพราะพังแล้ว **ผู้ใช้เลิกเชื่อตัวเลขทั้งจอ**: การรวมระยะจากสองแหล่ง
/// (ต้องไม่ทับกัน) กับก้าวที่ต้องไม่บวกซ้ำเมื่อสลับเข้าออกหลายรอบ
final class WalkSessionTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func defaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "walk.session.tests")!
        d.removePersistentDomain(forName: "walk.session.tests")
        return d
    }

    // MARK: - รวมระยะจากสองแหล่ง

    /// GPS วัดตอนอยู่หน้าจอ · ชิปนับก้าววัดตอนไม่ได้อยู่หน้าจอ — **คนละช่วงเวลา จึงบวกกันได้ตรง ๆ**
    /// เอาสองแหล่งมาวัดช่วงเดียวกันเมื่อไหร่ ระยะจะเบิ้ลทันทีโดยไม่มีอะไรฟ้อง
    func testDistanceAddsTheTwoSourcesThatMeasureDifferentStretches() {
        XCTAssertEqual(WalkMath.totalDistance(foregroundGPS: 800, awayPedometer: 250), 1050)
        XCTAssertEqual(WalkMath.totalDistance(foregroundGPS: 800, awayPedometer: 0), 800)
    }

    // MARK: - ก้าว

    /// ถามชิปทั้งรอบทีเดียวแล้ว **เขียนทับ** ไม่ใช่บวกเข้าไปทีละช่วง — สลับเข้าออกสามรอบแล้ว
    /// บวกทุกครั้งจะได้ก้าวเป็นสามเท่าของที่เดินจริง
    func testStepsOverwriteInsteadOfAccumulating() {
        var steps = WalkMath.mergedSteps(queried: 1_200, previous: nil)
        steps = WalkMath.mergedSteps(queried: 1_800, previous: steps)
        steps = WalkMath.mergedSteps(queried: 2_400, previous: steps)
        XCTAssertEqual(steps, 2_400)
    }

    /// เครื่องที่นับก้าวไม่ได้ (simulator ทุกตัว หรือคนที่ไม่ให้สิทธิ์ Motion) ถามแล้วได้ nil —
    /// ต้อง **ไม่ล้างเลขที่เคยได้มาแล้ว** ทิ้ง และต้องไม่กลายเป็น 0 ซึ่งอ่านว่า "เดินแล้วไม่ได้อะไร"
    func testAFailedQueryKeepsWhateverWasAlreadyCounted() {
        XCTAssertEqual(WalkMath.mergedSteps(queried: nil, previous: 900), 900)
        XCTAssertNil(WalkMath.mergedSteps(queried: nil, previous: nil))
    }

    // MARK: - รอบที่จำลงเครื่อง

    func testAnUnfinishedWalkSurvivesBeingWrittenAndReadBack() {
        let d = defaults()
        let session = WalkSession(startedAt: start, gpsDistanceMetres: 640,
                                  awayDistanceMetres: 120, awaySince: nil, steps: 1_500)
        WalkSessionStore.save(session, into: d)
        XCTAssertEqual(WalkSessionStore.load(from: d), session)
    }

    /// กดหยุดแล้วต้องไม่มีรอบค้าง — ไม่งั้นเปิดแอปวันหลังจะเจอรอบผีที่นับต่อจากเมื่อวาน
    func testStoppingLeavesNothingBehind() {
        let d = defaults()
        WalkSessionStore.save(WalkSession(startedAt: start), into: d)
        WalkSessionStore.clear(from: d)
        XCTAssertNil(WalkSessionStore.load(from: d))
    }

    /// **รอบที่ค้างข้ามคืนคือรอบที่ลืมกดหยุด ไม่ใช่รอบที่ยังเดินอยู่** — ฟื้นมันขึ้นมาแล้ว
    /// backfill จากชิปจะได้ระยะของทั้งวันรวมทั้งตอนขับรถกลับบ้าน ซึ่งเป็นตัวเลขที่ผิดแบบน่าอาย
    func testAWalkLeftRunningOvernightIsTreatedAsStale() {
        let session = WalkSession(startedAt: start)
        XCTAssertFalse(WalkSessionStore.isStale(session, now: start.addingTimeInterval(3 * 3600)))
        XCTAssertTrue(WalkSessionStore.isStale(session, now: start.addingTimeInterval(13 * 3600)))
    }

    /// ช่วงที่ไม่ได้อยู่หน้าจอต้องนับจากเวลาที่ออกไปจริง ๆ · ไม่เคยออกเลย = ไม่มีอะไรให้ถามชิป
    func testTheAwayWindowIsOnlyRealWhenTheAppActuallyLeft() {
        var session = WalkSession(startedAt: start)
        XCTAssertNil(session.awaySince)
        session.awaySince = start.addingTimeInterval(60)
        XCTAssertEqual(session.awaySince, start.addingTimeInterval(60))
    }
}
