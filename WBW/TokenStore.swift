import Foundation
import Security

/// ที่เก็บ JWT — แยกเป็น protocol เพื่อให้เทสสลับเป็นของในหน่วยความจำได้
///
/// บริบทเทสบางแบบตอบ `errSecMissingEntitlement` จาก Keychain ซึ่งจะทำให้เทสแดงด้วยเหตุผล
/// ที่ไม่เกี่ยวกับสิ่งที่กำลังตรวจ · ตรรกะการย้าย/ล้างอยู่ที่ `TokenStore` ทดสอบผ่านของปลอมได้ครบ
/// ส่วน `KeychainTokenStorage` มีเทสของตัวเองที่ข้ามได้ถ้า Keychain ใช้ไม่ได้
protocol TokenStorage {
    func read() -> String?
    func write(_ token: String)
    func clear()
}

/// Keychain จริง — generic password หนึ่งแถวต่อหนึ่ง account
struct KeychainTokenStorage: TokenStorage {
    let service: String
    let account: String

    /// `account` แยกได้เพื่อให้เทสไม่ไปเตะ session ที่ค้างอยู่บนซิมของคนรัน
    init(service: String = "th.ac.mfu.wbwSwift", account: String = "jwt") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }

    /// update ก่อน add — `SecItemAdd` บนแถวที่มีอยู่แล้วตอบ `errSecDuplicateItem` แล้วไม่เขียนอะไร
    /// เลย ผลคือล็อกอินบัญชีใหม่บนเครื่องที่เคยล็อกอินแล้วจะยังอ่านได้ token ของบัญชีเก่า
    ///
    /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:
    /// - `AfterFirstUnlock` ไม่ใช่ `WhenUnlocked` — งานนี้มี push กับงานเบื้องหลังที่ต้องอ่าน token
    ///   ตอนจอยังล็อกอยู่ (เครื่องอยู่ในกระเป๋าระหว่างเดิน)
    /// - `ThisDeviceOnly` = ไม่ sync ขึ้น iCloud Keychain และไม่ตามไปกับ backup ที่กู้ลงเครื่องอื่น
    func write(_ token: String) {
        let data = Data(token.utf8)
        let updated = SecItemUpdate(baseQuery as CFDictionary,
                                    [kSecValueData as String: data] as CFDictionary)
        guard updated != errSecSuccess else { return }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    func clear() { SecItemDelete(baseQuery as CFDictionary) }
}

/// **แหล่งเดียวของ JWT ทั้งแอป** — ห้ามใครอ่าน/เขียน token จาก `UserDefaults` อีก
///
/// เดิม token อยู่ใน `UserDefaults` คีย์ `wbw.token` ซึ่งเขียนลง plist ใน container ของแอป:
/// ติดไปกับ backup แบบไม่เข้ารหัส และอ่านได้ตรง ๆ บนเครื่องที่ jailbreak · token ของงานนี้
/// เปิดทางเข้าโปรไฟล์ ประวัติเช็คอิน แชทกลุ่ม และการยิง SOS ในนามคนอื่น
///
/// ย้ายเฉพาะ token · `wbw.user` (`AuthUser`: userId/username/role) ยังอยู่ที่เดิม — ไม่ใช่ความลับ
/// (แสดงบนจออยู่แล้ว) และย้ายด้วยก็ไม่ได้ลดความเสี่ยงอะไรเพิ่ม แลกกับความซับซ้อนที่มากขึ้น
///
/// แคชค่าไว้ในหน่วยความจำเพราะ `DemoMode.active` ถามทุกครั้งที่มีการยิงเน็ต (18 จุด) และ
/// `CacheScope.suffix` ก็ถามต่ออีกที — อ่าน Keychain ทุกครั้งไม่คุ้ม · `NSLock` เพราะการอ่าน
/// เกิดจาก Task พื้นหลังได้ ส่วนการเขียนเกิดบน main actor (`Session`) เสมอ
enum TokenStore {
    /// คีย์เดิมใน `UserDefaults` — เหลือไว้เพื่อ **ย้ายของออก** อย่างเดียว ห้ามเขียนกลับ
    static let legacyKey = "wbw.token"
    /// หมุด "แอปตัวนี้เคยเปิดบนเครื่องนี้แล้ว" — อยู่ใน `UserDefaults` โดยตั้งใจ (ดู `prepare`)
    static let installMarkerKey = "wbw.keychain.installed"

