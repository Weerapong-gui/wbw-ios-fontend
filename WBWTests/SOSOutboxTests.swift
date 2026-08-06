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

    // MARK: - รีวิว Task 14 รอบสี่

    /// draft ที่เขียนไว้บนดิสก์โดย build ก่อนหน้า commit ที่เพิ่ม ownerId เข้ามา ไม่มีคีย์นี้ในไบต์เลย —
    /// ต้อง decode ผ่าน (ไม่ throw ทิ้งทั้งก้อน) โดย ownerId กลายเป็นค่าว่าง ไม่ใช่ทำให้ current() คืน
    /// nil เหมือน "ไม่มีเคสเลย" (พบจากรีวิว Task 14 รอบสี่ — ดูคอมเมนต์ที่ SOSDraft.init(from:))
    func testALegacyDraftMissingOwnerIdDecodesWithAnEmptyOwnerInsteadOfFailing() {
        let legacyJSON = """
        {"clientId":"legacy-1","deviceTime":"2026-08-01T09:00:00Z","forOther":false}
        """.data(using: .utf8)!
        UserDefaults.standard.set(legacyJSON, forKey: SOSOutbox.key(for: backend))

        let draft = SOSOutbox(backend: backend).current()
        XCTAssertEqual(draft?.clientId, "legacy-1", "field เดิมทั้งหมดต้องยัง decode ได้ปกติ")
        XCTAssertEqual(draft?.ownerId, "", "ownerId ที่หายไปต้องกลายเป็นค่าว่าง ไม่ใช่ทำให้ decode พังทั้งก้อน")
    }

    /// ไบต์ที่เสียหายจริง (ไม่ใช่ JSON เลยด้วยซ้ำ ไม่ใช่แค่คีย์หาย) ต้องถูกล้างออกจาก UserDefaults ตอน
    /// current() เจอเข้า ไม่ใช่แค่คืน nil เฉยๆ แล้วปล่อยไบต์เสียค้างอยู่ตลอดกาลจนกว่า save() ครั้งหน้า
    /// จะทับ (พบจากรีวิว Task 14 รอบสี่)
    func testUnreadableBytesAreClearedByCurrentRatherThanLeftLingering() {
        UserDefaults.standard.set(Data([0xFF, 0x00, 0xDE, 0xAD, 0xBE, 0xEF]), forKey: SOSOutbox.key(for: backend))

        XCTAssertNil(SOSOutbox(backend: backend).current())
        XCTAssertNil(UserDefaults.standard.data(forKey: SOSOutbox.key(for: backend)),
                     "ไบต์ที่อ่านไม่ได้ต้องถูกล้างออกจริง ไม่ใช่แค่คืน nil แล้วปล่อยค้างไว้")
    }
}
