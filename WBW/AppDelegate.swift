import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

extension Notification.Name {
    /// โพสต์เมื่อผู้ใช้แตะ push — ให้ MainTabView สลับไปแท็บประกาศ
    static let openNotificationsTab = Notification.Name("openNotificationsTab")
    /// โพสต์เมื่อผู้ใช้แตะ push ของแชท — ให้ MainTabView เปิดจอแชท
    static let openGroupChat = Notification.Name("openGroupChat")
    /// โพสต์เมื่อผู้ใช้แตะ push ขอความเห็นต่อฐาน — userInfo["checkpoint_id"] เป็น String
    static let openCheckinFeedback = Notification.Name("openCheckinFeedback")
    /// โพสต์เมื่อ push ขอความเห็น "มาถึง" ตอนแอปเปิดอยู่ (ยังไม่มีใครแตะ) — สัญญาณว่ามีของใหม่ฝั่ง
    /// server เท่านั้น ไม่พา userInfo อะไรมาและไม่สั่งเปิดจอไหนทั้งสิ้น (ดู willPresent)
    static let checkinFeedbackArrived = Notification.Name("checkinFeedbackArrived")
    /// โพสต์เมื่อผู้ใช้แตะ push เคส SOS ของเพื่อนในกลุ่ม — userInfo["sos_id"] เป็น String
    static let openSOSCase = Notification.Name("openSOSCase")
    /// โพสต์เมื่อ push เคส SOS ของเพื่อนมาถึงตอนแอปเปิดอยู่ (ยังไม่มีใครแตะ) — ทรงเดียวกับ
    /// checkinFeedbackArrived ทุกประการและด้วยเหตุผลเดียวกัน: push ที่มาถึงเฉยๆ ไม่ใช่การขออนุญาต
    /// แทรกจอที่ผู้ใช้กำลังใช้อยู่ ไม่พา userInfo มาและไม่เปิด SOSFriendView ให้เอง — แตะการ์ดใน
    /// รายการแจ้งเตือน หรือแตะตัว push ต่างหากถึงเข้าจอ (ดู didReceive)
    static let sosArrived = Notification.Name("sosArrived")
}

/// เก็บ notification name ที่แตะไว้ชั่วคราว เผื่อ NotificationCenter.post ยิงไปตอนยังไม่มีใคร subscribe
/// (cold launch: didReceive มักมาก่อน MainTabView จะติดตั้ง .onReceive ทัน เพราะมีหน้าสแปลชคั่นอยู่) —
/// one-shot: MainTabView.task ดึงไปโพสต์ซ้ำแล้วเคลียร์ทันทีที่มีโอกาส (ดู consume())
enum PendingPush {
    private static var pending: (name: Notification.Name, info: [AnyHashable: Any]?)?

    /// พก userInfo มาด้วยได้ — feedback ต้องรู้ว่าฐานไหน ไม่ใช่แค่ "เปิดหน้าไหน"
    static func hold(_ n: Notification.Name, info: [AnyHashable: Any]? = nil) {
        pending = (n, info)
    }

    /// อ่านแล้วเคลียร์ในตาเดียว กันโดนดึงไปใช้ซ้ำสองรอบ
    static func consume() -> (name: Notification.Name, info: [AnyHashable: Any]?)? {
        defer { pending = nil }
        return pending
    }

    /// เคลียร์ทิ้งหลัง .onReceive รับสดไปแล้ว (มีคน subscribe อยู่จริงตอน post — ไม่ใช่ cold launch) กันของที่
    /// hold() พักไว้ตอน didReceive ตกค้างข้าม mount ถัดไป (เช่น logout แล้ว login บัญชีอื่น) ทำให้ consume()
    /// ตอน mount ใหม่ดึงของเก่าที่ไม่เกี่ยวกับบัญชีนั้นมาเล่นซ้ำ
    static func clear() { pending = nil }

    /// เลขเคส SOS ใน payload ของ push · nil = push ชนิดอื่น
    ///
    /// เช็ค type ก่อนเสมอ — payload ของ push ชนิดอื่น (เช่น chat มี group_id) ต้องไม่ถูกอ่าน
    /// sos_id ผิดๆ ไปเป็นเลขเคสที่ไม่มีอยู่จริง ใช้ทั้งจาก didReceive (แตะ push) และ willPresent
    /// (push มาถึงตอนแอปเปิดอยู่) เป็นจุดตัดสินจุดเดียวว่า payload นี้ "เป็น SOS ที่มีเลขเคสจริง" ไหม
    static func sosId(from payload: [AnyHashable: Any]) -> Int64? {
        guard payload["type"] as? String == "sos" else { return nil }
        guard let raw = payload["sos_id"] as? String else { return nil }
        return Int64(raw)
    }
}

