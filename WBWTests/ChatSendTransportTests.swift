import XCTest
import SwiftData
@testable import WBW

/// ข้อความแชทต้องไม่กลายเป็น `.failed` เพราะเซิร์ฟเวอร์ล้นชั่วคราว
///
/// เดิม `APIClient.sendMessage` โยน `AppError.message` กับ **ทุก** status ที่ไม่ใช่ 200/201
/// และ `ChatSession.flushOutbox` catch-all แล้วตั้ง `m.state = .failed` ทันที · 502/503/524
/// จาก Cloudflare หน้า `api.studentunion.social` กับ 408/425 บนไวไฟภูเขาที่คนสองพันคนแย่งกันใช้
/// จึงกลายเป็นฟอง "ส่งไม่สำเร็จ แตะเพื่อลองใหม่" ทั้งที่ยิงซ้ำผ่านสบาย
///
/// ฝั่งความเห็นเช็คอินเจอเรื่องเดียวกันและแก้ไปแล้ว (ดูตารางเต็มที่ `APIClient.submitFeedback`)
/// แชทไม่ได้ยกท่านั้นมาใช้ · เทสชุดนี้คร่อมรอยต่อ "status ไหนกลายเป็น error ชนิดไหน แล้ว
/// outbox ทำอะไรต่อ" เหมือนที่ `FeedbackTransportTests` ทำไว้ ไม่ใช่เทสแค่ครึ่งเดียว
final class ChatSendTransportTests: XCTestCase {

    /// URLProtocol ปลอม — ดักเฉพาะ POST ข้อความแชท ไม่แตะเส้นทางอื่นของแอป
    final class StubURLProtocol: URLProtocol {
        /// nonisolated(unsafe): เหตุผลเดียวกับ `FeedbackTransportTests.StubURLProtocol`
        /// (สร้างบนคิวของ URLSession · เทสตั้งค่าก่อนยิงและอ่านหลังจบ ไม่มีการเขียนคาบกัน)
        nonisolated(unsafe) static var status = 201
        nonisolated(unsafe) static var body = Data()
        nonisolated(unsafe) static var requestCount = 0

        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.path.hasSuffix("/messages") == true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.requestCount += 1
            let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    /// 201 ของจริงจาก POST /wbw/groups/{id}/messages (รูปร่างตาม docs/backend-contract.md §3)
    private static func createdBody(clientId: String) -> Data {
        Data("""
        {"id":991,"group_id":1,"sender_id":"me","client_id":"\(clientId)","body":"ไง",
         "device_time":"2026-08-24T09:00:00.000Z","created_at":"2026-08-24T09:00:01.000Z",
         "first_name":"ดิน","last_name":"เดินดอย"}
        """.utf8)
    }

    override func setUp() {
        super.setUp()
        // ปักว่าไม่ได้อยู่ในโหมดเดโม่ — เหตุผลเต็มอยู่ที่ FeedbackTransportTests.setUp
        // (โหมดเดโม่มีทางลัดอยู่ก่อนทุกฟังก์ชันที่ยิงเน็ต คำขอจะไม่เคยถึง stub เลย)
        DemoMode.forcedActive = false
        URLProtocol.registerClass(StubURLProtocol.self)
        StubURLProtocol.status = 201
        StubURLProtocol.body = Self.createdBody(clientId: "c1")
        StubURLProtocol.requestCount = 0
    }

    override func tearDown() {
        DemoMode.forcedActive = nil
        URLProtocol.unregisterClass(StubURLProtocol.self)
        super.tearDown()
    }

    // MARK: - รอยต่อที่ 1: status → ชนิดของ error

