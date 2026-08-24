import XCTest
@testable import WBW

/// ของปลอมในหน่วยความจำ — เทสส่วนใหญ่ไม่ควรแตะ Keychain จริง (บริบทเทสบางแบบตอบ
/// `errSecMissingEntitlement` แล้วเทสจะแดงด้วยเหตุผลที่ไม่เกี่ยวกับสิ่งที่กำลังตรวจ)
final class FakeTokenStorage: TokenStorage {
    var stored: String?
    private(set) var writes = 0
    private(set) var clears = 0
    init(stored: String? = nil) { self.stored = stored }
    func read() -> String? { stored }
    func write(_ token: String) { stored = token; writes += 1 }
    func clear() { stored = nil; clears += 1 }
}

/// JWT ต้องอยู่ใน Keychain ไม่ใช่ `UserDefaults`
///
/// `UserDefaults` เขียนลง plist ใน container ของแอป ซึ่งติดไปกับ backup แบบไม่เข้ารหัส
/// และอ่านได้ตรง ๆ บนเครื่องที่ jailbreak · token ของงานนี้เปิดทางเข้าโปรไฟล์ ประวัติเช็คอิน
/// แชทกลุ่ม และการยิง SOS ในนามคนอื่น
///
/// ย้ายเฉพาะ **token** · `wbw.user` (`AuthUser`: userId/username/role) ยังอยู่ที่เดิม —
/// มันไม่ใช่ความลับ (แสดงบนจออยู่แล้ว) และการย้ายด้วยไม่ได้ลดความเสี่ยงอะไรเพิ่ม
final class TokenStoreTests: XCTestCase {
    private var fake = FakeTokenStorage()
    private let d = UserDefaults.standard

    private func wipeDefaults() {
        d.removeObject(forKey: TokenStore.legacyKey)
        d.removeObject(forKey: TokenStore.installMarkerKey)
    }

    override func setUp() {
        super.setUp()
        fake = FakeTokenStorage()
        wipeDefaults()
        TokenStore.resetForTesting(backend: fake)
    }

    override func tearDown() {
        wipeDefaults()
        TokenStore.resetForTesting(backend: KeychainTokenStorage())
        super.tearDown()
    }

    func testWriteReadClearRoundTrip() {
        XCTAssertNil(TokenStore.read())
        TokenStore.write("jwt-1")
        XCTAssertEqual(TokenStore.read(), "jwt-1")
        TokenStore.clear()
        XCTAssertNil(TokenStore.read())
    }

    // MARK: - ย้ายของคนที่ล็อกอินค้างอยู่

    /// อัปเดตแอป: หมุดยังไม่มี แต่มี token เดิมใน UserDefaults — ต้องย้ายเข้า Keychain
    /// **ห้ามให้ทุกคนหลุดล็อกอินตอนอัปเดต** งานนี้ปิดรับสมัครแล้ว คนที่หลุดออกมาล็อกอินกลับเข้าไปได้
    /// ก็จริง แต่ต้องจำรหัสผ่านที่ตั้งไว้ตั้งแต่ตอนสมัคร ซึ่งเป็นด่านที่ไม่ควรมีใครต้องเจอกลางงาน
    func testUpgradeMovesLegacyTokenIntoKeychainAndRemovesTheOldCopy() {
        d.set("jwt-เดิม", forKey: TokenStore.legacyKey)

        XCTAssertEqual(TokenStore.read(), "jwt-เดิม")
        XCTAssertNil(d.string(forKey: TokenStore.legacyKey),
                     "สำเนาเดิมใน UserDefaults ต้องถูกลบ ไม่งั้นย้ายแล้วก็ยังรั่วอยู่ที่เดิม")
        XCTAssertEqual(fake.stored, "jwt-เดิม")
    }

    /// ย้ายรอบเดียวพอ — เรียกซ้ำต้องไม่เขียนทับของใหม่ด้วยของเก่า
    func testMigrationRunsOnlyOnce() {
        d.set("jwt-เดิม", forKey: TokenStore.legacyKey)
        _ = TokenStore.read()
        TokenStore.write("jwt-ใหม่")
        d.set("jwt-ผี", forKey: TokenStore.legacyKey)   // ของค้างที่ไม่ควรถูกหยิบอีก

        XCTAssertEqual(TokenStore.read(), "jwt-ใหม่")
    }

    // MARK: - ลบแอปแล้วลงใหม่

