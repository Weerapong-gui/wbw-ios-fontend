import XCTest
import SwiftData
@testable import WBW

/// คุมการตั้ง `incoming` — ข้อความที่ MainTabView เอาไปเด้ง toast ตอนไม่ได้เปิดจอแชท
///
/// มีเพราะเจอบั๊กจริง: เงื่อนไข toast ที่ MainTabView เช็คแค่ "มี incoming + ไม่ได้เปิดจอแชท +
/// สวิตช์แจ้งเตือนเปิด" ไม่เคยถาม BlockedUsers เลย — บล็อกคนก่อกวนแล้วฟองข้อความหายจากจอแชทจริง
/// แต่แบนเนอร์ข้อความของเขายังเด้งใส่หน้าอยู่ ซึ่งขัดเจตนาของระบบบล็อก (Guideline 1.2)
/// จุดคุมอยู่ที่ ChatSession.apply ที่เดียว เพราะเป็นทางเดียวที่เซ็ต incoming
@MainActor
final class ChatIncomingTests: XCTestCase {

    private func makeContext() -> ModelContext {
        let schema = Schema([ChatMessage.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func dto(id: String, clientId: String, senderId: String = "other") -> MessageDTO {
        MessageDTO(id: id, groupId: 1, senderId: senderId, clientId: clientId, body: "x",
                   deviceTime: nil, createdAt: nil, firstName: "A", lastName: nil)
    }

    private func response(_ messages: [MessageDTO]) -> ChatSyncResponse {
        ChatSyncResponse(sinceId: 0, memberCount: 3, messages: messages, cursors: [])
    }

    /// พฤติกรรมพื้นฐานที่ไม่เคยมีเทสจับ: จอแชทไม่เปิด + ข้อความใหม่จากคนอื่น = ได้ toast
    func testFreshMessageFromSomeoneElseBecomesIncoming() {
        let chat = ChatSession()
        chat.testSetup(groupId: 1, context: makeContext())

        chat.apply(response([dto(id: "10", clientId: "c10")]), for: 1)

        XCTAssertEqual(chat.incoming?.clientId, "c10")
    }

    func testMyOwnMessageNeverBecomesIncoming() {
        let chat = ChatSession()
        chat.testSetup(groupId: 1, myId: "me", context: makeContext())

        chat.apply(response([dto(id: "10", clientId: "c10", senderId: "me")]), for: 1)

        XCTAssertNil(chat.incoming, "ข้อความของตัวเองห้ามเด้ง toast ใส่ตัวเอง")
    }

    // ===== คนที่ถูกบล็อก =====

    /// บล็อกแล้วต้องเงียบจริง — ไม่ใช่หายจากจอแชทแต่ยังเด้งแบนเนอร์
    func testBlockedSenderDoesNotBecomeIncoming() {
        let chat = ChatSession()
        chat.testSetup(groupId: 1, context: makeContext())
        chat.isBlocked = { $0 == "bad" }

        chat.apply(response([dto(id: "10", clientId: "c10", senderId: "bad")]), for: 1)

        XCTAssertNil(chat.incoming, "ข้อความของคนที่ถูกบล็อกห้ามกลายเป็น toast")
    }

    /// batch เดียวกันมีทั้งคนถูกบล็อกและไม่ถูก — toast ต้องเป็นของคนที่มองเห็นได้คนล่าสุด
    /// ไม่ใช่เงียบไปทั้ง batch เพียงเพราะตัวท้ายสุดเป็นของคนถูกบล็อก
    func testBatchEndingWithBlockedSenderFallsBackToVisibleOne() {
        let chat = ChatSession()
        chat.testSetup(groupId: 1, context: makeContext())
        chat.isBlocked = { $0 == "bad" }

        chat.apply(response([dto(id: "10", clientId: "c10", senderId: "friend"),
                             dto(id: "11", clientId: "c11", senderId: "bad")]), for: 1)

        XCTAssertEqual(chat.incoming?.clientId, "c10",
                       "ต้องถอยไปหาข้อความของคนที่มองเห็นได้ ไม่ใช่เงียบทั้ง batch")
    }
}
