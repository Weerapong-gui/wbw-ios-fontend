import CoreLocation
import XCTest
@testable import WBW

/// ประตูสองบานสำหรับหยุด raiseCall ค้างกลางอากาศแบบควบคุมได้ ไม่ใช่ Task.sleep เดา — เทสสั่ง
/// wait() บาน "started" เพื่อรู้แน่ว่า raiseCall เริ่มทำงานแล้วและกำลังค้างอยู่จริง ก่อนจะแทรก
/// cancel()/clearForLogout() แล้วค่อยเปิดบาน "proceed" ให้ raiseCall เดินต่อจนสำเร็จ จำลอง race
/// ที่รีวิว Task 12 จับได้: เน็ตช้าแล้วเพิ่งตอบสำเร็จหลังผู้ใช้กด cancel/logout ไปแล้ว
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        let w = waiters
        waiters.removeAll()
        w.forEach { $0.resume() }
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

@MainActor
final class SOSStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SOSOutbox().clear()
    }

    /// เคสต้องลงเครื่องก่อน แม้เน็ตจะพังตั้งแต่วินาทีแรก
    func testRaiseQueuesLocallyBeforeTheNetworkIsEvenTried() async {
        let store = SOSStore(raiseCall: { _, _ in throw AppError.offline })
        await store.raise(forOther: false, token: "t")
        XCTAssertNotNil(SOSOutbox().current(), "เคสต้องอยู่ในเครื่องแม้ส่งไม่ออก")
        XCTAssertEqual(store.status, .queued)
    }

    /// ไล่ทุก error ที่ transport โยนได้ — ไม่มีอันไหนลบเคส
    func testNoErrorPathEverClearsTheOutbox() async {
        let errors: [Error] = [AppError.offline,
                               AppError.retryable("503"),
                               AppError.message("400"),
                               URLError(.badServerResponse)]
        for e in errors {
            SOSOutbox().clear()
            let store = SOSStore(raiseCall: { _, _ in throw e })
            await store.raise(forOther: false, token: "t")
            XCTAssertNotNil(SOSOutbox().current(), "\(e) ทำให้เคสหาย")
        }
    }

    func testRetryReusesTheSameClientIDSoTheServerSeesOneCase() async {
        var seen: [String] = []
        let store = SOSStore(raiseCall: { _, draft in
            seen.append(draft.clientId)
            throw AppError.offline
        })
        await store.raise(forOther: false, token: "t")
        await store.flush(token: "t")
        await store.flush(token: "t")
        XCTAssertEqual(Set(seen).count, 1, "ทุกครั้งที่ retry ต้องใช้ clientId เดิม")
        XCTAssertEqual(seen.count, 3)
    }

    func testASuccessfulSendMovesTheStatusToReceivedAndKeepsTheCase() async {
        // raiseCall สำเร็จ = send() เรียก startStatusPoll ทันทีตอนจบ ถ้าไม่ฉีด activeCall ไว้ด้วย
        // ค่าเริ่มต้นของมันคือ APIClient.shared.activeSOS ตัวจริง ยูนิตเทสจะยิงออกเน็ตจริงแบบเงียบๆ
        // (ดูโน้ตการเทสใน task brief) — ฉีดเคสที่ resolved แล้วให้ poll loop จบตัวเองตั้งแต่รอบแรก
        // ไม่ค้างเป็น background task ลอยต่อหลังเทสนี้จบ
        let store = SOSStore(raiseCall: { _, _ in Self.sampleCase(acked: false) },
                             activeCall: { _, _ in Self.sampleCase(acked: false, resolved: true) })
        await store.raise(forOther: false, token: "t")
        XCTAssertEqual(store.status, .received)
        XCTAssertEqual(SOSOutbox().current()?.serverId, 7, "ต้องจำ id ของเซิร์ฟเวอร์ไว้")
    }

    func testTheCallFallbackAppearsOnlyAfterTheCaseHasBeenStuck() async {
        let store = SOSStore(raiseCall: { _, _ in throw AppError.offline },
                             callFallbackDelay: .milliseconds(50))
        await store.raise(forOther: false, token: "t")
        XCTAssertFalse(store.showCallFallback, "ยังไม่ควรขึ้นทันที")
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(store.showCallFallback, "ค้างนานแล้วต้องดันปุ่มโทรขึ้นมา")
    }

    func testCancelAfterAckReportsAlreadyAckedAndKeepsTheCaseVisible() async {
        // เหตุผลเดียวกับเทสด้านบน: raiseCall สำเร็จเลยต้องฉีด activeCall กัน startStatusPoll
        // หลุดออกไปเรียกเน็ตจริงด้วย — cancelCall ตัวนี้ฉีดไว้แล้วโดยบรีฟเดิม
        let store = SOSStore(raiseCall: { _, _ in Self.sampleCase(acked: false) },
                             cancelCall: { _, _ in .alreadyAcked },
                             activeCall: { _, _ in Self.sampleCase(acked: false, resolved: true) })
        await store.raise(forOther: false, token: "t")
        let outcome = await store.cancel(token: "t")
        XCTAssertEqual(outcome, .alreadyAcked)
        XCTAssertNotNil(store.serverCase, "ยกเลิกไม่ผ่าน เคสต้องยังอยู่บนจอ")
    }

    func testLogoutClearsTheOutboxSoTheNextAccountDoesNotInheritTheCase() async {
        let store = SOSStore(raiseCall: { _, _ in throw AppError.offline })
        await store.raise(forOther: false, token: "t")
        store.clearForLogout()
        XCTAssertNil(SOSOutbox().current())
        XCTAssertNil(store.status)
    }

    /// พบจากรีวิว Task 12: raise() เรียก send() ซึ่งค้างอยู่กลาง await raiseCall — ถ้า clearForLogout()
    /// แทรกเข้ามาตรงนั้นพอดีแล้ว raiseCall ที่ค้างอยู่ดันสำเร็จทีหลัง ผลที่มาสายต้องไม่ฟื้นเคสที่เพิ่ง
    /// ล็อกเอาต์ไปกลับมา — มิฉะนั้นบัญชีถัดไปจะสืบทอดเคสของบัญชีก่อนหน้าซึ่งเป็นเหตุผลทั้งหมดที่
    /// clearForLogout() มีอยู่ตั้งแต่แรก
    func testClearForLogoutDuringASuspendedSendDoesNotResurrectTheCase() async {
        let started = Gate()
        let proceed = Gate()
        let store = SOSStore(raiseCall: { _, _ in
            await started.open()
            await proceed.wait()
            return Self.sampleCase(acked: false)
        })

        let raising = Task { await store.raise(forOther: false, token: "t") }
        await started.wait()               // รอให้แน่ใจว่า raiseCall เริ่มค้างอยู่จริงแล้ว
        store.clearForLogout()             // แทรกเข้ามาระหว่างที่ค้างรอเน็ตอยู่พอดี
        await proceed.open()               // ปล่อยให้ raiseCall ที่ค้างอยู่สำเร็จทีหลัง
        await raising.value

        XCTAssertNil(SOSOutbox().current(), "เคสที่ล็อกเอาต์ไปแล้วต้องไม่ฟื้นกลับมาแม้ raiseCall จะเพิ่งสำเร็จทีหลัง")
        XCTAssertNil(store.draft, "draft ต้องยังเป็น nil หลัง raiseCall ที่มาสาย")
    }

    /// เหมือนเทสด้านบนแต่ผ่านทาง cancel() สาขาที่ยังไม่เคยถึงเซิร์ฟเวอร์ (local-only) — สอง gap
    /// รวมกันเป็นบั๊กเดียวตามที่รีวิวอธิบาย: chaseTask ที่ไม่มีใครเก็บ handle ไว้ก่อน (แก้แล้ว) และ
    /// send() ที่ไม่เช็ค generation หลังตื่นจาก await (แก้แล้วเช่นกัน)
    func testCancelDuringASuspendedSendDoesNotResurrectTheCase() async {
        let started = Gate()
        let proceed = Gate()
        let store = SOSStore(raiseCall: { _, _ in
            await started.open()
            await proceed.wait()
            return Self.sampleCase(acked: false)
        })

        let raising = Task { await store.raise(forOther: false, token: "t") }
        await started.wait()
        let outcome = await store.cancel(token: "t")   // draft.serverId ยังไม่มี ณ จุดนี้ = สาขา local-only
        await proceed.open()
        await raising.value

        XCTAssertEqual(outcome, .canceled)
        XCTAssertNil(SOSOutbox().current(), "เคสที่ยกเลิกไปแล้วต้องไม่ฟื้นกลับมาแม้ raiseCall จะเพิ่งสำเร็จทีหลัง")
        XCTAssertNil(store.draft, "draft ต้องยังเป็น nil หลัง raiseCall ที่มาสาย")
    }

    /// Task 14: relaunch เจอ draft ค้างจาก outbox — init() กู้ draft/status ให้เห็นทันทีแล้ว (เทสนี้
    /// จำลองด้วยการ save() ก่อนสร้าง store เอง) แต่ไม่เริ่ม retry loop ให้อัตโนมัติ (ดูคอมเมนต์ที่
    /// resumeIfNeeded) ผู้สร้าง store ต้องเรียกตัวนี้เองตอนพร้อมจริง — เทสนี้ยืนยันว่ามันยิงต่อด้วย
    /// token ที่ส่งเข้ามาใหม่ (ไม่ใช่ token ตอน raise() ครั้งแรกซึ่งไม่มีอยู่แล้วหลัง relaunch) และอัปเดต
    /// สถานะจากคำตอบจริงของเซิร์ฟเวอร์ ไม่ใช่ค้างคำว่า "queued" รอ poll รอบแรก
    ///
    /// (รีวิว Task 14 รอบสาม: เจตนาของเทสนี้คือ "คนเดิม re-authenticate" — currentUserId ของ store
    /// กับ ownerId ของ draft ที่ save() ไว้ล่วงหน้าจึงต้องตรงกัน "u1" ทั้งคู่ ต่างจาก
    /// testADifferentOwnerNeverAdoptsTheStoredDraft ด้านล่างที่ตั้งใจให้ไม่ตรงกัน)
    func testResumeIfNeededContinuesAQueuedCaseFoundAtInit() async {
        SOSOutbox().save(SOSDraft(clientId: "resume-1", deviceTime: "2026-08-06T10:00:00Z",
                                  forOther: false, ownerId: "u1"))

        var sentTokens: [String] = []
        let store = SOSStore(currentUserId: "u1", raiseCall: { token, _ in
            sentTokens.append(token)
            return Self.sampleCase(acked: false)
        }, activeCall: { _, _ in Self.sampleCase(acked: false, resolved: true) })

        XCTAssertEqual(store.status, .queued, "init ต้องกู้สถานะ queued มาก่อนแล้วโดยไม่ต้องรอ resume")
        await store.resumeIfNeeded(token: "resumed-token")

        XCTAssertEqual(sentTokens, ["resumed-token"], "resumeIfNeeded ต้องยิงต่อด้วย token ที่ส่งเข้ามา")
        XCTAssertEqual(store.status, .received, "ต้องอัปเดตเป็นสถานะจริงจากเซิร์ฟเวอร์ ไม่ใช่ค้างที่ queued")
    }

    /// รีวิว Task 14 รอบสาม: บัญชีที่สอง login บนเครื่องเดียวกันหลังบัญชีแรกเจอ 401 อัตโนมัติ (ซึ่งไม่
    /// ล้าง outbox แล้วตามการแก้ของรอบสอง — ดู handleLogout) ต้องไม่ได้รับ draft ของบัญชีแรกมาเป็นของ
    /// ตัวเองเด็ดขาด ไม่งั้น resumeIfNeeded ยิงมันต่อด้วย token ของบัญชีที่สอง ซึ่งถ้า draft ยังไม่เคย
    /// ถึงเซิร์ฟเวอร์เลย (serverId เป็น nil — เกิดขึ้นจริงเมื่อ 401 ที่ทำให้ล็อกเอาต์คือคำตอบของการยิง
    /// SOS เอง) เซิร์ฟเวอร์จะ INSERT เคสใหม่ที่ผูกกับบัญชีที่สอง แต่มีพิกัด/ข้อความของบัญชีแรก
    func testADifferentOwnerNeverAdoptsTheStoredDraft() {
        SOSOutbox().save(SOSDraft(clientId: "stranger-1", deviceTime: "2026-08-06T10:00:00Z",
                                  forOther: false, lat: 18.79, lng: 98.95, ownerId: "user-A"))

        let store = SOSStore(currentUserId: "user-B", raiseCall: { _, _ in
            XCTFail("เจ้าของไม่ตรง ต้องไม่ยิง raiseCall จากการรับ draft ของคนอื่นมาเลย")
            return Self.sampleCase(acked: false)
        })

        XCTAssertNil(store.draft, "เจ้าของไม่ตรง ต้องไม่รับ draft มาเป็นของตัวเอง")
        XCTAssertNil(store.status)
        XCTAssertNil(SOSOutbox().current(), "draft ของเจ้าของเก่าต้องถูกล้างทิ้ง ไม่ปล่อยค้างรอใครมาสืบทอด")
    }

    /// รีวิว Task 14 รอบสี่: draft ที่เขียนไว้บนดิสก์โดย build ก่อนหน้า commit ที่เพิ่ม ownerId เข้ามา
    /// ไม่มีคีย์นี้ในไบต์เลย — ownerId ต้อง decode เป็นค่าว่าง (ดู SOSDraft.init(from:)) ซึ่งไม่มีทาง
    /// match currentUserId ของบัญชีจริงคนไหนได้เลย จึงตกไปสาขา "เจ้าของไม่ตรง" ที่มีอยู่แล้วโดย
    /// อัตโนมัติ — เคสยังไม่ถูกรับมา (ถูกต้อง ไม่มีทางรู้ว่าเป็นของใคร) แต่ต้องล้างช่องทิ้งจริง ไม่ปล่อย
    /// ไบต์เก่าค้างจนกว่า save() ครั้งหน้าจะทับ — **ต้องไม่ใช่แค่ decode พังแล้วเงียบเหมือนไม่มีอะไรเกิด
    /// ขึ้น** ซึ่งเป็นบั๊กเดิมที่ทำให้เคสฉุกเฉินจริงที่ค้างอยู่ก่อนอัปเดตแอปหายไปเงียบๆ
    func testALegacyDraftMissingOwnerIdIsNotAdoptedAndTheSlotIsCleared() {
        let legacyJSON = """
        {"clientId":"legacy-1","deviceTime":"2026-08-01T09:00:00Z","forOther":false}
        """.data(using: .utf8)!
        UserDefaults.standard.set(legacyJSON, forKey: SOSOutbox.key(for: Config.backend))

        let store = SOSStore(currentUserId: "user-A", raiseCall: { _, _ in
            XCTFail("draft เก่าที่ไม่มีเจ้าของต้องไม่ถูกยิงต่อเด็ดขาด")
            return Self.sampleCase(acked: false)
        })

        XCTAssertNil(store.draft, "draft เก่าที่ decode ได้แต่ไม่มีเจ้าของต้องไม่ถูกรับมาเป็นของบัญชีนี้")
        XCTAssertNil(store.status)
        // เช็คคีย์ดิบใน UserDefaults ตรงๆ แทน SOSOutbox().current() เฉยๆ — .current() คืน nil ทั้งตอน
        // "ล้างแล้วจริง" และตอน "ไบต์เดิมยัง decode ไม่ผ่านค้างอยู่" เหมือนกันทุกประการ เช็คแค่ผลลัพธ์
        // จาก .current() จึงพิสูจน์ไม่ได้ว่าล้างจริงหรือแค่ยัง decode พังซ้ำทุกครั้งที่เรียก (พบตอนรัน
        // RED จริง: เทสนี้ผ่านแม้กับโค้ดก่อนแก้ ถ้าเช็คแค่ .current() — ต้องเช็คคีย์ดิบถึงจะเห็นบั๊ก)
        XCTAssertNil(UserDefaults.standard.data(forKey: SOSOutbox.key(for: Config.backend)),
                     "ต้องล้างคีย์ทิ้งจริงจาก UserDefaults ไม่ปล่อยไบต์เก่าที่ decode ไม่ผ่านค้างตลอดกาล")
    }

    /// เหมือนเทสด้านบนแต่ไบต์เสียหายจริง (ไม่ใช่ JSON ด้วยซ้ำ ไม่ใช่แค่คีย์หาย) — ทางออกต้องเหมือนกัน
    /// ทุกอย่าง: ไม่รับเคสมา และล้างช่องทิ้งจริง (พบจากรีวิว Task 14 รอบสี่)
    func testCorruptedBytesAreNotAdoptedAndTheSlotIsCleared() {
        UserDefaults.standard.set(Data([0xFF, 0x00, 0xDE, 0xAD, 0xBE, 0xEF]),
                                  forKey: SOSOutbox.key(for: Config.backend))

        let store = SOSStore(currentUserId: "user-A", raiseCall: { _, _ in
            XCTFail("ไบต์ที่เสียหายต้องไม่ถูกตีความเป็นเคสอะไรทั้งนั้น")
            return Self.sampleCase(acked: false)
        })

        XCTAssertNil(store.draft)
        XCTAssertNil(store.status)
        // ดูคอมเมนต์ที่เทสก่อนหน้าว่าทำไมต้องเช็คคีย์ดิบ ไม่ใช่แค่ผลของ .current()
        XCTAssertNil(UserDefaults.standard.data(forKey: SOSOutbox.key(for: Config.backend)),
                     "ต้องล้างคีย์ทิ้งจริงจาก UserDefaults ไม่ปล่อยไบต์เสียค้างตลอดกาล")
    }

    /// เปิดแอปแบบไม่มีเคสค้างเลย (คนส่วนใหญ่ทุกครั้งที่เปิดแอป) — resumeIfNeeded ต้องไม่ยิงเน็ตเปล่าๆ
    func testResumeIfNeededDoesNothingWithoutAQueuedCase() async {
        let store = SOSStore(raiseCall: { _, _ in
            XCTFail("ไม่มีเคสค้างเลย ไม่ควรยิง raiseCall")
            return Self.sampleCase(acked: false)
        })
        await store.resumeIfNeeded(token: "t")
        XCTAssertNil(store.status)
    }

    // MARK: - รีวิว Task 14 รอบสอง

    /// .wbwUnauthorized ใน Session.init ยิง logout() เองทันทีที่เจอ 401 จากไหนก็ได้ในแอป โดยไม่มีการ
    /// ยืนยันจากผู้ใช้เลยสักครั้ง — เคสที่ยังเปิดอยู่ต้องไม่ถูกล้างในเส้นทางนี้ ไม่งั้นคนที่มีเหตุฉุกเฉิน
    /// เปิดอยู่จะถูกเด้งไปหน้า login พร้อมเคสหายไปเงียบๆ กลางเหตุฉุกเฉิน ปล่อย draft ไว้ในเครื่องแทน
    /// ให้ resumeIfNeeded หยิบต่อได้ทันทีที่ล็อกอินกลับมา (ดูคอมเมนต์ที่ SOSStore.handleLogout)
    func testAutomaticLogoutLeavesTheOutboxIntactForReAuthenticationToResume() async {
        let store = SOSStore(raiseCall: { _, _ in throw AppError.offline })
        await store.raise(forOther: false, token: "t")
        XCTAssertNotNil(SOSOutbox().current())

        store.handleLogout(automatic: true)

        XCTAssertNotNil(SOSOutbox().current(),
                         "ล็อกเอาต์อัตโนมัติต้องไม่ล้างเคส — คนกลางเหตุฉุกเฉินไม่ควรเจอเคสหายไปเฉยๆ")
        XCTAssertNotNil(store.draft)
    }

    /// เส้นทางที่ผู้ใช้กด "ออกจากระบบ" เอง (SettingsView ถามยืนยันก่อนเรียก session.logout() เสมอ)
    /// ต้องล้างเหมือนเดิมทุกอย่าง — handleLogout(automatic: false) คือค่าที่เส้นทางนั้นส่งมา
    func testUserInitiatedLogoutStillClearsTheOutbox() async {
        let store = SOSStore(raiseCall: { _, _ in throw AppError.offline })
        await store.raise(forOther: false, token: "t")
        XCTAssertNotNil(SOSOutbox().current())

        store.handleLogout(automatic: false)

        XCTAssertNil(SOSOutbox().current(), "ล็อกเอาต์ที่ผู้ใช้กดเอง (ยืนยันแล้ว) ต้องล้างเหมือนเดิม")
        XCTAssertNil(store.draft)
    }

    /// startStatusPoll เดิมเรียก finish() ตอนเจอเคส resolved แต่ไม่เคยล้าง draft/outbox — เคสที่จบไป
    /// แล้วจริงยังเหลือร่องรอยในเครื่อง ถ้าแอปถูกปิดแล้วเปิดใหม่ init() จะกู้ draft นั้นมาเป็น queued
    /// อีกรอบทั้งที่จบไปแล้ว serverCase/status ต้องยังคง .closed ไว้ให้จอสถานะแสดงผลจบเรื่องได้ปกติ —
    /// เฉพาะ draft/outbox เท่านั้นที่ต้องไม่รอด
    func testAPollThatObservesResolutionClearsTheOutboxButKeepsClosedStatusVisible() async {
        let started = Gate()
        let proceed = Gate()
        let store = SOSStore(raiseCall: { _, _ in Self.sampleCase(acked: false) },
                             activeCall: { _, _ in
                                 await started.open()
                                 await proceed.wait()
                                 return Self.sampleCase(acked: true, resolved: true)
                             })
        await store.raise(forOther: false, token: "t")
        await started.wait()   // ยืนยันว่า poll เรียก activeCall ครั้งแรกแล้วและกำลังค้างอยู่จริง
        await proceed.open()   // ปล่อยให้ activeCall คืนเคสที่ resolved แล้ว

        // pollTask เป็น private เทสตรงๆ ไม่ได้ — รอผลที่สังเกตได้จากภายนอกแทน มีเพดานกันเทสค้างถ้า
        // อะไรพัง (โค้ดจริงไม่มี await คั่นระหว่างตื่นจาก activeCall กับ outbox.clear()/draft=nil เลย)
        var attempts = 0
        while SOSOutbox().current() != nil && attempts < 100 {
            try? await Task.sleep(for: .milliseconds(10))
            attempts += 1
        }

        XCTAssertNil(SOSOutbox().current(), "เคสที่ resolved แล้วต้องไม่เหลือ draft ค้างในเครื่อง")
        XCTAssertNil(store.draft)
        XCTAssertEqual(store.status, .closed(reason: "helped"), "สถานะยังต้องโชว์ผลจบเรื่องได้ตามปกติ")
    }

    /// เซิร์ฟเวอร์ตอบสำเร็จว่า "ไม่มีเคส" รัวๆ (ไม่ใช่ error) ต้องมีเพดานให้ poll หยุดเอง ไม่งั้นวน
    /// ตลอดกาลกินแบต/เน็ตของเคสที่จบไปนานแล้ว (ดู SOSStore.maxConsecutiveEmptyPolls) — pollInterval
    /// สั้นมากเฉพาะเทสนี้ ไม่ต้องรอเป็นนาทีจริงตามค่าเริ่มต้นจริง 1 วิ — ต้องส่งสัญญาณ statusCheckStopped
    /// ให้จอเห็นด้วย ไม่ใช่แค่หยุด task เงียบๆ (แก้จากรีวิว Task 14 รอบสาม)
    func testStatusPollGivesUpAfterRepeatedlyFindingNoCase() async {
        var callCount = 0
        let store = SOSStore(raiseCall: { _, _ in Self.sampleCase(acked: false) },
                             activeCall: { _, _ in callCount += 1; return nil },
                             pollInterval: .milliseconds(1))
        await store.raise(forOther: false, token: "t")

        // รอจนตัวนับ "นิ่ง" (ไม่ขยับต่ออีกแล้วหลายรอบติด) แทนที่จะรอเวลาคงที่ — ทนต่อความช้าของเครื่อง
        // ที่รันเทสได้ดีกว่าเดาเวลาตรงๆ
        var lastSeen = -1
        var stableRounds = 0
        while stableRounds < 5 {
            try? await Task.sleep(for: .milliseconds(20))
            if callCount == lastSeen { stableRounds += 1 } else { stableRounds = 0 }
            lastSeen = callCount
        }

        XCTAssertGreaterThanOrEqual(callCount, 20, "ต้องลองจนถึงเพดาน (20 ครั้งติด) ก่อนจะยอมเลิก")
        let settledCount = callCount
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(callCount, settledCount, "เกินเพดานแล้วต้องไม่ยิงต่อ — poll loop ต้องหยุดจริง")
        XCTAssertTrue(store.statusCheckStopped, "ต้องส่งสัญญาณให้จอสถานะรู้ว่าเลิกเช็คแล้ว ไม่ใช่หยุดเงียบๆ")
    }

    /// เน็ตหลุดจริง (request พังเอง throw ออกมา ไม่ใช่เซิร์ฟเวอร์ตอบสำเร็จว่า "ไม่มีเคส") ต้องไม่นับ
    /// เข้าเพดานเลย ไม่งั้นสัญญาณหลุดธรรมดาไม่กี่สิบวินาที — ซึ่งเป็นสิ่งที่ฟีเจอร์นี้ทั้งอันมีไว้ทนอยู่แล้ว
    /// — จะทำให้เลิก poll ไปเฉยๆ (พบจากรีวิว Task 14 รอบสาม) ยิงเกินเพดานไปมากแล้วแต่ต้องยังไม่หยุด
    /// errorBackoffSchedule สั้นมากเฉพาะเทสนี้เหมือนกับ pollInterval ด้านบน
    func testRepeatedNetworkErrorsDoNotTripTheCeiling() async {
        var callCount = 0
        let store = SOSStore(raiseCall: { _, _ in Self.sampleCase(acked: false) },
                             activeCall: { _, _ in callCount += 1; throw AppError.offline },
                             pollInterval: .milliseconds(1),
                             errorBackoffSchedule: [.milliseconds(1)])
        await store.raise(forOther: false, token: "t")

        // รอให้ยิงเกินเพดาน (20) ไปมากพอที่จะพิสูจน์ได้จริงว่า error ไม่ถูกนับเข้าไป มีเพดานเวลากันเทส
        // ค้างถ้าอะไรพัง
        var attempts = 0
        while callCount < 40 && attempts < 500 {
            try? await Task.sleep(for: .milliseconds(10))
            attempts += 1
        }

        XCTAssertGreaterThanOrEqual(callCount, 40, "error ต้องไม่ทำให้ poll หยุดก่อนถึง 40 ครั้ง (เกินเพดาน 20 ไปเท่าตัว)")
        XCTAssertFalse(store.statusCheckStopped, "error ไม่ใช่คำตอบว่าไม่มีเคส ต้องไม่นับเข้าเพดานจนหยุด")
    }

    /// เมื่อ poll หยุดจริง (ชนเพดาน "ไม่มีเคส" ติดกัน) ต้องมีทางกลับมา poll ต่อได้ — ปุ่ม "เช็คสถานะอีก
    /// ครั้ง" ใน SOSStatusView เรียกตัวนี้ (พบจากรีวิว Task 14 รอบสาม: เดิมไม่มีทางกลับมาเลยหลังหยุด)
    func testRetryStatusCheckRestartsPollingAfterItStopped() async {
        var callCount = 0
        let store = SOSStore(raiseCall: { _, _ in Self.sampleCase(acked: false) },
                             activeCall: { _, _ in callCount += 1; return nil },
                             pollInterval: .milliseconds(1))
        await store.raise(forOther: false, token: "t")

        var attempts = 0
        while !store.statusCheckStopped && attempts < 300 {
            try? await Task.sleep(for: .milliseconds(10))
            attempts += 1
        }
        XCTAssertTrue(store.statusCheckStopped, "ต้องหยุดจริงหลังชนเพดานก่อน ไม่งั้นเทสนี้ไม่ได้ทดสอบอะไร")
        let countWhenStopped = callCount

        store.retryStatusCheck(token: "t")
        XCTAssertFalse(store.statusCheckStopped, "กดลองใหม่ต้องล้างสถานะ 'หยุดแล้ว' ทันที")

        attempts = 0
        while callCount <= countWhenStopped && attempts < 300 {
            try? await Task.sleep(for: .milliseconds(10))
            attempts += 1
        }
        XCTAssertGreaterThan(callCount, countWhenStopped, "ต้องยิง activeCall ต่อจริงหลังกดลองใหม่ ไม่ใช่แค่ล้างธง")
    }

    // MARK: - รีวิวรอบสุดท้าย: สองเส้นขนาน โน้ต และ for_other

    /// **กฎข้อแรกของสเปกทั้งฉบับ: "อย่ารอ GPS — การกดกับการได้พิกัดเป็นสองเส้นขนานกัน"**
    ///
    /// เดิม raise() ทำ `await send(...)` ให้จบก่อนแล้วค่อยเริ่มไล่ตาม GPS กับ retry loop ซึ่งกลับหัวกฎนี้
    /// พอดีในสถานการณ์เดียวที่ฟีเจอร์นี้มีไว้รับมือ: ในจุดอับสัญญาณ request แรกกินเวลาจนเต็มเพดาน และ
    /// ตลอดช่วงนั้นไม่มีการขอพิกัดเลยแม้แต่ครั้งเดียว
    ///
    /// เทสนี้แดงกับโค้ดเดิมโดยการ "ค้างจนหมดเวลา" ไม่ใช่ assert ผิด: ประตูกัน raiseCall ไว้ ถ้าการไล่ตาม
    /// GPS ยังอยู่หลัง await เส้นนั้น provider จะไม่ถูกแตะเลยจนกว่าประตูจะเปิด — ซึ่งไม่มีวันเกิด
    func testTheGPSChaseStartsWithoutWaitingForTheFirstSendToAnswer() async {
        let gate = Gate()
        let provider = ChaseProbeProvider()
        let asked = expectation(description: "ต้องเริ่มขอพิกัดก่อนที่การส่งครั้งแรกจะได้คำตอบ")
        provider.onRequest = { asked.fulfill() }

        let store = SOSStore(locator: SOSLocator(provider: provider),
                             raiseCall: { _, _ in
                                 await gate.wait()
                                 throw AppError.offline
                             },
                             activeCall: { _, _ in nil },
                             pollInterval: .seconds(60))

        let raising = Task { await store.raise(forOther: false, token: "t") }
        await fulfillment(of: [asked], timeout: 3)
        await gate.open()
        await raising.value

        XCTAssertNotNil(SOSOutbox().current(), "เคสยังต้องอยู่ในเครื่องตามเดิม")
    }

    /// สเปกข้อ 5 — for_other ต้องมีทางเข้าจริงในแอป ไม่ใช่แค่มีคอลัมน์รออยู่ฝั่งเซิร์ฟเวอร์
    ///
    /// SOSButton hard-code `forOther: false` ไว้เป็นผู้เรียก raise() เดียวของทั้งแอป ทางเข้าเดียวจึงเป็น
    /// ตัวนี้ · ต้องเป็น "เคสเดิม client_id เดิม" ไม่ใช่เคสที่สอง และกดซ้ำต้องไม่ยิงอะไรอีก
    func testMarkingSomeoneElseIsHurtBumpsTheSameCaseAndCannotBeUndone() async {
        var sent: [(clientId: String, forOther: Bool)] = []
        let store = SOSStore(raiseCall: { _, d in
                                 sent.append((d.clientId, d.forOther))
                                 return Self.sampleCase(acked: false, forOther: d.forOther)
                             },
                             activeCall: { _, _ in nil },
                             pollInterval: .seconds(60))

        await store.raise(forOther: false, token: "t")
        let marked = await store.markForOther(token: "t")

        XCTAssertTrue(marked, "เซิร์ฟเวอร์สะท้อน for_other กลับมาแล้วต้องรายงานว่าสำเร็จ")
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0].clientId, sent[1].clientId, "ต้องเป็นเคสเดิม ไม่ใช่เคสที่สอง")
        XCTAssertFalse(sent[0].forOther)
        XCTAssertTrue(sent[1].forOther)
        XCTAssertEqual(SOSOutbox().current()?.forOther, true, "ต้องติดไปกับ draft ที่ retry ใช้ด้วย")

        let markedAgain = await store.markForOther(token: "t")
        XCTAssertFalse(markedAgain, "กดซ้ำต้องไม่ยิงอะไรอีก")
        XCTAssertEqual(sent.count, 2)
    }

    /// โน้ตต้องส่งได้จริง และต้องบอกความจริงว่าถึงหรือยัง
    ///
    /// เดิมช่องพิมพ์มีแต่ `.onSubmit` ซึ่งไม่มีวันยิงกับ TextField(axis: .vertical) — ไม่มีทางส่งเลย
    /// สักทาง เทสนี้ค้ำเส้นทางที่ปุ่มส่งใช้ รวมถึงกรณีที่ต้องไม่ยิง (ข้อความว่าง) และกรณีที่ยิงแล้วไม่ถึง
    func testTheNoteIsSentAndOnlyReportsSuccessWhenTheServerEchoesItBack() async {
        var sentMessages: [String?] = []
        var shouldFail = false
        let store = SOSStore(raiseCall: { _, d in
                                 sentMessages.append(d.message)
                                 if shouldFail { throw AppError.offline }
                                 return Self.sampleCase(acked: false, message: d.message)
                             },
                             activeCall: { _, _ in nil },
                             pollInterval: .seconds(60))

        await store.raise(forOther: false, token: "t")
        let ok = await store.attachNote("  ขาหัก เดินต่อไม่ไหว  ", token: "t")
        XCTAssertTrue(ok)
        XCTAssertEqual(sentMessages.last ?? nil, "ขาหัก เดินต่อไม่ไหว", "ต้องตัดช่องว่างหัวท้ายก่อนส่ง")
        XCTAssertEqual(SOSOutbox().current()?.message, "ขาหัก เดินต่อไม่ไหว")

        let countBefore = sentMessages.count
        let blank = await store.attachNote("   ", token: "t")
        XCTAssertFalse(blank, "ข้อความว่างไม่ใช่ข้อความ")
        XCTAssertEqual(sentMessages.count, countBefore, "ข้อความว่างต้องไม่ยิงอะไรออกไปเลย")

        shouldFail = true
        let undelivered = await store.attachNote("เลือดออกเยอะ", token: "t")
        XCTAssertFalse(undelivered, "ส่งไม่ถึงต้องบอกว่าไม่ถึง ไม่ใช่ขึ้นว่าส่งแล้ว")
        XCTAssertEqual(SOSOutbox().current()?.message, "เลือดออกเยอะ", "ส่งไม่ถึงก็ต้องเก็บข้อความไว้")
    }

    /// resolved มีดีฟอลต์เป็น false เพื่อให้ call site เดิมจากบรีฟ (sampleCase(acked:)) ไม่ต้องแก้ —
    /// เพิ่มพารามิเตอร์นี้เข้ามาเพื่อฉีดเป็นค่าตอบของ activeCall stub ด้านบนเท่านั้น (ดูคอมเมนต์ที่เทส)
    /// forOther/message เพิ่มทีหลังด้วยเหตุผลเดียวกัน — ให้ stub สะท้อนค่าที่รับมาได้เหมือนเซิร์ฟเวอร์จริง
    private static func sampleCase(acked: Bool, resolved: Bool = false,
                                   forOther: Bool = false, message: String? = nil) -> SOSCase {
        SOSCase(id: 7, forOther: forOther, lat: nil, lng: nil, accuracyM: nil, locSource: "none",
                checkpointId: nil, checkpointName: nil, message: message, resolved: resolved,
                resolveReason: resolved ? "helped" : nil, ackedAt: acked ? "2026-08-06T10:01:00Z" : nil,
                ackedByName: acked ? "พี่หมอ" : nil,
                createdAt: "2026-08-06T10:00:00Z", emergencyPhone: "053-916-000")
    }
}

/// provider ที่ "ไม่เคยส่งพิกัดกลับมาเลย" แต่บอกได้ว่าถูกขอเมื่อไหร่ — จำลองจุดอับสัญญาณจริง
/// ซึ่งเป็นเงื่อนไขเดียวที่ทำให้ลำดับใน raise() มีผลต่างกันจริง (ถ้า fix มาทันที ลำดับไหนก็เหมือนกัน)
private final class ChaseProbeProvider: SOSLocationProviding {
    var onRequest: (() -> Void)?
    var authorizationStatus: CLAuthorizationStatus { .authorizedWhenInUse }
    var lastKnownLocation: CLLocation? { nil }
    func requestWhenInUseAuthorization() {}
    func requestLocation(_ completion: @escaping (CLLocation?) -> Void) { onRequest?() }
}
