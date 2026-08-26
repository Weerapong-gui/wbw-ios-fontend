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
}