/// จัดการ push ผ่าน Firebase (FCM ครอบ APNs)
/// ถ้าไม่มี GoogleService-Info.plist → ปิดแบบเงียบ (in-app poll ยังทำงาน)
final class PushManager {
    static let shared = PushManager()
    private(set) var enabled = false
    /// ไฟล์ Firebase ที่โหลดมาเป็นของ bundle นี้จริงไหม — เก็บไว้เพื่อให้บรรทัดวินิจฉัยพูดความจริง
    /// (ค่าเริ่มต้น `true` แปลว่า "ยังไม่เคยเช็ค" ไม่ใช่ "ผ่าน" — จะถูกเขียนทับตอน configure)
    private(set) var bundleMatched = true
    private var fcmToken: String?

    /// โหมดเดโม่ไม่แตะ Firebase เลยสักบรรทัด
    ///
    /// ไม่ใช่แค่ "ไม่ลงทะเบียน device token" — ตัว Firebase Messaging เองเป็นคนทำให้ระบบเด้ง
    /// dialog ขอสิทธิ์แจ้งเตือน (พิสูจน์แล้ว: guard ที่ `didFinishLaunching` ทำงานถูก
    /// `requestAuthorization` ของเราไม่เคยถูกเรียก — console ยืนยัน `enteringDemo=1` — แต่ dialog
    /// ยังเด้งอยู่ดี) · โหมดเดโม่ไม่มีทางได้รับ push สักอัน การขอสิทธิ์จึงเป็นการรบกวนล้วน ๆ
    /// และมันบัง reviewer ไม่ให้เห็นจอแรกด้วย
    static func enteringDemo() -> Bool {
        DemoMode.active || UserDefaults.standard.bool(forKey: "uitestDemo")
    }

    func configureFirebaseIfAvailable() {
        if enabled { return }
        if Self.enteringDemo() {
            NSLog("[push] โหมดเดโม่ — ข้าม Firebase ทั้งหมด (in-app ยังทำงาน)")
            return
        }
        // โหลด options จากไฟล์ตรงๆ — ไม่มี/โหลดไม่ได้ = ปิด push (in-app ยังทำงาน)
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else {
            NSLog("[push] ไม่มี GoogleService-Info.plist — ปิด push (in-app ยังทำงาน)")
            return
        }
        // **ไฟล์ของแอปอื่นต้องไม่ถูกใช้ configure** — เคยเกิดจริง 2026-08-25: ไฟล์ที่วางอยู่เป็นของ
        // bundle `th.ac.mfu.su.clubfair` (ค้างจากรอบที่เกือบย้ายไปรายการ Club Fair) ส่วนแอปเป็น
        // `th.ac.mfu.wbwSwift` · FCM ลงทะเบียนกับ app คนละใบใน Firebase token ที่ได้จึงไม่มีทาง
        // ตรงกับที่เซิร์ฟเวอร์ยิงไปหา — **ไม่มี error สักบรรทัด** เห็นแค่ push ไม่มาทั้งงาน
        bundleMatched = Self.bundleMatches(optionsBundleID: options.bundleID,
                                           appBundleID: Bundle.main.bundleIdentifier)
        guard bundleMatched else {
            NSLog("[push] GoogleService-Info.plist เป็นของ bundle %@ แต่แอปคือ %@ — ปิด push ทิ้ง เอาไฟล์ที่ถูกมาวางก่อน",
                  options.bundleID, Bundle.main.bundleIdentifier ?? "(ไม่รู้)")
            return
        }
        if FirebaseApp.app() == nil { FirebaseApp.configure(options: options) }
        enabled = true
        NSLog("[push] Firebase configured, push enabled")
    }

    func updateFcmToken(_ token: String) {
        fcmToken = token
        #if DEBUG
        NSLog("[push] FCM_TOKEN=%@", token)
        #endif
        registerCurrent()
    }

