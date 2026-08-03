import SwiftUI
import SwiftData

/// แถบแท็บหลัก — native TabView icon-only · iOS 26 เรนเดอร์เป็น Liquid Glass + fongkaew lens (แบบ App Store) ให้อัตโนมัติ
struct MainTabView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var progress: CheckinProgressStore
    @EnvironmentObject var host: ForestSceneHost
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var noti = NotiStore()
    @StateObject private var chat = ChatSession()
    @StateObject private var feedback = FeedbackStore()
    @State private var tab = 0
    @State private var chatOpen = false
    @State private var showNotifications = false
    // ฐานที่กำลังเปิดหน้าให้ความเห็นอยู่ (nil = ไม่มีจอเปิด) — จุดบรรจบของทั้ง 4 ทางเข้า: แตะ push ตอน
    // แอปปิด (PendingPush → .openCheckinFeedback), push ตอนแอปเปิด, แตะการ์ดในหน้าแจ้งเตือน,
    // และ toast จาก poll 60 วิ · ทุกทางเข้าตั้งตัวแปรนี้ตัวเดียว ไม่มีทางลัดอื่นไป FeedbackView
    @State private var feedbackCheckpoint: FeedbackTarget?
    // ฐานที่ toast กำลังเด้งอยู่ (ว่าง = ไม่มี) — คัดลอกมาจาก progress.newlyPending ตอนมันเปลี่ยน
    // แทนที่จะให้ view อ่าน newlyPending ตรงๆ เพราะ newlyPending ค้างค่าเดิมไว้จนกว่า load รอบถัดไป
    // จะทับ (นานสุด 60 วิ) ถ้าอ่านตรงๆ toast จะค้างจอเป็นนาทีแทนที่จะเป็น 3.5 วิ และโผล่กลับมาเอง
    // ทันทีที่ผู้ใช้ปิดฟอร์ม ราวกับเพิ่งเช็คอินใหม่ทั้งที่เพิ่งตอบไป
    @State private var toastBases: [CheckinProgressItem] = []
    // checkpoint ที่ต้องไปมาร์คแจ้งเตือนว่าอ่านแล้ว แต่ตอนได้เรื่องมา noti ยังโหลดไม่เสร็จ (cold launch:
    // .openCheckinFeedback ถูกโพสต์ก่อน noti.load() จะจบเสมอ ดูลำดับใน .task) — ลองใหม่ตอนโหลดจบ
    @State private var pendingReadCheckpoint: Int?

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
                // เรียกครั้งแรกตอน mount ด้วย ไม่ใช่แค่รอ onChange(tab)/onChange(chatOpen) ข้างล่าง —
                // host.suppressed อยู่ที่ host ซึ่งอายุยาวกว่า MainTabView instance นี้ (เช่น รอบก่อนออก
                // จากแท็บที่ไม่ใช่ Home/QR ทิ้ง suppressed = true ค้างไว้ แล้ว logout/login ใหม่ — instance
                // ใหม่นี้เริ่ม tab ที่ 0 จาก @State default แต่นั่นไม่ใช่ "การเปลี่ยนแปลง" ที่ onChange จับได้
                // เพราะไม่มี tab เก่าให้เทียบเลยด้วยซ้ำ — ไม่เรียกตรงนี้ suppressed จะค้างผิดจนกว่าจะมีคน
                // สลับแท็บจริงครั้งแรก ซึ่งอาจไม่เกิดเลยถ้าผู้ใช้อยู่ Home เฉยๆ ตั้งแต่ต้น)
                updateSceneGate()

                // push ที่แตะไว้ตอนแอปยังไม่ทันเปิด (cold launch) — didReceive มักโพสต์ก่อนหน้านี้จะติดตั้ง
                // .onReceive ทัน (มีสแปลชคั่นก่อนถึงจะ mount MainTabView) โพสต์ทิ้งไปเงียบๆ ไม่มีคนรับ ดึงมา
                // โพสต์ซ้ำตรงนี้ — .onReceive ติดมากับ body ก่อน .task เริ่มเสมอ รับได้แน่นอน
                if let pending = PendingPush.consume() {
                    NotificationCenter.default.post(name: pending.name, object: nil, userInfo: pending.info)
                }
                // โหลดจำนวนที่ยังไม่อ่านไว้โชว์ badge ตั้งแต่เข้าแอป
                await noti.load(token: session.token ?? "")
                await profile.load(token: session.token ?? "")
                // ความคืบหน้าเช็คอิน — คุมขนาดต้นไม้ที่ Home (Task 9)
                await progress.load(token: session.token ?? "")
                // ความเห็นที่ค้างคิวไว้ตอนเน็ตหลุดรอบก่อน (ปิดแอปไปแล้วเปิดใหม่ = ไม่มี .active ให้จับ)
                // — ถ้าไม่ยิงตรงนี้ ของค้างจะรออีกทีตอนสลับแอปออกแล้วกลับมาเท่านั้น
                await feedback.flush(token: session.token ?? "")
                chat.configure(groupId: profile.me?.groupId, token: session.token ?? "",
                               myId: profile.me?.userId ?? "", context: context)
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "uitestChat") { chatOpen = true }
                // เปิดหน้าแจ้งเตือนตรงๆ โดยไม่ต้องพึ่งปุ่มกระดิ่งจริง — ทรงเดียวกับ uitestChat ด้านบน
                // เป็นทางเดียวที่เข้าถึงหน้านี้ได้โดยไม่มี tap tooling ใช้ verify การ์ดขอความเห็น (Task 10)
                if UserDefaults.standard.bool(forKey: "uitestNotifications") { showNotifications = true }
                // เปิดหน้าให้ความเห็นตรงๆ ด้วย checkpoint id ที่ส่งมา — ทรงเดียวกับ uitestChat ด้านบน
                // checkpoint id จริงเริ่มที่ 1 เสมอ ใช้ 0/ไม่ส่งมาเป็นค่า "ไม่เปิด" ได้อย่างปลอดภัย
                // เป็นทางเดียวที่เปิด FeedbackView ได้ตรงๆ โดยไม่มี tap tooling (ทางเข้าจริงทั้ง 4 ทาง
                // ต้องมีเหตุมาจากข้างนอก: push, การ์ดที่แตะ, หรือฐานใหม่จาก poll)
                let uitestFeedbackId = UserDefaults.standard.integer(forKey: "uitestFeedback")
                if uitestFeedbackId > 0 { feedbackCheckpoint = FeedbackTarget(id: uitestFeedbackId) }
                // ปิดแชทเองหลัง N วิ (แอปยัง foreground อยู่) — จำลอง "ผู้ใช้ปิดจอแชทแต่ไม่ได้ปิดแอป"
                // แบบ headless เพราะไม่มี tap tooling ใช้เทส GroupChatView.onDisappear
                let closeAfter = UserDefaults.standard.double(forKey: "uitestChatCloseAfter")
                if closeAfter > 0 {
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(closeAfter * 1_000_000_000))
                        chatOpen = false
                    }
                }
                // จำลอง "แตะสลับแท็บ" แบบ headless (ไม่มี tap tooling ในสภาพแวดล้อมนี้ — ทรงเดียวกับ
                // uitestChatCloseAfter ด้านบน) ใช้ verify การสลับแท็บ "จริง" ในโปรเซสเดียวกัน ต่างจาก
                // -uitestTab (ตั้งค่าเริ่มต้นตอน launch เท่านั้น) ตรงที่นี่คือ transition สดๆ ระหว่างแอปรัน
                // อยู่ — จำเป็นสำหรับพิสูจน์บั๊กที่พึ่ง state ค้างข้าม transition (เช่น host.enabled ก่อนแก้
                // เป็น derived property ในรีวิวรอบนี้) เปิดแยกทีละหน้าด้วย simctl launch คนละรอบไม่มีทาง
                // reproduce บั๊กคลาสนี้เลย เพราะ host ถูกสร้างใหม่ทุกรอบ ไม่มี state ค้างให้ทดสอบ
                //
                // รูปแบบ: "<วินาทีนับจาก launch>:<เลขแท็บ>,<วินาที>:<เลขแท็บ>,..." เช่น "6:4,12:0"
                let tabSequence = UserDefaults.standard.string(forKey: "uitestTabSequence") ?? ""
                for step in tabSequence.split(separator: ",") {
                    let parts = step.split(separator: ":")
                    guard parts.count == 2, let at = Double(parts[0]), let target = Int(parts[1]) else { continue }
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(at * 1_000_000_000))
                        tab = target
                    }
                }
                #endif
            }
            .task {
                // poll สำรอง — push เป็นทางหลัก แต่ build ที่ไม่มี GoogleService-Info.plist
                // ปิด push ทั้งอัน และผู้ใช้ปฏิเสธสิทธิ์ก็มี · 60 วิคือจุดที่คนยืนอยู่ที่ฐาน
                // รอไม่นานเกินไป และผู้เข้าร่วม 2,000 คนคิดเป็น ~33 req/s ซึ่งรับไหว
                //
                // ไม่ต้องเก็บ handle มายกเลิกเอง — SwiftUI ยกเลิก .task ให้ตอน view หาย (ล็อกเอาต์) ·
                // ไม่หยุดตอนแอปลงหลัง แต่ timer ของแอปที่ถูก suspend ไม่เดินอยู่แล้ว และ
                // .onChange(of: scenePhase) ด้านล่างโหลดใหม่ให้ตอนกลับมา .active
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled else { break }
                    await progress.load(token: session.token ?? "")
                }
            }
            // ฐานใหม่โผล่ (จาก poll, จาก .active, หรือจาก reload หลังส่งความเห็น) — ยึดไว้เป็นของ
            // toast รอบนี้ · ข้าม [] เพราะนั่นแปลว่า "รอบนี้ไม่มีอะไรใหม่" ไม่ใช่ "ให้ปิด toast"
            // (toast ปิดตัวเองด้วย .task 3.5 วิ หรือตอนถูกแตะ) ถ้าเคลียร์ตามทุกครั้ง toast จะหายทันที
            // ที่ poll รอบถัดไปวิ่งพอดี
            .onChange(of: progress.newlyPending) { _, fresh in
                guard !fresh.isEmpty else { return }
                toastBases = fresh
            }
            // แตะ push ขอความเห็น (ทั้งแบบแอปปิดอยู่แล้วเล่นซ้ำจาก PendingPush และแบบรับสด)
            .onReceive(NotificationCenter.default.publisher(for: .openCheckinFeedback)) { note in
                guard let raw = note.userInfo?["checkpoint_id"] as? String, let id = Int(raw)
                else { return }   // payload ไม่มีเลขฐาน = เปิดฟอร์มเปล่าไม่ได้ ทิ้งเงียบๆ ดีกว่าเปิดผิดฐาน
                feedbackCheckpoint = FeedbackTarget(id: id)
                markFeedbackNotiRead(checkpointId: id)
                PendingPush.clear()   // รับสดแล้ว — เคลียร์กัน mount ถัดไปดึงไปเล่นซ้ำ (ดู PendingPush.clear())
            }
            // noti โหลดเสร็จหลังจากที่มี push ค้างรอมาร์คอยู่ — ลองใหม่ (ดูคอมเมนต์ที่ pendingReadCheckpoint)
            .onChange(of: noti.loaded) { _, done in
                guard done, let cp = pendingReadCheckpoint else { return }
                pendingReadCheckpoint = nil
                markFeedbackNotiRead(checkpointId: cp)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNotificationsTab)) { _ in
                showNotifications = true   // noti ไม่มี tab แล้ว → เปิดเป็น sheet
                // รับสดแล้ว (มีคน subscribe อยู่จริงตอน post) — เคลียร์ของที่ hold() พักไว้ กัน mount ถัดไป
                // (เช่น login บัญชีอื่นหลัง logout) ดึงไปเล่นซ้ำทั้งที่ไม่เกี่ยวกับบัญชีนั้นเลย
                PendingPush.clear()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openGroupChat)) { _ in
                // ไม่เช็ค profile.me?.groupId ตรงนี้ — cold launch: อาจถูกเรียกก่อน profile.load() (network
                // round trip ใน .task) จะจบ เช็คแล้วจะเป็น false เสมอ ทำให้ push ถูกทิ้งไปเงียบๆ overlay เอง
                // เช็คเงื่อนไขนี้ซ้ำอยู่แล้ว (ดูด้านล่าง) ซึ่ง re-evaluate เองเมื่อโปรไฟล์โหลดเสร็จภายหลัง —
                // ถ้าไม่มีกลุ่มจริงๆ ก็แค่ลงแท็บ 3 เฉยๆ ไม่มี overlay โผล่มา
                tab = 3
                chatOpen = true
                PendingPush.clear()   // รับสดแล้ว — เคลียร์กัน mount ถัดไปดึงไปเล่นซ้ำ (ดู PendingPush.clear())
            }
            .onChange(of: profile.me?.groupId) { _, gid in
                chat.configure(groupId: gid, token: session.token ?? "",
                               myId: profile.me?.userId ?? "", context: context)
            }
            .onChange(of: scenePhase) { _, phase in
                // ตั้งใจแยก 2 เงื่อนไข ไม่ใช้ else — .inactive (Control Center, สายเรียกเข้า, app switcher)
                // ไม่ได้แขวน socket จริง ต้องปล่อยให้ sync/heartbeat วิ่งต่อ มีแค่ .background เท่านั้นที่ iOS
                // แขวน connection จริง — ปล่อยให้ push รับช่วงตอนนั้น
                if phase == .active {
                    chat.start()
                    // กลับมา foreground — ความคืบหน้าอาจเปลี่ยนระหว่างที่แอปอยู่หลัง (เช็คอินฐานใหม่)
                    // และเน็ตอาจกลับมาแล้ว ลองส่งความเห็นที่ค้างคิวอีกรอบ
                    Task {
                        await progress.load(token: session.token ?? "")
                        await feedback.flush(token: session.token ?? "")
                    }
                }
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
            // เปิดฉากป่าเฉพาะแท็บที่มันเป็นพื้นหลังจริง (Home, QR) และเฉพาะตอนไม่มีจอแชททับเต็มจออยู่ — แท็บ
            // Map รัน MapLibre บน GPU อยู่แล้ว · SU RUN กับ Group ทับเต็มจอ ปล่อยให้ฉากวิ่งอยู่ข้างหลังคือเผา
            // แบตให้สิ่งที่ไม่มีใครเห็น (host.suppressed ยังถูกตั้ง false จาก .forestBackground ของ Home/QR
            // เองผ่าน wantsScene ด้วย onAppear/onDisappear — สองตัวนี้เป็นชั้นกันซ้ำที่จับเงื่อนไข chatOpen
            // ซึ่ง forestBackground มองไม่เห็น เพราะ Home ยังคง mount อยู่ใต้ GroupChatView ตอนแชทเปิดทับ
            // ไม่ได้ disappear จริง)
            //
            // เรียกผ่าน updateSceneGate() แทนที่จะใส่นิพจน์ `host.suppressed = !((t == 0 || t == 4) &&
            // !chatOpen)` ตรงๆ ใน closure ของ .onChange — วัดจริงแล้วว่าใส่ตรงๆ ทำให้ compiler พังด้วย
            // "unable to type-check this expression in reasonable time" (ยืนยันด้วย
            // -Xfrontend -warn-long-expression-type-checking=50: ใช้ ~1.5 วินาทีแล้วชนขีดจำกัดภายในของ
            // solver) แม้จะแยก .onChange ออกเป็น modifier เดี่ยวๆ ก็ยังพัง — ลองใส่ closure ว่างเปล่า
            // `{ _, _ in }` แทนแล้ว build ผ่านทันที พิสูจน์ว่าตัวนิพจน์บูลีนเองคือปัญหา ไม่ใช่ความยาวของ
            // modifier chain ย้ายนิพจน์ไปเป็นฟังก์ชันธรรมดาตัดปัญหาที่ root แทนที่จะเดาเพิ่ม
            .onChange(of: tab) { _, _ in updateSceneGate() }
            .onChange(of: chatOpen) { _, _ in updateSceneGate() }

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

            // แบนเนอร์เช็คอิน — ฐานที่เพิ่งโดนสแกน แตะแล้วเข้าหน้าให้คะแนนทันที (ทรงเดียวกับแบนเนอร์
            // แชทด้านบนทุกอย่าง: ตำแหน่ง, transition, zIndex, ปิดเองใน 3.5 วิ)
            if let base = toastBases.first, canShowCheckinToast {
                VStack {
                    CheckinToast(baseName: base.name, remaining: toastBases.count - 1, onTap: {
                        toastBases = []
                        feedbackCheckpoint = FeedbackTarget(id: base.checkpointId)
                    })
                    Spacer()
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
                .task(id: base.checkpointId) {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    toastBases = []
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: chatOpen)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: chat.incoming?.clientId)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toastBases.first?.checkpointId)
        .sheet(isPresented: $showNotifications) {
            NotificationsView(store: noti, token: session.token ?? "", onOpenFeedback: { id in
                showNotifications = false
                // หน่วงก่อนเปิดชีตที่สอง — สองชีตแขวนอยู่บน view เดียวกัน ถ้าสั่งเปิดอันใหม่ในรอบ
                // เดียวกับที่เพิ่งสั่งปิดอันเก่า UIKit ยังถือว่าอันเก่า present อยู่ ชีตใหม่จะถูกทิ้งเงียบๆ
                // (แตะการ์ดแล้วไม่มีอะไรเกิดขึ้นเลย) 0.35 วิคือความยาว dismiss transition มาตรฐาน
                Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    feedbackCheckpoint = FeedbackTarget(id: id)
                }
            })
        }
        // หน้าให้ความเห็นต่อฐาน — จุดบรรจบของทั้ง 4 ทางเข้า (ดูคอมเมนต์ที่ feedbackCheckpoint ด้านบน)
        // ใช้ .sheet(item:) ไม่ใช่ isPresented เพื่อให้ค่า checkpoint กับการเปิดจอเป็นของชิ้นเดียวกัน —
        // ตั้ง item ใหม่ทับตอนจอยังเปิดอยู่จึงเปลี่ยนฐานให้เองได้ ไม่ใช่ค้างฐานเก่าเพราะ Bool ไม่เปลี่ยน
        // ห่อด้วย FeedbackTarget แทนที่จะเติม Identifiable ให้ Int ทั้ง type — นั่นเป็น conformance ระดับ
        // stdlib ที่ทั้งโปรเจกต์ (และ SwiftUI เอง) มองเห็น ชนกับของที่มาทีหลังแน่นอน
        // แนบ environmentObject ตรงๆ ให้ session/progress/feedback แม้ sheet จะสืบทอด environment ของ
        // ผู้เปิดอยู่แล้วตามปกติของ SwiftUI — feedback เป็น @StateObject ที่ประกาศในไฟล์นี้เอง ไม่มีใคร
        // ประกาศไว้ให้จาก WBWApp (ทรงเดียวกับ chat) จึงต้องแนบเองแน่ๆ ส่วน session/progress แนบซ้ำกันสงสัย
        .sheet(item: $feedbackCheckpoint) { target in
            FeedbackView(checkpointId: target.id, onClose: { feedbackCheckpoint = nil })
                .environmentObject(session)
                .environmentObject(progress)
                .environmentObject(feedback)
        }
        // MainTabView หายทั้งจอ (ล็อกเอาต์เท่านั้น — RootView สลับ MainTabView/StaffScanView ตาม role บน
        // session.user ตัวเดียวกัน ไปไม่ถึง role ใหม่ได้โดยไม่ผ่าน logout()+login ก่อน) — logout() ไม่แตะ
        // profile.me เลย ("ยังไม่ authenticated" แค่ session.user เป็น nil) ดังนั้น
        // .onChange(of: profile.me?.groupId) ไม่มีทางจับจังหวะนี้ได้ ต้องเรียก purgeForLogout() ตรงนี้แทน
        // (stop() ตัวเองอยู่แล้วด้วย) ไม่งั้น syncLoop ที่กำลังวิ่งอยู่ (ถือ self ไว้แน่นระหว่าง await) ไม่มีวัน
        // ถูกเก็บขยะ กลายเป็น orphan ยิง long-poll ด้วย token เก่าไปเรื่อยๆ — purge เพิ่มเพราะบัญชีที่ 2 ที่
        // login เครื่องเดียวกันไม่ควรเห็นข้อความ/สืบทอด cursor ของบัญชีก่อนหน้า
        .onDisappear {
            chat.purgeForLogout()
            // ต้นไม้ของบัญชีนี้ต้องไม่ค้างให้บัญชีถัดไปเห็นตอน MainTabView ถูกสร้างใหม่หลัง login —
            // ตัว store ในหน่วยความจำล้างที่นี่ ส่วน cache บนดิสก์ล้างที่ Session.logout() (คนละที่กันเพราะ
            // Session ไม่ได้ถือ store ไว้ ดูคอมเมนต์ที่นั่น)
            progress.clear()
        }
    }

    /// ผสมเงื่อนไขแท็บปัจจุบัน + จอแชทเปิดอยู่หรือเปล่า เป็นค่า host.suppressed เดียว (ดูคอมเมนต์ที่เรียกใช้)
    /// เขียน suppressed ไม่ใช่ enabled ตรงๆ อีกต่อไป — enabled เป็น derived property แล้ว (ดูคอมเมนต์ยาว
    /// ที่ ForestSceneHost.enabled) ตรงนี้แค่บอกว่า "แท็บ/จอแชทตอนนี้อนุญาตให้ฉากโชว์ไหม" เฉยๆ
    private func updateSceneGate() {
        host.suppressed = !((tab == 0 || tab == 4) && !chatOpen)
    }

    /// toast เช็คอินโผล่ได้ไหมตอนนี้ — ไม่แทรกตอนมีจอแชท/ชีตเปิดคาอยู่ (ผู้ใช้กำลังทำอย่างอื่นค้าง และ
    /// ใต้ชีตก็มองไม่เห็นอยู่ดี) และไม่ซ้อน toast แชทที่เด้งอยู่ก่อน — สองอันวางตำแหน่งเดียวกันเป๊ะ
    /// ทับกันแล้วอ่านไม่ออกทั้งคู่ · อันที่ถูกกันไว้ไม่หาย มันโผล่ต่อเองเมื่อเงื่อนไขเปิด
    ///
    /// แยกเป็น property แทนที่จะใส่นิพจน์บูลีนยาวๆ ใน `if` ของ body — ไฟล์นี้มีประวัติทำ type-checker
    /// พังด้วยนิพจน์แบบนี้มาแล้ว (ดูคอมเมนต์ยาวที่ .onChange(of: tab))
    private var canShowCheckinToast: Bool {
        !chatOpen && !showNotifications && feedbackCheckpoint == nil && chat.incoming == nil
    }

    /// มาร์คแจ้งเตือนขอความเห็นของฐานนี้ว่าอ่านแล้ว — เส้นทาง push พาเข้าฟอร์มตรงๆ ไม่ผ่าน
    /// NotificationsView ซึ่งเป็นที่เดียวที่ markAllRead ทำงาน ไม่ทำตรงนี้ badge กระดิ่งจะค้างเลขของ
    /// เรื่องที่ผู้ใช้จัดการไปแล้ว
    ///
    /// หาไม่เจอ = จำไว้ลองใหม่ตอน noti โหลดเสร็จ (cold launch เข้าเคสนี้เสมอ ดู pendingReadCheckpoint)
    private func markFeedbackNotiRead(checkpointId: Int) {
        guard let i = noti.items.firstIndex(where: {
            $0.feedbackCheckpointId == checkpointId && $0.isUnread
        }) else {
            if !noti.loaded { pendingReadCheckpoint = checkpointId }
            return
        }
        let id = noti.items[i].id
        // อัปเดตในเครื่องก่อน ไม่รอเน็ต — badge ต้องลดทันทีที่ผู้ใช้เข้าฟอร์ม ถ้าเน็ตพลาดก็แค่ค้าง
        // ไม่อ่านที่ฝั่ง server แล้ว markAllRead รอบหน้าที่เปิดหน้าแจ้งเตือนเก็บกวาดให้เอง
        noti.items[i].readAt = ISO8601DateFormatter().string(from: Date())
        Task { try? await APIClient.shared.markRead(token: session.token ?? "", id: id) }
    }
}

/// ห่อ checkpoint id ให้ `.sheet(item:)` ใช้ได้ — Int ไม่ conform Identifiable เอง
/// (ดูคอมเมนต์ที่ .sheet(item:) ว่าทำไมไม่เติม conformance ให้ Int ตรงๆ)
private struct FeedbackTarget: Identifiable { let id: Int }

/// พื้นป่าเปล่า (Event/Voucher ยังไม่ออกแบบเนื้อหาใน DOI-APP)
struct ForestBlank: View {
    var body: some View {
        Color.clear
            .forestBackground(day: ForestMath.dayStill)
    }
}
