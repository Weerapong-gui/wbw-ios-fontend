import XCTest
@testable import WBW

/// cache ของ progress ต้องแยกตาม backend — checkpoint_id คนละชุดต่อ backend
/// ถ้าใช้ key เดียวกัน สลับ backend แล้วต้นไม้ผิดขนาดแบบเงียบๆ ไม่มี error ไม่มี log
/// (กับดักเดียวกับ cursor แชท ดู docs/sus-test-backend.md)
final class CheckinProgressStoreTests: XCTestCase {

    func testCacheKeyDiffersPerBackend() {
        let keys = Set([
            CheckinProgressStore.cacheKey(for: .prodNode),
            CheckinProgressStore.cacheKey(for: .nodeLocal),
            CheckinProgressStore.cacheKey(for: .susLocal),
            CheckinProgressStore.cacheKey(for: .susProd),
            CheckinProgressStore.cacheKey(for: .susLan),
        ])
        XCTAssertEqual(keys.count, 5, "ทุก backend ต้องได้ key ไม่ซ้ำกัน")
    }

    func testDecodesServerPayload() throws {
        let json = """
        {"total": 8, "checked_in": [
          {"checkpoint_id": 1, "name": "วิหารพระเจ้าล้านทอง", "activity_name": null, "sequence": 1,
           "at": "2026-08-29T09:12:03Z", "answered": false, "rating": null, "comment": null},
          {"checkpoint_id": 2, "name": "สวนกุหลาบ", "activity_name": null, "sequence": 2,
           "at": "2026-08-29T09:40:00Z", "answered": false, "rating": null, "comment": null}
        ]}
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let p = try dec.decode(CheckinProgress.self, from: json)

        XCTAssertEqual(p.total, 8)
        XCTAssertEqual(p.stage, 2)
        XCTAssertEqual(p.checkedIn.first?.name, "วิหารพระเจ้าล้านทอง")
    }

    func testDecodesEmptyCheckedIn() throws {
        let json = #"{"total": 8, "checked_in": []}"#.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let p = try dec.decode(CheckinProgress.self, from: json)
        XCTAssertEqual(p.stage, 0)
        XCTAssertEqual(p.total, 8)
    }

    func testDecodesNullSequence() throws {
        let json = """
        {"total": 8, "checked_in": [
          {"checkpoint_id": 5, "name": "จุดปลูก", "activity_name": null, "sequence": null,
           "at": "2026-08-29T10:00:00Z", "answered": false, "rating": null, "comment": null}
        ]}
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let p = try dec.decode(CheckinProgress.self, from: json)
        XCTAssertNil(p.checkedIn[0].sequence)
    }

    @MainActor
    func testCacheRoundTrip() throws {
        let key = CheckinProgressStore.cacheKey(for: .susLocal)
        UserDefaults.standard.removeObject(forKey: key)

        let store = CheckinProgressStore()
        let value = CheckinProgress(total: 8, checkedIn: [
            CheckinProgressItem(checkpointId: 1, name: "ฐาน 1", activityName: "กิจกรรม 1", sequence: 1,
                                 at: "2026-08-29T09:00:00Z", answered: true, rating: 5, comment: "สนุกมาก"),
        ])
        store.cache(value, backend: .susLocal)

        let fresh = CheckinProgressStore()
        fresh.restoreFromCache(backend: .susLocal)
        XCTAssertEqual(fresh.progress, value)

        UserDefaults.standard.removeObject(forKey: key)
    }

    @MainActor
    func testRestoreFromOtherBackendCacheIsIgnored() throws {
        let susKey = CheckinProgressStore.cacheKey(for: .susLocal)
        let nodeKey = CheckinProgressStore.cacheKey(for: .prodNode)
        UserDefaults.standard.removeObject(forKey: susKey)
        UserDefaults.standard.removeObject(forKey: nodeKey)

        let store = CheckinProgressStore()
        store.cache(CheckinProgress(total: 8, checkedIn: [
            CheckinProgressItem(checkpointId: 1, name: "ฐาน 1", activityName: "กิจกรรม 1", sequence: 1,
                                 at: "2026-08-29T09:00:00Z", answered: true, rating: 5, comment: "สนุกมาก"),
        ]), backend: .susLocal)

        let fresh = CheckinProgressStore()
        fresh.restoreFromCache(backend: .prodNode)
        XCTAssertNil(fresh.progress, "cache ของ backend อื่นต้องไม่ถูกหยิบมาใช้")

        UserDefaults.standard.removeObject(forKey: susKey)
    }

    // MARK: - ฟิลด์ความเห็น (spec 2)

    private func decodeProgress(_ json: String) throws -> CheckinProgress {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(CheckinProgress.self, from: json.data(using: .utf8)!)
    }

