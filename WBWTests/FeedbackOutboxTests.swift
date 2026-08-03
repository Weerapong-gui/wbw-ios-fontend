import XCTest
@testable import WBW

/// outbox เก็บความเห็นที่ส่งไม่สำเร็จไว้ใน UserDefaults
///
/// คนยืนอยู่กลางเขา สัญญาณไม่แน่ กดส่งแล้วเน็ตหลุดต้องไม่หายไปเฉยๆ
/// key ต้องแยกตาม backend เหมือน cache ตัวอื่นทุกตัวในแอป — checkpoint_id คนละชุด
final class FeedbackOutboxTests: XCTestCase {

    private func freshOutbox(_ backend: Backend = .susLocal) -> FeedbackOutbox {
        UserDefaults.standard.removeObject(forKey: FeedbackOutbox.key(for: backend))
        return FeedbackOutbox(backend: backend)
    }

    private func draft(_ id: String, checkpoint: Int = 1) -> FeedbackDraft {
        FeedbackDraft(clientId: id, checkpointId: checkpoint, rating: 3,
                      comment: "ดี", deviceTime: "2026-08-29T09:00:00Z")
    }

    override func tearDown() {
        for b in [Backend.prodNode, .nodeLocal, .susLocal, .susProd, .susLan] {
            UserDefaults.standard.removeObject(forKey: FeedbackOutbox.key(for: b))
        }
        super.tearDown()
    }

    func testKeyDiffersPerBackend() {
        let keys = Set([Backend.prodNode, .nodeLocal, .susLocal, .susProd, .susLan]
            .map(FeedbackOutbox.key(for:)))
        XCTAssertEqual(keys.count, 5, "ทุก backend ต้องได้ key ไม่ซ้ำกัน")
    }

    func testAddThenAllRoundTrips() {
        let box = freshOutbox()
        box.add(draft("a"))
        XCTAssertEqual(box.all().map(\.clientId), ["a"])

        let reread = FeedbackOutbox(backend: .susLocal)
        XCTAssertEqual(reread.all().map(\.clientId), ["a"], "ต้องอ่านกลับได้จาก UserDefaults")
    }

    func testAddSameClientIdDoesNotDuplicate() {
        let box = freshOutbox()
        box.add(draft("a"))
        box.add(draft("a"))
        XCTAssertEqual(box.all().count, 1)
    }

    /// ตอบฐานเดิมซ้ำด้วย client_id ใหม่ ต้องแทนที่ของเดิมในคิว ไม่ใช่กองสองอัน
    func testAddSameCheckpointReplaces() {
        let box = freshOutbox()
        box.add(draft("a", checkpoint: 4))
        box.add(draft("b", checkpoint: 4))
        XCTAssertEqual(box.all().map(\.clientId), ["b"])
    }

    func testRemoveByClientId() {
        let box = freshOutbox()
        box.add(draft("a", checkpoint: 1))
        box.add(draft("b", checkpoint: 2))
        box.remove(clientId: "a")
        XCTAssertEqual(box.all().map(\.clientId), ["b"])
    }

    /// remove(checkpointId:) ต้องเล็งด้วย checkpoint ไม่ใช่ clientId และไม่แตะฐานอื่น — ไม่ใช่เทส "ลบได้
    /// หลาย draft พร้อมกันของฐานเดียว" เพราะสภาพนั้นเกิดไม่ได้ (add() กันไว้แล้วว่าฐานเดียวมีค้างได้อย่าง
    /// มาก 1 draft เสมอ ดู testAddSameCheckpointReplaces)
    func testRemoveByCheckpointOnlyAffectsThatCheckpoint() {
        let box = freshOutbox()
        box.add(draft("old", checkpoint: 4))
        box.add(draft("other", checkpoint: 7))
        box.remove(checkpointId: 4)
        XCTAssertEqual(box.all().map(\.clientId), ["other"], "ฐานอื่นต้องไม่ถูกกระทบ")
    }

    func testOtherBackendQueueIsInvisible() {
        let box = freshOutbox(.susLocal)
        box.add(draft("a"))
        XCTAssertTrue(FeedbackOutbox(backend: .prodNode).all().isEmpty)
    }
}