    /// เทสสลับเป็นของปลอมผ่าน `resetForTesting` — โค้ดแอปไม่ตั้งค่านี้เอง
    /// (ทรงเดียวกับ `DemoMode.forcedActive`)
    nonisolated(unsafe) private static var backend: TokenStorage = KeychainTokenStorage()
    nonisolated(unsafe) private static var cache: String?
    nonisolated(unsafe) private static var cacheLoaded = false
    nonisolated(unsafe) private static var prepared = false
    private static let lock = NSLock()

    static func read() -> String? {
        lock.lock(); defer { lock.unlock() }
        prepareLocked()
        if !cacheLoaded {
            cache = backend.read()
            cacheLoaded = true
        }
        return cache
    }

    static func write(_ token: String) {
        lock.lock(); defer { lock.unlock() }
        prepareLocked()
        backend.write(token)
        cache = token
        cacheLoaded = true
    }

    static func clear() {
        lock.lock(); defer { lock.unlock() }
        prepareLocked()
        backend.clear()
        cache = nil
        cacheLoaded = true
    }

    /// ทำครั้งเดียวต่อการรันแอป · **ต้องยิงก่อนทุกทางเข้า** ไม่ใช่แค่ตอนอ่าน
    ///
    /// ถ้ายิงเฉพาะตอนอ่าน แล้วมีใครเขียนก่อนอ่านครั้งแรก (ล็อกอินสำเร็จตั้งแต่จอแรก) การอ่าน
    /// ครั้งถัดไปจะเข้าใจว่าเป็นการติดตั้งใหม่แล้วล้าง token ที่เพิ่งเขียนทิ้ง = ล็อกอินแล้วหลุดทันที
    ///
    /// สองงาน ตามลำดับนี้เท่านั้น:
    ///
    /// 1. **ติดตั้งใหม่ = ล้างของค้าง** — Keychain รอดการลบแอป ส่วน `UserDefaults` ไม่รอด
    ///    หมุดหายไปพร้อมแอปจึงเป็นสัญญาณ "ติดตั้งใหม่" ที่เชื่อได้ · ไม่ล้างแล้วคนที่ลบแอปเพื่อ
    ///    ออกจากระบบจะกลับมาเจอบัญชีเดิมค้างอยู่ ซึ่งบนเครื่องที่นักศึกษายืมกันใช้คือบัญชีหลุด
    /// 2. **ย้ายของคนที่ล็อกอินค้างอยู่ก่อนอัปเดต** — ไม่ย้ายแล้วทุกคนหลุดล็อกอินตอนอัปเดต
    ///    งานปิดรับสมัครไปแล้ว คนที่หลุดต้องจำรหัสผ่านตั้งแต่ตอนสมัครให้ได้ ซึ่งเป็นด่านที่ไม่ควร
    ///    มีใครต้องเจอกลางงาน
    ///
    /// ลำดับนี้ถูกทั้งสองกรณี: ตอนอัปเดตหมุดยังไม่มีเหมือนกัน แต่ข้อ 1 ล้าง Keychain ที่ว่างอยู่แล้ว
    /// (ยังไม่เคยมีใครเขียน) แล้วข้อ 2 ค่อยเติมของเดิมเข้าไป
    private static func prepareLocked(defaults: UserDefaults = .standard) {
        guard !prepared else { return }
        prepared = true

        if !defaults.bool(forKey: installMarkerKey) {
            backend.clear()
            defaults.set(true, forKey: installMarkerKey)
        }
        if let legacy = defaults.string(forKey: legacyKey), !legacy.isEmpty {
            backend.write(legacy)
            defaults.removeObject(forKey: legacyKey)
        }
    }

    #if DEBUG
    /// สำหรับเทสหน่วยเท่านั้น — สลับที่เก็บแล้วรีเซ็ตสถานะ "ทำ prepare ไปแล้ว" กับแคช
    static func resetForTesting(backend newBackend: TokenStorage) {
        lock.lock(); defer { lock.unlock() }
        backend = newBackend
        cache = nil
        cacheLoaded = false
        prepared = false
    }
    #endif
}
