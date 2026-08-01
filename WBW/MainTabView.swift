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
                .badge(chat.unreadCount)
                // QR แยกเป็นปุ่มเดี่ยว (role .search) — My QR Code สำหรับเช็คอิน
                Tab(value: 4, role: .search) { MyQRCodeView() } label: { Image(systemName: "qrcode") }
            }
            .tint(Color.wbwGold)
            .task {
                // push ที่แตะไว้ตอนแอปยังไม่ทันเปิด (cold launch) — didReceive มักโพสต์ก่อนหน้านี้จะติดตั้ง
                // .onReceive ทัน (มีสแปลชคั่นก่อนถึงจะ mount MainTabView) โพสต์ทิ้งไปเงียบๆ ไม่มีคนรับ ดึงมา
                // โพสต์ซ้ำตรงนี้ — .onReceive ติดมากับ body ก่อน .task เริ่มเสมอ รับได้แน่นอน
                if let pending = PendingPush.consume() {
                    NotificationCenter.default.post(name: pending, object: nil)
                }
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
            .onReceive(NotificationCenter.default.publisher(for: .openGroupChat)) { _ in
                // ไม่เช็ค profile.me?.groupId ตรงนี้ — cold launch: อาจถูกเรียกก่อน profile.load() (network
                // round trip ใน .task) จะจบ เช็คแล้วจะเป็น false เสมอ ทำให้ push ถูกทิ้งไปเงียบๆ overlay เอง
                // เช็คเงื่อนไขนี้ซ้ำอยู่แล้ว (ดูด้านล่าง) ซึ่ง re-evaluate เองเมื่อโปรไฟล์โหลดเสร็จภายหลัง —
                // ถ้าไม่มีกลุ่มจริงๆ ก็แค่ลงแท็บ 3 เฉยๆ ไม่มี overlay โผล่มา
                tab = 3
                chatOpen = true
            }
            .onChange(of: profile.me?.groupId) { _, gid in
                chat.configure(groupId: gid, token: session.token ?? "",
                               myId: profile.me?.userId ?? "", context: context)
            }
            .onChange(of: scenePhase) { _, phase in
                // ตั้งใจแยก 2 เงื่อนไข ไม่ใช้ else — .inactive (Control Center, สายเรียกเข้า, app switcher)
                // ไม่ได้แขวน socket จริง ต้องปล่อยให้ sync/heartbeat วิ่งต่อ มีแค่ .background เท่านั้นที่ iOS
                // แขวน connection จริง — ปล่อยให้ push รับช่วงตอนนั้น
                if phase == .active { chat.start() }
                else if phase == .background { chat.stop() }
            }
            // โดนเอาออกจากกลุ่มระหว่าง sync (403) — ปิดจอแชท + โหลดโปรไฟล์ใหม่ (purge cache ทำใน
            // ChatSession ไปแล้วก่อนตั้ง kickedOut)
            .onChange(of: chat.kickedOut) { _, kicked in
                guard kicked else { return }
                chatOpen = false
                chat.kickedOut = false
                Task { await profile.load(token: session.token ?? "") }
            }

            // แชทกลุ่ม — overlay เลื่อนขึ้นจากล่าง (navbar หายแบบเด้งๆ)
            if chatOpen, profile.me?.groupId != nil {
                GroupChatView(store: chat, onClose: { chatOpen = false })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }

            // แบนเนอร์ในแอป — เฉพาะตอนไม่ได้เปิดจอแชท
            if let m = chat.incoming, !chatOpen {
                VStack {
                    ChatToast(message: m, photoUrl: nil, onTap: {
                        chat.incoming = nil
                        tab = 3
                        chatOpen = true
                    })
                    Spacer()
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
                .task(id: m.clientId) {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    chat.incoming = nil
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: chatOpen)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: chat.incoming?.clientId)
        .sheet(isPresented: $showNotifications) {
            NotificationsView(store: noti, token: session.token ?? "")
        }
        // MainTabView หายทั้งจอ (ล็อกเอาต์เท่านั้น — RootView สลับ MainTabView/StaffScanView ตาม role บน
        // session.user ตัวเดียวกัน ไปไม่ถึง role ใหม่ได้โดยไม่ผ่าน logout()+login ก่อน) — logout() ไม่แตะ
        // profile.me เลย ("ยังไม่ authenticated" แค่ session.user เป็น nil) ดังนั้น
        // .onChange(of: profile.me?.groupId) ไม่มีทางจับจังหวะนี้ได้ ต้องเรียก purgeForLogout() ตรงนี้แทน
        // (stop() ตัวเองอยู่แล้วด้วย) ไม่งั้น syncLoop ที่กำลังวิ่งอยู่ (ถือ self ไว้แน่นระหว่าง await) ไม่มีวัน
        // ถูกเก็บขยะ กลายเป็น orphan ยิง long-poll ด้วย token เก่าไปเรื่อยๆ — purge เพิ่มเพราะบัญชีที่ 2 ที่
        // login เครื่องเดียวกันไม่ควรเห็นข้อความ/สืบทอด cursor ของบัญชีก่อนหน้า
        .onDisappear { chat.purgeForLogout() }
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