    func testDecodesFeedbackFields() throws {
        let p = try decodeProgress("""
        {"total": 8, "checked_in": [
          {"checkpoint_id": 1, "name": "ฐานหนึ่ง", "activity_name": "กิจกรรมหนึ่ง", "sequence": 1,
           "at": "2026-08-29T09:00:00Z", "answered": true, "rating": 3, "comment": "ดีมาก"},
          {"checkpoint_id": 2, "name": "ฐานสอง", "activity_name": null, "sequence": 2,
           "at": "2026-08-29T10:00:00Z", "answered": false, "rating": null, "comment": null}
        ]}
        """)
        XCTAssertEqual(p.checkedIn[0].activityName, "กิจกรรมหนึ่ง")
        XCTAssertTrue(p.checkedIn[0].answered)
        XCTAssertEqual(p.checkedIn[0].rating, 3)
        XCTAssertNil(p.checkedIn[1].activityName)
        XCTAssertFalse(p.checkedIn[1].answered)
        XCTAssertNil(p.checkedIn[1].rating)
    }

    /// ฐานที่ยังไม่ตอบ เรียงใหม่สุดก่อน — toast เด้งของฐานล่าสุด
    func testPendingIsUnansweredNewestFirst() throws {
        let p = try decodeProgress("""
        {"total": 8, "checked_in": [
          {"checkpoint_id": 1, "name": "เก่าสุด", "activity_name": null, "sequence": 1,
           "at": "2026-08-29T09:00:00Z", "answered": false, "rating": null, "comment": null},
          {"checkpoint_id": 2, "name": "ตอบแล้ว", "activity_name": null, "sequence": 2,
           "at": "2026-08-29T10:00:00Z", "answered": true, "rating": 2, "comment": null},
          {"checkpoint_id": 3, "name": "ใหม่สุด", "activity_name": null, "sequence": 3,
           "at": "2026-08-29T11:00:00Z", "answered": false, "rating": null, "comment": null}
        ]}
        """)
        XCTAssertEqual(p.pending.map(\.checkpointId), [3, 1])
    }

    func testPendingEmptyWhenAllAnswered() throws {
        let p = try decodeProgress("""
        {"total": 8, "checked_in": [
          {"checkpoint_id": 1, "name": "ฐาน", "activity_name": null, "sequence": 1,
           "at": "2026-08-29T09:00:00Z", "answered": true, "rating": 1, "comment": null}
        ]}
        """)
        XCTAssertTrue(p.pending.isEmpty)
    }

    /// stage ต้องนับทุกฐานที่เช็คอิน ไม่ใช่เฉพาะที่ยังไม่ตอบ — ต้นไม้ไม่หดตอนตอบความเห็น
    func testStageUnaffectedByAnswering() throws {
        let p = try decodeProgress("""
        {"total": 8, "checked_in": [
          {"checkpoint_id": 1, "name": "a", "activity_name": null, "sequence": 1,
           "at": "t", "answered": true, "rating": 3, "comment": null},
          {"checkpoint_id": 2, "name": "b", "activity_name": null, "sequence": 2,
           "at": "t", "answered": false, "rating": null, "comment": null}
        ]}
        """)
        XCTAssertEqual(p.stage, 2)
    }

    @MainActor
    func testItemLookupByCheckpoint() throws {
        let store = CheckinProgressStore()
        store.cache(try decodeProgress("""
        {"total": 8, "checked_in": [
          {"checkpoint_id": 5, "name": "จุดปลูก", "activity_name": "ปลูกป่า", "sequence": 5,
           "at": "t", "answered": false, "rating": null, "comment": null}
        ]}
        """), backend: .susLocal)
        XCTAssertEqual(store.item(checkpointId: 5)?.name, "จุดปลูก")
        XCTAssertNil(store.item(checkpointId: 99))
        UserDefaults.standard.removeObject(forKey: CheckinProgressStore.cacheKey(for: .susLocal))
    }

    // MARK: - answered ต้อง tolerant ตอน decode (fix round 1) — เผื่อ cache รุ่นเก่าก่อนมีฟีเจอร์นี้

    /// payload ที่ไม่มีคีย์ answered เลย (เช่น response เก่ากว่าฟีเจอร์นี้) ต้อง decode ผ่าน
    /// และถือว่ายังไม่ตอบ ไม่ใช่โยน error ทิ้งทั้งก้อน
    func testAnsweredDefaultsToFalseWhenKeyMissing() throws {
        let p = try decodeProgress("""
        {"total": 8, "checked_in": [
          {"checkpoint_id": 1, "name": "ฐาน", "activity_name": "กิจกรรม", "sequence": 1,
           "at": "2026-08-29T09:00:00Z", "rating": null, "comment": null}
        ]}
        """)
        XCTAssertFalse(p.checkedIn[0].answered)
    }

