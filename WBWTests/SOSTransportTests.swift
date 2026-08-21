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

        /// สิ่งที่ "ออกไปจริง" ในคำขอล่าสุด — ไม่ใช่แค่สิ่งที่ตอบกลับมา
        ///
        /// จำเป็นเพราะเทสทั้งไฟล์นี้ (และทั้ง SOSStoreTests ซึ่งฉีด raiseCall ปลอมทุกตัว) ตรวจแต่
        /// ขาตอบกลับ ไม่มีใครดูขาส่งเลยสักตัว — บรรทัด req.httpBody หายไปได้ทั้งบรรทัดโดยที่เทส
        /// 211 ตัวยังเขียวสนิท (เกิดขึ้นจริงมาแล้ว ดู testRaiseSOSActuallyPutsTheDraftInTheBody)
        nonisolated(unsafe) static var lastMethod: String?
        nonisolated(unsafe) static var lastBody = Data()

        /// URLSession แปลง httpBody เป็น httpBodyStream ระหว่างทางเสมอ ตัว httpBody ที่ URLProtocol
        /// เห็นจึงเป็น nil ทั้งที่ผู้เรียกตั้งไว้จริง — ต้องอ่านจาก stream แทน ไม่ใช่สรุปว่า "ไม่มี body"
        /// (อ่านผิดจุดจะทำให้เทสแดงตลอดแม้โค้ดถูก ซึ่งแย่พอๆ กับเขียวตลอดแม้โค้ดผิด)
        static func outgoingBody(of request: URLRequest) -> Data {
            if let b = request.httpBody { return b }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open()
            defer { stream.close() }
            var out = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                out.append(buf, count: n)
            }
            return out
        }

        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.path.contains("/sos") == true
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.lastMethod = request.httpMethod
            Self.lastBody = Self.outgoingBody(of: request)
            let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": Self.contentType])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    /// **ต้องปักว่าไม่ได้อยู่ในโหมดเดโม่** — เทสชุดนี้พิสูจน์เส้นทางเน็ตจริง แต่ `APIClient+SOS`
    /// มีทางลัดของโหมดเดโม่อยู่ก่อนทุกฟังก์ชัน (ดู `DemoSOS`) ถ้าโหมดเดโม่ติดอยู่ คำขอจะไม่เคย
    /// ออกไปถึง `URLProtocol` ปลอมเลยสักครั้ง แล้วเทสจะฟ้องเป็นอย่างอื่น (เจอจริง: เคสที่ได้กลับมา
    /// มี id 9004 ซึ่งเป็นเลขของ `DemoSOS` ไม่ใช่ของ stub)
    ///
    /// และมันติดได้จริงโดยไม่มีใครในเทสตั้งเลย — เทสยูนิตรันใน**โปรเซสเดียวกับแอป** จึงอ่าน
    /// `UserDefaults` ใบเดียวกับที่ `Session.startDemo()` เขียน token เดโม่ทิ้งไว้ตอนรันแอปจริง
    /// บนซิมเครื่องเดียวกัน · `DemoMode.active` อ่านจาก token นั้นโดยตั้งใจ (ดูคอมเมนต์ที่นั่น)
    /// ผลคือเทสผ่านหรือไม่ผ่านขึ้นกับว่าใครเปิดแอปโหมดเดโม่ค้างไว้ก่อนหน้า
    override func setUp() {
        super.setUp()
        DemoMode.forcedActive = false
        URLProtocol.registerClass(SOSStubURLProtocol.self)
        SOSStubURLProtocol.status = 200
        SOSStubURLProtocol.body = Data()
        SOSStubURLProtocol.contentType = "application/json"
        SOSStubURLProtocol.lastMethod = nil
        SOSStubURLProtocol.lastBody = Data()
    }

    override func tearDown() {
        URLProtocol.unregisterClass(SOSStubURLProtocol.self)
        DemoMode.forcedActive = nil
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

    // MARK: - ขาส่ง: คำขอต้องมีของอยู่ในนั้นจริง ไม่ใช่แค่ยิงออกไปได้

    /// **บั๊กที่ทำให้ต้องมีเทสนี้: `req.httpBody = try JSONSerialization.data(...)` หายไปทั้งบรรทัด**
    ///
    /// ถูกเขียนทับด้วย `req.timeoutInterval = 20` ตอนแก้เรื่องเพดานเวลา · `body` ยังถูกประกอบไว้
    /// ครบทุกฟิลด์ข้างบนเหมือนเดิม แค่ไม่มีใครแนบมันเข้ากับ request อีกต่อไป ผลคือ POST ออกไปตัวเปล่า
    /// เซิร์ฟเวอร์ `json.NewDecoder(r.Body).Decode(&req)` ได้ io.EOF ตอบ 400 ทุกครั้งไม่มียกเว้น
    /// `sosIsSuccess` รับแค่ 200/201 `send()` จึงเข้าสาขา catch เสมอ สถานะค้างที่ .queued ตลอดกาล
    /// retry ยิง 400 รัวตามตาราง 2/5/10/20/30/60 และ **ไม่มีเคสไหนถูกสร้างขึ้นเลยสักแถว** — ไม่มีใน
    /// ฟีดเจ้าหน้าที่ ไม่มี push ไม่มีแจ้งเตือนกลุ่ม · กฎ "ไม่ทิ้งเคส" ยังจริงและปุ่มโทรยังโผล่ที่ 20 วิ
    /// คนกดจึงถูกบอกให้โทร แต่ไม่มีอะไรในระบบดิจิทัลไปถึงใครเลย
    ///
    /// ไม่มีเทสไหนจับได้เลยเพราะ SOSStoreTests ฉีด raiseCall ปลอมทุกตัว และ raiseSOS ตัวจริงไม่มี
    /// เทสสักตัวที่ดูขาส่ง — ตัวนี้คือรูนั้น ต่อจากนี้การลบบรรทัด httpBody จะแดงทันที
    func testRaiseSOSActuallyPutsTheDraftInTheBody() async throws {
        SOSStubURLProtocol.status = 201
        SOSStubURLProtocol.body = Data("""
        {"id":11,"for_other":true,"lat":20.0439,"lng":99.899,"accuracy_m":12.0,
         "loc_source":"gps","checkpoint_id":2,"checkpoint_name":"สวนกุหลาบ","message":"ขาหัก",
         "resolved":false,"resolve_reason":null,"acked_at":null,"acked_by_name":null,
         "created_at":"2026-08-06T10:00:00Z","emergency_phone":"053-916-000"}
        """.utf8)

        let draft = SOSDraft(clientId: "6f1e0c9a-0000-0000-0000-0000000000aa",
                             deviceTime: "2026-08-06T10:00:00Z", forOther: true,
                             lat: 20.0439, lng: 99.899, accuracyM: 12, message: "ขาหัก",
                             ownerId: "u1")
        let c = try await APIClient.shared.raiseSOS(token: "t", draft: draft)
        XCTAssertEqual(c.id, 11)

        XCTAssertEqual(SOSStubURLProtocol.lastMethod, "POST")
        XCTAssertFalse(SOSStubURLProtocol.lastBody.isEmpty,
                       "POST /me/sos ออกไปโดยไม่มี body — เซิร์ฟเวอร์จะได้ io.EOF แล้วตอบ 400 ทุกครั้ง "
                       + "เคสจะไม่มีวันถูกสร้างขึ้นเลย")

        let sent = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: SOSStubURLProtocol.lastBody) as? [String: Any],
            "body ที่ส่งออกไปต้องเป็น JSON object")
        XCTAssertEqual(sent["client_id"] as? String, draft.clientId,
                       "client_id คือสิ่งเดียวที่ทำให้การ retry ไม่กลายเป็นเคสซ้ำ")
        XCTAssertEqual(sent["device_time"] as? String, draft.deviceTime)
        XCTAssertEqual(sent["for_other"] as? Bool, true)
        XCTAssertEqual(sent["lat"] as? Double ?? 0, 20.0439, accuracy: 0.00001)
        XCTAssertEqual(sent["lng"] as? Double ?? 0, 99.899, accuracy: 0.00001)
        XCTAssertEqual(sent["accuracy_m"] as? Double ?? 0, 12, accuracy: 0.00001)
        XCTAssertEqual(sent["message"] as? String, "ขาหัก")
    }

    /// พิกัด/ข้อความที่ยังไม่มี ต้องไม่ถูกส่งเป็น null — ฝั่ง Go ใช้ COALESCE ทับค่าเดิมเฉพาะเมื่อ
    /// "ส่งมาจริง" การส่ง key ที่ไม่มีค่ามาด้วยจึงต่างจากการไม่ส่ง key นั้นเลย (ดู Raise ใน repository)
    func testRaiseSOSOmitsFieldsTheDraftDoesNotHaveYet() async throws {
        SOSStubURLProtocol.status = 201
        SOSStubURLProtocol.body = Data("""
        {"id":12,"for_other":false,"lat":null,"lng":null,"accuracy_m":null,"loc_source":"none",
         "checkpoint_id":null,"checkpoint_name":null,"message":null,"resolved":false,
         "resolve_reason":null,"acked_at":null,"acked_by_name":null,
         "created_at":"2026-08-06T10:00:00Z","emergency_phone":null}
        """.utf8)

        let draft = SOSDraft(clientId: "6f1e0c9a-0000-0000-0000-0000000000bb",
                             deviceTime: "2026-08-06T10:00:00Z", forOther: false, ownerId: "u1")
        _ = try await APIClient.shared.raiseSOS(token: "t", draft: draft)

        let sent = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: SOSStubURLProtocol.lastBody) as? [String: Any])
        XCTAssertNotNil(sent["client_id"])
        XCTAssertNil(sent["lat"])
        XCTAssertNil(sent["lng"])
        XCTAssertNil(sent["accuracy_m"])
        XCTAssertNil(sent["message"])
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
