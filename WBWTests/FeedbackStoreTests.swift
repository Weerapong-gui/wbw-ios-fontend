import XCTest
@testable import WBW

/// FeedbackStore แยก error ที่ retry ได้ (AppError.offline) ออกจาก error ที่ retry ไม่ได้
/// (400/401/500 ฯลฯ) ตามแบบ ChatSession.flushOutbox (WBW/Chat/ChatSession.swift) — เทสชุดนี้ตรึง
/// พฤติกรรมนั้นทั้งฝั่ง submit (ตอบผู้ใช้ตรงตามจริง) และ flush (ของพังหนึ่งชิ้นห้ามบล็อกทั้งคิว)
///
/// เน็ตจริงถูกตัดออกด้วย submitCall ที่ฉีดผ่าน init — ไม่แตะ APIClient.shared เลย
final class FeedbackStoreTests: XCTestCase {

    /// ตัวปลอมของการเรียกเน็ต — คุมผลลัพธ์ต่อ clientId ได้ เพื่อจำลอง draft ตัวหนึ่งพังแบบ terminal
    /// ขณะที่อีกตัวสำเร็จ (เทส flush ไม่ให้ของพังบล็อกคิว) พร้อมจด clientId ที่ถูกเรียกไว้ตามลำดับ
    private final class FakeSubmitter {
        private(set) var calledClientIds: [String] = []
        var resultsByClientId: [String: Result<APIClient.FeedbackSubmitOutcome, Error>] = [:]
        var defaultResult: Result<APIClient.FeedbackSubmitOutcome, Error> = .success(.saved)

        func call(_ token: String, _ draft: FeedbackDraft) async throws -> APIClient.FeedbackSubmitOutcome {
            calledClientIds.append(draft.clientId)
            switch resultsByClientId[draft.clientId] ?? defaultResult {
            case let .success(outcome): return outcome
            case let .failure(error): throw error
            }
        }
    }

    private func draft(_ id: String, checkpoint: Int) -> FeedbackDraft {
        FeedbackDraft(clientId: id, checkpointId: checkpoint, rating: 3,
                      comment: "ดี", deviceTime: "2026-08-29T09:00:00Z")
    }

    private func outboxUnderTest() -> FeedbackOutbox { FeedbackOutbox(backend: Config.backend) }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: FeedbackOutbox.key(for: Config.backend))
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FeedbackOutbox.key(for: Config.backend))
        super.tearDown()
    }

    // MARK: - submit

    /// AppError.offline คือ error เดียวที่ retry ได้ — ต้องเข้า outbox รอรอบหน้า และ UI เห็น .saved
    /// (การันตีด้วย clientId เดิมตอน retry อยู่แล้ว ไม่ต้องบอกผู้ใช้ว่ายังไม่ถึงเซิร์ฟเวอร์)
    @MainActor
    func testSubmitOfflineQueuesDraftAndReportsSaved() async {
        let fake = FakeSubmitter()
        fake.defaultResult = .failure(AppError.offline)
        let store = FeedbackStore(submitCall: fake.call)
        let d = draft("a", checkpoint: 5)

        let outcome = await store.submit(d, token: "t")

        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(outboxUnderTest().all().map(\.clientId), ["a"], "ต้องเข้าคิวรอ retry รอบหน้า")
    }

    /// error อื่นที่ไม่ใช่ offline (400/401/500 ฯลฯ) ห้ามเข้า outbox — retry ด้วย draft เดิมยังไงก็ไม่
    /// สำเร็จ ต้องคืน .failed ให้ฟอร์มบอกความจริง ไม่ใช่ .saved ปลอมๆ
    @MainActor
    func testSubmitTerminalFailureReturnsFailedAndDoesNotQueue() async {
        let fake = FakeSubmitter()
        fake.defaultResult = .failure(AppError.message("rating must be 1..3"))
        let store = FeedbackStore(submitCall: fake.call)
        let d = draft("a", checkpoint: 5)

        let outcome = await store.submit(d, token: "t")

        XCTAssertEqual(outcome, .failed)
        XCTAssertTrue(outboxUnderTest().all().isEmpty, "error ที่ retry ไม่ได้ต้องไม่ถูกเก็บเข้าคิว")
    }

    /// ทางสำเร็จเดิม (รวม 409/403 ที่เป็นสถานะปลายทางแต่ไม่ใช่ error) ต้องยังล้างของค้างคิวเหมือนเดิม
    /// แม้ draft ตัวนี้เคยเข้าคิวไว้จาก attempt ก่อนหน้าที่ offline
    @MainActor
    func testSubmitSuccessReturnsOutcomeAndClearsQueue() async {
        let fake = FakeSubmitter()
        fake.defaultResult = .success(.alreadyAnswered)
        let store = FeedbackStore(submitCall: fake.call)
        let d = draft("a", checkpoint: 5)
        outboxUnderTest().add(d)

        let outcome = await store.submit(d, token: "t")

        XCTAssertEqual(outcome, .alreadyAnswered)
        XCTAssertTrue(outboxUnderTest().all().isEmpty)
    }

    // MARK: - flush

    /// draft ตัวแรกพังแบบ terminal ต้องไม่บล็อกตัวถัดไป — ทั้งคู่ถูกเรียกและหลุดจากคิวทั้งคู่
    /// (ตัวแรกเพราะทิ้งแบบ terminal ตัวที่สองเพราะสำเร็จ) คิวมีได้ถึง ~8 ชิ้นต่อคน ของพังชิ้นเดียว
    /// ห้ามพักคิวทั้งคิวไว้ถาวร
    @MainActor
    func testFlushDropsTerminalDraftAndContinuesToNext() async {
        let fake = FakeSubmitter()
        fake.resultsByClientId["bad"] = .failure(AppError.message("rating must be 1..3"))
        fake.resultsByClientId["good"] = .success(.saved)
        let store = FeedbackStore(submitCall: fake.call)
        outboxUnderTest().add(draft("bad", checkpoint: 1))
        outboxUnderTest().add(draft("good", checkpoint: 2))

        await store.flush(token: "t")

        XCTAssertEqual(fake.calledClientIds, ["bad", "good"], "ต้องยิงตัวถัดไปต่อ ไม่ใช่หยุดที่ตัวแรกที่พัง")
        XCTAssertTrue(outboxUnderTest().all().isEmpty, "ตัวพังถูกทิ้ง ตัวดีถูกส่งสำเร็จ ทั้งคู่ต้องหลุดจากคิว")
    }

    /// AppError.offline ต้องหยุดทั้งรอบทันที ไม่แตะ draft ที่เหลือเลย (เน็ตยังไม่กลับมา ไล่ยิงต่อ
    /// เปลืองเปล่า) ต่างจาก terminal failure ข้างบนที่ไปต่อได้
    @MainActor
    func testFlushStopsOnOfflineAndLeavesRestQueued() async {
        let fake = FakeSubmitter()
        fake.resultsByClientId["first"] = .failure(AppError.offline)
        fake.resultsByClientId["second"] = .success(.saved)
        let store = FeedbackStore(submitCall: fake.call)
        outboxUnderTest().add(draft("first", checkpoint: 1))
        outboxUnderTest().add(draft("second", checkpoint: 2))

        await store.flush(token: "t")

        XCTAssertEqual(fake.calledClientIds, ["first"], "offline ต้องหยุดทั้งรอบ ห้ามลามไปตัวถัดไป")
        XCTAssertEqual(outboxUnderTest().all().map(\.clientId), ["first", "second"],
                       "ทั้งคู่ต้องยังอยู่ในคิว รอรอบหน้าที่เน็ตกลับมา")
    }
}
