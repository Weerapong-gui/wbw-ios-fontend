import SwiftUI
import SwiftData

@main
struct WBWApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = Session()
    @StateObject private var settings = AppSettings()
    @StateObject private var profile = ProfileStore()
    @StateObject private var groups = GroupStore()
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
                .environmentObject(forestHost)
                .preferredColorScheme(settings.isDark ? .dark : .light)
                .modelContainer(for: ChatMessage.self)
        }
    }
}
