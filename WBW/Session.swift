import Foundation

@MainActor
final class Session: ObservableObject {
    @Published var user: AuthUser?
    @Published var token: String?
    /// true เฉพาะตอน logout() ล่าสุดถูกเรียกจาก authObserver (401 อัตโนมัติ) ไม่ใช่จากปุ่มที่ผู้ใช้กด
    /// เอง — MainTabView.onDisappear อ่านค่านี้ตัดสินใจว่าจะล้างเคส SOS ที่ค้างอยู่หรือไม่ (ผ่าน
    /// SOSStore.handleLogout(automatic:) ดูคอมเมนต์ยาวที่นั่น) ค่าเริ่มต้น false เพราะ logout()
    /// เขียนทับค่านี้ทุกครั้งที่ถูกเรียกไม่ว่าทางไหน (พบจากรีวิว Task 14 รอบสอง) ไม่มีทางค้างค่าเก่า
    /// ข้ามการล็อกเอาต์ครั้งถัดไป
    @Published private(set) var lastLogoutWasAutomatic = false

    /// **JWT ไม่ได้อยู่ใน `UserDefaults` แล้ว** — อยู่ใน Keychain ผ่าน `TokenStore` (ดูเหตุผลที่นั่น)
    /// ห้ามเพิ่มคีย์ token กลับมาที่นี่
    ///
    /// `userKey` ยังอยู่: `AuthUser` (userId/username/role) ไม่ใช่ความลับ — แสดงบนจออยู่แล้ว —
    /// และ `currentUserIdFromDisk()` ด้านล่างต้องอ่านได้โดยไม่ต้องมี `Session` instance อยู่ก่อน
    static let userKey = "wbw.user"
    private var authObserver: NSObjectProtocol?

