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
}