    /// ขอสิทธิ์แจ้งเตือน — **เรียกหลังล็อกอินสำเร็จเท่านั้น** (`Session.save(_:)`)
    ///
    /// ของเดิมขอตั้งแต่ `didFinishLaunching` กล่องจึงเด้งใส่คนที่ยังไม่ได้ล็อกอินบนจอ splash
    /// ที่ไม่มีอะไรอธิบายว่าแอปนี้คืออะไร — Guideline 5.1.1 เขียนเรื่องขอพร้อมบริบทไว้ตรง ๆ
    /// และ repo นี้เพิ่งเสียสองรอบรีวิวกับข้อ 5.1.1(iv) ของสิทธิ์ตำแหน่งไปแล้ว
    ///
    /// ไม่มีจออธิบายคั่นเหมือนตำแหน่งโดยตั้งใจ: จอแบบนั้นคือสิ่งที่โดนตีกลับมาสองรอบ และการ
    /// ขอสิทธิ์แจ้งเตือน "หลังล็อกอินของกิจกรรมที่มีประกาศ" มีบริบทในตัวมันเองอยู่แล้ว
    func requestAuthorizationIfNeeded() {
        guard enabled, !Self.enteringDemo() else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// ไฟล์ Firebase ที่วางอยู่เป็นของแอปนี้จริงไหม — อ่านค่าไม่ได้ก็นับว่าไม่ตรง
    ///
    /// เดาว่า "น่าจะใช่" แล้วปล่อยผ่านคือสิ่งที่ทำให้เรื่องนี้ใช้เวลาไล่หาสองรอบโดยเห็นแค่
    /// `device_token` ค้างที่ 0 ในฐานข้อมูล
    static func bundleMatches(optionsBundleID: String?, appBundleID: String?) -> Bool {
        guard let optionsBundleID, let appBundleID, !optionsBundleID.isEmpty, !appBundleID.isEmpty
        else { return false }
        return optionsBundleID == appBundleID
    }

    /// เคยกดอนุญาตไว้แล้วต้องขอ APNs token **ใหม่ทุกครั้งที่เปิดแอป**
    ///
    /// APNs token ไม่ใช่ของที่แอปเก็บไว้เองได้ — Apple กำหนดให้เรียก
    /// `registerForRemoteNotifications()` ทุก launch · ของเดิมเรียกจากเส้นทางขอสิทธิ์ที่วิ่ง
    /// เฉพาะตอนล็อกอินสำเร็จเท่านั้น เครื่องที่ล็อกอินค้างข้ามเวอร์ชัน (คือเกือบทุกคนในวันงาน)
    /// จึงไม่เคยมี APNs token เลยหลังอัปเดต แปลว่า FCM ไม่ออก token ต่อ และเซิร์ฟเวอร์ไม่มี
    /// device token ของคนนั้น — ทั้งที่กล่องสิทธิ์เคยกดอนุญาตไปนานแล้ว
    static func shouldRegisterForRemoteNotifications(authorization: UNAuthorizationStatus) -> Bool {
        switch authorization {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// บรรทัดวินิจฉัยสำหรับ log — ชี้ว่าตกด่านไหน โดยไม่ต้องต่อ debugger
    static func diagnosticLine(bundleMatches: Bool, firebaseEnabled: Bool,
                               authorization: UNAuthorizationStatus, hasFcmToken: Bool) -> String {
        "[push] bundle=\(bundleMatches ? "ตรง" : "ไม่ตรง") firebase=\(firebaseEnabled ? "พร้อม" : "ปิด") "
        + "สิทธิ์=\(authorization.rawValue) fcm=\(hasFcmToken ? "มี" : "ยังไม่มี")"
    }

    /// ขอ APNs token ใหม่ถ้าผู้ใช้เคยอนุญาตไว้แล้ว — **ไม่ขึ้นกล่องอะไรทั้งสิ้น**
    ///
    /// ไม่ใช่การขอสิทธิ์ จึงไม่แตะ Guideline 5.1.1(iv) ที่เพิ่งโดนตีกลับมาสองรอบ
    func registerForPushIfAlreadyAuthorized() {
        guard enabled, !Self.enteringDemo() else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            NSLog("%@", Self.diagnosticLine(bundleMatches: self?.bundleMatched ?? false,
                                            firebaseEnabled: self?.enabled ?? false,
                                            authorization: settings.authorizationStatus,
                                            hasFcmToken: self?.fcmToken?.isEmpty == false))
            guard Self.shouldRegisterForRemoteNotifications(authorization: settings.authorizationStatus)
            else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// คีย์เดียวกับที่ AppSettings เขียน — ประกาศไว้ที่นี่เพราะ PushManager ไม่ได้ถือ AppSettings
    /// (คนละ object กัน) พิมพ์คีย์ต่างกันเมื่อไหร่จะพังเงียบ ๆ ไม่มีอะไรฟ้อง
    static let notiEnabledKey = "wbw.noti.enabled"

    /// ไม่เคยตั้งค่า = เปิด — ต้องตีความเหมือน AppSettings.init ไม่งั้นเครื่องที่ไม่เคยเข้าหน้าตั้งค่า
    /// จะไม่ได้รับ push เลยสักครั้ง
    static func notificationsEnabledPreference() -> Bool {
        UserDefaults.standard.object(forKey: notiEnabledKey) as? Bool ?? true
    }

    /// เงื่อนไขทั้งหมดของการลงทะเบียน แยกเป็น static func บริสุทธิ์ให้เทสเรียกตรงได้
    /// โดยไม่ต้องมี Firebase/UserDefaults จริง
    static func shouldRegister(pushEnabled: Bool, notiEnabled: Bool, fcmToken: String?, jwt: String?) -> Bool {
        guard pushEnabled, notiEnabled,
              let fcm = fcmToken, !fcm.isEmpty,
              let jwt, !jwt.isEmpty
        else { return false }
        return true
    }

    /// ลงทะเบียนถ้ามีทั้ง JWT (login แล้ว) + fcmToken + ผู้ใช้ยังไม่ได้ปิดแจ้งเตือน
    ///
    /// ต้องเช็กสวิตช์ตรงนี้ ไม่ใช่แค่ตอนกดปิดในหน้าตั้งค่า — เดิมปิดแล้วถอน token จริง แต่ Session
    /// .save() ตอน login และ updateFcmToken() ตอน FCM หมุน token เรียกตัวนี้โดยไม่รู้เรื่องสวิตช์
    /// เครื่องจึงกลับไปอยู่ในรายชื่อรับ push เงียบ ๆ ทั้งที่สวิตช์ยังโชว์ปิดอยู่
    func registerCurrent() {
        // ตั้งค่าให้เองก่อน — ออกจากโหมดเดโม่แล้วล็อกอินจริงในรอบเดียวกัน Firebase จะยังไม่ถูก
        // configure เลย (ตอน launch ข้ามไป) ไม่เรียกตรงนี้เครื่องนั้นจะไม่ได้รับ push ทั้งวันโดยไม่มี
        // อะไรฟ้อง — อาการเดียวกับที่เคยไล่หาแล้วเห็นแค่ device_token ค้างที่ 0
        configureFirebaseIfAvailable()
        let jwt = TokenStore.read()
        guard Self.shouldRegister(pushEnabled: enabled,
                                  notiEnabled: Self.notificationsEnabledPreference(),
                                  fcmToken: fcmToken, jwt: jwt),
              let fcm = fcmToken, let jwt
        else {
            // ตกด่านไหนต้องรู้ — สามเงื่อนไขนี้เงียบเท่ากันหมดจากภายนอก และผลลัพธ์คือ
            // "ไม่ได้รับ push ทั้งงาน" เหมือนกันหมด
            NSLog("[push] ยังไม่ลงทะเบียนเครื่อง — push=%@ สวิตช์=%@ fcm=%@ jwt=%@",
                  enabled ? "พร้อม" : "ปิด",
                  Self.notificationsEnabledPreference() ? "เปิด" : "ปิด",
                  (fcmToken?.isEmpty == false) ? "มี" : "ยังไม่มี",
                  (jwt?.isEmpty == false) ? "มี" : "ยังไม่ล็อกอิน")
            return
        }
        // **ผลของการยิงต้องมีคนเห็น** — ของเดิมเป็น `try?` เปล่า ๆ ล้มเหลวแล้วเงียบสนิท
        // ซึ่งคืออาการเดิมที่ไล่หามาสองรอบโดยเห็นแค่ device_token ค้างที่ 0 ในฐานข้อมูล
        Task {
            do {
                try await APIClient.shared.registerDevice(token: jwt, fcmToken: fcm, platform: "ios")
                NSLog("[push] ลงทะเบียนเครื่องกับเซิร์ฟเวอร์สำเร็จ")
            } catch {
                NSLog("[push] ลงทะเบียนเครื่องไม่สำเร็จ: %@", String(describing: error))
            }
        }
    }

    /// ถอน token (เรียกก่อนล้าง JWT ตอน logout)
    func unregister() {
        guard let fcm = fcmToken,
              let jwt = TokenStore.read(), !jwt.isEmpty
        else { return }
        Task { try? await APIClient.shared.unregisterDevice(token: jwt, fcmToken: fcm) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        PushManager.shared.configureFirebaseIfAvailable()  // idempotent — เผื่อ WBWApp.init ยังไม่รัน
        guard PushManager.shared.enabled else { return true }

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        // กันชั้นที่สอง — ชั้นแรกคือ configureFirebaseIfAvailable() ที่ข้ามทั้งก้อนในโหมดเดโม่
        // (ทำให้ guard `enabled` ด้านบนคืนก่อนถึงตรงนี้อยู่แล้ว) เก็บไว้ทั้งคู่เพราะสองทางนี้
        // เปลี่ยนแยกกันได้ในอนาคต
        guard !PushManager.enteringDemo() else { return true }
        // **ขอ APNs token ใหม่ทุก launch สำหรับคนที่เคยอนุญาตไว้แล้ว** — ไม่ใช่การขอสิทธิ์
        // ไม่มีกล่องอะไรขึ้น (ดู `registerForPushIfAlreadyAuthorized`) · ขาดบรรทัดนี้ไปคือเหตุที่
        // เครื่องซึ่งล็อกอินค้างข้ามเวอร์ชันไม่ได้รับ push เลยสักอันทั้งที่เคยกดอนุญาตแล้ว
        PushManager.shared.registerForPushIfAlreadyAuthorized()
        // **ไม่ขอสิทธิ์แจ้งเตือนตรงนี้แล้ว ตั้งแต่ 2026-08-25 — ห้ามใส่กลับ**
        //
        // ของเดิมเรียก `requestAuthorization` ที่นี่ กล่องของระบบจึงเด้งใส่คนที่ยังไม่ได้ล็อกอิน
        // บนจอ splash ที่ไม่มีอะไรอธิบายว่าแอปนี้คืออะไรด้วยซ้ำ — รูปแบบเดียวกับที่
        // `LocationPrimer` ถูกสร้างขึ้นมาแก้ตาม Guideline 5.1.1 (ขอพร้อมบริบท)
        // · ย้ายไปขอหลังล็อกอินสำเร็จที่ `Session.save(_:)` ผ่าน
        // `PushManager.requestAuthorizationIfNeeded()` ซึ่งลำดับกับชีตอธิบายตำแหน่งถูกคุมด้วย
        // `PermissionSequence` ไม่ให้กล่องสองใบซ้อนกัน
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // FCM token พร้อม/รีเฟรช
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        PushManager.shared.updateFcmToken(fcmToken)
    }

    /// แสดง banner ตอนแอปเปิดอยู่ (foreground) — ยกเว้นชนิดที่แอปมี "ของแทน" อยู่ในจอแล้ว
    ///
    /// **ตัวตัดสินอยู่ที่ `PushPresentation.foreground` ไม่ใช่ในเมธอดนี้** — ย้ายออกไปเมื่อ
    /// 2026-08-25 เพราะเรียกจากเทสไม่ได้เลย (ต้องมี `UNNotification` จริงซึ่งสร้างเองไม่ได้)
    /// ตอนนี้ทุกสาขามีเทสคุมที่ `WBWTests/PushPresentationTests.swift`
    ///
    /// ที่นี่เหลือแค่แปลงของจากระบบเป็นอาร์กิวเมนต์ แล้วทำตามคำตอบ
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let info = notification.request.content.userInfo
        let decision = PushPresentation.foreground(type: info["type"] as? String,
                                                   sosId: PendingPush.sosId(from: info))
        // สัญญาณต้องโพสต์ก่อนตอบ completion — จอที่รออยู่ (MainTabView) จะได้เริ่มโหลดของใหม่
        // ทันที ไม่ต้องรอรอบ poll ถัดไป
        if let signal = decision.signal { NotificationCenter.default.post(name: signal, object: nil) }
        completionHandler(decision.showsSystemBanner ? [.banner, .sound, .badge] : [])
    }

    // แตะ notification → เปิดหน้าที่ตรงกับชนิด
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let type = info["type"] as? String
        let name: Notification.Name
        var carried: [AnyHashable: Any]?
        switch type {
        case "chat":
            name = .openGroupChat
        case "checkin_feedback":
            name = .openCheckinFeedback
            carried = ["checkpoint_id": info["checkpoint_id"] as? String ?? ""]
        case "sos":
            name = .openSOSCase
            carried = ["sos_id": info["sos_id"] as? String ?? ""]
        default:
            name = .openNotificationsTab
        }
        PendingPush.hold(name, info: carried)   // เผื่อยังไม่มีใคร subscribe (cold launch) — MainTabView.task ดึงไปโพสต์ซ้ำเอง
        NotificationCenter.default.post(name: name, object: nil, userInfo: carried)
        completionHandler()
    }
}
