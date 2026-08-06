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

    private let tokenKey = "wbw.token"
    /// static (ไม่ใช่ instance) เพราะ currentUserIdFromDisk() ด้านล่างต้องอ่านคีย์เดียวกันนี้ได้โดย
    /// ไม่ต้องมี Session instance อยู่ก่อน (ดูคอมเมนต์ที่นั่น) — แหล่งเดียวกัน ไม่ใช่ string ซ้ำสอง
    /// ที่ต้องคอยแก้พร้อมกันเอง
    private static let userKey = "wbw.user"
    private var authObserver: NSObjectProtocol?

    init() {
        token = UserDefaults.standard.string(forKey: tokenKey)
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
        // **ต้องเขียนลง UserDefaults ด้วย ไม่ใช่ตั้งแค่ตัวแปรในหน่วยความจำ** — PushManager
        // .registerCurrent() อ่าน JWT จาก UserDefaults คีย์ tokenKey ตรงๆ ไม่ได้ถาม Session
        // ถ้าตั้งแค่ในหน่วยความจำ guard ตรงนั้นจะไม่ผ่านตลอดกาล เครื่องจึงไม่เคยลงทะเบียน
        // device token เลย และ push ทดสอบไม่ได้เลยสักครั้งโดยไม่มีอะไรฟ้อง (เสียเวลาไล่หา
        // มาแล้วรอบหนึ่ง — เห็นแค่ device_token ค้างที่ 0 โดยไม่มี error ที่ไหนเลย)
        //
        // เขียนให้เหมือน save() แทบทุกอย่าง เพื่อให้ hook นี้เทียบเท่าการ login จริง ไม่ใช่ครึ่งใบ —
        // ข้อยกเว้นเดียวที่ตั้งใจ: **ไม่** เรียก SOSLocator.shared.requestPermission() ที่นี่ hook นี้
        // มีไว้ข้ามการพิมพ์รหัสผ่านตอนเทส UI ไม่ใช่ให้เจอกล่องขอสิทธิ์ตำแหน่งจริงทุกครั้งที่ launch
        // ด้วย flag นี้ ผลคือ authorization ค้างที่ .notDetermined เท่านั้น — เป็นสถานะของระบบที่
        // ตรวจสอบได้ตรงๆ ไม่ใช่ contract ที่ซ่อนอยู่แบบที่เคยพลาดกับ UserDefaults ด้านบน
        if let t = UserDefaults.standard.string(forKey: "uitestToken"), !t.isEmpty {
            let u = UserDefaults.standard.string(forKey: "uitestUser") ?? "tester"
            let r = UserDefaults.standard.string(forKey: "uitestRole") ?? "participant"
            let fake = AuthUser(userId: "", username: u, role: r)
            token = t
            user = fake
            UserDefaults.standard.set(t, forKey: tokenKey)
            UserDefaults.standard.set(try? JSONEncoder().encode(fake), forKey: Self.userKey)
            PushManager.shared.registerCurrent()
        }
        #endif
    }

    func save(_ res: LoginResponse) {
        user = res.user
        token = res.token
        UserDefaults.standard.set(res.token, forKey: tokenKey)
        UserDefaults.standard.set(try? JSONEncoder().encode(res.user), forKey: Self.userKey)
        // ผูก device token กับผู้ใช้ที่เพิ่ง login (ถ้ามี FCM token แล้ว)
        PushManager.shared.registerCurrent()
        // ขอสิทธิ์ตำแหน่งหลังล็อกอินสำเร็จเท่านั้น — ตอนเปิดแอปครั้งแรกผู้ใช้ยังไม่รู้ว่าแอปนี้คืออะไร
        // และการขอสิทธิ์ตอนกด SOS คือทั้งช้าที่สุดและถูกปฏิเสธมากที่สุด (แนวเดียวกับที่วางแผนไว้กับ
        // push notification — ดู push-notification-gaps) · เรียกผ่าน .shared ไม่ใช่ SOSLocator()
        // ลอยๆ — ต้องมีคนถือ CLLocationManager ข้างในไว้จนกว่า OS จะเก็บกล่องขอสิทธิ์เสร็จ ไม่งั้น ARC
        // เก็บทันทีที่จบ statement (ดูคอมเมนต์ที่ SOSLocator.shared) · เรียกตรงๆ ได้โดยไม่ต้อง await
        // (SOSLocator เป็น @MainActor เหมือน Session ตรงนี้เอง ไม่ข้าม actor และ save() เองก็ไม่ใช่ async)
        SOSLocator.shared.requestPermission()
    }

    /// automatic: true เฉพาะตอนเรียกจาก authObserver ด้านบน (401 ที่ไม่มีใครขอ) · ปุ่ม "ออกจากระบบ"
    /// ทั้งสองจอ (SettingsView, StaffScanView) เรียกแบบไม่ใส่ค่านี้ = false เสมอ ค่าเริ่มต้นจึงตรงกับ
    /// เส้นทางที่พบบ่อยที่สุด (พบจากรีวิว Task 14 รอบสอง — ดูคอมเมนต์ที่ lastLogoutWasAutomatic)
    func logout(automatic: Bool = false) {
        lastLogoutWasAutomatic = automatic
        // ถอน device token ก่อนล้าง JWT (unregister อ่าน JWT)
        PushManager.shared.unregister()
        user = nil
        token = nil
        UserDefaults.standard.removeObject(forKey: tokenKey)
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
        // ความเห็นที่ยังค้างคิว (เขียนตอนเน็ตหลุด) ต้องไม่ถูก flush ทีหลังด้วย token ของบัญชีถัดไป —
        // backend ผูกความเห็นกับเจ้าของ token ไม่ใช่กับคนที่พิมพ์ ของค้างจะกลายเป็นความเห็นของคนอื่น
        // เงียบๆ · อยู่ที่เดียวกับ cache ต้นไม้ด้วยเหตุผลเดียวกัน (ดูคอมเมนต์ด้านบน)
        FeedbackOutbox(backend: Config.backend).clear()
        // push ที่แตะค้างไว้แต่ยังไม่มีใครมารับ (แตะตอนอยู่หน้า login หรือตอนเป็นเจ้าหน้าที่ — ทั้งสองจอ
        // ไม่ mount MainTabView จึงไม่มี consume() มาดึงไป) ต้องไม่รอดข้ามไปถึงบัญชีถัดไปบนเครื่องเดียวกัน
        // แล้วเปิดฟอร์มให้คะแนนฐานของคนก่อนหน้าให้เอง — ตัว MainTabView เคลียร์เฉพาะตอนรับสดได้เท่านั้น
        PendingPush.clear()
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
