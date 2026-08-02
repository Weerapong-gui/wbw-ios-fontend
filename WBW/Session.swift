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
        // เทส UI บน simulator (พิมพ์ login ไม่ได้): launch ด้วย `-uitestToken <jwt> -uitestUser <username>`
        if let t = UserDefaults.standard.string(forKey: "uitestToken"), !t.isEmpty {
            token = t
            let u = UserDefaults.standard.string(forKey: "uitestUser") ?? "tester"
            let r = UserDefaults.standard.string(forKey: "uitestRole") ?? "participant"
            user = AuthUser(userId: "", username: u, role: r)
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
        // ต้นไม้ของบัญชีก่อนหน้าต้องไม่ตกทอดไปให้บัญชีถัดไปบนเครื่องเดียวกัน
        // Session ไม่ได้ถือ store ไว้ จึงลบ cache ตรงๆ · ตัว store ในหน่วยความจำ
        // ถูกล้างที่ MainTabView.onDisappear (ทางเดียวกับ chat.purgeForLogout)
        UserDefaults.standard.removeObject(
            forKey: CheckinProgressStore.cacheKey(for: Config.backend))
    }
}
