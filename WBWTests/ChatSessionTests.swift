import XCTest
@testable import WBW

final class ChatSessionTests: XCTestCase {
    private func msg(_ id: Int64?, _ sender: String) -> ChatMessage {
        ChatMessage(clientId: "c\(id ?? -1)-\(sender)", serverId: id, groupId: 1,
                    senderId: sender, body: "x", deviceTime: Date(), createdAt: Date(),
                    senderName: sender, state: id == nil ? .pending : .sent)
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
}
