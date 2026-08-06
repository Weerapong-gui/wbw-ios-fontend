import XCTest
@testable import WBW

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