    /// กันเทสทั้งไฟล์ผ่านด้วยเหตุผลผิด — ถ้า stub ไม่ดัก ทุกอันจะได้ AppError.offline แทน
    func testStubActuallyInterceptsAPIClient() async throws {
        let dto = try await APIClient.shared.sendMessage(
            token: "t", groupId: 1, clientId: "c1", body: "ไง",
            deviceTime: "2026-08-24T09:00:00.000Z")
        XCTAssertEqual(dto.id, "991")
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func testTransientStatusesThrowRetryable() async {
        // 408/425 = Cloudflare (ส่ง body ไม่จบ / TLS early data) · 429 = ล้น · 5xx = origin หรือ
        // gateway ล้ม · 404/407 = ทางผ่านเพี้ยนชั่วคราว · 599 = status ที่ยังไม่มีใครนึกถึง
        for status in [408, 425, 429, 500, 502, 503, 504, 524, 404, 407, 599] {
            StubURLProtocol.status = status
            StubURLProtocol.body = Data(#"{"error":"เซิร์ฟเวอร์ไม่ว่าง"}"#.utf8)
            do {
                _ = try await APIClient.shared.sendMessage(
                    token: "t", groupId: 1, clientId: "c1", body: "ไง",
                    deviceTime: "2026-08-24T09:00:00.000Z")
                XCTFail("status \(status) ต้องโยน error")
            } catch AppError.retryable {
                // ถูกแล้ว
            } catch {
                XCTFail("status \(status) ต้องเป็น .retryable ไม่ใช่ \(error)")
            }
        }
    }

    func testRequestFaultsThrowTerminalMessage() async {
        // ทุกตัวคือ error ที่เกิดจากตัว request เอง — ยิงซ้ำด้วย body/header/URL เดิมไม่มีวันผ่าน
        for status in [400, 401, 403, 405, 410, 413, 414, 415, 422] {
            StubURLProtocol.status = status
            StubURLProtocol.body = Data(#"{"error":"ส่งไม่ได้"}"#.utf8)
            do {
                _ = try await APIClient.shared.sendMessage(
                    token: "t", groupId: 1, clientId: "c1", body: "ไง",
                    deviceTime: "2026-08-24T09:00:00.000Z")
                XCTFail("status \(status) ต้องโยน error")
            } catch AppError.message {
                // ถูกแล้ว
            } catch {
                XCTFail("status \(status) ต้องเป็น .message ไม่ใช่ \(error)")
            }
        }
    }

    // MARK: - รอยต่อที่ 2: error → สถานะของข้อความใน outbox

    @MainActor
    private func session() -> ChatSession {
        let schema = Schema([ChatMessage.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let s = ChatSession()
        s.testSetup(groupId: 1, myId: "me", token: "t", context: ModelContext(container))
        return s
    }

    /// หัวใจของบั๊ก — 503 ต้องทิ้งข้อความไว้ที่ `.pending` ให้ sync loop รอบหน้าเก็บ
    @MainActor
    func testTransientFailureKeepsMessagePendingNotFailed() async {
        let s = session()
        StubURLProtocol.status = 503
        StubURLProtocol.body = Data(#"{"error":"เซิร์ฟเวอร์ไม่ว่าง"}"#.utf8)

        s.send("ไง", senderName: "ฉัน")
        await s.testFlushOutbox()

        XCTAssertEqual(s.messages.count, 1)
        XCTAssertEqual(s.messages.first?.state, .pending,
                       "503 ชั่วคราวต้องไม่กลายเป็น .failed ให้ผู้ใช้ต้องกด retry เอง")
    }

    @MainActor
    func testTerminalFailureMarksMessageFailed() async {
        let s = session()
        StubURLProtocol.status = 413
        StubURLProtocol.body = Data(#"{"error":"ข้อความยาวเกินไป"}"#.utf8)

        s.send("ไง", senderName: "ฉัน")
        await s.testFlushOutbox()

        XCTAssertEqual(s.messages.first?.state, .failed,
                       "413 ยิงซ้ำก็ไม่มีวันผ่าน ต้องบอกผู้ใช้ ไม่ใช่วนส่งเงียบๆ ตลอดไป")
    }

    @MainActor
    func testSuccessMarksMessageSent() async {
        let s = session()
        s.send("ไง", senderName: "ฉัน")
        let cid = s.messages.first?.clientId ?? ""
        StubURLProtocol.body = Self.createdBody(clientId: cid)

        await s.testFlushOutbox()

        XCTAssertEqual(s.messages.first?.state, .sent)
        XCTAssertEqual(s.messages.first?.serverId, 991)
    }

    /// 503 แล้วเน็ตกลับมาดี — flush รอบถัดไปต้องส่งของเดิมได้ ไม่ใช่ค้างเป็น .failed ถาวร
    @MainActor
    func testPendingMessageSurvivesTransientFailureAndSendsOnRetry() async {
        let s = session()
        StubURLProtocol.status = 503
        StubURLProtocol.body = Data(#"{"error":"เซิร์ฟเวอร์ไม่ว่าง"}"#.utf8)
        s.send("ไง", senderName: "ฉัน")
        await s.testFlushOutbox()
        XCTAssertEqual(s.messages.first?.state, .pending)

        let cid = s.messages.first?.clientId ?? ""
        StubURLProtocol.status = 201
        StubURLProtocol.body = Self.createdBody(clientId: cid)
        await s.testFlushOutbox()

        XCTAssertEqual(s.messages.first?.state, .sent)
    }
}
