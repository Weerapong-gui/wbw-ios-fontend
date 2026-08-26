import SwiftData
import XCTest
@testable import WBW

/// **ส่งครั้งเดียวแต่ได้สองฟอง เมื่อคำตอบของ POST หายไประหว่างทาง**
///
/// เส้นทางที่พัง (เจอตอนไล่บั๊ก "กดสองครั้งได้สองฟอง" เมื่อ 2026-08-27 · คนละเรื่องกัน):
/// POST ถึง server แล้ว server สร้างแถวเรียบร้อย **แต่คำตอบหายกลางทาง** (เน็ตหลุด/timeout →
/// `.offline`/`.retryable`) ข้อความในเครื่องจึงค้างเป็น `.pending` โดยไม่มี `serverId`
/// · พอ long-poll รอบถัดไปส่งแถวนั้นกลับมา **โดยที่ `client_id` ว่าง** ตัวถอดรหัสตั้งคีย์แทน
/// เป็น `srv-<id>` (ดู `MessageDTO.init(from:)`) → `merge` หาไม่เจอทั้งทาง clientId และ serverId
/// → แทรกฟองใหม่ ขณะที่ฟอง pending เดิมยังอยู่ = **สองฟองจากการส่งครั้งเดียว** และฟองที่ค้าง
/// จะถูก POST ซ้ำรอบหน้า กลายเป็นแถวที่สามที่ server
///
/// ตัวจับคู่ใช้ `device_time` เป็นหลัก ไม่ใช่การเดา: แอปเป็นคนสร้างค่านี้แล้วส่งไปกับ POST
/// (`sendMessage` ส่ง `device_time`) server จึง echo ค่าเดิมกลับมา — คู่ที่ถูกต้องจึงห่างกัน
/// แทบเป็นศูนย์ ไม่ใช่การจับคู่แบบหลวม ๆ ด้วยเนื้อความอย่างเดียว
@MainActor
final class ChatLostEchoTests: XCTestCase {

