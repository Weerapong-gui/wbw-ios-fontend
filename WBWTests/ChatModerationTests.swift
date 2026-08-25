import XCTest
@testable import WBW

/// เครื่องมือจัดการเนื้อหาในแชทกลุ่ม — **Guideline 1.2 บังคับ ไม่ใช่ของแถม**
///
/// แชทกลุ่มคือ user-generated content · Apple บังคับสี่อย่างสำหรับแอปที่มี UGC:
/// กรองเนื้อหา, ทางรายงาน, ทางบล็อกคนที่ก่อกวน และช่องทางติดต่อที่เผยแพร่ไว้ ·
/// สามอย่างแรกอยู่ในแอป (ไฟล์นี้ค้ำไว้) อย่างที่สี่คือหน้า /support บนเว็บ
///
/// ทั้งหมดทำฝั่งเครื่องล้วน ไม่มี endpoint ใหม่ใน backend — บล็อกคือการซ่อนบนเครื่องนี้
/// และรายงานคือการเปิดแอปเมลพร้อมข้อมูลที่ทีมงานต้องใช้ตามหาข้อความนั้น
final class ChatModerationTests: XCTestCase {

    private var savedBlocklist: Any?

    override func setUp() {
        super.setUp()
        savedBlocklist = UserDefaults.standard.object(forKey: BlockedUsers.storageKey)
        UserDefaults.standard.removeObject(forKey: BlockedUsers.storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(savedBlocklist, forKey: BlockedUsers.storageKey)
        super.tearDown()
    }

    private func message(id: String, sender: String, name: String, body: String = "ข้อความ") -> ChatMessage {
        ChatMessage(clientId: id, serverId: 1, groupId: 1, senderId: sender, body: body,
                    deviceTime: Date(timeIntervalSince1970: 1_700_000_000), createdAt: nil,
                    senderName: name, state: .sent)
    }

    // MARK: - บล็อก

    func testBlockingHidesThatPersonsMessagesOnly() {
        let messages = [
            message(id: "a", sender: "u1", name: "หนึ่ง"),
            message(id: "b", sender: "u2", name: "สอง"),
            message(id: "c", sender: "u1", name: "หนึ่ง"),
        ]
        let visible = ChatModeration.visible(messages, blocked: ["u1"])
        XCTAssertEqual(visible.map(\.clientId), ["b"],
                       "ข้อความของคนที่บล็อกต้องหายไปทั้งหมด และของคนอื่นต้องอยู่ครบ")
    }

    func testNothingIsHiddenWhenNobodyIsBlocked() {
        let messages = [message(id: "a", sender: "u1", name: "หนึ่ง")]
        XCTAssertEqual(ChatModeration.visible(messages, blocked: []).count, 1)
    }

    func testBlocklistSurvivesRestartAndCanBeUndone() {
        let store = BlockedUsers()
        store.block("u9", name: "เก้า")
        XCTAssertTrue(store.isBlocked("u9"))

        // อ่านใหม่จากดิสก์ = เหมือนเปิดแอปรอบหน้า
        XCTAssertTrue(BlockedUsers().isBlocked("u9"), "บล็อกแล้วต้องรอดข้ามการเปิดแอป")

        store.unblock("u9")
        XCTAssertFalse(store.isBlocked("u9"))
        XCTAssertFalse(BlockedUsers().isBlocked("u9"), "ปลดบล็อกแล้วต้องหายจากดิสก์ด้วย")
    }

    /// เก็บชื่อไว้ด้วย ไม่ใช่แค่ id — จอปลดบล็อกต้องบอกได้ว่าใครคือใคร
    func testBlocklistRemembersTheNameForTheUnblockScreen() {
        let store = BlockedUsers()
        store.block("u9", name: "เก้า")
        XCTAssertEqual(store.entries.map(\.name), ["เก้า"])
        XCTAssertEqual(store.entries.map(\.id), ["u9"])
    }

    /// คีย์ต้องต่อ suffix ของโหมดเดโม่เหมือน cache ตัวอื่น ไม่งั้นบล็อกในโหมดเดโม่
    /// ไปโผล่ในบัญชีจริง (กติกาข้อ 6 ของ skill)
    func testStorageKeyFollowsTheDemoCacheScope() {
        XCTAssertEqual(BlockedUsers.storageKey, "wbw.chat.blocked" + CacheScope.suffix)
    }

    // MARK: - รายงาน

    func testReportOpensMailToTheEventTeamWithEnoughToFindTheMessage() throws {
        let m = message(id: "abc-123", sender: "u7", name: "เจ็ด", body: "ข้อความที่ถูกรายงาน")
        let url = try XCTUnwrap(ChatModeration.reportMailURL(for: m, reporterId: "me-1"))

        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertTrue(url.absoluteString.contains(Config.contactEmail),
                      "ต้องส่งไปกล่องเดียวกับที่นโยบายและหน้า /support ประกาศไว้")

        let decoded = url.absoluteString.removingPercentEncoding ?? ""
        for needle in ["abc-123", "u7", "me-1"] {
            XCTAssertTrue(decoded.contains(needle),
                          "อีเมลต้องมี \(needle) ไม่งั้นทีมงานตามหาข้อความนั้นไม่เจอ")
        }
    }

    // MARK: - ทางเข้าต้องมีอยู่จริงบนจอ

    /// ผู้ตรวจของ Apple ต้องกดเจอเอง — ปุ่มที่มีแต่ในโค้ดแต่ไม่ได้ต่อกับจอ = ตีกลับเหมือนไม่มี
    func testChatScreenOffersReportAndBlock() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let chat = try String(contentsOf: root.appendingPathComponent("WBW/GroupChatView.swift"),
                              encoding: .utf8)
        XCTAssertTrue(chat.contains("chat_report"), "จอแชทยังไม่มีปุ่มรายงาน")
        XCTAssertTrue(chat.contains("chat_block"), "จอแชทยังไม่มีปุ่มบล็อก")

        // ทางที่ **มองเห็นได้** ไม่ต้องกดค้าง — ผู้ตรวจของ Apple หาเมนูที่ซ่อนอยู่ไม่เจอ
        let members = try String(contentsOf: root.appendingPathComponent("WBW/GroupMembersView.swift"),
                                 encoding: .utf8)
        XCTAssertTrue(members.contains("chat_block"),
                      "โปรไฟล์สมาชิกในกลุ่มยังไม่มีปุ่มบล็อกที่กดเห็นได้โดยไม่ต้องกดค้างในแชท")

        let settings = try String(contentsOf: root.appendingPathComponent("WBW/SettingsView.swift"),
                                  encoding: .utf8)
        XCTAssertTrue(settings.contains("settings_blocked"),
                      "ตั้งค่ายังไม่มีจอ 'ผู้ใช้ที่บล็อกไว้' ให้ปลดบล็อก — บล็อกแล้วถอนไม่ได้ก็เป็นปัญหาเอง")
    }

