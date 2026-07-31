import XCTest
@testable import WBW

final class ChatSessionTests: XCTestCase {
    private func msg(_ id: Int64?, _ sender: String) -> ChatMessage {
        ChatMessage(clientId: "c\(id ?? -1)-\(sender)", serverId: id, groupId: 1,
                    senderId: sender, body: "x", deviceTime: Date(), createdAt: Date(),
                    senderName: sender, state: id == nil ? .pending : .sent)
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
}
