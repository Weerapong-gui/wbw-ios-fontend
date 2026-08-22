import XCTest
@testable import WBW

/// โหมดเดโม่คือคำตอบของ Guideline 2.1 รอบนี้ — บัญชี `6939999999` ที่ส่งให้ Apple ล็อกอินไม่ผ่าน
/// (prod ตอบ 401 ยืนยันด้วยการยิงจริง) และงานปิดรับสมัครที่ 2000/2000 ที่นั่งไปแล้ว สมัครใหม่ไม่ได้
///
/// เทสชุดนี้จับสองอย่างที่พังแล้วไม่มีอะไรฟ้อง: fixture ที่ไม่ตรงกับ model (จะได้จอว่างบนเครื่อง
/// reviewer แทนที่จะแดงตอนเทส) และ cache ของโหมดเดโม่ที่ไม่ได้แยกจากของจริง (ข้อมูลจำลอง
/// ค้างข้ามไปให้บัญชีจริงบนเครื่องเดียวกัน — อาการเดียวกับกับดัก "สลับ backend แล้วไม่ล้าง")
final class DemoModeTests: XCTestCase {

    override func tearDown() {
        DemoMode.forcedActive = nil
        super.tearDown()
    }

    // MARK: - fixture ต้อง decode ผ่านด้วยตัวถอดรหัสตัวเดียวกับของจริง

    func testProfileFixtureDecodes() {
        XCTAssertEqual(DemoData.me.role, "participant",
                       "role เดโม่ต้องเป็น participant ไม่งั้น RootView จะพาไปจอเจ้าหน้าที่ที่เปิดกล้องสแกนจริง")
        XCTAssertFalse(DemoData.me.fullName.isEmpty)
        XCTAssertNotNil(DemoData.me.qrToken, "บัตรผู้เข้าร่วมกับแท็บ QR วาดจาก qr_token — ไม่มีแล้วสองจอนั้นว่าง")
        XCTAssertNotNil(DemoData.me.bibNumber)
        XCTAssertNotNil(DemoData.me.bloodType, "จอ Medical ID ต้องมีของให้ดู ไม่ใช่ 'Non' ทุกช่อง")
    }

    func testProgressFixtureSitsMidBloom() {
        XCTAssertEqual(DemoData.progress.total, 12)
        XCTAssertEqual(DemoData.progress.stage, 5)
        let stage = BloomStages.stage(checkedIn: DemoData.progress.stage, total: DemoData.progress.total)
        XCTAssertTrue((1...4).contains(stage),
                      "ตั้งใจให้ดอกไม้อยู่กลางทาง — เมล็ดดูไม่ออกว่ามีฟีเจอร์ บานเต็มก็ไม่เหลืออะไรให้เห็นว่าโตได้อีก")
    }

    func testProgressHasAnUnansweredBaseSoTheFeedbackFormCanOpen() {
        XCTAssertFalse(DemoData.progress.pending.isEmpty,
                       "ต้องเหลือฐานที่ยังไม่ให้คะแนน ไม่งั้น reviewer เปิดฟอร์ม feedback ไม่ได้เลย")
    }

    func testNotificationFixtureCoversEveryLevel() {
        let levels = Set(DemoData.notifications.map(\.level))
        XCTAssertTrue(levels.isSuperset(of: ["info", "warning", "emergency"]),
                      "จอแจ้งเตือนแยกสีตามระดับ — มีระดับเดียวจะดูเหมือนไม่มีฟีเจอร์นั้น")
        XCTAssertTrue(DemoData.notifications.contains { $0.feedbackCheckpointId != nil },
                      "ต้องมีการ์ดชนิด checkin_feedback ที่กดแล้วเปิดฟอร์มได้จริง")
        XCTAssertTrue(DemoData.notifications.contains(where: \.isUnread),
                      "ต้องมีอย่างน้อยหนึ่งใบที่ยังไม่อ่าน ไม่งั้นตัวเลขบนกระดิ่งหน้า Home เป็นศูนย์")
    }

    func testGroupFixtureShowsBothFullAndOpenGroups() {
        XCTAssertTrue(DemoData.groups.contains(where: \.isFull),
                      "จอเข้ากลุ่มมีสถานะ 'เต็ม' แยกต่างหาก ต้องมีตัวอย่างให้เห็น")
        XCTAssertTrue(DemoData.groups.contains { !$0.isFull })
        XCTAssertFalse(DemoData.groupMembers.members.isEmpty)
    }

    func testChatFixtureHasBothSidesOfTheConversation() {
        let senders = Set(DemoData.chatMessages.map(\.senderId))
        XCTAssertGreaterThan(senders.count, 1,
                             "แชทที่มีคนพูดคนเดียวไม่ได้แสดงว่าเป็นแชทกลุ่ม")
        XCTAssertTrue(senders.contains(DemoMode.user.userId),
                      "ต้องมีข้อความของตัวเองด้วย ไม่งั้นไม่เห็นฟองข้อความฝั่งขวาเลย")
    }