    func testModerationCopyExistsInBothLanguages() {
        defer { Loc.use(.system) }
        for language in [AppLanguage.th, .en] {
            Loc.use(language)
            for key in ["chat_report", "chat_block", "chat_unblock",
                        "settings_blocked", "blocked_empty", "blocked_note"] {
                XCTAssertNotEqual(Loc.t(key), key,
                                  "ไม่มีคีย์ \(key) ในภาษา \(language) — ผู้ใช้จะเห็นชื่อคีย์บนเมนู")
            }
        }
    }

    // MARK: - ตัวกรองก่อนส่ง (Guideline 1.2 ข้อแรก)

    /// **Apple บังคับ "a method for filtering objectionable material from being posted"**
    ///
    /// สามข้อที่เหลือ (รายงาน · บล็อก · ช่องทางติดต่อ) มีมาตั้งแต่แรก แต่ข้อนี้ไม่เคยมีเลย
    /// ทั้งฝั่งแอปและฝั่ง SUS — แชทกลุ่มรับข้อความอะไรก็ได้ · ขาดข้อเดียวก็นับว่าไม่ครบสี่
    /// และเป็นเหตุตีกลับได้โดยไม่ต้องรอให้มีใครก่อกวนจริงก่อน
    func testCleanMessagesGoThrough() {
        for text in ["เจอกันที่ฐาน 3 นะ", "see you at base 3", "น้ำหมดแล้วครับ ใครมีเพิ่ม"] {
            XCTAssertTrue(ChatModeration.allowsSending(text), "ข้อความปกติต้องส่งได้: \(text)")
        }
    }

    func testThaiProfanityIsBlockedBeforeItIsPosted() {
        for text in ["ไอ้เหี้ย", "พูดอะไรของมึงควย", "เย็ดแม่"] {
            XCTAssertFalse(ChatModeration.allowsSending(text), "ต้องกันไว้ก่อนส่ง: \(text)")
        }
    }

    func testEnglishProfanityIsBlockedBeforeItIsPosted() {
        for text in ["what the fuck", "SHIT", "you bitch"] {
            XCTAssertFalse(ChatModeration.allowsSending(text), "ต้องกันไว้ก่อนส่ง: \(text)")
        }
    }

    /// **คำสะอาดที่มีคำหยาบซ่อนอยู่ข้างในต้องผ่าน** — กับดัก Scunthorpe ของจริง
    ///
    /// ฝั่งอังกฤษจึงเทียบขอบคำ ไม่ใช่ `contains` · ฝั่งไทยเทียบ `contains` ได้เพราะไม่มีช่องว่าง
    /// ระหว่างคำ แต่แลกด้วยการที่ลิสต์ต้องมีแต่คำที่ยาวพอจะไม่ไปโผล่ในคำสุภาพ (เช่นไม่ใส่ "หี"
    /// ซึ่งเป็นส่วนหนึ่งของ "หีบ")
    func testWordsThatMerelyContainAProfanityAreNotBlocked() {
        for text in ["Scunthorpe", "assassin", "classic analysis", "หีบสมบัติ", "ปลาหมึกสด"] {
            XCTAssertTrue(ChatModeration.allowsSending(text), "คำสุภาพต้องไม่โดนกัน: \(text)")
        }
    }

    /// ช่องว่างกับตัวพิมพ์ใหญ่-เล็กหลอกตัวกรองไม่ได้
    func testFilterIgnoresCaseAndSurroundingPunctuation() {
        XCTAssertFalse(ChatModeration.allowsSending("Fuck!"))
        XCTAssertFalse(ChatModeration.allowsSending("(shit)"))
    }
}
