import XCTest
import SwiftData
@testable import WBW

/// เทสกลุ่มนี้คุม apply/merge/purge/purgeAll/purgeForLogout — ก่อนหน้านี้ทั้งหมด private และไม่มีเทส
/// ใดเรียกถึงเลย (ตามที่รีวิวรอบสุดท้ายชี้ไว้) ใช้ ModelContainer ในหน่วยความจำ ไม่แตะดิสก์ ไม่ต้องมีเน็ต —
/// เข้าถึงผ่าน testSetup(...) ซึ่งตั้งค่าตรงๆ โดยไม่เรียก start() (กัน Task ยิง network จริงตอนเทส)
@MainActor
final class ChatSessionPersistenceTests: XCTestCase {

    /// **ปักว่าไม่ได้อยู่ในโหมดเดโม่** — เทสชุดนี้พิสูจน์เส้นทางเน็ตจริง แต่ `APIClient`
    /// มีทางลัดของโหมดเดโม่อยู่ก่อนทุกฟังก์ชันที่ยิงเน็ต ถ้าโหมดเดโม่ติดอยู่คำขอจะไม่เคยออกไปถึง
    /// `URLProtocol` ปลอมเลย · เทสยูนิตรันใน**โปรเซสเดียวกับแอป** จึงอ่าน `UserDefaults`
    /// ใบเดียวกับที่ `Session.startDemo()` เขียน token เดโม่ทิ้งไว้ตอนรันแอปจริงบนซิมเครื่องเดียวกัน
    ///
    /// **นี่คือคำอธิบายของ "คลาสที่แกว่งเอง" ที่เอกสารหลายใบบันทึกไว้ว่าหาสาเหตุไม่ได้** —
    /// มันไม่ได้แกว่ง มันแดงตรงกับตอนที่มีคนเปิดแอปโหมดเดโม่ค้างไว้ก่อนรันเทส
    override func setUp() {
        super.setUp()
        DemoMode.forcedActive = false
    }

