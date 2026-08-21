import XCTest
@testable import WBW

/// เทสชุดนี้พิสูจน์บั๊กร้ายแรง "คำตอบของผู้เข้าร่วมหายเงียบๆ ตอนเซิร์ฟเวอร์ตอบ 503" แบบ
/// **เดินครบเส้นจริง** ไม่ใช่แค่ระดับ store: HTTP status ของจริง → APIClient.submitFeedback ของจริง
/// → FeedbackStore ของจริง → FeedbackOutbox บน UserDefaults ของจริง
///
/// เทสใน FeedbackStoreTests ฉีด AppError.retryable เข้าไปตรงๆ ซึ่งพิสูจน์ได้แค่ครึ่งเดียว — ถ้า
/// APIClient แปลง 503 เป็น AppError.message เหมือนเดิม บั๊กก็ยังอยู่ครบทั้งที่เทสชุดนั้นเขียวหมด
/// รอยต่อ "status ตัวไหนกลายเป็น error ชนิดไหน" คือที่ที่บั๊กอยู่จริง จึงต้องมีเทสคร่อมมันโดยเฉพาะ
///
/// วิธี: URLProtocol ปลอมที่ลงทะเบียนไว้ทั้งโปรเซส ดัก request ของ URLSession.shared (ตัวที่
/// APIClient ใช้) แล้วตอบ status ที่กำหนด — ไม่มีเน็ตจริง ไม่แตะ Config.backend
final class FeedbackTransportTests: XCTestCase {

    /// URLProtocol ปลอม — ตอบ status ที่ตั้งไว้ให้ทุก request ที่วิ่งผ่าน URLSession.shared
    final class StubURLProtocol: URLProtocol {
        /// nonisolated(unsafe): URLProtocol ถูกสร้างบนคิวของ URLSession ไม่ใช่ main — เทสตั้งค่า
        /// ก่อนยิงและอ่านหลังจบเสมอ (ไม่มีการเขียนคาบกัน) จึงไม่ต้องมี lock ให้รกกว่าที่ควร
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var body = Data()
        /// header ที่ตอบกลับ — มีเพื่อให้ response ปลอมเหมือนของจริงทั้งก้อน (Cloudflare ตอบ
        /// text/html, backend เราตอบ application/json) การจำแนกไม่ได้อ่านค่านี้ ตั้งใจ: header
        /// ปลอมง่ายกว่า body และ gateway บางตัวก็ตอบ application/json ทั้งที่ไม่ใช่ของ origin
        nonisolated(unsafe) static var contentType = "application/json"
        nonisolated(unsafe) static var requestCount = 0

        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.path.hasSuffix("/me/feedback") == true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.requestCount += 1
            let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": Self.contentType])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    // MARK: - body ของจริงจากทั้งสองฝั่ง
    //
    // ตรึงไว้ให้ตรงกับที่ backend ส่งจริง (ยืนยันด้วย TestSubmitFeedbackForbiddenBodyIsErrorEnvelope
    // และ TestSubmitFeedbackConflictBodyIsFeedbackRow ฝั่ง Go): 403 ออกจาก middleware.WriteError
    // เป็น {"error":"..."} ส่วน 409 ออกจาก WriteJSON เป็น "แถวความเห็นเดิม" ไม่ใช่ envelope
    // (json.Encoder ของ Go ปิดท้ายด้วย \n จึงใส่ไว้ด้วย)

