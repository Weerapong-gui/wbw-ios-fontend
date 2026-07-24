import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

extension Notification.Name {
    /// โพสต์เมื่อผู้ใช้แตะ push — ให้ MainTabView สลับไปแท็บประกาศ
    static let openNotificationsTab = Notification.Name("openNotificationsTab")
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

    // แสดง banner ตอนแอปเปิดอยู่ (foreground)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // แตะ notification → เปิดแท็บประกาศ
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationCenter.default.post(name: .openNotificationsTab, object: nil)
        completionHandler()
    }
}
