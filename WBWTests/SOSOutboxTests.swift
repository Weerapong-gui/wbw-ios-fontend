import XCTest
@testable import WBW

final class SOSOutboxTests: XCTestCase {
    private let backend = Backend.susProd

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: SOSOutbox.key(for: backend))
    }

    func testEmptyOutboxHasNoCase() {
        XCTAssertNil(SOSOutbox(backend: backend).current())
    }

    func testSavedDraftSurvivesAFreshOutboxInstance() {
        let draft = SOSDraft(clientId: "c1", deviceTime: "2026-08-06T10:00:00Z", forOther: false, ownerId: "u1")
        SOSOutbox(backend: backend).save(draft)
        XCTAssertEqual(SOSOutbox(backend: backend).current(), draft)
    }

    /// เคสมีได้ทีละหนึ่ง — เขียนทับเสมอ ไม่ต่อท้าย
    func testSavingAgainReplacesRatherThanQueues() {
        let outbox = SOSOutbox(backend: backend)
        outbox.save(SOSDraft(clientId: "c1", deviceTime: "2026-08-06T10:00:00Z", forOther: false, ownerId: "u1"))
        let second = SOSDraft(clientId: "c2", deviceTime: "2026-08-06T10:05:00Z", forOther: true, ownerId: "u1")
        outbox.save(second)
        XCTAssertEqual(outbox.current(), second)
    }

    /// key ผูกกับ backend เหมือน cache ทุกตัวในแอป — เคสของ backend หนึ่งต้องไม่โผล่ในอีกอันหนึ่ง
    func testTheKeyIsNamespacedPerBackend() {
        XCTAssertNotEqual(SOSOutbox.key(for: .susProd), SOSOutbox.key(for: .susLocal))
    }

    func testUpdatingWithAServerIDKeepsTheSameClientID() {
        let outbox = SOSOutbox(backend: backend)
        var draft = SOSDraft(clientId: "c1", deviceTime: "2026-08-06T10:00:00Z", forOther: false, ownerId: "u1")
        outbox.save(draft)
        draft.serverId = 42
        outbox.save(draft)
        XCTAssertEqual(outbox.current()?.clientId, "c1")
        XCTAssertEqual(outbox.current()?.serverId, 42)
    }
}