    private func session() -> ChatSession {
        let schema = Schema([ChatMessage.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let s = ChatSession()
        s.testSetup(groupId: 1, myId: "me", context: ModelContext(container))
        return s
    }

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// DTO ที่ server ส่งกลับมาโดยไม่มี `client_id` — ผ่านตัวถอดรหัสจริง ไม่ได้ประกอบเอง
    /// เพื่อให้คีย์แทน `srv-<id>` มาจากทางเดียวกับของจริง
    private func echoWithoutClientId(id: Int, body: String, deviceTime: Date,
                                     senderId: String = "me") throws -> MessageDTO {
        let json = """
        {"id": \(id), "group_id": 1, "sender_id": "\(senderId)", "client_id": null,
         "body": "\(body)", "device_time": "\(iso.string(from: deviceTime))",
         "created_at": "\(iso.string(from: deviceTime.addingTimeInterval(1)))",
         "first_name": "ฉัน", "last_name": null}
        """
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(MessageDTO.self, from: Data(json.utf8))
    }

    // MARK: - อาการ

    func testAnEchoWithoutClientIdPromotesMyStuckMessageInsteadOfDuplicatingIt() throws {
        let s = session()
        s.send("ถึงฐาน 5 แล้ว", senderName: "ฉัน")
        let stuck = try XCTUnwrap(s.messages.first)
        XCTAssertNil(stuck.serverId, "ตั้งต้น: ยังไม่ได้คำตอบจาก server")

        let echo = try echoWithoutClientId(id: 991, body: "ถึงฐาน 5 แล้ว",
                                           deviceTime: stuck.deviceTime)
        s.merge([echo], groupId: 1)

        XCTAssertEqual(s.messages.count, 1, """
            ส่งครั้งเดียวต้องได้ฟองเดียว — ฟองที่ค้างต้องถูกเลื่อนเป็น .sent ไม่ใช่มีเพื่อนใหม่มาต่อท้าย
            """)
        XCTAssertEqual(s.messages.first?.serverId, 991)
        XCTAssertEqual(s.messages.first?.state, .sent,
                       "ฟองที่ค้างต้องเลิกค้าง ไม่งั้นมันจะถูก POST ซ้ำรอบหน้าเป็นแถวที่สาม")
    }

    // MARK: - ตัวจับคู่ต้องไม่หลวมจนไปฉกของคนอื่น

    func testAnEchoFromSomeoneElseNeverStealsMyPendingMessage() throws {
        let s = session()
        s.send("ถึงแล้ว", senderName: "ฉัน")
        let mine = try XCTUnwrap(s.messages.first)

        // คนอื่นพิมพ์คำเดียวกันในวินาทีเดียวกัน — เกิดขึ้นได้จริงในกลุ่มที่กำลังเดินถึงฐานพร้อมกัน
        let echo = try echoWithoutClientId(id: 992, body: "ถึงแล้ว",
                                           deviceTime: mine.deviceTime, senderId: "other")
        s.merge([echo], groupId: 1)

        XCTAssertEqual(s.messages.count, 2, "ข้อความของคนอื่นต้องขึ้นเป็นฟองของเขาเอง")
        XCTAssertNil(s.messages.first(where: { $0.senderId == "me" })?.serverId,
                     "ของเราต้องยังค้างอยู่ ไม่ใช่ถูกเลื่อนสถานะด้วยแถวของคนอื่น")
    }

    func testAnEchoFromLongAgoDoesNotMatchAFreshPendingMessage() throws {
        let s = session()
        s.send("555", senderName: "ฉัน")
        let mine = try XCTUnwrap(s.messages.first)

        // เนื้อความเดียวกันแต่คนละครั้ง (ห่างกันเป็นนาที) — ห้ามจับคู่กัน
        let echo = try echoWithoutClientId(id: 993, body: "555",
                                           deviceTime: mine.deviceTime.addingTimeInterval(-600))
        s.merge([echo], groupId: 1)

        XCTAssertEqual(s.messages.count, 2)
        XCTAssertNil(s.messages.first(where: { $0.state == .pending })?.serverId)
    }

    /// echo ที่มี `client_id` จริงแต่ไม่ตรงกับของในเครื่อง = ข้อความของคนอื่นตามปกติ
    /// ต้องแทรกเป็นฟองใหม่เหมือนเดิม — ตัวจับคู่ใหม่ต้องไม่ไปยุ่งกับเส้นทางปกติ
    func testANormalEchoWithARealClientIdStillInsertsAsBefore() {
        let s = session()
        let dto = MessageDTO(id: "994", groupId: 1, senderId: "other", clientId: "their-uuid",
                             body: "สวัสดี", deviceTime: nil, createdAt: nil,
                             firstName: "เขา", lastName: nil)
        s.merge([dto], groupId: 1)

        XCTAssertEqual(s.messages.count, 1)
        XCTAssertEqual(s.messages.first?.clientId, "their-uuid")
    }

    /// สองข้อความค้างที่เนื้อความเหมือนกัน — echo ต้องไปเข้าคู่กับตัวที่เวลาใกล้ที่สุด
    /// ไม่ใช่ตัวแรกที่เจอ (ไม่งั้นอีกตัวจะค้างถาวรแล้วถูกส่งซ้ำ)
    func testTheEchoMatchesTheNearestPendingMessageWhenBodiesRepeat() throws {
        let s = session()
        let now = Date()
        for offset in [-30.0, 0.0] {
            let m = ChatMessage(clientId: "c\(offset)", serverId: nil, groupId: 1, senderId: "me",
                                body: "555", deviceTime: now.addingTimeInterval(offset),
                                createdAt: nil, senderName: "ฉัน", state: .pending)
            s.testInsert(m)
        }

        let echo = try echoWithoutClientId(id: 995, body: "555", deviceTime: now)
        s.merge([echo], groupId: 1)

        XCTAssertEqual(s.messages.count, 2, "ต้องไม่มีฟองที่สามงอกมา")
        let promoted = s.messages.filter { $0.serverId != nil }
        XCTAssertEqual(promoted.count, 1)
        XCTAssertEqual(promoted.first?.clientId, "c0.0", "ต้องเข้าคู่กับตัวที่เวลาใกล้ที่สุด")
    }
}
