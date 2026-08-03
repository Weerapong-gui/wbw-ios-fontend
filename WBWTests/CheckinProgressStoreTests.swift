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
    // diff ตัวนี้คือหัวใจของ poll 60 วิ ซึ่งเป็นทางเข้าเดียวที่เหลือเมื่อ push ใช้ไม่ได้ (build ที่ไม่มี
    // GoogleService-Info.plist ปิด push ทั้งอัน = ทุก build ที่ CI สร้าง) เดิมไม่มีเทสเลยสักบรรทัด
    // เพราะ load() เรียก APIClient.shared ตรงๆ — ตอนนี้ฉีด progressCall แทนได้แล้ว (ทรงเดียวกับ
    // FeedbackStore.submitCall) เทสด้านล่างจึงเดินผ่าน load() ของจริงทั้งหมด ไม่มีการ assert
    // ค่าเริ่มต้นแทนพฤติกรรมอีก

    /// ตัวปลอมของ GET /me/progress — คืนค่าตามคิวที่ตั้งไว้ และ "ค้าง" ที่การเรียกครั้งที่ระบุได้
    /// เพื่อจำลองสอง request ที่คาบกันแล้วกลับมาสลับลำดับ (ถ้าไม่มีประตูนี้ รอบแรกจะจบก่อนรอบสอง
    /// เริ่มเสมอ เทสก็ผ่านแม้ไม่มีตัวกันเลย = จับอะไรไม่ได้)
    private final class FakeProgressLoader {
        private(set) var callCount = 0
        var queue: [CheckinProgress] = []
        /// การเรียกครั้งที่เท่าไรที่ต้องค้างรอ release() (nil = ไม่ค้างเลย)
        var gateCall: Int?
        private var gate: CheckedContinuation<Void, Never>?

        func call(_ token: String) async throws -> CheckinProgress {
            callCount += 1
            let value = queue.isEmpty ? CheckinProgress(total: 8, checkedIn: []) : queue.removeFirst()
            if gateCall == callCount {
                await withCheckedContinuation { c in gate = c }
            }
            return value
        }

        var isWaiting: Bool { gate != nil }
        func release() { gate?.resume(); gate = nil }
    }

    private func progress(pending ids: [Int]) -> CheckinProgress {
        CheckinProgress(total: 8, checkedIn: ids.map {
            CheckinProgressItem(checkpointId: $0, name: "ฐาน \($0)", activityName: nil, sequence: $0,
                                at: "2026-08-29T09:00:00Z", answered: false, rating: nil, comment: nil)
        })
    }

    /// เคลียร์ cache ของ backend ที่เทสชุดนี้ใช้ — load() เขียน cache ทุกรอบ และ restoreFromCache
    /// จะหยิบของค้างจากเทสก่อนหน้ามาใช้ถ้าไม่ล้าง
    @MainActor
    private func withCleanCache(_ body: () async -> Void) async {
        let key = CheckinProgressStore.cacheKey(for: .susLocal)
        UserDefaults.standard.removeObject(forKey: key)
        await body()
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// โหลดครั้งแรกของ session ต้องไม่รายงานว่ามีฐาน "เพิ่ง" รอประเมิน แม้ payload จะมีฐานค้างอยู่ —
    /// เปิดแอปมาเจอของค้างเก่าไม่ควรเด้ง toast ราวกับเพิ่งโดนสแกนเมื่อกี้
    @MainActor
    func testNewlyPendingIsEmptyOnFirstLoad() async {
        await withCleanCache {
            let loader = FakeProgressLoader()
            loader.queue = [progress(pending: [1, 2])]
            let store = CheckinProgressStore(progressCall: loader.call)

            await store.load(token: "t", backend: .susLocal)

            XCTAssertEqual(store.progress?.pending.count, 2, "ต้องโหลดข้อมูลมาจริง ไม่งั้นเทสไม่ได้พิสูจน์อะไร")
            XCTAssertTrue(store.newlyPending.isEmpty, "โหลดครั้งแรกต้องไม่นับว่าเป็นฐานที่เพิ่งรอประเมิน")
        }
    }

    /// ฐานใหม่ที่โผล่ในรอบที่สอง (เพิ่งโดนสแกนจริง) ต้องเข้า newlyPending — และต้องมีแค่ตัวนั้น
    /// ไม่ใช่ทั้งกอง ไม่งั้น toast จะเด้งฐานที่ค้างมาตั้งแต่ต้นซ้ำทุกรอบ
    @MainActor
    func testNewlyPendingReportsGenuinelyNewBase() async {
        await withCleanCache {
            let loader = FakeProgressLoader()
            loader.queue = [progress(pending: [1]), progress(pending: [1, 2])]
            let store = CheckinProgressStore(progressCall: loader.call)

            await store.load(token: "t", backend: .susLocal)
            await store.load(token: "t", backend: .susLocal)

            XCTAssertEqual(store.newlyPending.map(\.checkpointId), [2],
                           "เฉพาะฐานที่เพิ่งโผล่เท่านั้น ฐาน 1 ค้างมาตั้งแต่รอบก่อนไม่ใช่ของใหม่")
        }
    }

    /// poll รอบถัดไปที่ได้ข้อมูลชุดเดิม ต้องไม่เด้งซ้ำ — เทียบกับรอบก่อนเสมอ ไม่ใช่กับ "เคยเด้งไปหรือยัง"
    @MainActor
    func testNewlyPendingEmptyWhenSecondLoadUnchanged() async {
        await withCleanCache {
            let loader = FakeProgressLoader()
            loader.queue = [progress(pending: [1, 2]), progress(pending: [1, 2]), progress(pending: [1, 2])]
            let store = CheckinProgressStore(progressCall: loader.call)

            await store.load(token: "t", backend: .susLocal)
            await store.load(token: "t", backend: .susLocal)
            XCTAssertTrue(store.newlyPending.isEmpty, "ข้อมูลชุดเดิมต้องไม่เด้งซ้ำ")

            await store.load(token: "t", backend: .susLocal)
            XCTAssertTrue(store.newlyPending.isEmpty, "รอบที่สามก็ยังต้องเงียบ")
        }
    }

    /// ฐานที่ถูกตอบไปแล้ว (หลุดจาก pending) แล้วโผล่กลับมาไม่ได้ — แต่ฐานใหม่จริงๆ หลังจากนั้นต้องยังจับได้
    @MainActor
    func testNewlyPendingTracksLatestRoundOnly() async {
        await withCleanCache {
            let loader = FakeProgressLoader()
            loader.queue = [progress(pending: [1]), progress(pending: []), progress(pending: [3])]
            let store = CheckinProgressStore(progressCall: loader.call)

            await store.load(token: "t", backend: .susLocal)   // รอบแรก: เงียบเสมอ
            await store.load(token: "t", backend: .susLocal)   // ตอบฐาน 1 ไปแล้ว
            XCTAssertTrue(store.newlyPending.isEmpty)

            await store.load(token: "t", backend: .susLocal)   // ฐาน 3 เพิ่งโดนสแกน
            XCTAssertEqual(store.newlyPending.map(\.checkpointId), [3])
        }
    }

    /// clear() (ล็อกเอาต์) ต้องรีเซ็ตตัวเทียบทั้งชุด ไม่ใช่แค่ progress — บัญชีถัดไปบนเครื่องเดียวกัน
    /// ต้องเริ่มนับใหม่หมด ทั้ง lastPendingIds และ firstLoadDone
    ///
    /// พิสูจน์ผ่านพฤติกรรมที่มองเห็นได้จริง: โหลดครั้งแรก "หลัง" clear() ต้องเงียบเหมือนโหลดครั้งแรกของ
    /// session ใหม่ (firstLoadDone ถูกรีเซ็ต) และฐานที่บัญชีก่อนค้างไว้ต้องไม่ถูกกลืนว่า "ไม่ใหม่"
    /// (lastPendingIds ถูกรีเซ็ต) — เดิมเทสนี้เทียบแต่ค่าเริ่มต้นกับ progress == nil เท่านั้น
    @MainActor
    func testClearResetsPendingDiffState() async {
        await withCleanCache {
            let loader = FakeProgressLoader()
            loader.queue = [progress(pending: [1]), progress(pending: [1, 2]),
                            progress(pending: [1, 2]), progress(pending: [1, 2, 5])]
            let store = CheckinProgressStore(progressCall: loader.call)

            await store.load(token: "t", backend: .susLocal)
            await store.load(token: "t", backend: .susLocal)
            XCTAssertEqual(store.newlyPending.map(\.checkpointId), [2], "ต้องมีของจริงให้ clear() ล้าง")
            XCTAssertNotNil(store.progress)

            store.clear()
            XCTAssertNil(store.progress)
            XCTAssertTrue(store.newlyPending.isEmpty)

            // โหลดครั้งแรกของ "บัญชีใหม่" — ฐาน 1/2 ที่บัญชีก่อนเคยเห็นต้องไม่เด้ง toast
            await store.load(token: "t", backend: .susLocal)
            XCTAssertTrue(store.newlyPending.isEmpty,
                          "firstLoadDone ต้องถูกรีเซ็ต ไม่งั้นบัญชีใหม่จะโดน toast ของค้างทั้งกองตอนเข้าแอป")

            // รอบถัดมามีฐาน 5 เพิ่มจริง — ตัวเทียบต้องเริ่มนับใหม่จากรอบก่อนหน้า ไม่ใช่จากของบัญชีเก่า
            await store.load(token: "t", backend: .susLocal)
            XCTAssertEqual(store.newlyPending.map(\.checkpointId), [5],
                           "lastPendingIds ต้องถูกสร้างใหม่จากรอบหลัง clear() ไม่ใช่ค้างของเดิม")
        }
    }

    // MARK: - สอง load ที่คาบกันกลับมาสลับลำดับ (fix รอบสุดท้าย)

    /// load() ถูกเรียกจากห้าที่โดยไม่มีใครคุมลำดับ · ผลลัพธ์ของรอบที่ "เก่ากว่า" ที่กลับมาทีหลังต้อง
    /// ถูกทิ้ง ไม่ใช่เขียนทับรอบใหม่ — ไม่งั้น state ถอยหลังทั้งชุด: ต้นไม้หน้า Home หดลงหนึ่งขั้นให้
    /// เห็นกับตา, ฐาน B หลุดจาก liveToastBases ทำให้ toast หายกลางคัน แล้ว poll รอบถัดไปเด้ง toast
    /// ฐาน B ซ้ำอีกครั้งราวกับเพิ่งโดนสแกน (เกิดทุกครั้งที่สแกนสองฐานติดกันเร็วๆ บนเน็ตแย่ๆ)
    @MainActor
    func testStaleLoadResponseDoesNotRollBackState() async {
        await withCleanCache {
            let loader = FakeProgressLoader()
            // รอบที่ 1 = ของเก่า (ยิงก่อนฐาน 2 ถูกสแกน) ค้างไว้ที่ประตู · รอบที่ 2 = ของใหม่ ผ่านทันที
            loader.queue = [progress(pending: [1]), progress(pending: [1, 2]), progress(pending: [1, 2])]
            loader.gateCall = 1
            let store = CheckinProgressStore(progressCall: loader.call)

            let stale = Task { await store.load(token: "t", backend: .susLocal) }
            while !loader.isWaiting { await Task.yield() }   // รอให้รอบเก่าเข้าไปติดที่ประตูจริงๆ

            await store.load(token: "t", backend: .susLocal)  // รอบใหม่ลงก่อน
            XCTAssertEqual(store.progress?.stage, 2)

            loader.release()                                  // รอบเก่ากลับมาทีหลัง
            await stale.value

            XCTAssertEqual(store.progress?.stage, 2, "ต้นไม้ต้องไม่หดกลับเพราะคำตอบเก่ามาถึงทีหลัง")
            XCTAssertEqual(store.progress?.pending.map(\.checkpointId).sorted(), [1, 2])

            // ตัวเทียบต้องไม่ถอยตามไปด้วย — ถ้าถอย รอบถัดไปที่ได้ข้อมูลชุดเดิมจะเด้ง toast ฐาน 2 ซ้ำ
            await store.load(token: "t", backend: .susLocal)
            XCTAssertTrue(store.newlyPending.isEmpty,
                          "ฐาน 2 ถูกรายงานไปแล้ว ต้องไม่ถูกนับเป็นของใหม่ซ้ำอีกรอบ")
        }
    }
}
