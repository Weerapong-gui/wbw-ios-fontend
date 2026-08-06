import XCTest
@testable import WBW

@MainActor
final class StaffSOSTests: XCTestCase {

    func testCasesAreSortedNewestFirst() {
        let store = StaffSOSStore(feedCall: { _, _ in [] })
        store.apply([Self.make(id: 1, updated: "2026-08-06T10:00:00Z"),
                     Self.make(id: 2, updated: "2026-08-06T10:05:00Z")])
        XCTAssertEqual(store.cases.first?.id, 2)
    }

    /// เคสที่ปิดแล้วต้องยังอยู่ให้เห็นสักพัก — หายไปเฉยๆ แยกไม่ออกจาก "โหลดไม่ขึ้น"
    func testResolvedCasesStayInTheListButAreMarked() {
        let store = StaffSOSStore(feedCall: { _, _ in [] })
        store.apply([Self.make(id: 1, updated: "2026-08-06T10:00:00Z", resolved: true)])
        XCTAssertEqual(store.cases.count, 1)
        XCTAssertTrue(store.cases[0].resolved)
    }

    func testTheOpenCountIgnoresResolvedCasesBecauseTheBadgeMeansWorkLeft() {
        let store = StaffSOSStore(feedCall: { _, _ in [] })
        store.apply([Self.make(id: 1, updated: "2026-08-06T10:00:00Z", resolved: true),
                     Self.make(id: 2, updated: "2026-08-06T10:01:00Z", resolved: false)])
        XCTAssertEqual(store.openCount, 1)
    }

    func testACoarseFixIsLabelledSoNobodyTrustsTheBase() {
        let c = Self.make(id: 1, updated: "2026-08-06T10:00:00Z", accuracy: 500)
        XCTAssertTrue(c.accuracyLabel.contains("500"))
        XCTAssertTrue(c.isCoarse)
    }

    func testACaseWithNoPositionSaysSoInsteadOfShowingZeroZero() {
        let c = Self.make(id: 1, updated: "2026-08-06T10:00:00Z", lat: nil, lng: nil)
        XCTAssertEqual(c.positionLabel, "ไม่ทราบตำแหน่ง")
    }

    // MARK: - cursor เป็นคู่ "<updated_at>|<id>" ไม่ใช่ updated_at เดี่ยวๆ
    // (ดู task brief หัวข้อ "The cursor is a compound value")

    func testCursorIsBuiltAsThePairFromTheNewestRowNotUpdatedAtAlone() {
        let store = StaffSOSStore(feedCall: { _, _ in [] })
        store.apply([Self.make(id: 5, updated: "2026-08-06T10:00:00Z"),
                     Self.make(id: 9, updated: "2026-08-06T10:05:00Z")])
        XCTAssertEqual(store.cursor, "2026-08-06T10:05:00Z|9")
    }

    /// สองเคสเวลาเท่ากันเป๊ะ — ต้องใช้ id เข้ามาตัดสินร่วมด้วยเท่านั้นที่ cursor จะนิ่ง ไม่สุ่มเปลี่ยนไปมา
    /// ตาม Dictionary ภายใน — ถ้า cursor สร้างจาก updated_at เดี่ยวๆ เคสที่ id ต่ำกว่าจะหลุดหายจากทุก
    /// poll ถัดไปถาวรทันทีที่ชนเวลาเดียวกับอีกเคส
    func testTwoCasesSharingTheSameInstantStillProduceAStableCursor() {
        let store = StaffSOSStore(feedCall: { _, _ in [] })
        store.apply([Self.make(id: 3, updated: "2026-08-06T10:00:00Z"),
                     Self.make(id: 7, updated: "2026-08-06T10:00:00Z")])
        XCTAssertEqual(store.cursor, "2026-08-06T10:00:00Z|7", "id สูงกว่าต้องชนะเมื่อเวลาเท่ากันเป๊ะ")
        XCTAssertEqual(store.cases.first?.id, 7)
    }

