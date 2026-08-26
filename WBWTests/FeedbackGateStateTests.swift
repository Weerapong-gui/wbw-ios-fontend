import XCTest
@testable import WBW

/// กติกาการตัดสินใจของ feedback gate — ยกจาก FeedbackGate.kt ฝั่ง Android คำต่อคำ
/// (สเปก: docs/superpowers/specs/2026-08-26-feedback-gate-and-event-design.md)
final class FeedbackGateStateTests: XCTestCase {

    private func item(_ id: Int, answered: Bool, at: String) -> CheckinProgressItem {
        CheckinProgressItem(checkpointId: id, name: "ฐาน \(id)", activityName: nil,
                            sequence: id, at: at, answered: answered,
                            rating: answered ? 4 : nil, comment: nil)
    }

    /// เวลาอ้างอิงคงที่ของเทสชุดนี้ · `at` ที่ backend ส่งมาเป็น RFC3339 UTC ไม่มีเศษวินาที
    private let now = ISO8601DateFormatter().date(from: "2026-08-29T12:00:00Z")!

    private func atMinutesAgo(_ minutes: Int) -> String {
        ISO8601DateFormatter().string(from: now.addingTimeInterval(-Double(minutes) * 60))
    }

    // ===== gate ยึดจอเฉพาะฐานที่ "เพิ่งเช็คอิน" =====

    /// **หัวใจของ gate คือความสด ไม่ใช่แค่ "ยังไม่ตอบ"** — เหตุผลทั้งหมดที่ยอมให้จอนี้ยึดจอ
    /// คือผู้ใช้ยังยืนอยู่ที่ฐานตรงนั้น เห็นของที่กำลังให้คะแนนอยู่ตรงหน้า
    ///
    /// เช็คอินที่ค้างมาหลายวันไม่เข้าเงื่อนไขนั้นเลย และการยกฟอร์มที่ปิดไม่ได้ขึ้นมาขวาง
    /// คนที่เพิ่งเปิดแอปวันหลังคือกับดักล้วน ๆ — คำตอบที่ได้ก็เป็นความทรงจำของความทรงจำ
    /// (เหตุผลเดียวกับที่สเปกยกมาจาก Android) · ของเก่ายังตอบได้ทางแจ้งเตือน/ชีตที่ปัดปิดได้เหมือนเดิม
    func testAFreshCheckinGatesTheScreen() {
        let p = CheckinProgress(total: 9, checkedIn: [item(1, answered: false, at: atMinutesAgo(3))])
        XCTAssertEqual(
            FeedbackGateState.decide(progress: p, queuedCheckpoints: [], skippedCheckpoints: [],
                                     eventDismissed: false, now: now),
            .base(p.checkedIn[0]))
    }

    /// **เคสที่เจอจริงบน production 2026-08-27**: บัญชีรีวิวของ App Store ถูก staff สแกนเข้า
    /// 8 ฐานไว้ตั้งแต่ 24 ส.ค. แล้วไม่เคยให้คะแนน · ผู้ตรวจล็อกอินแล้วจะเจอฟอร์มที่ปิดไม่ได้
    /// ทันทีแปดฟอร์มติดกัน ซึ่งเป็นแพทเทิร์นเดียวกับที่โดน Guideline 5.1.1(iv) มาแล้วสองรอบ
    func testACheckinFromDaysAgoDoesNotGateAnything() {
        let threeDays = atMinutesAgo(3 * 24 * 60)
        let p = CheckinProgress(total: 9, checkedIn: [item(1, answered: false, at: threeDays)])
        XCTAssertNil(
            FeedbackGateState.decide(progress: p, queuedCheckpoints: [], skippedCheckpoints: [],
                                     eventDismissed: false, now: now),
            "เช็คอินค้างจากวันก่อนต้องไม่ยึดจอ — ไม่มีใครยืนอยู่ที่ฐานนั้นแล้ว")
    }

    func testTheOldestFreshCheckinWinsAndStaleOnesAreIgnored() {
        let p = CheckinProgress(total: 9, checkedIn: [
            item(1, answered: false, at: atMinutesAgo(2 * 24 * 60)),   // ค้างจากเมื่อวาน
            item(5, answered: false, at: atMinutesAgo(30)),            // เพิ่งเช็คอิน
            item(6, answered: false, at: atMinutesAgo(10)),
        ])
        XCTAssertEqual(
            FeedbackGateState.decide(progress: p, queuedCheckpoints: [], skippedCheckpoints: [],
                                     eventDismissed: false, now: now),
            .base(p.checkedIn[1]), "ต้องถามฐานที่เพิ่งถึงและเก่าที่สุดในกลุ่มที่ยังสด")
    }

