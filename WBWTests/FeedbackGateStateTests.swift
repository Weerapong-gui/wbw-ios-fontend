import XCTest
@testable import WBW

/// กติกาการตัดสินใจของ feedback gate — ยกจาก FeedbackGate.kt ฝั่ง Android คำต่อคำ
/// (สเปก: docs/superpowers/specs/2026-08-26-feedback-gate-and-event-design.md)
final class FeedbackGateStateTests: XCTestCase {

    private func item(_ id: Int, answered: Bool, at: String) -> CheckinProgressItem {
        CheckinProgressItem(checkpointId: id, name: "ฐาน \(id)", activityName: nil,
                            sequence: id, at: at, answered: answered,
                            rating: answered ? 4 : nil, comment: nil)
    }

    // ===== ฟิลด์ใหม่บน CheckinProgress =====

    /// server ยังไม่ส่ง event_feedback_answered มา (SUS ยังไม่มี endpoint) — ขาดต้องเป็น false
    /// ไม่ใช่ decode ล่ม: ถามซ้ำดีกว่าแอปเปิดไม่ขึ้น
    func testEventFeedbackAnsweredDefaultsToFalseWhenAbsent() throws {
        let json = #"{"total":2,"checked_in":[]}"#
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let p = try dec.decode(CheckinProgress.self, from: Data(json.utf8))
        XCTAssertFalse(p.eventFeedbackAnswered)
    }

    func testEventFeedbackAnsweredDecodesWhenPresent() throws {
        let json = #"{"total":2,"checked_in":[],"event_feedback_answered":true}"#
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let p = try dec.decode(CheckinProgress.self, from: Data(json.utf8))
        XCTAssertTrue(p.eventFeedbackAnswered)
    }

    /// complete สูตรเดียวกับ Android: total > 0 && count >= total —
    /// งานที่ไม่มีฐานเลยต้องไม่นับว่าจบ ไม่งั้น event form เด้งใส่ทุกคนตั้งแต่ยังไม่เริ่มเดิน
    func testCompleteRequiresANonZeroTotalFullyCollected() {
        XCTAssertFalse(CheckinProgress(total: 0, checkedIn: []).complete,
                       "งานที่ไม่มีฐาน = ยังไม่จบ ไม่ใช่จบตั้งแต่เกิด")
        XCTAssertFalse(CheckinProgress(total: 2, checkedIn: [item(1, answered: true, at: "a")]).complete)
        XCTAssertTrue(CheckinProgress(total: 1, checkedIn: [item(1, answered: true, at: "a")]).complete)
    }

    // ===== decide =====

    func testNoProgressMeansNoGate() {
        XCTAssertNil(FeedbackGateState.decide(progress: nil, eventDismissed: false))
    }

    /// ทีละฐาน เรียงตามลำดับที่เดินถึง — โดนสแกนสามฐานตอนมือถืออยู่ในกระเป๋า
    /// ต้องเจอฟอร์มของฐานแรกก่อน ไม่ใช่ฐานล่าสุด (ตรงข้ามกับ toast)
    func testPendingBaseComesOldestFirst() {
        let p = CheckinProgress(total: 5, checkedIn: [
            item(3, answered: false, at: "2026-08-29T10:30:00Z"),
            item(1, answered: false, at: "2026-08-29T09:00:00Z"),
            item(2, answered: true,  at: "2026-08-29T10:00:00Z"),
        ])
        XCTAssertEqual(FeedbackGateState.decide(progress: p, eventDismissed: false),
                       .base(p.checkedIn[1]), "ฐานที่ถึงก่อนต้องถูกถามก่อน")
    }

    func testAllAnsweredButRouteUnfinishedMeansNoGate() {
        let p = CheckinProgress(total: 5, checkedIn: [item(1, answered: true, at: "a")])
        XCTAssertNil(FeedbackGateState.decide(progress: p, eventDismissed: false))
    }

    /// ครบทุกฐาน + ตอบครบ + ยังไม่เคยตอบทั้งงาน = ถึงคิว event form
    func testEventDueWhenRouteCompleteAndEverythingAnswered() {
        let p = CheckinProgress(total: 1, checkedIn: [item(1, answered: true, at: "a")])
        XCTAssertEqual(FeedbackGateState.decide(progress: p, eventDismissed: false), .event)
    }

    /// ฐานค้างตอบมาก่อน event เสมอ — แม้เส้นทางจะครบแล้ว
    func testPendingBaseBeatsEventEvenWhenComplete() {
        let p = CheckinProgress(total: 1, checkedIn: [item(1, answered: false, at: "a")])
        XCTAssertEqual(FeedbackGateState.decide(progress: p, eventDismissed: false),
                       .base(p.checkedIn[0]))
    }

    func testEventAnsweredOnServerMeansNoGate() {
        let p = CheckinProgress(total: 1, checkedIn: [item(1, answered: true, at: "a")],
                                eventFeedbackAnswered: true)
        XCTAssertNil(FeedbackGateState.decide(progress: p, eventDismissed: false))
    }

    /// ข้ามไปก่อน (ส่งไม่สำเร็จ) = เงียบแค่รันนี้ — decide เคารพ flag ที่ caller ถือ
    func testEventDismissedThisRunMeansNoGate() {
        let p = CheckinProgress(total: 1, checkedIn: [item(1, answered: true, at: "a")])
        XCTAssertNil(FeedbackGateState.decide(progress: p, eventDismissed: true))
    }

    // ===== FeedbackGateItem — ตัวห่อให้ .fullScreenCover(item:) =====

    /// **id ต้องเปลี่ยนตามฐาน** — ตอบฐานแรกเสร็จแล้วฐานถัดไปขึ้นแทนที่ในคราวเดียว (cover ไม่ได้ปิด
    /// ระหว่างกลาง) ถ้า id เท่ากัน SwiftUI ถือว่าเป็น view เดิม @State ข้างใน (rating/comment/sent)
    /// ไม่รีเซ็ต = คะแนนที่พิมพ์ให้ฐาน A ไหลเข้าฟอร์มฐาน B — กับดักเดียวกับที่ Android จดไว้ที่
    /// viewModel(key:) และที่ .sheet(item:) ของ MainTabView ต้องใส่ .id(target.id) ด้วยเหตุผลเดียวกัน
    func testItemIdIsPerCheckpoint() {
        let a = FeedbackGateItem(state: .base(item(1, answered: false, at: "a")))
        let b = FeedbackGateItem(state: .base(item(2, answered: false, at: "b")))
        XCTAssertEqual(a?.id, "base-1")
        XCTAssertNotEqual(a?.id, b?.id, "คนละฐานต้องได้ id คนละตัว ไม่งั้นฟอร์มไม่ถูกสร้างใหม่")
    }

    /// event มีได้ครั้งเดียวทั้งงาน — id คงที่ ไม่ผูกกับฐานไหน
    func testEventItemHasStableId() {
        XCTAssertEqual(FeedbackGateItem(state: .event)?.id, "event")
    }

    /// nil เข้า nil ออก — "ไม่มี gate" ต้องไม่กลายเป็น item ที่เปิดจอเปล่า
    func testNoStateMeansNoItem() {
        XCTAssertNil(FeedbackGateItem(state: nil))
    }
}
