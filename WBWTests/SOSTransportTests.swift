import XCTest
@testable import WBW

/// เทสชุดนี้คือแนวกันหลักของกฎที่สำคัญที่สุดในฟีเจอร์นี้:
/// **ไม่มี status code ไหนที่ทำให้เคส SOS หายไปเงียบๆ ได้**
///
/// FeedbackStore.flush เคยลบคำตอบผู้ใช้ทิ้งเพราะเจอ error ที่ไม่ใช่ offline (แก้ใน 12e7cbc)
/// ของ SOS ต้องแรงกว่านั้น — feedback ยังยอมทิ้งเมื่อเจอ 400/401 แต่ SOS ไม่ยอมแม้แต่กรณีนั้น
/// เพราะราคาของการทิ้งไม่เท่ากันเลย
final class SOSTransportTests: XCTestCase {

    /// ไล่ทุก status code ที่เป็นไปได้ ไม่ใช่แค่ที่นึกออก
    func testNoHTTPStatusIsTerminalForAQueuedCase() {
        let envelope = Data(#"{"error":"อะไรสักอย่าง"}"#.utf8)
        for status in 100...599 {
            XCTAssertFalse(APIClient.sosIsTerminal(status: status, data: envelope),
                           "status \(status) ทำให้เคส SOS ถูกทิ้ง — ห้ามมี status ไหนทำแบบนี้ได้")
        }
    }

    func testSuccessStatusesAreNotTreatedAsFailures() {
        for status in [200, 201] {
            XCTAssertTrue(APIClient.sosIsSuccess(status: status))
        }
        for status in [400, 401, 403, 409, 500, 503] {
            XCTAssertFalse(APIClient.sosIsSuccess(status: status))
        }
    }

    /// 409 ของ origin เรามีความหมายจริง (รับเรื่องแล้ว/เลยเวลา) แต่ 409 ของ WAF ไม่มี
    func testCancelTreatsOnlyAnOriginEnvelopeAsAMeaningful409() {
        let origin = Data(#"{"error":"เจ้าหน้าที่รับเรื่องแล้ว ให้โทรบอกแทน"}"#.utf8)
        let waf = Data("<html><body>Access denied</body></html>".utf8)
        XCTAssertTrue(APIClient.sosIsOriginEnvelope(origin))
        XCTAssertFalse(APIClient.sosIsOriginEnvelope(waf))
    }

    func testDecodingACaseFromTheServerShape() throws {
        let json = Data("""
        {"id":7,"for_other":true,"lat":20.0439,"lng":99.899,"accuracy_m":12.0,
         "loc_source":"gps","checkpoint_id":2,"checkpoint_name":"สวนกุหลาบ","message":null,
         "resolved":false,"resolve_reason":null,"acked_at":null,"acked_by_name":null,
         "created_at":"2026-08-06T10:00:00Z","emergency_phone":"053-916-000"}
        """.utf8)
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let c = try dec.decode(SOSCase.self, from: json)
        XCTAssertEqual(c.id, 7)
        XCTAssertEqual(c.checkpointName, "สวนกุหลาบ")
        XCTAssertEqual(c.status, .received)
    }

    func testStatusBecomesOnTheWayOnceAcked() throws {
        let json = Data("""
        {"id":7,"for_other":false,"lat":null,"lng":null,"accuracy_m":null,"loc_source":"none",
         "checkpoint_id":null,"checkpoint_name":null,"message":null,"resolved":false,
         "resolve_reason":null,"acked_at":"2026-08-06T10:01:00Z","acked_by_name":"พี่หมอ",
         "created_at":"2026-08-06T10:00:00Z","emergency_phone":null}
        """.utf8)
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        XCTAssertEqual(try dec.decode(SOSCase.self, from: json).status, .onTheWay)
    }

    /// ช่องว่างที่รีวิวของ Task 9 เจอ: ไม่มีเทสไหน decode เคสที่ปิดแล้วเลย
    /// resolved=true ต้องชนะ acked_at เสมอ (เคสจริงมักถูก ack ก่อนถูกปิด) ไม่ใช่แค่ตอน
    /// ไม่เคย ack มาก่อน — ถ้า status ไปเช็ค ackedAt ก่อน resolved เทสนี้จะจับได้ทันที
    func testStatusBecomesClosedWhenResolved() throws {
        let json = Data("""
        {"id":7,"for_other":false,"lat":20.0439,"lng":99.899,"accuracy_m":12.0,
         "loc_source":"gps","checkpoint_id":2,"checkpoint_name":"สวนกุหลาบ","message":null,
         "resolved":true,"resolve_reason":"helped","acked_at":"2026-08-06T10:01:00Z",
         "acked_by_name":"พี่หมอ","created_at":"2026-08-06T10:00:00Z","emergency_phone":"053-916-000"}
        """.utf8)
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let c = try dec.decode(SOSCase.self, from: json)
        XCTAssertEqual(c.status, .closed(reason: "helped"))
    }

    // MARK: - พบจากรีวิว: activeSOS ต้องเดินผ่านเครือข่ายจริง ไม่ใช่แค่ decode เฉยๆ

    /// URLProtocol ปลอม — ดักเฉพาะ path ที่มี "/sos" เท่านั้น ไม่แตะ endpoint อื่นที่ไฟล์เทสอื่น
    /// (เช่น FeedbackTransportTests) อาจลงทะเบียนดักอยู่พร้อมกันในโปรเซสเดียวกัน
    final class SOSStubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var body = Data()
        nonisolated(unsafe) static var contentType = "application/json"

        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.path.contains("/sos") == true
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": Self.contentType])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(SOSStubURLProtocol.self)
        SOSStubURLProtocol.status = 200
        SOSStubURLProtocol.body = Data()
        SOSStubURLProtocol.contentType = "application/json"
    }

    override func tearDown() {
        URLProtocol.unregisterClass(SOSStubURLProtocol.self)
        super.tearDown()
    }

    /// ตรวจก่อนว่า stub ดักคำขอของ APIClient ได้จริง — ถ้าไม่ เทสข้างล่างจะผ่าน/พังด้วยเหตุผล
    /// ผิดๆ (เน็ตจริงต่อไม่ติด → .offline ซึ่งบังเอิญไม่ตรงกับที่แต่ละเทสเช็คอยู่แล้วก็จริง
    /// แต่พิสูจน์ให้ชัดไว้ดีกว่าเดา) — ยิงผ่าน activeSOS จริง ไม่ใช่ decode ลอยๆ
    func testStubActuallyInterceptsActiveSOS() async throws {
        SOSStubURLProtocol.body = Data("""
        {"id":9,"for_other":false,"lat":null,"lng":null,"accuracy_m":null,"loc_source":"none",
         "checkpoint_id":null,"checkpoint_name":null,"message":null,"resolved":false,
         "resolve_reason":null,"acked_at":null,"acked_by_name":null,
         "created_at":"2026-08-06T10:00:00Z","emergency_phone":null}
        """.utf8)
        let result = try await APIClient.shared.activeSOS(token: "t", wait: 0)
        XCTAssertEqual(result?.id, 9)
    }

    /// หัวใจของบั๊กที่รีวิวจับได้: json.NewEncoder(w).Encode(nil) ฝั่ง Go (middleware.WriteJSON)
    /// ต่อ "\n" ท้ายเสมอ — ตอนไม่มีเคสเปิดอยู่ (กรณีส่วนใหญ่ของทุก poll) body จริงคือ "null\n"
    /// 5 ไบต์ ไม่ใช่ "null" 4 ไบต์ · เทียบ string ตรงๆ แบบเดิมจึงพลาดกรณีนี้ทุกครั้ง ไม่ใช่บางครั้ง
    /// แล้วร่วงไป decode ต่อจน throw DecodingError ดิบ (ไม่ใช่แม้แต่ AppError) ยิงผ่าน activeSOS
    /// จริงเพื่อพิสูจน์ว่าช่องทางที่ใช้จริงรอดจาก byte ท้ายๆ ได้ ไม่ใช่แค่ตัว decode เฉยๆ
    func testActiveSOSTreatsTrailingNewlineNullAsNoOpenCase() async throws {
        SOSStubURLProtocol.body = Data("null\n".utf8)
        let result = try await APIClient.shared.activeSOS(token: "t", wait: 0)
        XCTAssertNil(result, "null\\n (รูปจริงที่ Go ส่ง) ต้องแปลว่าไม่มีเคสเปิดอยู่ ไม่ใช่ throw")
    }

    // MARK: - พบจากรีวิว: decode ที่พังบน 200/201 ต้องออกเป็น AppError.retryable ไม่ใช่ error ดิบ

    /// JSON ที่ถูกต้องแต่ไม่ตรง shape ของ SOSCase (ขาด field บังคับอย่าง id) — เกิดได้จริงถ้า
    /// proxy ตัดกลาง response หรือ backend เปลี่ยน schema โดยไม่รู้ตัว
    private static let unparsableCaseBody = Data(#"{"unexpected":"shape"}"#.utf8)

    func testActiveSOSTreatsAnUnparsableSuccessBodyAsRetryableNotARawError() async {
        SOSStubURLProtocol.body = Self.unparsableCaseBody
        do {
            _ = try await APIClient.shared.activeSOS(token: "t", wait: 0)
            XCTFail("body ที่ decode ไม่ได้ต้อง throw")
        } catch AppError.retryable {
            // ถูกต้อง
        } catch {
            XCTFail("ต้องเป็น AppError.retryable ไม่ใช่ \(error)")
        }
    }

    func testRaiseSOSTreatsAnUnparsableSuccessBodyAsRetryableNotARawError() async {
        SOSStubURLProtocol.status = 201
        SOSStubURLProtocol.body = Self.unparsableCaseBody
        let draft = SOSDraft(clientId: "c1", deviceTime: "2026-08-06T10:00:00Z", forOther: false, ownerId: "u1")
        do {
            _ = try await APIClient.shared.raiseSOS(token: "t", draft: draft)
            XCTFail("body ที่ decode ไม่ได้ต้อง throw")
        } catch AppError.retryable {
            // ถูกต้อง
        } catch {
            XCTFail("ต้องเป็น AppError.retryable ไม่ใช่ \(error)")
        }
    }

    func testSOSCaseTreatsAnUnparsableSuccessBodyAsRetryableNotARawError() async {
        SOSStubURLProtocol.body = Self.unparsableCaseBody
        do {
            _ = try await APIClient.shared.sosCase(token: "t", id: 7)
            XCTFail("body ที่ decode ไม่ได้ต้อง throw")
        } catch AppError.retryable {
            // ถูกต้อง
        } catch {
            XCTFail("ต้องเป็น AppError.retryable ไม่ใช่ \(error)")
        }
    }

    func testStaffSOSFeedTreatsAnUnparsableSuccessBodyAsRetryableNotARawError() async {
        SOSStubURLProtocol.body = Data(#"[{"unexpected":"shape"}]"#.utf8)
        do {
            _ = try await APIClient.shared.staffSOSFeed(token: "t", since: nil, wait: 0)
            XCTFail("body ที่ decode ไม่ได้ต้อง throw")
        } catch AppError.retryable {
            // ถูกต้อง
        } catch {
            XCTFail("ต้องเป็น AppError.retryable ไม่ใช่ \(error)")
        }
    }
}
