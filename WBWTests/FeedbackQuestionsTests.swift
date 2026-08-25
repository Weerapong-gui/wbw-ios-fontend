import XCTest
@testable import WBW

/// ให้คะแนนฐาน **สี่คำถาม ไม่ใช่คำถามเดียว** — ยกมาจาก branch `work` ของ Android (`3011729`)
///
/// เหตุผลที่ต้นทางเขียนไว้: "ฐานนี้เป็นอย่างไรบ้าง" คำถามเดียวยุบทุกอย่างที่ฐานหนึ่งเป็นให้เหลือ
/// เลขตัวเดียว แล้วผู้จัดเอาไปทำอะไรต่อไม่ได้ · ฐานหนึ่งมีวิวดีแต่กิจกรรมน่าเบื่อก็ได้ หรือ
/// เจ้าหน้าที่ดูแลดีแต่ไม่มีที่นั่งก็ได้ — ถามแยกคือสิ่งที่ทำให้คำตอบใช้ได้จริงปีหน้า
///
/// เซิร์ฟเวอร์รองรับอยู่แล้ว: `rating` บังคับ ส่วน `rating_scenery`/`rating_activity`/`rating_staff`
/// เป็น optional ทั้งสามตัว
final class FeedbackQuestionsTests: XCTestCase {

    private let deviceTime = "2026-08-25T09:00:00Z"

    // MARK: - ของค้างคิวจากเวอร์ชันก่อน

    /// **draft ที่ค้างอยู่ใน `UserDefaults` ตั้งแต่ก่อนมีสามฟิลด์นี้ต้อง decode ผ่าน**
    ///
    /// คิวความเห็นเป็นก้อน JSON ก้อนเดียว decode ไม่ออกหนึ่งใบ = ทั้งคิวหาย และคนที่ตอบไว้ตอน
    /// ไม่มีสัญญาณบนดอยจะเสียคำตอบทั้งหมดโดยไม่มีอะไรบอก (กับดักที่ `FeedbackOutbox` บันทึกไว้เอง)
    func testDraftsQueuedBeforeTheExtraQuestionsStillDecode() throws {
        let legacy = #"""
        {"clientId":"c1","checkpointId":5,"rating":3,"comment":"ดีมาก","deviceTime":"\#(deviceTime)"}
        """#
        let draft = try JSONDecoder().decode(FeedbackDraft.self, from: Data(legacy.utf8))
        XCTAssertEqual(draft.rating, 3)
        XCTAssertNil(draft.ratingScenery)
        XCTAssertNil(draft.ratingActivity)
        XCTAssertNil(draft.ratingStaff)
    }

    func testAFullDraftSurvivesARoundTrip() throws {
        let draft = FeedbackDraft(clientId: "c2", checkpointId: 3, rating: 5,
                                  ratingScenery: 4, ratingActivity: 2, ratingStaff: 5,
                                  comment: nil, deviceTime: deviceTime)
        let data = try JSONEncoder().encode(draft)
        XCTAssertEqual(try JSONDecoder().decode(FeedbackDraft.self, from: data), draft)
    }

    // MARK: - ส่งได้เมื่อไหร่

    /// **ภาพรวมคือข้อเดียวที่บังคับ** — อีกสามข้อไม่ตอบก็ส่งได้ (เซิร์ฟเวอร์รับ null)
    /// บังคับครบสี่ข้อคือการเปลี่ยนแบบสอบถามให้ยาวขึ้นสามเท่าสำหรับคนที่กำลังยืนกลางแดด
    func testOnlyTheOverallRatingIsRequired() {
        XCTAssertFalse(FeedbackDraft.canSubmit(overall: nil))
        XCTAssertTrue(FeedbackDraft.canSubmit(overall: 1))
        XCTAssertTrue(FeedbackDraft.canSubmit(overall: 5))
    }

    // MARK: - ก้อนที่ยิงขึ้นเซิร์ฟเวอร์

    /// คีย์ที่ไม่มีค่าต้อง **ไม่ถูกใส่ลงไปเลย** ไม่ใช่ส่ง null — เซิร์ฟเวอร์แยกสองอย่างนี้ไม่ออก
    /// ก็จริง แต่ก้อนที่มีคีย์ว่างเต็มไปหมดคือของที่อ่านยากตอนไล่ log ในวันงาน
    func testTheRequestOnlyCarriesTheAnswersThatExist() throws {
        let sparse = FeedbackDraft(clientId: "c3", checkpointId: 1, rating: 4,
                                   ratingScenery: nil, ratingActivity: nil, ratingStaff: nil,
                                   comment: nil, deviceTime: deviceTime)
        let body = APIClient.feedbackBody(draft: sparse)
        XCTAssertEqual(body["client_id"] as? String, "c3")
        XCTAssertEqual(body["checkpoint_id"] as? Int, 1)
        XCTAssertEqual(body["rating"] as? Int, 4)
        XCTAssertEqual(body["device_time"] as? String, deviceTime)
        for absent in ["rating_scenery", "rating_activity", "rating_staff", "comment"] {
            XCTAssertNil(body[absent], "คีย์ \(absent) ไม่ควรอยู่ในก้อนเมื่อผู้ใช้ไม่ได้ตอบ")
        }
    }

    func testTheRequestCarriesEveryAnswerWhenAllFourAreGiven() {
        let full = FeedbackDraft(clientId: "c4", checkpointId: 2, rating: 5,
                                 ratingScenery: 4, ratingActivity: 3, ratingStaff: 2,
                                 comment: "ร่มดี", deviceTime: deviceTime)
        let body = APIClient.feedbackBody(draft: full)
        XCTAssertEqual(body["rating_scenery"] as? Int, 4)
        XCTAssertEqual(body["rating_activity"] as? Int, 3)
        XCTAssertEqual(body["rating_staff"] as? Int, 2)
        XCTAssertEqual(body["comment"] as? String, "ร่มดี")
    }

    /// **สเกลต้องเท่ากันสองแอป** — ฝั่ง Android ถาม 1–5 ทุกข้อ · iOS เคยเป็นสามหน้า (1–3)
    /// ปล่อยไว้คนละสเกลแปลว่าผู้จัดเอาคะแนนสองแอปมารวมกันไม่ได้เลย ทั้งที่เป็นงานเดียวกัน
    func testTheScaleMatchesTheOtherApp() {
        XCTAssertEqual(FeedbackDraft.scale, 1...5)
    }
}
