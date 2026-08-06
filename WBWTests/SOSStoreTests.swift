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
    func testResumeIfNeededContinuesAQueuedCaseFoundAtInit() async {
        SOSOutbox().save(SOSDraft(clientId: "resume-1", deviceTime: "2026-08-06T10:00:00Z", forOther: false))

        var sentTokens: [String] = []
        let store = SOSStore(raiseCall: { token, _ in
            sentTokens.append(token)
            return Self.sampleCase(acked: false)
        }, activeCall: { _, _ in Self.sampleCase(acked: false, resolved: true) })

        XCTAssertEqual(store.status, .queued, "init ต้องกู้สถานะ queued มาก่อนแล้วโดยไม่ต้องรอ resume")
        await store.resumeIfNeeded(token: "resumed-token")

        XCTAssertEqual(sentTokens, ["resumed-token"], "resumeIfNeeded ต้องยิงต่อด้วย token ที่ส่งเข้ามา")
        XCTAssertEqual(store.status, .received, "ต้องอัปเดตเป็นสถานะจริงจากเซิร์ฟเวอร์ ไม่ใช่ค้างที่ queued")
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

    /// เซิร์ฟเวอร์ไม่รู้จักเคสนี้เลย (activeCall ตอบ nil รัวๆ) ต้องมีเพดานให้ poll หยุดเอง ไม่งั้นวน
    /// ตลอดกาลกินแบต/เน็ตของเคสที่จบไปนานแล้ว (ดู SOSStore.maxConsecutiveEmptyPolls) — pollInterval
    /// สั้นมากเฉพาะเทสนี้ ไม่ต้องรอเป็นนาทีจริงตามค่าเริ่มต้นจริง 1 วิ
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
    }

    /// resolved มีดีฟอลต์เป็น false เพื่อให้ call site เดิมจากบรีฟ (sampleCase(acked:)) ไม่ต้องแก้ —
    /// เพิ่มพารามิเตอร์นี้เข้ามาเพื่อฉีดเป็นค่าตอบของ activeCall stub ด้านบนเท่านั้น (ดูคอมเมนต์ที่เทส)
    private static func sampleCase(acked: Bool, resolved: Bool = false) -> SOSCase {
        SOSCase(id: 7, forOther: false, lat: nil, lng: nil, accuracyM: nil, locSource: "none",
                checkpointId: nil, checkpointName: nil, message: nil, resolved: resolved,
                resolveReason: resolved ? "helped" : nil, ackedAt: acked ? "2026-08-06T10:01:00Z" : nil,
                ackedByName: acked ? "พี่หมอ" : nil,
                createdAt: "2026-08-06T10:00:00Z", emergencyPhone: "053-916-000")
    }
}