    override func tearDown() {
        DemoMode.forcedActive = nil
        super.tearDown()
    }
    private func makeContext() -> ModelContext {
        let schema = Schema([ChatMessage.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func dto(id: String, clientId: String, senderId: String = "other", body: String = "x") -> MessageDTO {
        MessageDTO(id: id, groupId: 1, senderId: senderId, clientId: clientId, body: body,
                   deviceTime: nil, createdAt: nil, firstName: "A", lastName: nil)
    }

    // ===== apply(_:for:) =====

    func testApplyMergesMessagesSetsCursorsAndMemberCountWhenGroupMatches() {
        let chat = ChatSession()
        chat.testSetup(groupId: 1, context: makeContext())
        let response = ChatSyncResponse(sinceId: 0, memberCount: 5,
                                         messages: [dto(id: "10", clientId: "c10")],
                                         cursors: [ReadCursor(userId: "other", lastReadId: 3)])

        chat.apply(response, for: 1)

        XCTAssertEqual(chat.messages.map(\.clientId), ["c10"])
        XCTAssertEqual(chat.memberCount, 5)
        XCTAssertEqual(chat.cursors, [ReadCursor(userId: "other", lastReadId: 3)])
    }

    func testApplyDropsResponseWhenGroupChangedMidFlight() {
        let chat = ChatSession()
        chat.testSetup(groupId: 1, context: makeContext())
        let response = ChatSyncResponse(sinceId: 0, memberCount: 5,
                                         messages: [dto(id: "10", clientId: "c10")], cursors: [])

        // จำลอง configure() สลับกลุ่มระหว่างที่ long-poll ค้างอยู่ (สูงสุด 25s) — response นี้เป็นของกลุ่ม 1
        // (เก่า) แต่ตอนนี้ session ย้ายไปกลุ่ม 2 แล้ว
        chat.testSetup(groupId: 2)
        chat.apply(response, for: 1)

        XCTAssertTrue(chat.messages.isEmpty, "response ของกลุ่มเก่าต้องไม่ถูกเอามาใช้กับกลุ่มปัจจุบัน")
        XCTAssertEqual(chat.memberCount, 0, "memberCount ต้องไม่ถูกเขียนทับด้วยเลขของกลุ่มเก่า")
    }

    // ===== merge(_:groupId:) =====

    func testMergeInsertsNewAndDedupesRepeatedServerId() {
        let chat = ChatSession()
        chat.testSetup(groupId: 1, context: makeContext())

        let fresh = chat.merge([dto(id: "5", clientId: "c5")], groupId: 1)
        XCTAssertEqual(fresh.map(\.clientId), ["c5"])
        XCTAssertEqual(chat.messages.count, 1)

        // ข้อความเดิมมาซ้ำ (long-poll คาบเกี่ยวรอบถัดไป) — ต้องไม่ถูกนับว่าใหม่หรือถูกแทรกซ้ำ
        let freshAgain = chat.merge([dto(id: "5", clientId: "c5")], groupId: 1)
        XCTAssertTrue(freshAgain.isEmpty, "server id ที่มีอยู่แล้วต้องไม่ถูกนับว่าใหม่อีกครั้ง")
        XCTAssertEqual(chat.messages.count, 1, "ต้องไม่มีแถวซ้ำ")
    }

    // ===== purge(upTo:) =====

    func testPurgeRemovesMessagesAtOrBelowSinceIdButKeepsPending() {
        let chat = ChatSession()
        chat.testSetup(groupId: 1, context: makeContext())
        _ = chat.merge([dto(id: "1", clientId: "c1"), dto(id: "5", clientId: "c5"),
                        dto(id: "6", clientId: "c6")], groupId: 1)
        chat.send("ยังไม่ส่ง", senderName: "me")   // token ว่าง → flushOutbox ไม่ยิง network จริง, สถานะค้าง .pending
        XCTAssertEqual(chat.messages.count, 4)

        chat.purge(upTo: 5)

        XCTAssertEqual(chat.messages.compactMap(\.serverId), [6])
        XCTAssertEqual(chat.messages.count, 2, "ข้อความที่ยังไม่ส่ง (pending) ต้องรอดจากการตัด")
    }

    // ===== purgeAll() — โดนเอาออกจากกลุ่ม (403) =====

    func testPurgeAllClearsPersistedKeysEvenWhenContextIsNil() {
        let chat = ChatSession()
        chat.testSetup(groupId: 42, myId: "me")   // ไม่ส่ง context — จำลอง edge case context ยัง nil
        UserDefaults.standard.set(99, forKey: "chat.cursor.42")
        UserDefaults.standard.set(50, forKey: "chat.read.42")
        defer {
            UserDefaults.standard.removeObject(forKey: "chat.cursor.42")
            UserDefaults.standard.removeObject(forKey: "chat.read.42")
        }

        chat.purgeAll()

        XCTAssertNil(UserDefaults.standard.object(forKey: "chat.cursor.42"),
                     "purgeAll ต้องล้าง cursor ที่ persist ไว้ แม้ context จะ nil")
        XCTAssertNil(UserDefaults.standard.object(forKey: "chat.read.42"),
                     "purgeAll ต้องล้าง read cursor ที่ persist ไว้ แม้ context จะ nil")
    }

    func testPurgeAllClearsIncomingSoStaleToastDoesNotRenderADeletedMessage() {
        let chat = ChatSession()
        chat.testSetup(groupId: 1, myId: "me")
        chat.incoming = ChatMessage(clientId: "x", serverId: 1, groupId: 1, senderId: "other",
                                    body: "hi", deviceTime: Date(), createdAt: Date(),
                                    senderName: "Other", state: .sent)

        chat.purgeAll()

        XCTAssertNil(chat.incoming, "toast ที่ค้างชี้ข้อความเดิมต้องถูกเคลียร์ ไม่งั้นจะ render @Model ที่ลบไปแล้ว")
    }

    /// น้องของเทสข้างบน — `purge(upTo:)` ก็ลบ `@Model` ทิ้งเหมือนกัน แต่เดิมไม่ได้เคลียร์ `incoming`
    ///
    /// เส้นทางที่พังจริง: toast ข้อความใหม่โผล่อยู่บนจอ (MainTabView ถือ `chat.incoming` ไว้ render)
    /// แล้ว sync รอบถัดไปได้ `since_id` ที่สูงกว่าข้อความนั้น (เกิดตอนถูกเอาออกแล้วเข้ากลุ่มใหม่
    /// ระหว่างที่ toast ยังไม่หาย) — `purge` ลบแถวนั้นจาก SwiftData ส่วน toast ยังถือ reference
    /// ไปที่ object ที่ตายแล้ว พออ่าน `.senderName`/`.body` ต่อคือแอปดับ
    func testPurgeUpToClearsIncomingWhenThatMessageIsCutOff() {
        let chat = ChatSession()
        let context = makeContext()
        chat.testSetup(groupId: 1, myId: "me", context: context)
        chat.merge([dto(id: "3", clientId: "c3")], groupId: 1)
        chat.incoming = chat.messages.first

        chat.purge(upTo: 5)

        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertNil(chat.incoming, "toast ที่ชี้ข้อความที่เพิ่งถูกตัดทิ้งต้องถูกเคลียร์ ไม่งั้น render @Model ที่ลบแล้ว")
    }

    /// อีกทิศ — ข้อความที่รอดจุดตัด toast ต้องไม่ถูกดับไปด้วย (กันแก้เกินมือเป็น `incoming = nil` ล้วน)
    func testPurgeUpToKeepsIncomingWhenThatMessageSurvives() {
        let chat = ChatSession()
        let context = makeContext()
        chat.testSetup(groupId: 1, myId: "me", context: context)
        chat.merge([dto(id: "9", clientId: "c9")], groupId: 1)
        chat.incoming = chat.messages.first

        chat.purge(upTo: 5)

        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertNotNil(chat.incoming)
    }

    /// **ข้อความที่เราส่งเองวนกลับมาทาง long-poll ต้อง promote แถว pending เดิม ไม่ใช่เพิ่มแถวใหม่**
    ///
    /// นี่คือทางเดินปกติของทุกข้อความที่ส่งสำเร็จ: optimistic insert (serverId nil) → POST →
    /// sync รอบถัดไปส่งแถวเดียวกันกลับมาพร้อม server id — regression ตรงนี้คือข้อความตัวเอง
    /// ขึ้นซ้ำสองฟองทุกครั้งที่ส่ง และไม่เคยมีเทสจับสาขานี้เลย (เทส dedupe เดิมจับเฉพาะแถว
    /// ที่ .sent ไปแล้ว)
    func testMergePromotesMyPendingMessageInsteadOfDuplicatingIt() {
        let chat = ChatSession()
        chat.testSetup(groupId: 1, myId: "me", context: makeContext())
        chat.send("สวัสดี", senderName: "ฉัน")   // token ว่าง — flush ที่ send จุดไว้จบเงียบ ไม่แตะเน็ต
        let cid = chat.messages.first?.clientId ?? ""
        XCTAssertNil(chat.messages.first?.serverId)

        let echoed = MessageDTO(id: "42", groupId: 1, senderId: "me", clientId: cid,
                                body: "สวัสดี", deviceTime: nil,
                                createdAt: "2026-08-24T09:00:01.000Z", firstName: "ฉัน", lastName: nil)
        _ = chat.merge([echoed], groupId: 1)

        XCTAssertEqual(chat.messages.count, 1, "ต้องยุบเข้าแถวเดิม ไม่ใช่กลายเป็นสองฟอง")
        XCTAssertEqual(chat.messages.first?.serverId, 42)
        XCTAssertEqual(chat.messages.first?.state, .sent)
    }

    // ===== purgeForLogout() =====

    func testPurgeForLogoutRemovesMessagesAcrossAllGroupsAndClearsAllChatDefaults() {
        // purgeForLogout กวาด UserDefaults.standard จริงทั้งเครื่อง: ทุกคีย์ `chat.*` +
        // blocklist ทุก scope — สแนปของที่คลาสอื่น (เช่น ChatModerationTests) ฝากไว้แล้วคืน
        // ให้หลังเทส ไม่งั้นลำดับการรันข้ามคลาสตัดสินว่าใครแดง
        let defaults = UserDefaults.standard
        let swept = defaults.dictionaryRepresentation().filter {
            $0.key.hasPrefix("chat.") || $0.key.hasPrefix(BlockedUsers.keyPrefix)
        }
        addTeardownBlock {
            for (key, value) in swept { defaults.set(value, forKey: key) }
        }

        let context = makeContext()
        let chat = ChatSession()
        chat.testSetup(groupId: 1, context: context)
        _ = chat.merge([dto(id: "1", clientId: "c1")], groupId: 1)

        // ข้อความค้างจากกลุ่มอื่นที่บัญชีเดิมเคยแคชไว้บนเครื่องนี้ (เช่นเคยอยู่กลุ่ม 2 มาก่อน) — ไม่ได้ผ่าน
        // session ปัจจุบันเลย (groupId ปัจจุบันคือ 1) แต่ยังอยู่ใน ModelContext เดียวกันที่แชร์กันทั้งเครื่อง
        let other = ChatMessage(clientId: "other", serverId: 2, groupId: 2, senderId: "x",
                                body: "y", deviceTime: Date(), createdAt: Date(),
                                senderName: "x", state: .sent)
        context.insert(other)
        try? context.save()
        UserDefaults.standard.set(7, forKey: "chat.cursor.2")
        UserDefaults.standard.set(7, forKey: "chat.read.2")
        defer {
            UserDefaults.standard.removeObject(forKey: "chat.cursor.1")
            UserDefaults.standard.removeObject(forKey: "chat.read.1")
            UserDefaults.standard.removeObject(forKey: "chat.cursor.2")
            UserDefaults.standard.removeObject(forKey: "chat.read.2")
        }

        chat.purgeForLogout()

        let remaining = (try? context.fetch(FetchDescriptor<ChatMessage>())) ?? []
        XCTAssertTrue(remaining.isEmpty, "logout ต้องล้างข้อความทุกกลุ่มที่แคชไว้ในเครื่อง ไม่ใช่แค่กลุ่มปัจจุบัน")
        XCTAssertNil(UserDefaults.standard.object(forKey: "chat.cursor.2"),
                     "cursor ของกลุ่มอื่น (ไม่ใช่กลุ่มปัจจุบัน) ต้องถูกล้างด้วย ไม่งั้นบัญชีถัดไปที่ login เครื่อง")
        XCTAssertNil(UserDefaults.standard.object(forKey: "chat.read.2"))
        XCTAssertTrue(chat.messages.isEmpty)
    }
}
