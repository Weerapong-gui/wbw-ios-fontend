import XCTest
@testable import WBW

/// รายการฐานทั้งงานที่ดึงจาก `GET /wbw/checkpoints`
///
/// โครงยกมาจาก `CheckinProgressStore` ทั้งดุ้นโดยตั้งใจ — กับดักชุดเดียวกันเป๊ะ (คีย์แคชต้องแยก
/// ตาม backend และตามโหมดเดโม่, คำตอบที่มาช้าห้ามทับของใหม่กว่า, ออฟไลน์ต้องยังมีของเก่าให้ดู)
/// และมันคือกับดักที่เคยเสียเวลาจริงมาแล้วทั้งหมด ไม่ใช่การเผื่อ
final class CheckpointStoreTests: XCTestCase {

    private func sample(_ id: Int, sequence: Int?, name: String,
                        nameEn: String? = nil, activity: String? = nil,
                        activityEn: String? = nil,
                        type: String = "activity", requiresCheckin: Bool = true) -> Checkpoint {
        Checkpoint(id: id, sequence: sequence, name: name, nameEn: nameEn,
                   activityName: activity, activityNameEn: activityEn,
                   type: type, requiresCheckin: requiresCheckin)
    }

    // MARK: - คีย์แคช

    /// **คีย์ต้องต่างกันครบทั้งห้า backend** — สลับ backend ไปทดสอบแล้วไม่ล้างข้อมูลแอป
    /// จะได้ชื่อฐานของอีกเซิร์ฟเวอร์มาขึ้นบนแผนที่โดยไม่มีอะไรฟ้อง
    func testCacheKeyDiffersForEveryBackend() {
        let keys = Set([Backend.prodNode, .nodeLocal, .susLocal, .susProd, .susLan]
            .map { CheckpointStore.cacheKey(for: $0) })
        XCTAssertEqual(keys.count, 5, "คีย์แคชซ้ำกันข้าม backend")
    }

    /// คีย์ต้องลงท้ายด้วย `CacheScope.suffix` เสมอ ไม่งั้น `Session.clearDemoCaches()` หาไม่เจอ
    /// แล้วชื่อฐานปลอมของโหมดเดโม่จะค้างอยู่ในบัญชีจริง
    func testCacheKeyCarriesTheDemoScope() {
        DemoMode.forcedActive = true
        defer { DemoMode.forcedActive = nil }
        XCTAssertTrue(CheckpointStore.cacheKey(for: .susProd).hasSuffix(CacheScope.demoSuffix))
    }

    // MARK: - ค้นหา

    @MainActor
    func testFindsByBothSequenceAndCheckpointId() async {
        let store = CheckpointStore(checkpointCall: { _ in
            [self.sample(5, sequence: 5, name: "จุดปลูก"),
             self.sample(9, sequence: nil, name: "MFU Botanical Garden",
                         type: "restroom", requiresCheckin: false)]
        })
        await store.load(token: "t", backend: .susProd)

        // แผนที่ค้นด้วย sequence (เลขที่ปั้นบนหมุด) ส่วนฟอร์มความเห็นค้นด้วย checkpointId
        XCTAssertEqual(store.checkpoint(sequence: 5)?.name, "จุดปลูก")
        XCTAssertEqual(store.checkpoint(checkpointId: 9)?.name, "MFU Botanical Garden")
        XCTAssertNil(store.checkpoint(sequence: 99))
    }

    /// จุดบริการทั้งสี่ไม่มี `sequence` — ค่า null เป็นของจริงที่ backend ส่งมา ไม่ใช่กรณีสมมติ
    /// ถ้าเผลออ่านเป็น 0 มันจะไปชนกับการค้นหาฐานและกลายเป็น "ฐานที่ 0"
    @MainActor
    func testServicePointsWithoutSequenceNeverMatchABase() async {
        let store = CheckpointStore(checkpointCall: { _ in
            [self.sample(9, sequence: nil, name: "MFU Botanical Garden",
                         type: "restroom", requiresCheckin: false)]
        })
        await store.load(token: "t", backend: .susProd)
        XCTAssertNil(store.checkpoint(sequence: 0))
        XCTAssertNotNil(store.checkpoint(checkpointId: 9))
    }

    // MARK: - แคชกับออฟไลน์

    @MainActor
    func testCachedListSurvivesAFailedLoad() async {
        let key = CheckpointStore.cacheKey(for: .susProd)
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let good = CheckpointStore(checkpointCall: { _ in [self.sample(1, sequence: 1, name: "ฐานแรก")] })
        await good.load(token: "t", backend: .susProd)

        // ยิงใหม่แล้วเน็ตพัง — ต้องยังเห็นของเดิมจากแคช ไม่ใช่จอว่าง (ออฟไลน์กลางเขาเป็นเรื่องปกติ)
        struct Boom: Error {}
        let offline = CheckpointStore(checkpointCall: { _ in throw Boom() })
        await offline.load(token: "t", backend: .susProd)
        XCTAssertEqual(offline.checkpoint(sequence: 1)?.name, "ฐานแรก")
    }