    /// **Keychain รอดการลบแอป ส่วน UserDefaults ไม่รอด** — ลบแอปเพื่อ "ออกจากระบบ" แล้วลงใหม่
    /// ต้องไม่เด้งเข้าแอปด้วย token ของคนก่อน · บนเครื่องที่นักศึกษายืมกันใช้ นี่คือการหลุดบัญชีจริง
    ///
    /// หมุดอยู่ใน UserDefaults โดยตั้งใจ: มันหายไปพร้อมแอป ซึ่งคือสัญญาณ "ติดตั้งใหม่" ที่ต้องการ
    func testFreshInstallWipesTheLeftoverKeychainItem() {
        fake.stored = "jwt-ของเจ้าของเครื่องคนก่อน"

        XCTAssertNil(TokenStore.read())
        XCTAssertEqual(fake.clears, 1)
        XCTAssertTrue(d.bool(forKey: TokenStore.installMarkerKey))
    }

    /// เปิดแอปรอบต่อ ๆ ไปต้องไม่ล้าง — ไม่งั้นทุกคนหลุดล็อกอินทุกครั้งที่เปิดแอป
    func testSubsequentLaunchesKeepTheToken() {
        d.set(true, forKey: TokenStore.installMarkerKey)
        fake.stored = "jwt-1"

        XCTAssertEqual(TokenStore.read(), "jwt-1")
        XCTAssertEqual(fake.clears, 0)
    }

    /// กับดักลำดับ: เขียนก่อนอ่านครั้งแรก · ถ้า `write` ไม่ปักหมุดให้ก่อน การอ่านครั้งถัดไปจะ
    /// เข้าใจว่าเป็นการติดตั้งใหม่แล้วล้าง token ที่เพิ่งเขียนทิ้ง = ล็อกอินสำเร็จแล้วหลุดทันที
    func testWritingBeforeTheFirstReadIsNotWipedAfterwards() {
        TokenStore.write("jwt-เพิ่งล็อกอิน")
        XCTAssertEqual(TokenStore.read(), "jwt-เพิ่งล็อกอิน")
        XCTAssertEqual(fake.stored, "jwt-เพิ่งล็อกอิน")
        XCTAssertTrue(d.bool(forKey: TokenStore.installMarkerKey),
                      "การเขียนต้องปักหมุดให้ด้วย ไม่งั้นการอ่านครั้งถัดไปจะล้างของที่เพิ่งเขียน")
    }
}

/// Keychain ของจริง — แยกออกมาเพราะพึ่งบริการของระบบ ไม่ใช่ตรรกะของเรา
final class KeychainTokenStorageTests: XCTestCase {
    /// account แยกจากของจริง ไม่งั้นเทสจะเตะ session ที่ค้างอยู่บนซิมของคนรัน
    private let store = KeychainTokenStorage(account: "jwt-test")

    override func tearDown() { store.clear(); super.tearDown() }

    func testRoundTripThroughTheRealKeychain() throws {
        store.clear()
        store.write("jwt-จริง")
        let read = store.read()
        try XCTSkipIf(read == nil, "Keychain ใช้ไม่ได้ในบริบทเทสนี้ — ข้ามไป ตรรกะอยู่ที่ TokenStoreTests แล้ว")
        XCTAssertEqual(read, "jwt-จริง")

        store.write("jwt-จริง-2")
        XCTAssertEqual(store.read(), "jwt-จริง-2", "เขียนทับของเดิมได้ ไม่ใช่เพิ่มแถวใหม่แล้วอ่านได้ของเก่า")

        store.clear()
        XCTAssertNil(store.read())
    }
}

/// ห้ามมีใครกลับไปอ่าน/เขียน JWT จาก `UserDefaults` อีก
///
/// ตอนสำรวจพบว่า `AppDelegate` อ่าน `"wbw.token"` เป็นสตริงดิบสองที่ ไม่ได้ผ่านค่าคงที่ด้วยซ้ำ
/// — คีย์ที่กระจายอยู่หลายที่คือเหตุที่การย้ายที่เก็บพลาดได้เงียบ ๆ (ย้ายแล้วเหลือคนอ่านที่เดิม
/// อยู่หนึ่งจุด = push ไม่ทำงานทั้งงานโดยไม่มีอะไรฟ้อง ซึ่งเคยเสียเวลาไล่หามาแล้วรอบหนึ่ง)
final class TokenStorageLocationTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func testNoSourceReadsTheJWTFromUserDefaults() throws {
        let root = Self.repoRoot.appendingPathComponent("WBW")
        for path in try FileManager.default.subpathsOfDirectory(atPath: root.path)
        where path.hasSuffix(".swift") && path != "TokenStore.swift" {
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            let code = text.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            XCTAssertFalse(code.contains("\"wbw.token\""),
                           "\(path) ยังอ้างคีย์ JWT ใน UserDefaults ตรง ๆ — ต้องผ่าน TokenStore")
        }
    }
}
