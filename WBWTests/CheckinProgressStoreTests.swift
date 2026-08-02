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
          {"checkpoint_id": 1, "name": "วิหารพระเจ้าล้านทอง", "sequence": 1, "at": "2026-08-29T09:12:03Z"},
          {"checkpoint_id": 2, "name": "สวนกุหลาบ", "sequence": 2, "at": "2026-08-29T09:40:00Z"}
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
          {"checkpoint_id": 5, "name": "จุดปลูก", "sequence": null, "at": "2026-08-29T10:00:00Z"}
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
            CheckinProgressItem(checkpointId: 1, name: "ฐาน 1", sequence: 1, at: "2026-08-29T09:00:00Z"),
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
            CheckinProgressItem(checkpointId: 1, name: "ฐาน 1", sequence: 1, at: "2026-08-29T09:00:00Z"),
        ]), backend: .susLocal)

        let fresh = CheckinProgressStore()
        fresh.restoreFromCache(backend: .prodNode)
        XCTAssertNil(fresh.progress, "cache ของ backend อื่นต้องไม่ถูกหยิบมาใช้")

        UserDefaults.standard.removeObject(forKey: susKey)
    }
}