    /// แคชของ backend อื่นต้องไม่ถูกอ่านมาใช้
    @MainActor
    func testCacheFromAnotherBackendIsIgnored() async {
        let a = CheckpointStore.cacheKey(for: .susProd)
        let b = CheckpointStore.cacheKey(for: .nodeLocal)
        UserDefaults.standard.removeObject(forKey: a)
        UserDefaults.standard.removeObject(forKey: b)
        defer {
            UserDefaults.standard.removeObject(forKey: a)
            UserDefaults.standard.removeObject(forKey: b)
        }

        let store = CheckpointStore(checkpointCall: { _ in [self.sample(1, sequence: 1, name: "ของ susProd")] })
        await store.load(token: "t", backend: .susProd)

        let other = CheckpointStore(checkpointCall: { _ in [] })
        other.restoreFromCache(backend: .nodeLocal)
        XCTAssertNil(other.checkpoint(sequence: 1), "อ่านแคชข้าม backend มาใช้")
    }

    /// คำตอบที่มาช้ากว่าห้ามทับของที่ใหม่กว่า — สองรอบยิงพร้อมกันได้จริง เพราะ `load()` ถูกเรียก
    /// จากหลายที่โดยไม่มีใครคุมลำดับ (แพทเทิร์นเดียวกับ `CheckinProgressStore`)
    @MainActor
    func testAStaleResponseCannotOverwriteANewerOne() async {
        let slow = CheckpointStore(checkpointCall: { _ in
            try? await Task.sleep(nanoseconds: 60_000_000)
            return [self.sample(1, sequence: 1, name: "ของเก่า")]
        })
        let first = Task { await slow.load(token: "t", backend: .susProd) }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await slow.load(token: "t", backend: .susProd)
        _ = await first.value
        XCTAssertNotNil(slow.checkpoint(sequence: 1))
    }

    // MARK: - ภาษา

    /// ชื่อที่โชว์ต้องตามภาษาที่ผู้ใช้เลือกในแอป ไม่ใช่ภาษาของเครื่อง
    ///
    /// `/wbw/me/progress` ที่ใช้อยู่เดิม**ไม่มีฟิลด์ `_en` เลย** คนที่ตั้งแอปเป็นอังกฤษจึงเห็นชื่อฐาน
    /// เป็นไทยมาตลอด — endpoint ใหม่แก้เรื่องนี้ได้ก็ต่อเมื่อฝั่งแอปเลือกฟิลด์ถูก
    func testDisplayNameFollowsTheInAppLanguage() {
        defer { Loc.use(.system) }
        let cp = sample(1, sequence: 1, name: "จุดปลูก", nameEn: "Planting Point",
                        activity: "ปลูกป่า", activityEn: "Tree planting")
        Loc.use(.th)
        XCTAssertEqual(cp.displayName, "จุดปลูก")
        XCTAssertEqual(cp.displayActivity, "ปลูกป่า")
        Loc.use(.en)
        XCTAssertEqual(cp.displayName, "Planting Point")
        XCTAssertEqual(cp.displayActivity, "Tree planting")
    }

    /// ฐานที่ยังไม่มีคนแปลชื่ออังกฤษต้องถอยไปใช้ชื่อไทย ไม่ใช่โชว์ค่าว่าง
    func testFallsBackToThaiWhenEnglishIsMissing() {
        defer { Loc.use(.system) }
        Loc.use(.en)
        XCTAssertEqual(sample(1, sequence: 1, name: "ฐานผ้าใบ").displayName, "ฐานผ้าใบ")
        XCTAssertEqual(sample(2, sequence: 2, name: "x", nameEn: "").displayName, "x",
                       "ค่าว่างต้องนับเป็นไม่มีคำแปล ไม่ใช่คำแปลที่เป็นช่องว่าง")
    }

    // MARK: - ถอดรหัสจากสายเน็ตจริง

    /// ฟิลด์ที่หายไปต้องไม่ทำให้ decode พังทั้งก้อน — ถ้าพัง ชื่อฐานหายหมดทั้งแผนที่พร้อมกัน
    /// ไม่ใช่หายทีละแถว (บทเรียนเดียวกับ `CheckinProgressItem.answered`)
    func testDecodesARowThatIsMissingOptionalFields() throws {
        let json = """
        [{"id":7,"sequence":7,"name":"ฐานผ้าใบ","type":"activity","requires_checkin":true}]
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let list = try decoder.decode([Checkpoint].self, from: Data(json.utf8))
        XCTAssertEqual(list.first?.name, "ฐานผ้าใบ")
        XCTAssertNil(list.first?.nameEn)
        XCTAssertNil(list.first?.activityName)
    }
}
