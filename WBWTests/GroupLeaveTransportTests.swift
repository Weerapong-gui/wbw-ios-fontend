import XCTest
@testable import WBW

/// พิสูจน์ว่า 409 จาก /groups/leave เดินทางถึงผู้เรียกจริง ไม่ถูกกลืนระหว่างทาง
/// (ของเดิม leaveGroup ใช้ deviceCall ซึ่ง `try?` ทิ้งทุก error — จอจะเงียบสนิทตอนสิทธิ์หมด)
/// วิธีเดียวกับ FeedbackTransportTests: URLProtocol ปลอมดัก URLSession.shared
final class GroupLeaveTransportTests: XCTestCase {

    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var body = Data()

        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.path.hasSuffix("/groups/leave") == true
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
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
        // **ปักว่าไม่ได้อยู่ในโหมดเดโม่** — เทสชุดนี้พิสูจน์เส้นทางเน็ตจริง แต่ `APIClient`
        // มีทางลัดของโหมดเดโม่อยู่ก่อนทุกฟังก์ชันที่ยิงเน็ต (18 จุด) ถ้าโหมดเดโม่ติดอยู่ คำขอ
        // จะไม่เคยออกไปถึง `URLProtocol` ปลอมเลย แล้วเทสจะฟ้องเป็นอย่างอื่น
        //
        // และมันติดได้โดยไม่มีใครในเทสตั้งเลย — เทสยูนิตรันใน**โปรเซสเดียวกับแอป** จึงอ่าน
        // `UserDefaults` ใบเดียวกับที่ `Session.startDemo()` เขียน token เดโม่ทิ้งไว้ตอนรันแอปจริง
        // บนซิมเครื่องเดียวกัน (`DemoMode.active` อ่านจาก token นั้นโดยตั้งใจ)
        //
        // **นี่คือคำอธิบายของ "คลาสที่แกว่งเอง" ที่เอกสารหลายใบในโปรเจกต์บันทึกไว้ว่าหาสาเหตุไม่ได้**
        // — มันไม่ได้แกว่ง มันแดงตรงกับตอนที่มีคนเปิดแอปโหมดเดโม่ค้างไว้ก่อนรันเทส
        DemoMode.forcedActive = false
        URLProtocol.registerClass(StubURLProtocol.self)
    }
    override func tearDown() {
        DemoMode.forcedActive = nil
        URLProtocol.unregisterClass(StubURLProtocol.self)
        super.tearDown()
    }

    func testLeaveConflictSurfacesServerMessage() async {
        StubURLProtocol.status = 409
        StubURLProtocol.body = Data(#"{"error":"สิทธิ์ออกจากกลุ่มหมดแล้ว"}"#.utf8)
        do {
            try await APIClient.shared.leaveGroup(token: "t")
            XCTFail("ต้องโยน error ไม่ใช่ผ่านเงียบ ๆ")
        } catch {
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "สิทธิ์ออกจากกลุ่มหมดแล้ว")
        }
    }

    func testLeaveSuccessDoesNotThrow() async throws {
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data(#"{"ok":true}"#.utf8)
        try await APIClient.shared.leaveGroup(token: "t")
    }
}