    init() {
        token = TokenStore.read()
        // 401 จากที่ไหนก็ตาม (token หมดอายุ/เปลี่ยน secret) → logout อัตโนมัติ (แทนจอว่าง)
        // automatic: true — ไม่มีการยืนยันจากผู้ใช้เกิดขึ้นเลยสักครั้งในเส้นทางนี้ (ดูคอมเมนต์ที่
        // lastLogoutWasAutomatic และ logout(automatic:) ว่าทำไมเรื่องนี้สำคัญ)
        authObserver = NotificationCenter.default.addObserver(
            forName: .wbwUnauthorized, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.token != nil else { return }
                self.logout(automatic: true)
            }
        }
        if let data = UserDefaults.standard.data(forKey: Self.userKey) {
            user = try? JSONDecoder().decode(AuthUser.self, from: data)
        }
        #if DEBUG
        // เทส UI บนเครื่องที่พิมพ์ login ไม่ได้: launch ด้วย `-uitestToken <jwt> -uitestUser <username>`
        //
        // **ต้องเขียนลงที่เก็บด้วย ไม่ใช่ตั้งแค่ตัวแปรในหน่วยความจำ** — PushManager
        // .registerCurrent() อ่าน JWT จาก TokenStore ตรงๆ ไม่ได้ถาม Session
        // ถ้าตั้งแค่ในหน่วยความจำ guard ตรงนั้นจะไม่ผ่านตลอดกาล เครื่องจึงไม่เคยลงทะเบียน
        // device token เลย และ push ทดสอบไม่ได้เลยสักครั้งโดยไม่มีอะไรฟ้อง (เสียเวลาไล่หา
        // มาแล้วรอบหนึ่ง — เห็นแค่ device_token ค้างที่ 0 โดยไม่มี error ที่ไหนเลย)
        //
        // เขียนให้เหมือน save() แทบทุกอย่าง เพื่อให้ hook นี้เทียบเท่าการ login จริง ไม่ใช่ครึ่งใบ —
        // ข้อยกเว้นเดียวที่ตั้งใจ: **ไม่** เรียก SOSLocator.shared.requestPermission() ที่นี่ hook นี้
        // มีไว้ข้ามการพิมพ์รหัสผ่านตอนเทส UI ไม่ใช่ให้เจอกล่องขอสิทธิ์ตำแหน่งจริงทุกครั้งที่ launch
        // ด้วย flag นี้ ผลคือ authorization ค้างที่ .notDetermined เท่านั้น — เป็นสถานะของระบบที่
        // ตรวจสอบได้ตรงๆ ไม่ใช่ contract ที่ซ่อนอยู่แบบที่เคยพลาดกับ UserDefaults ด้านบน
        // เข้าโหมดเดโม่ตอน launch — มีไว้ถ่ายสกรีนช็อตให้ App Store โดยไม่ต้องมีตัวกดจอ
        // (เครื่องนี้ไม่มี idb) ตัวโหมดเดโม่เองอยู่ใน Release ปกติ แค่ "ทางเข้าอัตโนมัติ" ที่เป็น DEBUG
        if UserDefaults.standard.bool(forKey: "uitestDemo") {
            if UserDefaults.standard.bool(forKey: "uitestDemoNoGroup") {
                DemoData.me = DemoData.meWithoutGroup
            }
            startDemo()
        }
        if let t = UserDefaults.standard.string(forKey: "uitestToken"), !t.isEmpty {
            let u = UserDefaults.standard.string(forKey: "uitestUser") ?? "tester"
            let r = UserDefaults.standard.string(forKey: "uitestRole") ?? "participant"
            let fake = AuthUser(userId: "", username: u, role: r)
            token = t
            user = fake
            TokenStore.write(t)
            UserDefaults.standard.set(try? JSONEncoder().encode(fake), forKey: Self.userKey)
            PushManager.shared.registerCurrent()
        }
        #endif
    }

    /// เข้าโหมดเดโม่ — เทียบเท่า `save(_:)` ทุกอย่าง **ยกเว้นไม่ลงทะเบียน FCM และไม่ขอสิทธิ์ตำแหน่ง**
    ///
    /// ลงทะเบียน device token ด้วย token ปลอมจะได้ 401 จาก backend ซึ่ง `APIClient.send` แปลเป็น
    /// `.wbwUnauthorized` แล้ว `Session` จะเตะตัวเองออกจากโหมดเดโม่ทันทีที่เพิ่งเข้ามา ·
    /// ส่วนสิทธิ์ตำแหน่งไม่ขอเพราะโหมดนี้มีไว้ให้ผู้รีวิวเดินดูจอ ไม่ใช่ให้เจอกล่องขอสิทธิ์จริง
    func startDemo() {
        // ล้างของค้างจากรอบเดโม่ก่อนหน้า — ถ้าปล่อยไว้ ข้อความที่ reviewer คนก่อนพิมพ์ทิ้งไว้
        // จะโผล่ค้างอยู่ในแชทของรอบถัดไป
        Self.clearDemoCaches()
        user = DemoMode.user
        token = DemoMode.token
        TokenStore.write(DemoMode.token)
        UserDefaults.standard.set(try? JSONEncoder().encode(DemoMode.user), forKey: Self.userKey)
    }

    /// cache ของโหมดเดโม่ทุกก้อน (คีย์ลงท้าย `CacheScope.demoSuffix`) — ต้องล้างทั้งตอนเข้าและออก
    /// ไม่งั้นจะซ้ำรอยกับดักเดิมของ repo นี้: ข้อมูลคนละแหล่งปนกันแบบเงียบ ๆ ไม่มี error ให้เห็น
    static func clearDemoCaches() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasSuffix(CacheScope.demoSuffix) || key.hasPrefix("chat.") {
            defaults.removeObject(forKey: key)
        }
    }

    func save(_ res: LoginResponse) {
        user = res.user
        token = res.token
        TokenStore.write(res.token)
        UserDefaults.standard.set(try? JSONEncoder().encode(res.user), forKey: Self.userKey)
        // ผูก device token กับผู้ใช้ที่เพิ่ง login (ถ้ามี FCM token แล้ว)
        PushManager.shared.registerCurrent()
        // ขอสิทธิ์แจ้งเตือน **ที่นี่ ไม่ใช่ตอนเปิดแอป** — ของเดิมขอใน `didFinishLaunching`
        // กล่องจึงเด้งใส่คนที่ยังไม่ได้ล็อกอินบนจอ splash ที่ยังไม่มีบริบทอะไรเลย
        // (Guideline 5.1.1 · ดู `PushManager.requestAuthorizationIfNeeded`)
        // · ลำดับกับชีตอธิบายตำแหน่งคุมด้วย `PermissionSequence` ไม่ให้กล่องสองใบซ้อนกัน
        PushManager.shared.requestAuthorizationIfNeeded()
        // **ตรงนี้เคยเรียก `SOSLocator.shared.requestPermission()` ตรง ๆ — ห้ามใส่กลับ**
        //
        // กล่องขอสิทธิ์ของระบบเด้งใส่คนที่เพิ่งเห็นหน้า Home เป็นครั้งแรกโดยไม่มีอะไรบนจอบอกว่า
        // เอาไปทำอะไร ซึ่ง Guideline 5.1.1 เขียนไว้ตรง ๆ ว่าต้องขอพร้อมบริบท · repo นี้เพิ่งแก้
        // อาการหน้าตาเหมือนกันเป๊ะไปรอบหนึ่งแล้ว (แท็บ SU RUN ขอสิทธิ์เองตอน TabView mount ทุกแท็บ
        // พร้อมกัน — `docs/appstore-1.0-8-verification.md` §5) แต่บรรทัดนี้รอดมา
        //
        // เจตนาเดิม (ขอล่วงหน้าเพราะตอนกด SOS สายเกินไปและถูกปฏิเสธมากที่สุด) ยังอยู่ครบ —
        // ย้ายไปที่ `LocationPrimerSheet` ซึ่งอธิบายก่อนแล้วค่อยเรียกกล่องของระบบเมื่อผู้ใช้กดปุ่ม
        // ประตูว่าจะโชว์เมื่อไหร่อยู่ที่ `LocationPrimer.shouldShow`
    }

    /// automatic: true เฉพาะตอนเรียกจาก authObserver ด้านบน (401 ที่ไม่มีใครขอ) · ปุ่ม "ออกจากระบบ"
    /// ทั้งสองจอ (SettingsView, StaffScanView) เรียกแบบไม่ใส่ค่านี้ = false เสมอ ค่าเริ่มต้นจึงตรงกับ
    /// เส้นทางที่พบบ่อยที่สุด (พบจากรีวิว Task 14 รอบสอง — ดูคอมเมนต์ที่ lastLogoutWasAutomatic)
    func logout(automatic: Bool = false) {
        lastLogoutWasAutomatic = automatic
        // โหมดเดโม่ไม่เคยลงทะเบียน device token ไว้ (ดู startDemo) — ยิง unregister ด้วย token
        // ปลอมจะได้ 401 กลับมาแล้ววน .wbwUnauthorized เข้า logout ซ้ำอีกรอบ
        let wasDemo = DemoMode.active
        if !wasDemo {
            // ถอน device token ก่อนล้าง JWT (unregister อ่าน JWT)
            PushManager.shared.unregister()
        }
        user = nil
        token = nil
        TokenStore.clear()
        UserDefaults.standard.removeObject(forKey: Self.userKey)
        // ต้นไม้ของบัญชีก่อนหน้าต้องไม่ตกทอดไปให้บัญชีถัดไปบนเครื่องเดียวกัน — เจ้าของเดียวของการลบ
        // UserDefaults key นี้ (เดิมเคยลบซ้ำที่ CheckinProgressStore.clear() ด้วย รวมมาไว้ที่เดียวเพราะ
        // ที่นี่เป็นจุดเดียวที่ยิงทุกเส้นทาง logout จริง ทั้งบัญชี participant และ staff — staff ไม่ mount
        // MainTabView เลยจึงไม่มีทางเรียก progress.clear() ที่ MainTabView.onDisappear ได้)
        // Session ไม่ได้ถือ store ไว้ จึงลบ cache ตรงๆ ที่นี่ · ตัว store ในหน่วยความจำถูกล้างแยกที่
        // MainTabView.onDisappear (progress.clear() นั่นแค่ progress = nil ไม่แตะ UserDefaults แล้ว —
        // ดูคอมเมนต์ที่ CheckinProgressStore.clear())
        UserDefaults.standard.removeObject(
            forKey: CheckinProgressStore.cacheKey(for: Config.backend))
        // ชื่อฐานไม่ใช่ข้อมูลส่วนตัว แต่ล้างที่เดียวกันเพื่อไม่ให้มีของค้างข้ามบัญชีสองมาตรฐาน —
        // และเพราะบัญชีถัดไปอาจอยู่คนละ backend ที่มีชุดฐานคนละชุด
        UserDefaults.standard.removeObject(
            forKey: CheckpointStore.cacheKey(for: Config.backend))
        // ความเห็นที่ยังค้างคิว (เขียนตอนเน็ตหลุด) ต้องไม่ถูก flush ทีหลังด้วย token ของบัญชีถัดไป —
        // backend ผูกความเห็นกับเจ้าของ token ไม่ใช่กับคนที่พิมพ์ ของค้างจะกลายเป็นความเห็นของคนอื่น
        // เงียบๆ · อยู่ที่เดียวกับ cache ต้นไม้ด้วยเหตุผลเดียวกัน (ดูคอมเมนต์ด้านบน)
        FeedbackOutbox(backend: Config.backend).clear()
        // push ที่แตะค้างไว้แต่ยังไม่มีใครมารับ (แตะตอนอยู่หน้า login หรือตอนเป็นเจ้าหน้าที่ — ทั้งสองจอ
        // ไม่ mount MainTabView จึงไม่มี consume() มาดึงไป) ต้องไม่รอดข้ามไปถึงบัญชีถัดไปบนเครื่องเดียวกัน
        // แล้วเปิดฟอร์มให้คะแนนฐานของคนก่อนหน้าให้เอง — ตัว MainTabView เคลียร์เฉพาะตอนรับสดได้เท่านั้น
        PendingPush.clear()
        if wasDemo { Self.clearDemoCaches() }
    }

    /// อ่าน user id ปัจจุบันตรงจาก UserDefaults โดยไม่ต้องมี Session instance เลย — ใช้ตอนที่ยังไม่มี
    /// @EnvironmentObject ให้อ่านได้ (พบจากรีวิว Task 14 รอบสาม: MainTabView ต้องรู้ user id ตอนสร้าง
    /// @StateObject ของ SOSStore เอง ซึ่งเกิดก่อนที่ environment จะถูกฉีดเข้ามาตามลำดับของ SwiftUI —
    /// @StateObject default-value expression อ้าง @EnvironmentObject ไม่ได้ ดูคอมเมนต์ที่ SOSStore.init)
    ///
    /// ปลอดภัยเพราะ save()/logout() เขียนทั้ง in-memory (user/token) และ UserDefaults (คีย์เดียวกันนี้)
    /// ในฟังก์ชันเดียวกันก่อน return เสมอ ไม่มีช่องให้สองที่ไม่ตรงกัน — คืน "" (ไม่ใช่ nil) เมื่อยังไม่
    /// เคย login เลยหรือ decode ไม่ผ่าน เพื่อให้ SOSStore.init เทียบตรงๆ กับ SOSDraft.ownerId (String
    /// ไม่ใช่ String?) ได้โดยไม่ต้อง unwrap
    static func currentUserIdFromDisk() -> String {
        guard let data = UserDefaults.standard.data(forKey: userKey),
              let user = try? JSONDecoder().decode(AuthUser.self, from: data)
        else { return "" }
        return user.userId
    }
}
