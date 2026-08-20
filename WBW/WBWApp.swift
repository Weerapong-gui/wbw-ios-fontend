import SwiftUI
import SwiftData

@main
struct WBWApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = Session()
    @StateObject private var settings = AppSettings()
    @StateObject private var profile = ProfileStore()
    @StateObject private var groups = GroupStore()
    @StateObject private var progress = CheckinProgressStore()
    @StateObject private var forestHost = ForestSceneHost()

    init() {
        // configure Firebase ที่นี่ — รันแน่นอนตอนแอปเริ่ม (ก่อน delegate/proxy)
        PushManager.shared.configureFirebaseIfAvailable()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(settings)
                .environmentObject(profile)
                .environmentObject(groups)
                .environmentObject(progress)
                .environmentObject(forestHost)
                // `auto` = ส่ง nil ปล่อยให้เดินตามระบบ (ThemeMode ของ Android)
                .preferredColorScheme(settings.themeMode == .auto
                                      ? nil
                                      : (settings.themeMode == .dark ? .dark : .light))
                // ตัวขับของ i18n ทั้งแอป — `Text("key")` ใน SwiftUI resolve ผ่าน locale ตัวนี้
                // เปลี่ยนค่าแล้วทุกจอ re-render เป็นภาษาใหม่ทันที ไม่ต้องรีสตาร์ทแอป
                .environment(\.locale, settings.language.locale ?? Locale.autoupdatingCurrent)
                .modelContainer(for: ChatMessage.self)
        }
    }
}