    /// round-trip จริง ไม่ใช่แค่ดูว่า cursor ถูกสร้างถูกรูปแบบ — poll รอบถัดไปต้องส่ง cursor
    /// ที่ apply() ของรอบก่อนคำนวณไว้กลับไปแบบไม่เปลี่ยนรูป (ไม่ตัด id ทิ้ง ไม่แยกกลับเป็น updated_at
    /// เดี่ยวๆ) — ฉีด pollInterval สั้นๆ เพื่อไม่ต้องรอ 1 วินาทีจริงต่อรอบ
    func testTheCursorSentOnTheNextPollIsExactlyWhatApplyComputedUnchanged() async throws {
        var received: [String?] = []
        let store = StaffSOSStore(feedCall: { _, since in
            received.append(since)
            return received.count == 1 ? [Self.make(id: 3, updated: "2026-08-06T10:00:00Z")] : []
        }, pollInterval: .milliseconds(5))
        store.start(token: "t")
        // รอให้ loop ยิงอย่างน้อยสองรอบ — รอบแรกไม่มี cursor (nil) รอบสองต้องพก cursor ที่รอบแรก
        // apply() คำนวณไว้กลับไปตรงๆ
        try await Task.sleep(for: .milliseconds(300))
        store.stop()
        XCTAssertGreaterThanOrEqual(received.count, 2, "loop ต้องยิงอย่างน้อยสองรอบภายใน 300ms ที่ poll ทุก 5ms")
        XCTAssertNil(received[0], "รอบแรกยังไม่เคยมี cursor")
        XCTAssertEqual(received[1], "2026-08-06T10:00:00Z|3")
    }

    // MARK: - เคสใหม่ต้องทับเต็มจอ ไม่ใช่แค่ badge (ดู RootView + StaffSOSAlertView)

    /// โหลดครั้งแรก (baseline) ไม่ใช่ "เคสเพิ่งเข้ามา" ในสายตาเจ้าหน้าที่คนนี้ — ถ้าทับจอทุกเคสที่มีอยู่
    /// ก่อนแล้วตอนเปิดแอป เจ้าหน้าที่ที่เข้างานตอนมี 5 เคสเปิดค้างอยู่แล้วจะโดนจอทับซ้อนกัน 5 ชั้นทันที
    func testTheFirstLoadDoesNotTriggerTheFullScreenAlert() {
        let store = StaffSOSStore(feedCall: { _, _ in [] })
        store.apply([Self.make(id: 1, updated: "2026-08-06T10:00:00Z")])
        XCTAssertNil(store.newCase)
    }

    func testACaseArrivingAfterTheBaselineTriggersTheFullScreenAlert() {
        let store = StaffSOSStore(feedCall: { _, _ in [] })
        store.apply([Self.make(id: 1, updated: "2026-08-06T10:00:00Z")])
        store.apply([Self.make(id: 2, updated: "2026-08-06T10:05:00Z")])
        XCTAssertEqual(store.newCase?.id, 2)
    }

    /// เคสเดิมแค่ถูกอัปเดต (เช่น มีคนรับเรื่องแล้ว) ไม่ใช่เคสใหม่ — ห้ามทับจอซ้ำทุกครั้งที่มีการเปลี่ยนแปลง
    func testAnUpdateToAnAlreadySeenCaseDoesNotRetriggerTheAlert() {
        let store = StaffSOSStore(feedCall: { _, _ in [] })
        store.apply([Self.make(id: 1, updated: "2026-08-06T10:00:00Z")])
        store.apply([Self.make(id: 1, updated: "2026-08-06T10:05:00Z")]) // อัปเดตเคสเดิม id 1
        XCTAssertNil(store.newCase)
    }

    /// เคสที่เพิ่งเห็นเป็นครั้งแรกแต่ปิดไปแล้วตั้งแต่แถวแรกที่เห็น (เช่น เจ้าหน้าที่คนอื่นปิดเร็วกว่า poll
    /// รอบนี้จะทันเห็นตอนยังเปิดอยู่) ไม่ต้องทับจอ — ไม่มีอะไรเร่งด่วนให้ทำแล้ว
    func testAResolvedCaseArrivingFreshDoesNotTriggerTheAlert() {
        let store = StaffSOSStore(feedCall: { _, _ in [] })
        store.apply([Self.make(id: 1, updated: "2026-08-06T10:00:00Z")])
        store.apply([Self.make(id: 2, updated: "2026-08-06T10:05:00Z", resolved: true)])
        XCTAssertNil(store.newCase)
    }