    /// `at` ที่ parse ไม่ออก = ไม่ยก gate · ทิศนี้ปลอดภัยกว่าอีกทิศชัดเจน: ถ้า backend เปลี่ยน
    /// ฟอร์แมตวันเวลา ผลที่แย่ที่สุดคือกลับไปใช้ทางเดิม (แจ้งเตือน + ชีตที่ปัดปิดได้) ซึ่งยังเก็บ
    /// คำตอบได้ · ทิศตรงข้ามคือยกฟอร์มที่ปิดไม่ได้ขึ้นมาให้ทุกคนพร้อมกัน
    func testAnUnparseableTimestampNeverGates() {
        let p = CheckinProgress(total: 9, checkedIn: [item(1, answered: false, at: "เมื่อกี้")])
        XCTAssertNil(
            FeedbackGateState.decide(progress: p, queuedCheckpoints: [], skippedCheckpoints: [],
                                     eventDismissed: false, now: now))
    }

    /// ตรึงฟอร์แมตที่ backend ส่งมาจริง (`at.UTC().Format(time.RFC3339)` — ไม่มีเศษวินาที ลงท้าย Z)
    /// ให้เทสเป็นตัวจับ ไม่ใช่ปล่อยให้ gate เงียบหายไปเองถ้าฝั่ง server เปลี่ยนฟอร์แมต
    func testTheRealBackendTimestampFormatParses() {
        let p = CheckinProgress(total: 9, checkedIn: [item(1, answered: false, at: "2026-08-29T11:55:00Z")])
        XCTAssertNotNil(
            FeedbackGateState.decide(progress: p, queuedCheckpoints: [], skippedCheckpoints: [],
                                     eventDismissed: false, now: now),
            "ฟอร์แมตนี้คือของจริงจาก SUS — parse ไม่ออกเมื่อไหร่ gate จะหายไปทั้งฟีเจอร์เงียบ ๆ")
    }

    /// ฐานที่ผู้ใช้กด "ข้ามไปก่อน" หลังส่งพังแบบถาวร — ห้ามยกกลับมาซ้ำในรันนี้
    /// (จำแค่ในหน่วยความจำเหมือน `eventDismissed` เพราะ server ยังไม่เคยได้คำตอบ เปิดแอปใหม่ถามได้)
    func testASkippedBaseDoesNotComeBack() {
        let p = CheckinProgress(total: 9, checkedIn: [item(1, answered: false, at: atMinutesAgo(5))])
        XCTAssertNil(
            FeedbackGateState.decide(progress: p, queuedCheckpoints: [], skippedCheckpoints: [1],
                                     eventDismissed: false, now: now))
    }

    // ===== ฟอร์มทั้งงานก็ต้องสดเหมือนกัน =====

    /// **เหตุผลเดียวกับฟอร์มต่อฐาน: ยึดจอได้เพราะ "เพิ่งเดินจบ" ไม่ใช่ "เคยเดินจบเมื่อสามวันก่อน"**
    ///
    /// เคสจริงที่ต้องกัน: บัญชีรีวิวของ App Store เช็คอินไว้ครบ 8 ฐานตั้งแต่ 24 ส.ค. พอ Zero Waste
    /// ถูกตัดออกจากการนับ (total 9 → 8) บัญชีนั้นกลายเป็น "เดินครบ" ทันที ผู้ตรวจล็อกอินแล้วจะเจอ
    /// ฟอร์มความเห็นทั้งงานยึดเต็มจอ = แพทเทิร์นเดียวกับที่โดน Guideline 5.1.1(iv) มาแล้วสองรอบ
    func testAWalkFinishedDaysAgoDoesNotRaiseTheEventForm() {
        let old = atMinutesAgo(3 * 24 * 60)
        let p = CheckinProgress(total: 2, checkedIn: [item(1, answered: true, at: old),
                                                      item(2, answered: true, at: old)])
        XCTAssertNil(
            FeedbackGateState.decide(progress: p, queuedCheckpoints: [], skippedCheckpoints: [],
                                     eventDismissed: false, now: now),
            "เดินจบตั้งแต่สามวันก่อน ไม่มีใครกำลังยืนอยู่ปลายทางแล้ว")
    }

