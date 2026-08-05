import Foundation

@MainActor
final class Session: ObservableObject {
    @Published var user: AuthUser?
    @Published var token: String?

    private let tokenKey = "wbw.token"
    private let userKey = "wbw.user"
    private var authObserver: NSObjectProtocol?

    init() {
        token = UserDefaults.standard.string(forKey: tokenKey)
        // 401 จากที่ไหนก็ตาม (token หมดอายุ/เปลี่ยน secret) → logout อัตโนมัติ (แทนจอว่าง)
        authObserver = NotificationCenter.default.addObserver(
            forName: .wbwUnauthorized, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.token != nil else { return }
                self.logout()
            }
        }
        if let data = UserDefaults.standard.data(forKey: userKey) {
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
        // เขียนให้เหมือน save() ทุกอย่าง เพื่อให้ hook นี้เทียบเท่าการ login จริง ไม่ใช่ครึ่งใบ
        if let t = UserDefaults.standard.string(forKey: "uitestToken"), !t.isEmpty {
            let u = UserDefaults.standard.string(forKey: "uitestUser") ?? "tester"
            let r = UserDefaults.standard.string(forKey: "uitestRole") ?? "participant"
            let fake = AuthUser(userId: "", username: u, role: r)
            token = t
            user = fake
            UserDefaults.standard.set(t, forKey: tokenKey)
            UserDefaults.standard.set(try? JSONEncoder().encode(fake), forKey: userKey)
            PushManager.shared.registerCurrent()
        }
        #endif
    }

    func save(_ res: LoginResponse) {
        user = res.user
        token = res.token
        UserDefaults.standard.set(res.token, forKey: tokenKey)
        UserDefaults.standard.set(try? JSONEncoder().encode(res.user), forKey: userKey)
        // ผูก device token กับผู้ใช้ที่เพิ่ง login (ถ้ามี FCM token แล้ว)
        PushManager.shared.registerCurrent()
    }

    func logout() {
        // ถอน device token ก่อนล้าง JWT (unregister อ่าน JWT)
        PushManager.shared.unregister()
        user = nil
        token = nil
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: userKey)
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
}