    /// พบจากรีวิว: ฟีดฉุกเฉินว่างเปล่าเป็นปกติเกือบทั้งวันของงาน — apply([]) ไม่เติมอะไรใน seenIDs สักตัว
    /// ถ้าตัดสิน baseline จาก seenIDs.isEmpty เคสจริงเคสแรกที่มาถึงหลังช่วงเงียบ (ไม่ว่าจะเงียบมากี่ตา)
    /// จะยังถูกนับเป็น baseline อยู่ดี จอทับเต็มจอไม่มีวันเปิดเลยสำหรับเหตุฉุกเฉินจริงตัวแรกของวัน — พัง
    /// ตรงจุดที่สเปกทั้งอันมีไว้ป้องกันพอดี (เจ้าหน้าที่กำลังก้มมองคิว QR อยู่)
    func testEmptyPollsBeforeTheFirstRealCaseStillLetItTriggerTheAlert() {
        let store = StaffSOSStore(feedCall: { _, _ in [] })
        store.apply([]) // long-poll ตอบกลับมาแบบไม่มีเคส — เป็นปกติเกือบทั้งวัน
        store.apply([]) // อีกตา ยังไม่มีอะไร
        store.apply([Self.make(id: 1, updated: "2026-08-06T10:00:00Z")]) // เคสฉุกเฉินจริงตัวแรกของวัน
        XCTAssertEqual(store.newCase?.id, 1, "เคสจริงตัวแรกหลังช่วงเงียบต้องเด้งจอทับ ไม่ใช่ถูกนับเป็น baseline")
    }

    // MARK: - เคสของตัวเจ้าหน้าที่เอง (จากปุ่ม SOS ของตัวเอง) ต้องไม่มาแย่ง fullScreenCover กับ
    // SOSStatusView ของตัวเอง (ดู StaffHomeView.staffOwnSOS + StaffSOSStore.currentUserId)

    func testACaseRaisedByTheLoggedInStaffMemberThemselvesDoesNotTriggerTheAlert() {
        let store = StaffSOSStore(feedCall: { _, _ in [] }, currentUserId: "staff-self")
        store.apply([Self.make(id: 1, updated: "2026-08-06T10:00:00Z")]) // baseline
        store.apply([Self.make(id: 2, updated: "2026-08-06T10:05:00Z", participantId: "staff-self")])
        XCTAssertNil(store.newCase, "เคสของตัวเองมี SOSStatusView ของตัวเองเปิดทับอยู่แล้ว ไม่ต้องมีจอ \"มีเหตุฉุกเฉินใหม่\" ซ้อนอีกชั้น")
    }

    /// ต้องไม่กันเคสของ "คนอื่น" ไปด้วยจากการเช็ค currentUserId — แค่เคสของตัวเองเท่านั้นที่ถูกยกเว้น
    func testACaseRaisedBySomeoneElseStillTriggersTheAlertWhenCurrentUserIdIsSet() {
        let store = StaffSOSStore(feedCall: { _, _ in [] }, currentUserId: "staff-self")
        store.apply([Self.make(id: 1, updated: "2026-08-06T10:00:00Z")]) // baseline
        store.apply([Self.make(id: 2, updated: "2026-08-06T10:05:00Z", participantId: "someone-else")])
        XCTAssertEqual(store.newCase?.id, 2)
    }

    /// เคสของตัวเองยังต้องอยู่ในลิสต์ตามปกติ — ที่ถูกกันออกคือแค่การเด้งจอทับเท่านั้น ไม่ใช่หายจากแท็บ SOS ไปด้วย
    func testACaseRaisedByTheLoggedInStaffMemberStillAppearsInTheList() {
        let store = StaffSOSStore(feedCall: { _, _ in [] }, currentUserId: "staff-self")
        store.apply([Self.make(id: 1, updated: "2026-08-06T10:00:00Z", participantId: "staff-self")])
        XCTAssertEqual(store.cases.count, 1)
        XCTAssertEqual(store.cases.first?.id, 1)
    }

    private static func make(id: Int64, updated: String, resolved: Bool = false,
                             accuracy: Double? = 12, lat: Double? = 20.04, lng: Double? = 99.89,
                             participantId: String = "11111111-1111-1111-1111-111111111111") -> SOSStaffCase {
        SOSStaffCase(id: id, forOther: false, lat: lat, lng: lng, accuracyM: accuracy,
                     locSource: lat == nil ? "none" : "gps",
                     checkpointId: lat == nil ? nil : 2,
                     checkpointName: lat == nil ? nil : "สวนกุหลาบ",
                     message: nil, resolved: resolved,
                     resolveReason: resolved ? "helped" : nil,
                     ackedAt: nil, ackedByName: nil,
                     createdAt: "2026-08-06T10:00:00Z", emergencyPhone: nil,
                     updatedAt: updated,
                     participantId: participantId,
                     firstName: "สมชาย", lastName: "ใจดี", bib: 42, groupNumber: 3,
                     contactPhone: "0891234567",
                     emergencyContactName: "แม่", emergencyContactPhone: "0899876543",
                     bloodType: nil, healthNotes: nil)
    }
}
