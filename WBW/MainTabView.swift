import SwiftUI
import SwiftData

/// แถบแท็บหลัก — native TabView icon-only · iOS 26 เรนเดอร์เป็น Liquid Glass + fongkaew lens (แบบ App Store) ให้อัตโนมัติ
struct MainTabView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @Environment(\.modelContext) private var context
    @StateObject private var noti = NotiStore()
    @State private var tab = 0
    @State private var chatOpen = false

    init() {
        #if DEBUG
        _tab = State(initialValue: UserDefaults.standard.integer(forKey: "uitestTab"))
        #endif
    }

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                Tab(value: 0) { HomeView() } label: { Image(systemName: "house.fill") }
                Tab(value: 1) { MapScreen() } label: { Image(systemName: "map.fill") }
                Tab(value: 2) { NotificationsView(store: noti, token: session.token ?? "") } label: { Image(systemName: "newspaper.fill") }
                    .badge(noti.unreadCount)
                Tab(value: 3) {
                    GroupTabView(onBack: { tab = 0 }, onOpenChat: { chatOpen = true })
                } label: {
                    Image(systemName: profile.me?.groupId == nil ? "sharedwithyou" : "message.fill")
                }
                // QR แยกเป็นปุ่มเดี่ยว (role .search) — My QR Code สำหรับเช็คอิน
                Tab(value: 4, role: .search) { MyQRCodeView() } label: { Image(systemName: "qrcode") }
            }
            .tint(Color.wbwGold)
            .task {
                // โหลดจำนวนที่ยังไม่อ่านไว้โชว์ badge ตั้งแต่เข้าแอป
                await noti.load(token: session.token ?? "")
                await profile.load(token: session.token ?? "")
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "uitestChat") { chatOpen = true }
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNotificationsTab)) { _ in
                tab = 2  // แตะ push → เปิดแท็บประกาศ
            }

            // แชทกลุ่ม — overlay เลื่อนขึ้นจากล่าง (navbar หายแบบเด้งๆ)
            if chatOpen, let gid = profile.me?.groupId {
                GroupChatView(groupId: gid, token: session.token ?? "", myId: profile.me?.userId ?? "",
                              context: context, onClose: { chatOpen = false })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: chatOpen)
    }
}

/// พื้นป่าเปล่า (Event/Voucher ยังไม่ออกแบบเนื้อหาใน DOI-APP)
struct ForestBlank: View {
    var body: some View {
        Color.clear
            .background {
                Image("bg_forest").resizable().scaledToFill().ignoresSafeArea()
            }
    }
}
