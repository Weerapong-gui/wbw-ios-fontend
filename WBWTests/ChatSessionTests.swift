import XCTest
import SwiftData
@testable import WBW

final class ChatSessionTests: XCTestCase {
    private func msg(_ id: Int64?, _ sender: String) -> ChatMessage {
        ChatMessage(clientId: "c\(id ?? -1)-\(sender)", serverId: id, groupId: 1,
                    senderId: sender, body: "x", deviceTime: Date(), createdAt: Date(),
                    senderName: sender, state: id == nil ? .pending : .sent)
    }

    /// ModelContainer ในหน่วยความจำ — เหมือนแพทเทิร์นใน ChatSessionPersistenceTests ใช้กับ merge(...)
    /// เพื่อใส่ข้อความที่มี serverId จริง ให้ markRead() มีอะไรให้ขยับจริง (ดูเหตุผลเต็มที่
    /// testUnreadLineSnapshotTakenBeforeMarkRead ด้านล่าง)
    private func makeContext() -> ModelContext {
        let schema = Schema([ChatMessage.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    /// ข้อความปลอม ระบุ createdAt/deviceTime เองได้ — ใช้ทดสอบการเรียงตาม displayTime (createdAt ?? deviceTime)
    private func msg(_ id: Int64?, _ sender: String, createdAt: Date?, deviceTime: Date? = nil) -> ChatMessage {
        let dt = deviceTime ?? createdAt ?? Date()
        return ChatMessage(clientId: "c\(id ?? -1)-\(sender)-\(dt.timeIntervalSince1970)",
                           serverId: id, groupId: 1, senderId: sender, body: "x",
                           deviceTime: dt, createdAt: createdAt,
                           senderName: sender, state: id == nil ? .pending : .sent)
    }

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        return f.date(from: iso)!
    }

    func testUnreadCountsOnlyOthersMessagesAboveCursor() {
        let msgs = [msg(1, "a"), msg(2, "me"), msg(3, "b"), msg(nil, "me")]
        XCTAssertEqual(ChatSession.unreadCount(messages: msgs, myLastReadId: 1, myId: "me"), 1)
        XCTAssertEqual(ChatSession.unreadCount(messages: msgs, myLastReadId: 0, myId: "me"), 2)
        XCTAssertEqual(ChatSession.unreadCount(messages: msgs, myLastReadId: 9, myId: "me"), 0)
    }

    func testReadCountCountsCursorsAtOrAboveMessage() {
        let cursors = [ReadCursor(userId: "a", lastReadId: 5),
                       ReadCursor(userId: "b", lastReadId: 3),
                       ReadCursor(userId: "c", lastReadId: 0)]
        XCTAssertEqual(ChatSession.readCount(for: msg(3, "me"), cursors: cursors), 2)
        XCTAssertEqual(ChatSession.readCount(for: msg(5, "me"), cursors: cursors), 1)
        XCTAssertEqual(ChatSession.readCount(for: msg(6, "me"), cursors: cursors), 0)
    }

    func testReadCountIsZeroForUnsentMessage() {
        let cursors = [ReadCursor(userId: "a", lastReadId: 99)]
        XCTAssertEqual(ChatSession.readCount(for: msg(nil, "me"), cursors: cursors), 0)
    }

    func testPurgePredicateDropsSentMessagesAtOrBelowCutoffButKeepsPending() {
        let msgs = [msg(1, "a"), msg(5, "a"), msg(6, "a"), msg(nil, "me")]
        let kept = msgs.filter { ChatSession.survivesCutoff($0, sinceId: 5) }
        XCTAssertEqual(kept.compactMap(\.serverId), [6])
        XCTAssertEqual(kept.count, 2, "ข้อความที่ยังไม่ส่งต้องอยู่ต่อ")
    }

    // ===== เรียงตาม displayTime ไม่ใช่ serverId (id vs created_at คนละนาฬิกากันใน Postgres) =====

    func testSortOrdersByDisplayTimeNotServerId() {
        // จำลองบั๊กจริง: id 2 commit ก่อน (เพราะ transaction ของ id 1 ค้างจังหวะแล้วโดนแซง) แต่ created_at
        // (เวลาเริ่ม transaction) ของ id 1 เก่ากว่า — ต้องเรียงตาม created_at ให้ตรงกับที่ ChatRowBuilder สมมุติ
        let higherIdEarlierCreated = msg(2, "a", createdAt: date("2026-07-31T09:00:00+07:00"))
        let lowerIdLaterCreated = msg(1, "a", createdAt: date("2026-07-31T09:05:00+07:00"))
        let sorted = ChatSession.sorted([higherIdEarlierCreated, lowerIdLaterCreated])
        XCTAssertEqual(sorted.map(\.serverId), [2, 1],
                       "id 2 created_at เก่ากว่าต้องมาก่อน id 1 แม้ id จะต่ำกว่า")
    }

    func testSortTieBreaksByServerIdWhenDisplayTimeIsEqual() {
        let same = date("2026-07-31T09:00:00+07:00")
        let higherId = msg(2, "a", createdAt: same)
        let lowerId = msg(1, "a", createdAt: same)
        let sorted = ChatSession.sorted([higherId, lowerId])
        XCTAssertEqual(sorted.map(\.serverId), [1, 2], "เวลาเท่ากันเป๊ะ ต้อง tiebreak ด้วย serverId จากน้อยไปมาก")
    }

    func testSortKeepsUnsentMessagesLast() {
        // ข้อความยังไม่ส่งมี deviceTime เก่ากว่าข้อความที่ส่งแล้วด้วยซ้ำ — ถ้าเรียงตาม displayTime เฉยๆ
        // โดยไม่มี carve-out ให้ serverId เป็น nil จะหลุดไปอยู่หน้าแทน ต้องยังอยู่ท้ายเสมอเหมือนเดิม
        let pending = msg(nil, "a", createdAt: nil, deviceTime: date("2026-07-31T00:00:00+07:00"))
        let sent = msg(5, "a", createdAt: date("2026-07-31T09:00:00+07:00"))
        let sorted = ChatSession.sorted([sent, pending])
        XCTAssertEqual(sorted.map(\.serverId), [5, nil], "ข้อความยังไม่ส่งต้องอยู่ท้ายเสมอ แม้ deviceTime จะเก่ากว่า")
    }

    func testReadStatusText() {
        XCTAssertEqual(ChatReadStatus.text(readCount: 0, memberCount: 10), Loc.t("chat_sent"))
        XCTAssertEqual(ChatReadStatus.text(readCount: 3, memberCount: 10),
                       String(format: Loc.t("chat_read_by"), 3))
        // ครบทุกคนที่ไม่ใช่เรา = member_count - 1
        XCTAssertEqual(ChatReadStatus.text(readCount: 9, memberCount: 10),
                       String(format: Loc.t("chat_read_by_all"), 9))
        // กลุ่มมีเราคนเดียว — ไม่มีใครให้อ่าน
        XCTAssertEqual(ChatReadStatus.text(readCount: 0, memberCount: 1), Loc.t("chat_sent"))
    }

    /// ขอบ `memberCount == 0` (ยังไม่รู้จำนวนสมาชิก) — pin พฤติกรรมปัจจุบันไว้กันคนแก้พังเงียบ ๆ
    ///
    /// readCount > 0 พร้อม memberCount 0 **เกิดไม่ได้ในทางปฏิบัติ**: cursors กับ memberCount
    /// มากับ sync response ก้อนเดียวกันเสมอ (apply เซ็ตคู่กัน) เปิดจากแคชเย็น ๆ ได้ cursors ว่าง
    /// = readCount 0 → "ส่งแล้ว" ซึ่งถูก · ที่ pin ไว้คือขา readCount > 0: สูตร max(-1, 0)
    /// ทำให้ตกขา "อ่านครบ" — ถ้าวันหนึ่ง cursors ถูกแคชแยกจาก memberCount ขึ้นมา ขานี้จะ
    /// โกหกว่าอ่านครบทั้งที่ไม่รู้ด้วยซ้ำว่ากลุ่มมีกี่คน เทสนี้คือหมุดให้คนที่ทำแบบนั้นมาเจอ
    func testReadStatusWithUnknownMemberCount() {
        XCTAssertEqual(ChatReadStatus.text(readCount: 0, memberCount: 0), Loc.t("chat_sent"))
        XCTAssertEqual(ChatReadStatus.text(readCount: 2, memberCount: 0),
                       String(format: Loc.t("chat_read_by_all"), 2))
    }

    // ===== สแนปเส้น "ข้อความใหม่" ต้องเกิดก่อน markRead() เสมอ =====

    /// เส้น "ข้อความใหม่" คำนวณจากค่านี้ · ถ้าอ่านค่าสดจาก myLastReadId เส้นจะไม่มีวันโผล่
    /// เพราะ setScreenVisible เรียก markRead() ซึ่งดัน myLastReadId ขึ้นสุดในเฟรมเดียวกัน
    ///
    /// ต้องมีข้อความจริงที่ serverId เกิน myLastReadId เดิม (ผ่าน merge(...) ไม่ใช่แค่ testSetup เฉยๆ)
    /// ไม่งั้น markRead() จะเป็น no-op (guard maxId > myLastReadId ไม่ผ่าน เพราะ messages ว่าง maxId เลยเป็น 0
    /// เท่ากับ myLastReadId เดิมพอดี) แล้วเทสนี้จะผ่านไม่ว่าจะสแนปก่อนหรือหลัง markRead() ก็ตาม — ไม่พิสูจน์
    /// ลำดับที่เทสนี้มีไว้ยันเลย
    @MainActor
    func testUnreadLineSnapshotTakenBeforeMarkRead() {
        let s = ChatSession()
        s.testSetup(groupId: 1, myId: "me", context: makeContext())
        let dto = MessageDTO(id: "5", groupId: 1, senderId: "other", clientId: "c5", body: "x",
                             deviceTime: nil, createdAt: nil, firstName: "A", lastName: nil)
        _ = s.merge([dto], groupId: 1)   // ข้อความจากคนอื่น serverId 5 — markRead() มีอะไรให้ขยับจริง
        XCTAssertEqual(s.unreadLineSnapshot, .max, "ก่อนเปิดจอต้องแปลว่าอ่านหมดแล้ว")
        XCTAssertEqual(s.myLastReadId, 0, "ยังไม่เปิดจอ — ยังไม่มีอะไรถูก markRead")

        s.setScreenVisible(true)
        XCTAssertEqual(s.unreadLineSnapshot, 0, "สแนปต้องเป็นค่า myLastReadId ก่อน markRead")
        XCTAssertEqual(s.myLastReadId, 5, "markRead() ต้องขยับ myLastReadId ไปถึงข้อความล่าสุดจริง")
        XCTAssertLessThan(s.unreadLineSnapshot, s.myLastReadId,
                          "สแนปต้องค้างอยู่ค่าก่อน markRead ไม่ใช่ค่าหลัง — ถ้าเท่ากันแปลว่าสแนปไปเกิดหลัง markRead")

        s.setScreenVisible(false)
        XCTAssertEqual(s.unreadLineSnapshot, .max, "ปิดจอแล้วต้องรีเซ็ตกลับ")
    }
}
