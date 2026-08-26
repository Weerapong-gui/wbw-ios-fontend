import XCTest
@testable import WBW

/// รอยต่อ HTTP ของ long-poll แชท — `APIClient+Chat.swift` ทั้งไฟล์ไม่เคยมีเทสแตะเลย
/// ทั้งที่ 403 ของมันคือทางเดียวที่ลาก `purgeAll()` + `kickedOut` (ลบข้อความทั้งเครื่อง)
///
/// stub ดักเฉพาะ `/chat/sync` กับ `/chat/read` — ไม่ชนกับ stub ของ `ChatSendTransportTests`
/// ที่ดัก `/messages` (ทั้งสองลงทะเบียนกับ URLSession.shared เหมือนกัน แยกกันด้วย path)
final class ChatSyncTransportTests: XCTestCase {

    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var body = Data()
        nonisolated(unsafe) static var failsWithError = false
        /// URL ของทุก request ที่ผ่าน stub — ใช้พิสูจน์ query string (after/wait)
        nonisolated(unsafe) static var capturedURLs: [URL] = []

        override class func canInit(with request: URLRequest) -> Bool {
            let path = request.url?.path ?? ""
            return path.hasSuffix("/chat/sync") || path.hasSuffix("/chat/read")
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            if let url = request.url { Self.capturedURLs.append(url) }
            if Self.failsWithError {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private static let okBody = Data("""
    {"since_id":0,"member_count":3,
     "messages":[{"id":10,"group_id":1,"sender_id":"u1","client_id":"c10","body":"ไง",
                  "device_time":null,"created_at":"2026-08-24T09:00:01.000Z",
                  "first_name":"ดิน","last_name":null}],
     "cursors":[{"user_id":"u1","last_read_id":9}]}
    """.utf8)

    override func setUp() {
        super.setUp()
        DemoMode.forcedActive = false   // ทางลัดเดโม่อยู่ก่อนทุกฟังก์ชันที่ยิงเน็ต — ปักไว้ไม่งั้น stub ไม่เคยถูกเรียก
        URLProtocol.registerClass(StubURLProtocol.self)
        StubURLProtocol.status = 200
        StubURLProtocol.body = Self.okBody
        StubURLProtocol.failsWithError = false
        StubURLProtocol.capturedURLs = []
    }

    override func tearDown() {
        DemoMode.forcedActive = nil
        URLProtocol.unregisterClass(StubURLProtocol.self)
        super.tearDown()
    }

    func testSuccessfulSyncDecodesMessagesAndCursors() async throws {
        let r = try await APIClient.shared.chatSync(token: "t", groupId: 1, after: 0, wait: 0)
        XCTAssertEqual(r.memberCount, 3)
        XCTAssertEqual(r.messages.map(\.clientId), ["c10"])
        XCTAssertEqual(r.cursors, [ReadCursor(userId: "u1", lastReadId: 9)])
    }

    /// 403 = โดนเอาออกจากกลุ่ม — ต้องเป็น `.notInGroup` เป๊ะ ๆ ไม่ใช่ error ทั่วไป
    /// เพราะ syncLoop ใช้ case นี้ตัดสินใจ **ลบข้อความทั้งเครื่อง** (purgeAll + kickedOut)
    /// จำแนกผิดทางใดทางหนึ่ง = ลบข้อมูลคนที่ยังอยู่ในกลุ่ม หรือคนโดนเตะแล้ว loop วน backoff ตลอดไป
    func testForbiddenBecomesNotInGroup() async {
        StubURLProtocol.status = 403
        StubURLProtocol.body = Data(#"{"error":"ไม่ได้อยู่ในกลุ่ม"}"#.utf8)
        do {
            _ = try await APIClient.shared.chatSync(token: "t", groupId: 1, after: 0, wait: 0)
            XCTFail("403 ต้องโยน error")
        } catch AppError.notInGroup {
            // ถูกแล้ว
        } catch {
            XCTFail("403 ต้องเป็น .notInGroup ไม่ใช่ \(error)")
        }
    }

    func testServerErrorBecomesGenericMessageNotKickOut() async {
        StubURLProtocol.status = 500
        do {
            _ = try await APIClient.shared.chatSync(token: "t", groupId: 1, after: 0, wait: 0)
            XCTFail("500 ต้องโยน error")
        } catch AppError.notInGroup {
            XCTFail("500 ห้ามกลายเป็น .notInGroup — เซิร์ฟเวอร์ล้มชั่วคราวต้องไม่ลบข้อความทั้งเครื่อง")
        } catch {
            // error ทั่วไป — syncLoop จะ backoff แล้วลองใหม่ ซึ่งคือพฤติกรรมที่ต้องการ
        }
    }

    func testNetworkFailureBecomesOffline() async {
        StubURLProtocol.failsWithError = true
        do {
            _ = try await APIClient.shared.chatSync(token: "t", groupId: 1, after: 0, wait: 0)
            XCTFail("เน็ตล่มต้องโยน error")
        } catch AppError.offline {
            // ถูกแล้ว
        } catch {
            XCTFail("เน็ตล่มต้องเป็น .offline ไม่ใช่ \(error)")
        }
    }

    /// `after` โผล่ใน query เฉพาะตอนมีของแล้ว — รอบแรก (after 0) ต้องไม่ส่ง ให้ server
    /// ตีความว่า "ขอตั้งแต่จุดตัดประวัติ" ส่วน `wait` ต้องไปเสมอ
    func testAfterParameterAppearsOnlyWhenPositive() async throws {
        _ = try await APIClient.shared.chatSync(token: "t", groupId: 1, after: 0, wait: 25)
        _ = try await APIClient.shared.chatSync(token: "t", groupId: 1, after: 42, wait: 25)

        let queries = StubURLProtocol.capturedURLs.map { $0.query ?? "" }
        XCTAssertEqual(queries.count, 2)
        XCTAssertFalse(queries[0].contains("after="), "after=0 ต้องไม่ถูกส่ง: \(queries[0])")
        XCTAssertTrue(queries[0].contains("wait=25"))
        XCTAssertTrue(queries[1].contains("after=42"), "มี cursor แล้วต้องส่ง after: \(queries[1])")
    }

    /// `chatRead` ไม่ throw ไม่ว่าอะไรจะเกิด — ผู้เรียกทำอะไรกับความล้มเหลวไม่ได้อยู่แล้ว
    /// (heartbeat ตัวถัดไปยิงซ้ำค่าเดิม/ใหม่กว่าเอง) แค่ต้องยิงถึงจริงและไม่พาแอปล่ม
    func testChatReadSwallowsFailuresQuietly() async {
        StubURLProtocol.status = 500
        await APIClient.shared.chatRead(token: "t", groupId: 1, lastReadId: 7)

        StubURLProtocol.failsWithError = true
        await APIClient.shared.chatRead(token: "t", groupId: 1, lastReadId: 7)

        XCTAssertEqual(StubURLProtocol.capturedURLs.filter { $0.path.hasSuffix("/chat/read") }.count, 2,
                       "ทั้งสองครั้งต้องยิงออกจริง แล้วกลืน error เงียบ ๆ ไม่ throw ไม่ crash")
    }
}
