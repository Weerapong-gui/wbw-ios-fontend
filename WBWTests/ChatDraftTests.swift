import XCTest
import SwiftData
@testable import WBW

/// ตัวตัดสิน "ร่างนี้ส่งได้ไหม" ต้องมีตัวเดียวทั้งแอป
///
/// เดิมมีสองตัวที่ไม่ตรงกัน: ปุ่มส่งใน `GroupChatView` เช็คด้วย `.whitespaces` ส่วน
/// `ChatSession.send` เช็คด้วย `.whitespacesAndNewlines` — ร่างที่มีแต่ขึ้นบรรทัดใหม่
/// ("\n\n" ซึ่งเกิดง่ายมากเพราะช่องพิมพ์เป็น `axis: .vertical` ปุ่ม Return = ขึ้นบรรทัด)
/// จึงเปิดปุ่มให้กดได้ แต่ guard ฝั่ง store เตะทิ้ง แล้ว view ก็ล้างช่องต่อ
/// = **ข้อความหายเงียบ ไม่มีฟอง ไม่มี error ไม่มีอะไรบอกว่าไม่ได้ส่ง**
final class ChatDraftTests: XCTestCase {

    func testBlankDraftsCannotSend() {
        XCTAssertFalse(ChatDraft.canSend(""))
        XCTAssertFalse(ChatDraft.canSend("   "))
        XCTAssertFalse(ChatDraft.canSend("\t"))
    }

    /// หัวใจของบั๊ก — ตัวเก่าที่ใช้ `.whitespaces` ตอบ true กับสามอันนี้ทั้งหมด
    func testNewlineOnlyDraftsCannotSend() {
        XCTAssertFalse(ChatDraft.canSend("\n"))
        XCTAssertFalse(ChatDraft.canSend("\n\n\n"))
        XCTAssertFalse(ChatDraft.canSend(" \n \n "))
    }

    func testDraftWithRealTextCanSend() {
        XCTAssertTrue(ChatDraft.canSend("ไง"))
        XCTAssertTrue(ChatDraft.canSend("  ไง  "))
        XCTAssertTrue(ChatDraft.canSend("\nไง\n"))
    }

    /// อีโมจิล้วนคือข้อความจริง ห้ามถูกนับเป็นร่างว่าง
    func testEmojiOnlyDraftCanSend() {
        XCTAssertTrue(ChatDraft.canSend("🌲"))
    }
}

/// ผูกสองฝั่งเข้าหากัน — เทสข้างบนยันตัวตัดสิน เทสนี้ยันว่า `ChatSession.send` **ตัดสินเหมือนกัน**
///
/// ถ้าวันหนึ่งมีใครแก้ trimming ฝั่งใดฝั่งหนึ่งอีก อันนี้จะแดงก่อนที่ผู้ใช้จะเจอข้อความหายเงียบ
@MainActor
final class ChatSendAgreementTests: XCTestCase {
    private func makeContext() -> ModelContext {
        let schema = Schema([ChatMessage.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func session() -> ChatSession {
        let s = ChatSession()
        s.testSetup(groupId: 1, myId: "me", context: makeContext())
        return s
    }

    func testStoreRejectsExactlyWhatCanSendRejects() {
        for draft in ["", "   ", "\n", "\n\n\n", " \n \n "] {
            let s = session()
            s.send(draft, senderName: "ฉัน")
            XCTAssertFalse(ChatDraft.canSend(draft), "canSend ต้องปฏิเสธ \(draft.debugDescription)")
            XCTAssertTrue(s.messages.isEmpty, "store ต้องไม่สร้างข้อความจาก \(draft.debugDescription)")
        }
    }

    func testStoreAcceptsWhatCanSendAcceptsAndTrimsIt() {
        let s = session()
        s.send("  ไง\n", senderName: "ฉัน")
        XCTAssertTrue(ChatDraft.canSend("  ไง\n"))
        XCTAssertEqual(s.messages.count, 1)
        XCTAssertEqual(s.messages.first?.body, "ไง")
    }
}
