import XCTest
@testable import WBW

/// ความเห็นทั้งงาน — endpoint ที่ SUS ยังไม่มี แอปส่งล่วงหน้าแบบเดียวกับ Android:
/// วันที่ endpoint เกิด ทุกเครื่องเริ่มส่งได้ทันที ระหว่างนั้น 404 ต้องเป็นความล้มเหลว
/// ที่ฟอร์มรับมือได้ (ปุ่มข้าม) ไม่ใช่ crash หรือค้างเงียบ
final class EventFeedbackTests: XCTestCase {

    private let deviceTime = "2026-08-29T17:00:00Z"

    func testBodyOmitsUnansweredKeys() {
        let sparse = EventFeedbackDraft(clientId: "e1", rating: 5,
                                        comment: nil, deviceTime: deviceTime)
        let body = APIClient.eventFeedbackBody(draft: sparse)
        XCTAssertEqual(body["client_id"] as? String, "e1")
        XCTAssertEqual(body["rating"] as? Int, 5)
        XCTAssertEqual(body["device_time"] as? String, deviceTime)
        for absent in ["rating_activity", "comment", "checkpoint_id"] {
            XCTAssertNil(body[absent], "คีย์ \(absent) ไม่ควรอยู่ในก้อน — event feedback ไม่ผูกกับฐานไหน")
        }
    }

    func testBodyCarriesActivityAndCommentWhenGiven() {
        let full = EventFeedbackDraft(clientId: "e2", rating: 4, ratingActivity: 3,
                                      comment: "สนุกมาก", deviceTime: deviceTime)
        let body = APIClient.eventFeedbackBody(draft: full)
        XCTAssertEqual(body["rating_activity"] as? Int, 3)
        XCTAssertEqual(body["comment"] as? String, "สนุกมาก")
    }

    // ===== transport (URLProtocol stub — ท่าเดียวกับ ChatSyncTransportTests) =====

    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var status = 201
        nonisolated(unsafe) static var body = Data("{}".utf8)
        nonisolated(unsafe) static var failsWithError = false
        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.path.hasSuffix("/me/event-feedback") == true
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            if Self.failsWithError {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
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

    override func setUp() {
        super.setUp()
        DemoMode.forcedActive = false
        URLProtocol.registerClass(StubURLProtocol.self)
        StubURLProtocol.status = 201
        StubURLProtocol.body = Data("{}".utf8)
        StubURLProtocol.failsWithError = false
    }
    override func tearDown() {
        DemoMode.forcedActive = nil
        URLProtocol.unregisterClass(StubURLProtocol.self)
        super.tearDown()
    }

    private func draft() -> EventFeedbackDraft {
        EventFeedbackDraft(clientId: "e9", rating: 5, comment: nil, deviceTime: deviceTime)
    }

    func testCreatedMeansSaved() async {
        let out = await APIClient.shared.submitEventFeedback(token: "t", draft: draft())
        XCTAssertEqual(out, .saved)
    }

    /// SUS ยังไม่มี endpoint — 404 คือชีวิตจริงวันงานถ้า migration ยังไม่ลง
    /// ต้องเป็น .failed (พาปุ่มข้ามโผล่) ไม่ใช่ .saved ปลอม ๆ ที่ทำให้คำตอบหายเงียบ
    func testMissingEndpointMeansFailedNotSilentSuccess() async {
        StubURLProtocol.status = 404
        let out = await APIClient.shared.submitEventFeedback(token: "t", draft: draft())
        XCTAssertEqual(out, .failed)
    }

    /// ยิงซ้ำด้วย client_id เดิม (server ตอบ 200 แถวเดิม) = สำเร็จ ไม่ใช่ error
    func testDuplicateResendIsStillSuccess() async {
        StubURLProtocol.status = 200
        let out = await APIClient.shared.submitEventFeedback(token: "t", draft: draft())
        XCTAssertEqual(out, .saved)
    }

    func testConflictMeansAlreadyAnswered() async {
        StubURLProtocol.status = 409
        let out = await APIClient.shared.submitEventFeedback(token: "t", draft: draft())
        XCTAssertEqual(out, .alreadyAnswered)
    }

    func testNetworkFailureIsFailed() async {
        StubURLProtocol.failsWithError = true
        let out = await APIClient.shared.submitEventFeedback(token: "t", draft: draft())
        XCTAssertEqual(out, .failed,
                       "ไม่มี outbox ของ event feedback — เน็ตล่มคือ .failed ให้ฟอร์มโชว์ปุ่มลองใหม่/ข้าม")
    }
}
