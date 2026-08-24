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
        if FirebaseApp.app() == nil { FirebaseApp.configure(options: options) }
        enabled = true
        NSLog("[push] Firebase configured, push enabled")
    }

    func updateFcmToken(_ token: String) {
        fcmToken = token
        registerCurrent()
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
        else { return }
        Task { try? await APIClient.shared.registerDevice(token: jwt, fcmToken: fcm, platform: "ios") }
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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async { application.registerForRemoteNotifications() }
            }
        }
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

    // แสดง banner ตอนแอปเปิดอยู่ (foreground) — ยกเว้นแชทกับขอความเห็นต่อฐาน ซึ่งใช้ toast ในแอปแทน
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let info = notification.request.content.userInfo
        let type = info["type"] as? String
        if type == "chat" || type == "checkin_feedback" {
            // ปิด banner/เสียง/badge ของระบบทิ้ง — ในแอปมีของแทนอยู่แล้ว แต่ "ของแทน" นั้นต้องมีจริง:
            // แชทมี ChatToast จาก long-poll ส่วนความเห็นต่อฐานเดิมไม่มีอะไรเลย ต้องรอ poll 60 วิ
            // (นานสุดคือเงียบสนิทเกือบนาทีทั้งที่กดปิด notification ของระบบไปแล้ว) — โพสต์สัญญาณให้
            // MainTabView โหลด progress + รายการแจ้งเตือนใหม่แทน toast เช็คอินจึงเด้งภายในไม่กี่วินาที
            // และ badge กระดิ่งขึ้นทันทีที่ push มาถึง · ตั้งใจไม่เปิดฟอร์มให้เอง — push ที่มาถึงเฉยๆ
            // ไม่ใช่การขออนุญาตแทรกจอที่ผู้ใช้กำลังใช้อยู่ (แตะ push ต่างหากถึงเข้าฟอร์ม ดู didReceive)
            if type == "checkin_feedback" {
                NotificationCenter.default.post(name: .checkinFeedbackArrived, object: nil)
            }
            completionHandler([])
            return
        }
        if PendingPush.sosId(from: info) != nil {
            // เคส SOS ของเพื่อนมาถึงตอนแอปเปิดอยู่ — ทรงเดียวกับ checkin_feedback ด้านบนทุกประการ:
            // ปิด banner ของระบบแล้วรีเฟรชรายการแจ้งเตือนแทน (ดู MainTabView.onReceive(.sosArrived))
            // ให้ badge กระดิ่ง/การ์ดอัปเดตทันที ไม่เปิด SOSFriendView ทับจอที่ผู้ใช้กำลังใช้อยู่เอง
            // — เช็คผ่าน PendingPush.sosId(from:) แทน type == "sos" ตรงๆ: payload ที่พังกลางทาง
            // (ไม่มี sos_id หรือ sos_id ไม่ใช่ตัวเลข) จะไม่ถูกนับว่าเป็น SOS ที่รู้เรื่อง ปล่อยให้ระบบ
            // ขึ้น banner เริ่มต้นแทนดีกว่าเงียบหายไปเฉยๆ โดยไม่มีอะไรแทนที่เลย
            NotificationCenter.default.post(name: .sosArrived, object: nil)
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound, .badge])
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