    /// 403 ของจริงจาก POST /wbw/me/feedback
    private static let originForbiddenBody = Data((#"{"error":"ยังไม่ได้เช็คอินฐานนี้"}"# + "\n").utf8)

    /// 409 ของจริง — แถวความเห็นเดิมที่ฟอร์มเอาไปแสดงแบบอ่านอย่างเดียว
    private static let originConflictBody = Data("""
    {"id":42,"checkpoint_id":3,"rating":2,"comment":"เฉยๆ","created_at":"2026-08-29T09:00:00Z"}

    """.utf8)

    /// หน้า block ของ Cloudflare — HTML ไม่ใช่ JSON และไม่เคยผ่าน origin เลย
    private static let cloudflareHTMLBody = Data("""
    <!DOCTYPE html><html><head><title>Access denied | api.studentunion.social used Cloudflare \
    to restrict access</title></head><body><h1>Error 1020</h1><p>Ray ID: 8f2c1a9b0e3d4567</p>\
    </body></html>
    """.utf8)

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
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data()
        StubURLProtocol.contentType = "application/json"
        StubURLProtocol.requestCount = 0
        UserDefaults.standard.removeObject(forKey: FeedbackOutbox.key(for: Config.backend))
    }

    override func tearDown() {
        DemoMode.forcedActive = nil
        URLProtocol.unregisterClass(StubURLProtocol.self)
        UserDefaults.standard.removeObject(forKey: FeedbackOutbox.key(for: Config.backend))
        super.tearDown()
    }

    private func draft(_ id: String) -> FeedbackDraft {
        FeedbackDraft(clientId: id, checkpointId: 3, rating: 3,
                      comment: "สนุกดี", deviceTime: "2026-08-29T09:00:00Z")
    }

    private func outbox() -> FeedbackOutbox { FeedbackOutbox(backend: Config.backend) }

    /// ตรวจก่อนว่า stub ดัก URLSession.shared ได้จริง — ถ้าไม่ ทุกเทสในไฟล์นี้จะกลายเป็นเทสของ
    /// เน็ตที่ต่อไม่ติด (ได้ AppError.offline) แล้วผ่านด้วยเหตุผลผิดๆ
    func testStubActuallyInterceptsAPIClient() async throws {
        StubURLProtocol.status = 201
        let outcome = try await APIClient.shared.submitFeedback(token: "t", draft: draft("a"))
        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(StubURLProtocol.requestCount, 1, "request ต้องวิ่งผ่าน stub จริง ไม่ใช่ออกเน็ต")
    }

    /// หัวใจของบั๊ก: ทุก status ที่ retry แล้วมีโอกาสสำเร็จต้องกลายเป็น AppError.retryable
    /// 500 = default arm ของ handler ฝั่ง Go · 502/503/524 = Cloudflare หน้า api.studentunion.social
    /// ตอบแทน origin · 429 = โดน rate limit ตอน 2,000 คนยิงพร้อมกัน
    func testServerErrorsMapToRetryable() async {
        for status in [429, 500, 502, 503, 504, 524] {
            StubURLProtocol.status = status
            do {
                _ = try await APIClient.shared.submitFeedback(token: "t", draft: draft("a"))
                XCTFail("status \(status) ต้องโยน error")
            } catch AppError.retryable {
                // ถูกต้อง
            } catch {
                XCTFail("status \(status) ต้องเป็น AppError.retryable ได้ \(error)")
            }
        }
    }

    /// ฝั่งตรงข้าม: status ที่ retry ไปก็ไม่มีวันผ่านต้องยังเป็น .message เหมือนเดิม
    /// ถ้าเผลอเหมารวมเป็น retryable จะได้ของพังค้างคิวถาวร ซึ่งเป็นอันตรายที่ Task 6 แก้ไว้
    ///
    /// รายการนี้คือ "รายชื่อขาว" ทั้งหมดของฝั่งปลายทาง — ทุกตัวคือ error ที่เกิดจาก **ตัว request เอง**
    /// ซึ่งไม่เปลี่ยนเลยตอน retry: body เดิม, header เดิม, URL เดิม, method เดิม
    func testRequestShapeErrorsStayTerminal() async {
        for status in [400, 401, 405, 410, 413, 414, 415, 422] {
            StubURLProtocol.status = status
            StubURLProtocol.body = Data(#"{"error":"ไม่ผ่าน"}"#.utf8)
            do {
                _ = try await APIClient.shared.submitFeedback(token: "t", draft: draft("a"))
                XCTFail("status \(status) ต้องโยน error")
            } catch AppError.message {
                // ถูกต้อง
            } catch {
                XCTFail("status \(status) ต้องเป็น AppError.message ได้ \(error)")
            }
        }
    }

    /// **หัวใจของรอบนี้ (ข้อ 1)** — การจำแนกกลับหัว: terminal คือรายชื่อที่ระบุไว้ชัด
    /// ที่เหลือ **ทั้งหมด** retry ได้
    ///
    /// 408 คือเคสจริงที่สุด: Cloudflare ตอบ 408 เมื่อ client ส่ง body ไม่จบภายในเวลา — เกิดได้เต็มๆ
    /// บนไวไฟภูเขาที่คนสองพันคนแย่งกันใช้ · 425 (Too Early) มาจากการ replay ของ TLS early data
    /// ซึ่ง Cloudflare เปิดไว้เป็นค่าเริ่มต้น · ทั้งคู่เคยตกลง default → .message → คำตอบผู้ใช้ถูกลบทิ้ง
    ///
    /// ราคาของการจำแนกผิดสองทางไม่เท่ากันเลย: เผลอ retry = เสีย POST เปล่าอย่างมากรอบละหนึ่งครั้ง
    /// ต่อฐาน (คิวมีเพดาน ~8 ชิ้นเพราะ outbox.add แทนที่ของฐานเดิม) · เผลอ terminal = คำตอบของ
    /// ผู้เข้าร่วมหายถาวรโดยไม่มีสัญญาณอะไรเลย
    func testEverythingNotOnTheTerminalListIsRetryable() async {
        for status in [402, 404, 406, 407, 408, 418, 423, 425, 426, 428, 429, 431, 451,
                       500, 502, 503, 504, 524, 599] {
            StubURLProtocol.status = status
            StubURLProtocol.body = Data()
            do {
                _ = try await APIClient.shared.submitFeedback(token: "t", draft: draft("a"))
                XCTFail("status \(status) ต้องโยน error")
            } catch AppError.retryable {
                // ถูกต้อง
            } catch {
                XCTFail("status \(status) ต้องเป็น AppError.retryable ได้ \(error)")
            }
        }
    }

    // MARK: - 403/409 ของ backend เรา กับ 403/409 ของอะไรที่ขวางอยู่หน้า origin (ข้อ 2)

    /// 403 ที่มาพร้อม error envelope ของ backend = "ยังไม่ได้เช็คอินฐานนี้" จริง → สถานะปลายทาง
    /// ฟอร์มพึ่งค่านี้ และ FeedbackStore.submit ล้างคิวของฐานนี้ทั้งฐานจากผลนี้
    func testForbiddenWithOriginEnvelopeIsTerminal() async throws {
        StubURLProtocol.status = 403
        StubURLProtocol.body = Self.originForbiddenBody
        let outcome = try await APIClient.shared.submitFeedback(token: "t", draft: draft("a"))
        XCTAssertEqual(outcome, .notCheckedIn)
    }

    /// 403 ที่ **ไม่ใช่** ของ backend (Cloudflare WAF/firewall rule ตอบเป็น HTML) ต้อง retry ได้
    ///
    /// นี่คือประตูที่อันตรายที่สุดของบั๊กชุดนี้: status เดียวกันเป๊ะ แต่ผลต่างกันสุดขั้ว — เส้น
    /// .notCheckedIn เรียก outbox.remove(checkpointId:) ซึ่งล้างคิว **ทั้งฐาน** ไม่ใช่แค่ draft เดียว
    /// status อย่างเดียวแบกการตัดสินใจนี้ไม่ไหว ต้องดู body ว่าออกมาจาก origin ของเราจริงไหม
    func testForbiddenFromEdgeIsRetryable() async {
        StubURLProtocol.status = 403
        StubURLProtocol.body = Self.cloudflareHTMLBody
        StubURLProtocol.contentType = "text/html; charset=UTF-8"
        do {
            _ = try await APIClient.shared.submitFeedback(token: "t", draft: draft("a"))
            XCTFail("403 ที่ไม่ใช่ของ backend ต้องโยน error")
        } catch AppError.retryable {
            // ถูกต้อง
        } catch {
            XCTFail("403 จาก Cloudflare ต้องเป็น AppError.retryable ได้ \(error)")
        }
    }

    /// 409 ของ backend มาเป็น "แถวความเห็นเดิม" ผ่าน WriteJSON ไม่ใช่ error envelope — ตัวจำแนก
    /// ต้องรับรูปนี้ด้วย ไม่งั้นทางที่ควรจบกลับกลายเป็น retry ไม่รู้จบ = คิวค้างถาวร
    /// (ทิศทางพังตรงข้ามของข้อ 2 ซึ่งอันตรายพอกัน)
    func testConflictWithOriginRowIsTerminal() async throws {
        StubURLProtocol.status = 409
        StubURLProtocol.body = Self.originConflictBody
        let outcome = try await APIClient.shared.submitFeedback(token: "t", draft: draft("a"))
        XCTAssertEqual(outcome, .alreadyAnswered)
    }

    /// เผื่อวันหน้า backend เปลี่ยนไปตอบ 409 เป็น envelope แบบ status อื่น — ก็ยังต้องเป็นปลายทาง
    func testConflictWithOriginEnvelopeIsTerminal() async throws {
        StubURLProtocol.status = 409
        StubURLProtocol.body = Data(#"{"error":"ตอบฐานนี้ไปแล้ว"}"#.utf8)
        let outcome = try await APIClient.shared.submitFeedback(token: "t", draft: draft("a"))
        XCTAssertEqual(outcome, .alreadyAnswered)
    }

    /// 409 ที่ไม่ได้ออกมาจาก origin ต้อง retry ได้เหมือน 403
    func testConflictFromEdgeIsRetryable() async {
        StubURLProtocol.status = 409
        StubURLProtocol.body = Self.cloudflareHTMLBody
        StubURLProtocol.contentType = "text/html; charset=UTF-8"
        do {
            _ = try await APIClient.shared.submitFeedback(token: "t", draft: draft("a"))
            XCTFail("409 ที่ไม่ใช่ของ backend ต้องโยน error")
        } catch AppError.retryable {
            // ถูกต้อง
        } catch {
            XCTFail("409 จาก edge ต้องเป็น AppError.retryable ได้ \(error)")
        }
    }

    /// body ว่าง/JSON ที่ไม่มีคีย์ของเราเลย ก็ไม่ใช่ของ origin — ตัวจำแนกต้องไม่ยอมรับ {} ด้วย
    /// (APIErrorBody มี error เป็น optional จึง decode ผ่านกับ JSON object ทุกก้อน ใช้แยกไม่ได้)
    func testForbiddenWithBodyThatIsNotOursIsRetryable() async {
        for body in [Data(), Data("{}".utf8), Data(#"{"message":"Forbidden"}"#.utf8)] {
            StubURLProtocol.status = 403
            StubURLProtocol.body = body
            do {
                _ = try await APIClient.shared.submitFeedback(token: "t", draft: draft("a"))
                XCTFail("403 ที่ body ไม่ใช่ของเราต้องโยน error")
            } catch AppError.retryable {
                // ถูกต้อง
            } catch {
                XCTFail("403 body \(String(data: body, encoding: .utf8) ?? "-") ต้อง retryable ได้ \(error)")
            }
        }
    }

    // MARK: - ครบเส้น: 503 จริงต้องไม่ทำให้คำตอบหาย

    /// กดส่งครั้งแรกแล้วเจอ 503 → ต้องเข้าคิว และ UI เห็น .saved
    /// (เดิม: .failed ไม่เก็บอะไรเลย = คำตอบหายตั้งแต่กดปุ่ม)
    @MainActor
    func testSubmitThrough503QueuesTheDraft() async {
        StubURLProtocol.status = 503
        let store = FeedbackStore(submitCall: APIClient.shared.submitFeedback)

        let outcome = await store.submit(draft("a"), token: "t")

        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(outbox().all().map(\.clientId), ["a"], "503 ต้องไม่ทำให้คำตอบหาย")
    }

    /// เส้นทางที่เจอจริงวันงาน: ตอบตอนไม่มีสัญญาณ → เข้าคิว → เดินไปฐานถัดไปแล้วปลดล็อกเครื่อง →
    /// flush เจอ 503 → **ของต้องยังอยู่** → รอบถัดไปที่เซิร์ฟเวอร์ฟื้น ของถึงปลายทางจริง
    @MainActor
    func testDraftSurvives503FlushAndLandsWhenServerRecovers() async {
        let store = FeedbackStore(submitCall: APIClient.shared.submitFeedback)
        outbox().add(draft("a"))

        StubURLProtocol.status = 503
        await store.flush(token: "t")
        XCTAssertEqual(outbox().all().map(\.clientId), ["a"],
                       "503 ระหว่าง flush ต้องไม่ลบคำตอบที่บอกผู้ใช้ไปแล้วว่า 'ส่งความเห็นแล้ว'")

        StubURLProtocol.status = 201
        await store.flush(token: "t")
        XCTAssertTrue(outbox().all().isEmpty, "เซิร์ฟเวอร์ฟื้นแล้วของค้างต้องไปถึงจริง")
    }

    /// 400 ระหว่าง flush ยังต้องทิ้งของตัวนั้นเหมือนเดิม — ไม่งั้นของพังจะค้างคิวถาวร
    @MainActor
    func testTerminalErrorDuringFlushStillDropsTheDraft() async {
        let store = FeedbackStore(submitCall: APIClient.shared.submitFeedback)
        outbox().add(draft("a"))

        StubURLProtocol.status = 400
        await store.flush(token: "t")

        XCTAssertTrue(outbox().all().isEmpty, "400 ส่งซ้ำไม่มีวันผ่าน ต้องไม่ค้างคิว")
    }

    // MARK: - ครบเส้น: 403 ของ edge ต้องไม่ล้างคิวทั้งฐาน

    /// ความเสียหายจริงของข้อ 2 วัดที่ตรงนี้ ไม่ใช่ที่ชนิด error: เส้น .notCheckedIn เรียก
    /// outbox.remove(checkpointId:) ซึ่งลบ **ทุก draft ของฐานนั้น** ไม่ใช่แค่ตัวที่เพิ่งส่ง
    /// Cloudflare ตอบ 403 หนึ่งครั้ง = คำตอบของฐานนั้นหายเกลี้ยงทั้งที่ฟอร์มบอกไปแล้วว่า "ส่งแล้ว"
    @MainActor
    func testEdgeForbiddenDoesNotWipeTheWholeBaseQueue() async {
        let store = FeedbackStore(submitCall: APIClient.shared.submitFeedback)
        outbox().add(draft("เก่า"))   // ของค้างของฐาน 3 จากรอบที่เน็ตหลุด

        StubURLProtocol.status = 403
        StubURLProtocol.body = Self.cloudflareHTMLBody
        StubURLProtocol.contentType = "text/html; charset=UTF-8"

        let outcome = await store.submit(draft("ใหม่"), token: "t")

        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(outbox().all().map(\.clientId), ["ใหม่"],
                       "403 ของ Cloudflare ต้องเก็บคำตอบไว้ retry ไม่ใช่ล้างคิวของฐานนี้ทิ้ง")
    }

    /// เส้นเดียวกันตอน flush — ของค้างต้องยังอยู่
    @MainActor
    func testEdgeForbiddenDuringFlushKeepsTheDraft() async {
        let store = FeedbackStore(submitCall: APIClient.shared.submitFeedback)
        outbox().add(draft("a"))

        StubURLProtocol.status = 403
        StubURLProtocol.body = Self.cloudflareHTMLBody
        StubURLProtocol.contentType = "text/html; charset=UTF-8"
        await store.flush(token: "t")
        XCTAssertEqual(outbox().all().map(\.clientId), ["a"], "403 ที่ไม่ใช่ของ backend ต้องไม่ลบคำตอบ")

        StubURLProtocol.status = 201
        StubURLProtocol.body = Data()
        StubURLProtocol.contentType = "application/json"
        await store.flush(token: "t")
        XCTAssertTrue(outbox().all().isEmpty, "พอผ่าน edge ได้จริง ของค้างต้องถึงปลายทาง")
    }

    /// ตัวคุมฝั่งตรงข้าม: 403 **ของจริง** ต้องยังล้างคิวทั้งฐานเหมือนเดิม ไม่งั้นของที่ส่งไม่ผ่าน
    /// แน่ๆ (ยังไม่เช็คอินฐานนี้) จะวนยิงไปตลอดกาล
    @MainActor
    func testOriginForbiddenStillClearsTheBaseQueue() async {
        let store = FeedbackStore(submitCall: APIClient.shared.submitFeedback)
        outbox().add(draft("เก่า"))

        StubURLProtocol.status = 403
        StubURLProtocol.body = Self.originForbiddenBody

        let outcome = await store.submit(draft("ใหม่"), token: "t")

        XCTAssertEqual(outcome, .notCheckedIn)
        XCTAssertTrue(outbox().all().isEmpty, "403 ของ backend เป็นสถานะปลายทาง ต้องล้างคิวของฐานนี้")
    }
}
