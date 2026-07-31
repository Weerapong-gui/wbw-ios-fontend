import SwiftUI
import SwiftData

/// แถบแท็บหลัก — native TabView icon-only · iOS 26 เรนเดอร์เป็น Liquid Glass + fongkaew lens (แบบ App Store) ให้อัตโนมัติ
struct MainTabView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var noti = NotiStore()
    @StateObject private var chat = ChatSession()
    @State private var tab = 0
    @State private var chatOpen = false
    @State private var showNotifications = false

    init() {
        #if DEBUG
        _tab = State(initialValue: UserDefaults.standard.integer(forKey: "uitestTab"))
        #endif
    }

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                Tab(value: 0) { HomeView(noti: noti) } label: { Image(systemName: "house.fill") }
                Tab(value: 1) { MapScreen() } label: { Image(systemName: "map.fill") }
                Tab(value: 2) { SURunView() } label: { Image(systemName: "figure.run") }
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
                chat.configure(groupId: profile.me?.groupId, token: session.token ?? "",
                               myId: profile.me?.userId ?? "", context: context)
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "uitestChat") { chatOpen = true }
                // ปิดแชทเองหลัง N วิ (แอปยัง foreground อยู่) — จำลอง "ผู้ใช้ปิดจอแชทแต่ไม่ได้ปิดแอป"
                // แบบ headless เพราะไม่มี tap tooling ใช้เทส GroupChatView.onDisappear
                let closeAfter = UserDefaults.standard.double(forKey: "uitestChatCloseAfter")
                if closeAfter > 0 {
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(closeAfter * 1_000_000_000))
                        chatOpen = false
                    }
                }
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNotificationsTab)) { _ in
                showNotifications = true   // noti ไม่มี tab แล้ว → เปิดเป็น sheet
            }
            .onChange(of: profile.me?.groupId) { _, gid in
                chat.configure(groupId: gid, token: session.token ?? "",
                               myId: profile.me?.userId ?? "", context: context)
            }
            .onChange(of: scenePhase) { _, phase in
                // background = iOS แขวน connection อยู่ดี ปล่อยให้ push รับช่วง
                phase == .active ? chat.start() : chat.stop()
            }

            // แชทกลุ่ม — overlay เลื่อนขึ้นจากล่าง (navbar หายแบบเด้งๆ)
            if chatOpen, profile.me?.groupId != nil {
                GroupChatView(store: chat, onClose: { chatOpen = false })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: chatOpen)
        .sheet(isPresented: $showNotifications) {
            NotificationsView(store: noti, token: session.token ?? "")
        }
        // MainTabView หายทั้งจอ (ล็อกเอาต์/สลับเป็น staff) — logout() ไม่แตะ profile.me เลย
        // ("ยังไม่ authenticated" แค่ session.user เป็น nil) ดังนั้น .onChange(of: profile.me?.groupId)
        // ไม่มีทางจับจังหวะนี้ได้ ต้อง stop() ตรงนี้ ไม่งั้น syncLoop ที่กำลังวิ่งอยู่ (ถือ self ไว้แน่นระหว่าง
        // await) ไม่มีวันถูกเก็บขยะ กลายเป็น orphan ยิง long-poll ด้วย token เก่าไปเรื่อยๆ
        .onDisappear { chat.stop() }
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
