import SwiftData
import XCTest
@testable import WBW

/// **กดปุ่มส่งเร็ว ๆ สองครั้ง ต้องได้ข้อความเดียว ไม่ใช่สองฟอง**
///
/// เจ้าของงานรายงานอาการนี้ 2026-08-27 · ไล่โค้ดแล้วไม่ใช่ภาพลวงบนจอตัวเอง: การกดครั้งที่สอง
/// สร้าง `ChatMessage` ใหม่พร้อม `clientId` ใหม่ ซึ่ง server มองเป็นคนละข้อความ (idempotent
/// เฉพาะ client_id เดิม) — ทั้งกลุ่มจึงเห็นซ้ำ ไม่ใช่แค่คนส่ง
///
/// ตัวกันเดิมมีชั้นเดียวคือ `.disabled(!ChatDraft.canSend(draft))` ที่ปุ่ม ซึ่งพึ่งสองอย่างที่
/// พึ่งไม่ได้: (1) ช่องพิมพ์ถูกล้างจริง — แต่ UITextView เขียนข้อความเก่ากลับเข้า binding ได้
/// (คอมเมนต์ยาวที่ `GroupChatView.send()` บันทึกอาการนี้ไว้เอง) (2) SwiftUI re-render ทัน
/// ก่อนนิ้วที่สองลง — ซึ่ง `SOSButton` เขียนบทเรียนไว้แล้วว่าการ์ดที่พึ่ง re-render ไม่ใช่การ์ด
///
/// ด่านจึงต้องอยู่ที่ store: เป็นทางผ่านเดียวของการส่งทุกทาง และเป็นชั้นเดียวที่เขียนเทส
/// พิสูจน์ได้จริง (จอแชทไม่มี tap tooling ในสภาพแวดล้อมนี้)
@MainActor
final class ChatDoubleSendTests: XCTestCase {

    private func session() -> ChatSession {
        let schema = Schema([ChatMessage.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let s = ChatSession()
        // token ว่างโดยตั้งใจ — `send` จุด `Task { flushOutbox() }` ไว้ ซึ่งจะจบเงียบทันทีที่
        // เห็น token ว่าง เทสจึงไม่แตะเน็ตเลย (ท่าเดียวกับ ChatSessionPersistenceTests)
        s.testSetup(groupId: 1, myId: "me", context: ModelContext(container))
        return s
    }

    // ===== อาการที่รายงานมา =====

    func testTappingSendTwiceQuicklyCreatesOneMessage() {
        let s = session()
        s.send("ถึงฐาน 5 แล้ว", senderName: "ฉัน")
        s.send("ถึงฐาน 5 แล้ว", senderName: "ฉัน")

        XCTAssertEqual(s.messages.count, 1, """
            กดสองครั้งได้สองฟอง — และเพราะ clientId คนละตัว server ก็เก็บสองแถวจริง
            ทั้งกลุ่มเห็นซ้ำ ไม่ใช่แค่คนส่ง
            """)
    }

    /// ค่าที่คืนกลับมีไว้ให้จอรู้ว่าการกดนั้นถูกกลืน — ไม่งั้นปุ่มสั่น haptic "ส่งแล้ว"
    /// ทั้งที่ไม่มีอะไรถูกส่ง ซึ่งสอนผู้ใช้ผิดว่ากดติดสองครั้ง
    func testTheSecondTapReportsThatNothingWasSent() {
        let s = session()
        XCTAssertTrue(s.send("ไง", senderName: "ฉัน"))
        XCTAssertFalse(s.send("ไง", senderName: "ฉัน"))
    }

    // ===== ด่านต้องไม่กว้างเกินจนกินเจตนาจริง =====

    func testTwoDifferentMessagesInARowBothGoThrough() {
        let s = session()
        s.send("หนึ่ง", senderName: "ฉัน")
        s.send("สอง", senderName: "ฉัน")

        XCTAssertEqual(s.messages.count, 2, "คนละข้อความคือคนละเจตนา ห้ามกลืน")
    }

    /// ตั้งใจส่งข้อความเดิมซ้ำหลังเว้นช่วง = เจตนาจริง ต้องส่งได้
    func testTheSameTextSentAgainAfterTheWindowGoesThrough() {
        let now = Date()
        let mine = ChatMessage(clientId: "c1", serverId: 1, groupId: 1, senderId: "me",
                               body: "555", deviceTime: now.addingTimeInterval(-5),
                               createdAt: nil, senderName: "ฉัน", state: .sent)
        XCTAssertFalse(ChatSession.isRepeatSend("555", of: mine, myId: "me", now: now),
                       "ห่างกัน 5 วินาทีคือคนตั้งใจพิมพ์ซ้ำ ไม่ใช่นิ้วเด้ง")
    }

    func testAnIdenticalMessageFromSomeoneElseDoesNotBlockMySend() {
        let now = Date()
        let theirs = ChatMessage(clientId: "c1", serverId: 1, groupId: 1, senderId: "other",
                                 body: "ถึงแล้ว", deviceTime: now.addingTimeInterval(-0.2),
                                 createdAt: nil, senderName: "เขา", state: .sent)
        XCTAssertFalse(ChatSession.isRepeatSend("ถึงแล้ว", of: theirs, myId: "me", now: now),
                       "คนอื่นเพิ่งพิมพ์คำเดียวกันต้องไม่ปิดปากเรา")
    }

    /// ไม่มีข้อความก่อนหน้าเลย (ข้อความแรกของห้อง) — ต้องส่งได้
    func testTheFirstMessageEverIsNeverARepeat() {
        XCTAssertFalse(ChatSession.isRepeatSend("สวัสดี", of: nil, myId: "me", now: Date()))
    }

    /// ช่องว่างหัวท้ายไม่ทำให้กลายเป็นคนละข้อความ — `send` ตัดก่อนเทียบเสมอ
    /// (ไม่งั้นการกดซ้ำที่คีย์บอร์ดแถมช่องว่างมาจะเล็ดลอดด่านไปได้)
    func testWhitespaceDoesNotDisguiseARepeat() {
        let now = Date()
        let mine = ChatMessage(clientId: "c1", serverId: nil, groupId: 1, senderId: "me",
                               body: "ไง", deviceTime: now.addingTimeInterval(-0.2),
                               createdAt: nil, senderName: "ฉัน", state: .pending)
        XCTAssertTrue(ChatSession.isRepeatSend("  ไง  ", of: mine, myId: "me", now: now))
    }
}
