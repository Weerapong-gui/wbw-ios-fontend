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
        nonisolated(unsafe) static var requestCount = 0

        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.path.hasSuffix("/me/feedback") == true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.requestCount += 1
            let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(StubURLProtocol.self)
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data()
        StubURLProtocol.requestCount = 0
        UserDefaults.standard.removeObject(forKey: FeedbackOutbox.key(for: Config.backend))
    }

    override func tearDown() {
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
    func testClientErrorsStayTerminal() async {
        for status in [400, 401, 422] {
            StubURLProtocol.status = status
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

    /// 409/403 ยังต้องเป็น "ผลลัพธ์" ไม่ใช่ error เหมือนเดิม — ฟอร์มพึ่งค่านี้ไปแสดงคำตอบเดิม
    func testConflictAndForbiddenRemainOutcomes() async throws {
        StubURLProtocol.status = 409
        let conflict = try await APIClient.shared.submitFeedback(token: "t", draft: draft("a"))
        XCTAssertEqual(conflict, .alreadyAnswered)

        StubURLProtocol.status = 403
        let forbidden = try await APIClient.shared.submitFeedback(token: "t", draft: draft("a"))
        XCTAssertEqual(forbidden, .notCheckedIn)
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
}