    func testAWalkJustFinishedStillRaisesTheEventForm() {
        let p = CheckinProgress(total: 2, checkedIn: [item(1, answered: true, at: atMinutesAgo(90)),
                                                      item(2, answered: true, at: atMinutesAgo(10))])
        XCTAssertEqual(
            FeedbackGateState.decide(progress: p, queuedCheckpoints: [], skippedCheckpoints: [],
                                     eventDismissed: false, now: now),
            .event, "เพิ่งเดินจบสิบนาทีที่แล้ว = จังหวะที่ฟอร์มนี้มีไว้ถาม")
    }

    /// เช็คอินฐานเก่า แต่ฐานสุดท้ายเพิ่งจบ — ยังนับว่าสด (ดูเช็คอินล่าสุด ไม่ใช่เก่าสุด)
    func testFreshnessLooksAtTheLastCheckinNotTheFirst() {
        let p = CheckinProgress(total: 2, checkedIn: [
            item(1, answered: true, at: atMinutesAgo(11 * 60)),   // เช้าวันเดียวกัน
            item(2, answered: true, at: atMinutesAgo(5)),
        ])
        XCTAssertEqual(
            FeedbackGateState.decide(progress: p, queuedCheckpoints: [], skippedCheckpoints: [],
                                     eventDismissed: false, now: now), .event)
    }

    // ===== ฟิลด์ใหม่บน CheckinProgress =====

    /// server ยังไม่ส่ง event_feedback_answered มา (SUS ยังไม่มี endpoint) — ขาดต้องเป็น false
    /// ไม่ใช่ decode ล่ม: ถามซ้ำดีกว่าแอปเปิดไม่ขึ้น
    func testEventFeedbackAnsweredDefaultsToFalseWhenAbsent() throws {
        let json = #"{"total":2,"checked_in":[]}"#
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let p = try dec.decode(CheckinProgress.self, from: Data(json.utf8))
        XCTAssertFalse(p.eventFeedbackAnswered)
    }

    func testEventFeedbackAnsweredDecodesWhenPresent() throws {
        let json = #"{"total":2,"checked_in":[],"event_feedback_answered":true}"#
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let p = try dec.decode(CheckinProgress.self, from: Data(json.utf8))
        XCTAssertTrue(p.eventFeedbackAnswered)
    }

    /// complete สูตรเดียวกับ Android: total > 0 && count >= total —
    /// งานที่ไม่มีฐานเลยต้องไม่นับว่าจบ ไม่งั้น event form เด้งใส่ทุกคนตั้งแต่ยังไม่เริ่มเดิน
    func testCompleteRequiresANonZeroTotalFullyCollected() {
        XCTAssertFalse(CheckinProgress(total: 0, checkedIn: []).complete,
                       "งานที่ไม่มีฐาน = ยังไม่จบ ไม่ใช่จบตั้งแต่เกิด")
        XCTAssertFalse(CheckinProgress(total: 2, checkedIn: [item(1, answered: true, at: atMinutesAgo(30))]).complete)
        XCTAssertTrue(CheckinProgress(total: 1, checkedIn: [item(1, answered: true, at: atMinutesAgo(30))]).complete)
    }

    // ===== decide =====

    func testNoProgressMeansNoGate() {
        XCTAssertNil(FeedbackGateState.decide(progress: nil, queuedCheckpoints: [],
                                              skippedCheckpoints: [], eventDismissed: false, now: now))
    }

    /// ทีละฐาน เรียงตามลำดับที่เดินถึง — โดนสแกนสามฐานตอนมือถืออยู่ในกระเป๋า
    /// ต้องเจอฟอร์มของฐานแรกก่อน ไม่ใช่ฐานล่าสุด (ตรงข้ามกับ toast)
    func testPendingBaseComesOldestFirst() {
        let p = CheckinProgress(total: 5, checkedIn: [
            item(3, answered: false, at: atMinutesAgo(90)),
            item(1, answered: false, at: atMinutesAgo(180)),
            item(2, answered: true,  at: atMinutesAgo(120)),
        ])
        XCTAssertEqual(FeedbackGateState.decide(progress: p, queuedCheckpoints: [],
                                                skippedCheckpoints: [], eventDismissed: false, now: now),
                       .base(p.checkedIn[1]), "ฐานที่ถึงก่อนต้องถูกถามก่อน")
    }

