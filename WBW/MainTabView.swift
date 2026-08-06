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
    // ปุ่ม SOS อยู่นอก TabView (ดูคอมเมนต์ที่ .overlay ข้างล่าง) ต้องมี store เดียวคงอยู่ข้ามการสลับ
    // แท็บทั้งหมด — สร้างที่นี่แทนที่จะสร้างในตัว SOSButton เอง ไม่งั้นสลับแท็บ (ซึ่ง MainTabView ไม่ได้
    // สร้างใหม่ แต่ SOSButton ก็ไม่ได้อยู่ใต้แท็บใดแท็บหนึ่งอยู่แล้ว) จะไม่มีปัญหานี้จริงๆ ก็ตาม —
    // แต่ยังต้องสร้างที่นี่เพื่อให้ .fullScreenCover ข้างล่างอ่าน store เดียวกันกับที่ SOSButton ยิง raise()
    @StateObject private var sos = SOSStore()
    @State private var tab = 0
    @State private var chatOpen = false
    @State private var showNotifications = false
    // จอสถานะ SOS เต็มจอ — Bool ตรงๆ ไม่ใช่ binding ที่คำนวณจาก sos.status เพราะเคสที่ปิดแล้ว
    // (closed) ต้องปิดจอได้ด้วยปุ่ม "ปิดหน้านี้" (ดู SOSStatusView) โดยไม่ต้องล้าง sos.status ไปด้วย —
    // ถ้าผูกตรงกับ status != nil การกดปิดจะไม่มีผลอะไรเพราะ status ยังไม่ nil อยู่ดี
    @State private var showSOSStatus = false
    // ฐานที่กำลังเปิดหน้าให้ความเห็นอยู่ (nil = ไม่มีจอเปิด) — จุดบรรจบของทั้ง 4 ทางเข้า: แตะ push ตอน
    // แอปปิด (PendingPush → .openCheckinFeedback), push ตอนแอปเปิด, แตะการ์ดในหน้าแจ้งเตือน,
    // และ toast จาก poll 60 วิ · ทุกทางเข้าตั้งตัวแปรนี้ตัวเดียว ไม่มีทางลัดอื่นไป FeedbackView
    @State private var feedbackCheckpoint: FeedbackTarget?
    // ฐานที่ toast "ยึดไว้" ให้เด้ง (ว่าง = ไม่มี) — คัดลอกมาจาก progress.newlyPending ตอนมันเปลี่ยน
    // แทนที่จะให้ view อ่าน newlyPending ตรงๆ เพราะ newlyPending ค้างค่าเดิมไว้จนกว่า load รอบถัดไป
    // จะทับ (นานสุด 60 วิ) ถ้าอ่านตรงๆ toast จะค้างคาจอเป็นนาทีแทนที่จะเป็น 3.5 วิ
    //
    // การยึดไว้แบบนี้แลกมาด้วยความเสี่ยงว่าของที่ยึดจะ "เก่า" — ยึดตอน toast โผล่ไม่ได้ (เงื่อนไขอาจปิด
    // อยู่ ดู canShowCheckinToast) ระหว่างนั้นผู้ใช้อาจไปตอบฐานนั้นจากหน้าแจ้งเตือนเรียบร้อยแล้ว จึงต้อง
    // เช็คซ้ำตอนจะแสดงจริงว่าฐานยัง "รอประเมิน" อยู่ไหม ไม่ใช่เชื่อค่าที่ยึดไว้ (ดู liveToastBases)
    @State private var toastBases: [CheckinProgressItem] = []
    // checkpoint ที่ต้องไปมาร์คแจ้งเตือนว่าอ่านแล้ว แต่ตอนได้เรื่องมายังหาแถวนั้นใน noti.items ไม่เจอ —
    // เกิดได้สองแบบ: cold launch (.openCheckinFeedback ถูกโพสต์ก่อน noti.load() จะจบเสมอ ดูลำดับใน
    // .task) และแอปเปิดค้างอยู่ก่อนแล้ว (รายการโหลดไปตั้งแต่ก่อนที่ backend จะสร้างแถวนี้ด้วยซ้ำ) —
    // ลองใหม่ทุกครั้งที่รายการเปลี่ยน จนกว่าจะมาร์คได้จริง
    @State private var pendingReadCheckpoint: Int?
    // ฐานที่การ์ดในหน้าแจ้งเตือนสั่งให้เปิดฟอร์มต่อ — พักไว้จนกว่าชีตแจ้งเตือนจะปิดจบจริง
    // (ดูคอมเมนต์ที่ .sheet(isPresented:onDismiss:))
    @State private var pendingFeedbackFromNoti: Int?

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
            // ปุ่ม SOS ลอยมุมล่างขวา เหนือแถบแท็บ · แนบด้วย .overlay บน TabView เอง (ไม่ใช่ลูกของ
            // แท็บไหนสักแท็บ) จึงไม่หายไปและไม่รีสตาร์ตตอนสลับแท็บ ตรงกับที่ตั้งใจไว้ว่าอยู่นอก
            // TabView — แท็บมี 5 อันเต็มแล้ว เพิ่มอันที่ 6 แปลว่าต้องสลับแท็บก่อนกด ช้าและหาไม่เจอ
            // ตอนตกใจ (ดูคอมเมนต์เต็มที่ SOSButton) · zIndex เริ่มต้น (ไม่ตั้งเอง) วางไว้ใต้แบนเนอร์แชท
            // (zIndex 1) โดยตั้งใจ — แชทเต็มจอทับได้ตามปกติเหมือนที่มันทับเนื้อหาแท็บอื่นอยู่แล้ว
            // ส่วนตอนกดครบจริง SOSStatusView เปิดเป็น fullScreenCover ซึ่งอยู่เหนือทุกชั้นเสมอไม่ว่า
            // zIndex จะเป็นเท่าไหร่ ปุ่มจึงถูกบังสนิทระหว่างมีเคสเปิดอยู่โดยไม่ต้องเขียนโค้ดกันเอง
            .overlay(alignment: .bottomTrailing) {
                SOSButton(store: sos, token: session.token ?? "", showStatus: $showSOSStatus)
                    .padding(.trailing, 20)
                    .padding(.bottom, 90)
            }
            .task {
                // เรียกครั้งแรกตอน mount ด้วย ไม่ใช่แค่รอ onChange(tab)/onChange(chatOpen) ข้างล่าง —
                // host.suppressed อยู่ที่ host ซึ่งอายุยาวกว่า MainTabView instance นี้ (เช่น รอบก่อนออก
                // จากแท็บที่ไม่ใช่ Home/QR ทิ้ง suppressed = true ค้างไว้ แล้ว logout/login ใหม่ — instance
                // ใหม่นี้เริ่ม tab ที่ 0 จาก @State default แต่นั่นไม่ใช่ "การเปลี่ยนแปลง" ที่ onChange จับได้
                // เพราะไม่มี tab เก่าให้เทียบเลยด้วยซ้ำ — ไม่เรียกตรงนี้ suppressed จะค้างผิดจนกว่าจะมีคน
                // สลับแท็บจริงครั้งแรก ซึ่งอาจไม่เกิดเลยถ้าผู้ใช้อยู่ Home เฉยๆ ตั้งแต่ต้น)
                updateSceneGate()

                // มีเคส SOS ค้างจากรอบก่อน (relaunch) — SOSStore.init() กู้ draft/status ให้เห็นทันที
                // ในตัว แต่ไม่เริ่ม retry loop ให้เองโดยตั้งใจ (ดูคอมเมนต์ที่ resumeIfNeeded) เปิดจอ
                // สถานะและสั่งให้ไปต่อที่นี่ ก่อนงานโหลดปกติข้างล่าง — เคส SOS สำคัญกว่า badge ที่ยังไม่
                // อ่าน ไม่ await inline เพราะ resumeIfNeeded รอผลเน็ตได้นานเป็นสิบวิ (ทางเดียวกับที่
                // raise() เองก็ยิงผ่าน Task { } แยกจาก SOSButton ไม่ใช่ await ตรงๆ) บล็อกอยู่ตรงนี้จะดึง
                // การโหลด noti/profile/progress ทั้งหมดข้างล่างช้าตามไปด้วยทั้งที่ไม่เกี่ยวกันเลย
                if sos.status != nil { showSOSStatus = true }
                Task { await sos.resumeIfNeeded(token: session.token ?? "") }

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
                chat.configure(groupId: profile.me?.groupId, token: session.token ?? "",
                               myId: profile.me?.userId ?? "", context: context)
                // ความเห็นที่ค้างคิวไว้ตอนเน็ตหลุดรอบก่อน (ปิดแอปไปแล้วเปิดใหม่ = ไม่มี .active ให้จับ)
                // — ถ้าไม่ยิงตรงนี้ ของค้างจะรออีกทีตอนสลับแอปออกแล้วกลับมาเท่านั้น
                //
                // อยู่ท้ายสุดของลำดับ await ตั้งใจ: คิวมีได้ถึง ~8 ชิ้น = POST เรียงกันสูงสุด 8 รอบ
                // ถ้าวางไว้ก่อน chat.configure แชทจะเริ่มช้าตามไปด้วยทั้งที่ไม่เกี่ยวกันเลย (บนเน็ตแย่ๆ
                // ซึ่งเป็นสภาพเดียวกับที่ทำให้มีของค้างตั้งแต่แรก ยิ่งชัด)
                await feedback.flush(token: session.token ?? "")
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
                // ยังไม่เจอแถวที่จะมาร์ค = จำไว้ลองใหม่ (ดูคอมเมนต์ที่ pendingReadCheckpoint)
                if !markFeedbackNotiRead(checkpointId: id) { pendingReadCheckpoint = id }
                PendingPush.clear()   // รับสดแล้ว — เคลียร์กัน mount ถัดไปดึงไปเล่นซ้ำ (ดู PendingPush.clear())
            }
            // push ขอความเห็นมาถึงตอนแอปเปิดอยู่ — willPresent กดของระบบทิ้งไปแล้ว ต้องมีของแทนจริงๆ
            // ให้เห็น ไม่ใช่เงียบไปจนกว่า poll รอบถัดไป (นานสุด 60 วิ) · progress ใหม่พา toast เช็คอินมา
            // ผ่าน newlyPending ส่วนรายการแจ้งเตือนใหม่พา badge กระดิ่งมา (ดู AppDelegate.willPresent)
            .onReceive(NotificationCenter.default.publisher(for: .checkinFeedbackArrived)) { _ in
                Task {
                    await progress.load(token: session.token ?? "")
                    await noti.load(token: session.token ?? "")
                }
            }
            // รายการแจ้งเตือนเปลี่ยน (โหลดครั้งแรกจบ หรือโหลดใหม่แล้วได้ของเพิ่ม) — ถ้ามี push ค้างรอ
            // มาร์คอยู่ ลองใหม่ · ค้างไว้จนกว่าจะมาร์คได้จริง ไม่ล้างทิ้งตอนลองแล้วพลาด เพราะเคสที่ต้อง
            // การคือ "แถวยังมาไม่ถึง" ซึ่งแก้ด้วยการรอรอบถัดไปเท่านั้น (ดูคอมเมนต์ที่ pendingReadCheckpoint)
            .onChange(of: noti.items) { _, _ in
                guard let cp = pendingReadCheckpoint, markFeedbackNotiRead(checkpointId: cp) else { return }
                pendingReadCheckpoint = nil
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
                    //
                    // โหลดรายการแจ้งเตือนด้วย: เส้นทางที่พบบ่อยที่สุดของ push คือ "แตะตอนแอปอยู่หลัง"
                    // ซึ่งพา .openCheckinFeedback มาก่อนที่รายการจะมีแถวนั้น (โหลดล่าสุดเกิดตั้งแต่ก่อน
                    // backend สร้างแถว) — ไม่โหลดใหม่ตรงนี้ก็ไม่มีอะไรให้ retry ของ pendingReadCheckpoint
                    // จับได้เลย badge กระดิ่งจะค้างเลขของเรื่องที่ผู้ใช้จัดการไปแล้วจนกว่าจะเปิดหน้าประกาศ
                    Task {
                        await progress.load(token: session.token ?? "")
                        await noti.load(token: session.token ?? "")
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
            if let base = liveToastBases.first, canShowCheckinToast {
                VStack {
                    CheckinToast(baseName: base.name, remaining: liveToastBases.count - 1, onTap: {
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
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: liveToastBases.first?.checkpointId)
        // สองชีตแขวนอยู่บน view เดียวกัน สั่งเปิดอันใหม่ในรอบเดียวกับที่เพิ่งสั่งปิดอันเก่าไม่ได้ —
        // UIKit ยังถือว่าอันเก่า present อยู่ ชีตใหม่ถูกทิ้งเงียบๆ (แตะการ์ดแล้วไม่มีอะไรเกิดขึ้นเลย)
        // ส่งไม้ต่อผ่าน onDismiss แทนการหน่วงเวลา: การ์ดแค่พักเลขฐานไว้แล้วปิดชีตตัวเอง ส่วนการเปิด
        // ฟอร์มเกิดตอน UIKit บอกเองว่าปิดจบแล้วจริง — ไม่ต้องเดาความยาว transition ซึ่งถ้าเดาพลาด
        // (iOS เปลี่ยน, ลด motion, เครื่องช้า) จะพังแบบเงียบสนิท คือแตะการ์ดแล้วไม่มีอะไรเกิดขึ้น
        .sheet(isPresented: $showNotifications, onDismiss: {
            guard let id = pendingFeedbackFromNoti else { return }
            pendingFeedbackFromNoti = nil
            feedbackCheckpoint = FeedbackTarget(id: id)
        }) {
            NotificationsView(store: noti, token: session.token ?? "", onOpenFeedback: { id in
                pendingFeedbackFromNoti = id
                showNotifications = false
            })
        }
        // หน้าให้ความเห็นต่อฐาน — จุดบรรจบของทั้ง 4 ทางเข้า (ดูคอมเมนต์ที่ feedbackCheckpoint ด้านบน)
        // ใช้ .sheet(item:) ไม่ใช่ isPresented เพื่อให้ค่า checkpoint กับการเปิดจอเป็นของชิ้นเดียวกัน
        // ไม่ใช่ Bool กับ Int ที่ต้องคอยตั้งให้ตรงกันเอง
        // ห่อด้วย FeedbackTarget แทนที่จะเติม Identifiable ให้ Int ทั้ง type — นั่นเป็น conformance ระดับ
        // stdlib ที่ทั้งโปรเจกต์ (และ SwiftUI เอง) มองเห็น ชนกับของที่มาทีหลังแน่นอน
        //
        // .id(target.id) จำเป็น: การตั้ง item ใหม่ทับตอนชีตยังเปิดอยู่ (push ฐานที่สองมาระหว่างฟอร์ม
        // ฐานแรกเปิดค้าง) เปลี่ยนแค่ property ที่ส่งเข้าไป ตัว view ยังเป็น identity เดิม @State
        // rating/comment/sent ข้างในจึงไม่รีเซ็ต = draft ของฐาน A ไหลเข้าฟอร์มฐาน B · ผูก identity กับ
        // เลขฐานบังคับให้ SwiftUI สร้าง state ชุดใหม่ให้ตรงๆ แทนที่จะพึ่งว่า SwiftUI จะเลือก
        // dismiss+present ใหม่ให้เอง (พฤติกรรมที่ไม่มีสัญญาไว้และต่างกันตามเวอร์ชัน)
        //
        // แนบ environmentObject ตรงๆ ให้ session/progress/feedback แม้ sheet จะสืบทอด environment ของ
        // ผู้เปิดอยู่แล้วตามปกติของ SwiftUI — feedback เป็น @StateObject ที่ประกาศในไฟล์นี้เอง ไม่มีใคร
        // ประกาศไว้ให้จาก WBWApp (ทรงเดียวกับ chat) จึงต้องแนบเองแน่ๆ ส่วน session/progress แนบซ้ำกันสงสัย
        .sheet(item: $feedbackCheckpoint) { target in
            FeedbackView(checkpointId: target.id, onClose: { feedbackCheckpoint = nil })
                .id(target.id)
                .environmentObject(session)
                .environmentObject(progress)
                .environmentObject(feedback)
        }
        // จอสถานะ SOS เต็มจอทันทีที่กดครบ ไม่ใช่ toast — คนกดต้องเห็นว่าเกิดอะไรขึ้น และปุ่มยกเลิก/โทร
        // ต้องอยู่ตรงหน้า ไม่ใช่ค้นหาจากที่ไหน (ดูคอมเมนต์เต็มที่ SOSStatusView) · fullScreenCover ไม่รับ
        // swipe ปิดเองแบบ .sheet โดยธรรมชาติของมันเอง — ทางเดียวที่จอนี้ปิดได้คือ showSOSStatus ถูกตั้ง
        // false ตรงๆ ซึ่งเกิดได้จาก (1) ปุ่ม "ปิดหน้านี้"/dismiss() ข้างในตอนเคส closed หรือ (2)
        // .onChange(of: store.status) ข้างในตอนยกเลิกแบบยังไม่ถึงเซิร์ฟเวอร์ (status กลายเป็น nil ทันที)
        // — ไม่มีทางถูกปัดหลุดมือขณะเคสยังเปิดอยู่ (queued/received/onTheWay) เลย
        .fullScreenCover(isPresented: $showSOSStatus) {
            SOSStatusView(store: sos, token: session.token ?? "")
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
            // เคส SOS ที่ยังค้างอยู่ต้องล้างตอนล็อกเอาต์ ไม่งั้นบัญชีถัดไปบนเครื่องเดียวกันสืบทอดเคสของ
            // บัญชีก่อนหน้าไปโดยไม่รู้ตัว แล้วเคสนั้นถูกยิงต่อด้วย token ของบัญชีใหม่ (ดูคอมเมนต์ยาวที่
            // SOSStore.clearForLogout — ตัวมันเองบอกว่าจอที่เรียกต้องถามยืนยันก่อน ไม่ใช่ล้างเงียบๆ ซึ่ง
            // SettingsView ทำอยู่แล้วผ่าน .alert("ออกจากระบบใช่หรือไม่") ก่อนเรียก session.logout() ทุก
            // ทาง onDisappear นี้เป็นแค่ขั้นตอนกลไกที่ทำงานหลังผู้ใช้ยืนยันไปแล้ว ทรงเดียวกับ
            // chat.purgeForLogout()/progress.clear() ด้านบนทุกอย่าง คนละหน้าที่กับ FeedbackOutbox ที่
            // Session.logout() ล้างตรงๆ เพราะ Session ไม่ได้ถือ SOSStore ไว้เหมือนกัน)
            sos.clearForLogout()
        }
    }

    /// ผสมเงื่อนไขแท็บปัจจุบัน + จอแชทเปิดอยู่หรือเปล่า เป็นค่า host.suppressed เดียว (ดูคอมเมนต์ที่เรียกใช้)
    /// เขียน suppressed ไม่ใช่ enabled ตรงๆ อีกต่อไป — enabled เป็น derived property แล้ว (ดูคอมเมนต์ยาว
    /// ที่ ForestSceneHost.enabled) ตรงนี้แค่บอกว่า "แท็บ/จอแชทตอนนี้อนุญาตให้ฉากโชว์ไหม" เฉยๆ
    private func updateSceneGate() {
        host.suppressed = !((tab == 0 || tab == 4) && !chatOpen)
    }

    /// ฐานใน toastBases ที่ยัง "รอประเมิน" อยู่จริง ณ ตอนนี้ — toast อ่านตัวนี้ ไม่ใช่ toastBases ตรงๆ
    ///
    /// toastBases ถูกยึดไว้ตอน newlyPending เปลี่ยน ซึ่งอาจเป็นคนละจังหวะกับตอนที่ toast โผล่ได้จริง
    /// (canShowCheckinToast ปิดอยู่) ระหว่างที่ค้างอยู่ผู้ใช้ไปตอบฐานนั้นเสร็จแล้วก็ได้ — เช่น poll ยึด
    /// ฐาน N ไว้ตอนหน้าแจ้งเตือนเปิดคาอยู่ แล้วผู้ใช้แตะการ์ดของฐาน N ตอบจนจบ ปิดหน้าแจ้งเตือน ถ้าไม่
    /// เช็คซ้ำตรงนี้ toast จะเด้งว่า "แตะเพื่อให้คะแนนฐานนี้" ทั้งที่เพิ่งให้ไป และแตะแล้วได้ฟอร์มอ่าน
    /// อย่างเดียว · เช็คกับ progress เสมอ แทนที่จะพยายามล้าง latch ให้ทันทุกทางเข้า
    private var liveToastBases: [CheckinProgressItem] {
        toastBases.filter { progress.item(checkpointId: $0.checkpointId)?.answered == false }
    }

    /// toast เช็คอินโผล่ได้ไหมตอนนี้ — ไม่แทรกตอนมีจอแชท/ชีตเปิดคาอยู่ (ผู้ใช้กำลังทำอย่างอื่นค้าง และ
    /// ใต้ชีตก็มองไม่เห็นอยู่ดี) และไม่ซ้อน toast แชทที่เด้งอยู่ก่อน — สองอันวางตำแหน่งเดียวกันเป๊ะ
    /// ทับกันแล้วอ่านไม่ออกทั้งคู่
    ///
    /// อันที่ถูกกันไว้ *ก่อนได้โผล่เลย* ยังโผล่ต่อเองเมื่อเงื่อนไขเปิด (latch ยังอยู่ครบ) แต่อันที่โผล่ไป
    /// แล้วค่อยโดนกันกลางคัน (เปิดชีตทับ) หายถาวร — SwiftUI ยกเลิก .task ที่นับ 3.5 วิ, `try?` กลืน
    /// CancellationError แล้วโค้ดไหลไปถึง toastBases = [] ต่อ · ไม่แก้ตรงนี้เพราะ toast เป็นทางลัด
    /// ไม่ใช่ทางเดียว — เรื่องเดียวกันยังอยู่ในรายการแจ้งเตือนให้กดเข้าฟอร์มได้อยู่ดี
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
    /// คืน false เมื่อยังหาแถวที่ยังไม่อ่านของฐานนี้ไม่เจอ — ผู้เรียกเก็บไว้ลองใหม่เอง (ดู
    /// pendingReadCheckpoint) ไม่เจอได้ทั้งตอนรายการยังไม่โหลด และตอนโหลดไปแล้วแต่แถวเพิ่งถูกสร้าง
    /// ทีหลัง จึงไม่เช็ค noti.loaded ตรงนี้เลย
    @discardableResult
    private func markFeedbackNotiRead(checkpointId: Int) -> Bool {
        guard let i = noti.items.firstIndex(where: {
            $0.feedbackCheckpointId == checkpointId && $0.isUnread
        }) else { return false }
        let id = noti.items[i].id
        // อัปเดตในเครื่องก่อน ไม่รอเน็ต — badge ต้องลดทันทีที่ผู้ใช้เข้าฟอร์ม ถ้าเน็ตพลาดก็แค่ค้าง
        // ไม่อ่านที่ฝั่ง server แล้ว markAllRead รอบหน้าที่เปิดหน้าแจ้งเตือนเก็บกวาดให้เอง
        noti.items[i].readAt = ISO8601DateFormatter().string(from: Date())
        Task { try? await APIClient.shared.markRead(token: session.token ?? "", id: id) }
        return true
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
