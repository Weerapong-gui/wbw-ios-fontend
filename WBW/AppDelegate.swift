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
}

/// จัดการ push ผ่าน Firebase (FCM ครอบ APNs)
/// ถ้าไม่มี GoogleService-Info.plist → ปิดแบบเงียบ (in-app poll ยังทำงาน)
final class PushManager {
    static let shared = PushManager()
    private(set) var enabled = false
    private var fcmToken: String?

    func configureFirebaseIfAvailable() {
        if enabled { return }
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

    /// ลงทะเบียนถ้ามีทั้ง JWT (login แล้ว) + fcmToken
    func registerCurrent() {
        guard enabled,
              let fcm = fcmToken,
              let jwt = UserDefaults.standard.string(forKey: "wbw.token"), !jwt.isEmpty
        else { return }
        Task { try? await APIClient.shared.registerDevice(token: jwt, fcmToken: fcm, platform: "ios") }
    }

    /// ถอน token (เรียกก่อนล้าง JWT ตอน logout)
    func unregister() {
        guard let fcm = fcmToken,
              let jwt = UserDefaults.standard.string(forKey: "wbw.token"), !jwt.isEmpty
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
        default:
            name = .openNotificationsTab
        }
        PendingPush.hold(name, info: carried)   // เผื่อยังไม่มีใคร subscribe (cold launch) — MainTabView.task ดึงไปโพสต์ซ้ำเอง
        NotificationCenter.default.post(name: name, object: nil, userInfo: carried)
        completionHandler()
    }
}