    func testAllAnsweredButRouteUnfinishedMeansNoGate() {
        let p = CheckinProgress(total: 5, checkedIn: [item(1, answered: true, at: atMinutesAgo(30))])
        XCTAssertNil(FeedbackGateState.decide(progress: p, queuedCheckpoints: [],
                                              skippedCheckpoints: [], eventDismissed: false, now: now))
    }

    /// ครบทุกฐาน + ตอบครบ + ยังไม่เคยตอบทั้งงาน = ถึงคิว event form
    func testEventDueWhenRouteCompleteAndEverythingAnswered() {
        let p = CheckinProgress(total: 1, checkedIn: [item(1, answered: true, at: atMinutesAgo(30))])
        XCTAssertEqual(FeedbackGateState.decide(progress: p, queuedCheckpoints: [],
                                                skippedCheckpoints: [], eventDismissed: false, now: now), .event)
    }

    /// ฐานค้างตอบมาก่อน event เสมอ — แม้เส้นทางจะครบแล้ว
    func testPendingBaseBeatsEventEvenWhenComplete() {
        let p = CheckinProgress(total: 1, checkedIn: [item(1, answered: false, at: atMinutesAgo(30))])
        XCTAssertEqual(FeedbackGateState.decide(progress: p, queuedCheckpoints: [],
                                                skippedCheckpoints: [], eventDismissed: false, now: now),
                       .base(p.checkedIn[0]))
    }

    func testEventAnsweredOnServerMeansNoGate() {
        let p = CheckinProgress(total: 1, checkedIn: [item(1, answered: true, at: atMinutesAgo(30))],
                                eventFeedbackAnswered: true)
        XCTAssertNil(FeedbackGateState.decide(progress: p, queuedCheckpoints: [],
                                              skippedCheckpoints: [], eventDismissed: false, now: now))
    }

    /// ข้ามไปก่อน (ส่งไม่สำเร็จ) = เงียบแค่รันนี้ — decide เคารพ flag ที่ caller ถือ
    func testEventDismissedThisRunMeansNoGate() {
        let p = CheckinProgress(total: 1, checkedIn: [item(1, answered: true, at: atMinutesAgo(30))])
        XCTAssertNil(FeedbackGateState.decide(progress: p, queuedCheckpoints: [],
                                              skippedCheckpoints: [], eventDismissed: true, now: now))
    }

    // ===== queuedCheckpoints — คำตอบที่ยังค้างอยู่ใน outbox =====

    /// **นี่คือทางที่ผู้ใช้ออกไม่ได้เลยถ้า gate ไม่นับคิว**: ตอบฐานตอนไม่มีสัญญาณ →
    /// `FeedbackStore.submit` จับ `AppError.offline` เก็บเข้า outbox แล้วคืน `.saved` → ฟอร์ม
    /// ตั้ง `sent = true` (ปุ่มส่งหายไป กลายเป็นอ่านอย่างเดียว) → `progress.load` ที่ตามมาล้มเหลว
    /// เงียบ ๆ เพราะเน็ตหลุดเหมือนกัน (`guard let fresh = try? ... else { return }`) → `answered`
    /// ยังเป็น false → gate ยกฐานเดิมขึ้นซ้ำ · gate ไม่มีปุ่มปิด และ cache ของ progress ยกฐานเดิม
    /// กลับมาหลังปิดแอปด้วย เหลือของที่กดได้บนจอชิ้นเดียวคือปุ่ม SOS
    ///
    /// คำตอบที่อยู่ในคิวคือคำตอบที่ผู้ใช้ให้ไปแล้วจริง ๆ — gate จึงต้องนับว่า "ตอบแล้ว" ความเข้มของ
    /// gate ไม่ได้ลดลง (ยังต้องให้คะแนนและกดส่งเหมือนเดิม) แค่เลิกให้ "จอปิดได้ไหม" ขึ้นกับเน็ต
    func testQueuedBaseDoesNotGateAndTheNextUnqueuedOneDoes() {
        let p = CheckinProgress(total: 5, checkedIn: [
            item(1, answered: false, at: atMinutesAgo(180)),
            item(2, answered: false, at: atMinutesAgo(120)),
        ])
        XCTAssertEqual(FeedbackGateState.decide(progress: p, queuedCheckpoints: [1],
                                                skippedCheckpoints: [], eventDismissed: false, now: now),
                       .base(p.checkedIn[1]),
                       "ฐาน 1 ตอบไปแล้ว (รออยู่ในคิว) ต้องข้ามไปถามฐาน 2 ไม่ใช่วนถามฐาน 1 ซ้ำ")
    }