    func testEchoedMessageSortsAfterTheFixtures() {
        let highest = DemoData.chatMessages.compactMap { Int64($0.id) }.max() ?? 0
        let echoed = DemoData.echo(clientId: "test-1", body: "สวัสดี",
                                   deviceTime: "2026-08-29T10:00:00Z", groupId: 7)
        XCTAssertGreaterThan(Int64(echoed.id) ?? 0, highest,
                             "ข้อความที่เพิ่งพิมพ์ต้องมี id สูงกว่าของเดิม ไม่งั้นมันจะไปโผล่กลางบทสนทนา")
        XCTAssertEqual(echoed.senderId, DemoMode.user.userId)
    }

    func testEchoSurvivesQuotesAndNewlines() {
        let tricky = "เขาบอกว่า \"ไปต่อ\"\nแล้วก็เดินไป"
        let echoed = DemoData.echo(clientId: "test-2", body: tricky,
                                   deviceTime: "2026-08-29T10:01:00Z", groupId: 7)
        XCTAssertEqual(echoed.body, tricky,
                       "ข้อความผู้ใช้ต้องผ่าน JSON encoder จริง — แปะลงสตริงตรง ๆ แล้วพิมพ์ \" จะทำให้แอปดับคาการรีวิว")
    }

    // MARK: - แยก cache ออกจากของจริง

    func testDemoCacheKeysDifferFromRealOnes() {
        DemoMode.forcedActive = false
        let real = [CheckinProgressStore.cacheKey(for: .susProd),
                    FeedbackOutbox.key(for: .susProd),
                    ConditionsStore.cacheKey(for: .susProd)]
        DemoMode.forcedActive = true
        let demo = [CheckinProgressStore.cacheKey(for: .susProd),
                    FeedbackOutbox.key(for: .susProd),
                    ConditionsStore.cacheKey(for: .susProd)]

        XCTAssertTrue(Set(real).isDisjoint(with: Set(demo)),
                      "cache ของโหมดเดโม่ต้องไม่ชนกับของบัญชีจริงเลยสักคีย์")
        for key in demo {
            XCTAssertTrue(key.hasSuffix(CacheScope.demoSuffix),
                          "\(key) ไม่ได้ลงท้ายด้วย \(CacheScope.demoSuffix) — Session.clearDemoCaches() จะล้างไม่เจอ")
        }
    }

    func testCacheKeysStillDifferPerBackendInsideDemoMode() {
        DemoMode.forcedActive = true
        let keys = [Backend.prodNode, .nodeLocal, .susLocal, .susProd, .susLan]
            .map(CheckinProgressStore.cacheKey(for:))
        XCTAssertEqual(Set(keys).count, 5,
                       "suffix ของโหมดเดโม่ต้องซ้อนบน cacheNamespace ไม่ใช่แทนที่มัน")
    }

    func testDemoTokenIsNotAJWT() {
        XCTAssertFalse(DemoMode.token.contains("."),
                       "token เดโม่ต้องไม่มีทางถูกเข้าใจผิดว่าเป็น JWT จริงของใคร")
    }

    /// **ชื่อฐานในสอง fixture ต้องตรงกัน** — การ์ดบนแผนที่อ่านชื่อจาก `checkpoints`
    /// ส่วน toast ตอนเช็คอินอ่านจาก `progress` ถ้าสองชุดใช้ชื่อคนละแบบ reviewer ของ App Review
    /// จะเห็นฐานเดียวกันชื่อไม่ตรงกันในจอเดียว ซึ่งอ่านเป็นแอปที่ยังทำไม่เสร็จ
    func testDemoCheckpointNamesMatchTheDemoProgress() {
        for visited in DemoData.progress.checkedIn {
            guard let match = DemoData.checkpoints.first(where: { $0.id == visited.checkpointId })
            else {
                XCTFail("ฐาน \(visited.checkpointId) อยู่ใน progress แต่ไม่มีในรายการฐาน")
                continue
            }
            XCTAssertEqual(match.name, visited.name,
                           "ฐาน \(visited.checkpointId) ชื่อไม่ตรงกันระหว่าง fixture สองชุด")
        }
    }

    /// จำนวนแถวต้องตรงกับ `total` ที่ progress บอก ไม่งั้นแถบความคืบหน้ากับแผนที่เล่าคนละเรื่อง
    func testDemoCheckpointCountMatchesTheProgressTotal() {
        XCTAssertEqual(DemoData.checkpoints.count, DemoData.progress.total)
    }
}
