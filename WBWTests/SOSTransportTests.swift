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
}