    /// ตอบครบทุกฐานตอนเน็ตหลุด แล้วเส้นทางยังไม่ครบ = ไม่มี gate เลย ผู้ใช้กลับไปเดินต่อได้
    func testAllPendingBasesQueuedMeansNoGate() {
        let p = CheckinProgress(total: 5, checkedIn: [
            item(1, answered: false, at: atMinutesAgo(180)),
            item(2, answered: false, at: atMinutesAgo(120)),
        ])
        XCTAssertNil(FeedbackGateState.decide(progress: p, queuedCheckpoints: [1, 2],
                                              skippedCheckpoints: [], eventDismissed: false, now: now),
                     "ทุกฐานที่ค้างมีคำตอบรออยู่ในคิวแล้ว ไม่เหลืออะไรให้ถาม")
    }

    /// เดินครบทุกฐานแล้วตอบฐานสุดท้ายตอนเน็ตหลุด — ฐานถือว่าตอบแล้ว คิวจึงส่งต่อให้ event form
    /// ตามกติกาเดิมทุกประการ (ไม่ใช่ "ไม่มี gate อะไรเลยเพราะมีของค้างคิว")
    func testQueuedBaseStillLetsTheEventFormThrough() {
        let p = CheckinProgress(total: 1, checkedIn: [item(1, answered: false, at: atMinutesAgo(30))])
        XCTAssertEqual(FeedbackGateState.decide(progress: p, queuedCheckpoints: [1],
                                                skippedCheckpoints: [], eventDismissed: false, now: now), .event)
    }

    /// คิวว่าง = พฤติกรรมเดิมเป๊ะ ๆ — ของใหม่ต้องไม่ไปเปลี่ยนเส้นทางปกติที่เทสด้านบนค้ำไว้
    func testEmptyQueueBehavesExactlyAsBefore() {
        let p = CheckinProgress(total: 5, checkedIn: [
            item(3, answered: false, at: atMinutesAgo(90)),
            item(1, answered: false, at: atMinutesAgo(180)),
        ])
        XCTAssertEqual(FeedbackGateState.decide(progress: p, queuedCheckpoints: [],
                                                skippedCheckpoints: [], eventDismissed: false, now: now),
                       .base(p.checkedIn[1]))
        // ฐานที่ไม่เกี่ยวข้องอยู่ในคิวก็ต้องไม่ทำให้ลำดับเพี้ยน
        XCTAssertEqual(FeedbackGateState.decide(progress: p, queuedCheckpoints: [7, 8],
                                                skippedCheckpoints: [], eventDismissed: false, now: now),
                       .base(p.checkedIn[1]))
    }

    // ===== FeedbackGateItem — ตัวห่อให้ .fullScreenCover(item:) =====

    /// **id ต้องเปลี่ยนตามฐาน** — ตอบฐานแรกเสร็จแล้วฐานถัดไปขึ้นแทนที่ในคราวเดียว (cover ไม่ได้ปิด
    /// ระหว่างกลาง) ถ้า id เท่ากัน SwiftUI ถือว่าเป็น view เดิม @State ข้างใน (rating/comment/sent)
    /// ไม่รีเซ็ต = คะแนนที่พิมพ์ให้ฐาน A ไหลเข้าฟอร์มฐาน B — กับดักเดียวกับที่ Android จดไว้ที่
    /// viewModel(key:) และที่ .sheet(item:) ของ MainTabView ต้องใส่ .id(target.id) ด้วยเหตุผลเดียวกัน
    func testItemIdIsPerCheckpoint() {
        let a = FeedbackGateItem(state: .base(item(1, answered: false, at: atMinutesAgo(30))))
        let b = FeedbackGateItem(state: .base(item(2, answered: false, at: "b")))
        XCTAssertEqual(a?.id, "base-1")
        XCTAssertNotEqual(a?.id, b?.id, "คนละฐานต้องได้ id คนละตัว ไม่งั้นฟอร์มไม่ถูกสร้างใหม่")
    }

    /// event มีได้ครั้งเดียวทั้งงาน — id คงที่ ไม่ผูกกับฐานไหน
    func testEventItemHasStableId() {
        XCTAssertEqual(FeedbackGateItem(state: .event)?.id, "event")
    }

    /// nil เข้า nil ออก — "ไม่มี gate" ต้องไม่กลายเป็น item ที่เปิดจอเปล่า
    func testNoStateMeansNoItem() {
        XCTAssertNil(FeedbackGateItem(state: nil))
    }
}