    /// จำลอง cache ที่เขียนไว้ก่อนฟีเจอร์นี้ขึ้น (ไม่มี answered/activity_name/rating/comment เลย) —
    /// restoreFromCache ต้องกู้ progress ได้ปกติ ไม่ใช่ปล่อยให้ decode พังเงียบๆ จน progress เป็น nil
    /// แล้วต้นไม้หน้า Home เหลือ 0 ทั้งที่เดินมาแล้วหลายฐาน (เคสจริง: อัปเดตแอปแล้วเดินป่าไม่มีเน็ต)
    /// คีย์ในนี้เป็น camelCase ตรงชื่อ property เพราะ cache เขียน/อ่านด้วย JSONEncoder/Decoder
    /// ค่า default (ไม่ผ่าน convertFromSnakeCase) ต่างจาก payload จากเน็ตที่เป็น snake_case
    @MainActor
    func testRestoresOldShapeCacheWithoutFeedbackFields() throws {
        let key = CheckinProgressStore.cacheKey(for: .susLocal)
        let oldShapeJSON = """
        {"total": 8, "checkedIn": [
          {"checkpointId": 1, "name": "ฐานหนึ่ง", "sequence": 1, "at": "2026-08-29T09:00:00Z"},
          {"checkpointId": 2, "name": "ฐานสอง", "sequence": 2, "at": "2026-08-29T10:00:00Z"}
        ]}
        """.data(using: .utf8)!
        UserDefaults.standard.set(oldShapeJSON, forKey: key)

        let store = CheckinProgressStore()
        store.restoreFromCache(backend: .susLocal)

        XCTAssertEqual(store.progress?.stage, 2, "ต้นไม้ต้องนับฐานที่เช็คอินได้ครบ แม้ cache เป็นรูปแบบเก่า")
        XCTAssertEqual(store.progress?.pending.count, 2, "ฐานเก่าที่ไม่มีคีย์ answered ต้องถือว่ายังไม่ตอบ")

        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - ฐานที่ "เพิ่ง" รอประเมิน (Task 11) — toast อ่านตัวนี้
    //
    // ตัว diff เต็มๆ (โหลดรอบ 2 เจอฐานใหม่ → newlyPending มีตัวนั้นตัวเดียว) ต้องยิงเน็ตจริงถึงจะเกิด —
    // load() เรียก APIClient.shared ตรงๆ ไม่มี seam ให้ฉีดของปลอม (ทั้งไฟล์นี้เป็นแบบนั้นมาแต่แรก) จะ
    // เขียนเทสให้ดูเหมือนครอบก็ต้องปลอม APIClient ทั้งตัวซึ่งเป็นการทดสอบของปลอม ไม่ใช่ของจริง —
    // พฤติกรรมนั้นจึงพิสูจน์กับ backend จริงใน Step 6/7 ของ task-11 แทน (ดู task-11-report.md)
    //
    // ที่เทสได้ตรงๆ คือค่าเริ่มต้นกับการรีเซ็ต · lastPendingIds/firstLoadDone เป็น private และเขียนได้
    // ทางเดียวคือผ่าน load() ที่ต้องมีเน็ต เทสตรงๆ จึงไม่ได้ — ที่ยืนยันได้คือ progress ซึ่งอ่านได้จริง
    // และต้องกลายเป็น nil หลัง clear()

    @MainActor
    func testNewlyPendingIsEmptyOnFirstLoad() {
        let store = CheckinProgressStore()
        XCTAssertTrue(store.newlyPending.isEmpty)
    }

    /// เติมของจริงเข้าไปก่อนเสมอ — เรียก clear() บน store ที่ยังเป็นค่าเริ่มต้นอยู่แล้ว เทสจะผ่านแม้
    /// clear() ลืมรีเซ็ตฟิลด์ไปทั้งตัว (ทุก assert เทียบกับค่าที่มันเป็นอยู่แล้วตั้งแต่ต้น) = เทสที่
    /// จับอะไรไม่ได้เลย
    @MainActor
    func testClearResetsPendingDiffState() {
        let store = CheckinProgressStore()
        let loaded = CheckinProgress(total: 8, checkedIn: [
            CheckinProgressItem(checkpointId: 3, name: "ลานย่อย 3", activityName: nil,
                                sequence: 3, at: "2026-08-29T09:00:00Z",
                                answered: false, rating: nil, comment: nil),
        ])
        store.cache(loaded, backend: .susLocal)
        XCTAssertNotNil(store.progress, "ต้องมีของให้ clear() ล้างจริงๆ ก่อน ไม่งั้นเทสไม่ได้พิสูจน์อะไร")

        store.clear()

        XCTAssertTrue(store.newlyPending.isEmpty)
        XCTAssertNil(store.progress)

        UserDefaults.standard.removeObject(forKey: CheckinProgressStore.cacheKey(for: .susLocal))
    }
}
