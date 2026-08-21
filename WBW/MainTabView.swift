import SwiftUI
import SwiftData

/// แถบแท็บหลัก — native TabView icon-only · iOS 26 เรนเดอร์เป็น Liquid Glass + fongkaew lens (แบบ App Store) ให้อัตโนมัติ
struct MainTabView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var progress: CheckinProgressStore
    @EnvironmentObject var checkpoints: CheckpointStore
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
    //
    // ไม่มี default value ตรงนี้ (ต่างจาก noti/chat/feedback ด้านบน) เพราะต้องส่ง currentUserId เข้าไป
    // ตอนสร้าง ซึ่งอ่านจาก UserDefaults ตรงๆ ผ่าน Session.currentUserIdFromDisk() ใน init() ด้านล่าง
    // ไม่ใช่จาก @EnvironmentObject session — @StateObject default-value expression ถูกประเมินก่อนที่
    // environment จะถูกฉีดเข้ามาตามลำดับของ SwiftUI เขียน session.user?.userId ตรงนี้ไม่ได้เลย (พบจาก
    // รีวิว Task 14 รอบสาม — ดูคอมเมนต์ยาวที่ SOSStore.init และ SOSDraft.ownerId ว่าทำไมต้องรู้เจ้าของ
    // ตั้งแต่ก่อน draft จะถูกกู้จาก outbox ด้วยซ้ำ ไม่ใช่รอถึง .task ตอน environment พร้อมแล้ว)
    @StateObject private var sos: SOSStore
    @State private var tab = 0
    // เส้นทางของแท็บกลุ่ม — ว่าง = อยู่ที่จอแชท · ถือไว้ที่นี่เพราะ push แจ้งเตือนและ toast
    // ต้องสั่งเด้งกลับรากได้จากข้างนอก GroupTabView
    @State private var groupPath: [GroupRoute] = []
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
    // เคส SOS ของเพื่อนที่กำลังเปิดจอให้ดูอยู่ (nil = ไม่มีจอเปิด) — จุดบรรจบของทั้ง 3 ทางเข้า: แตะ push
    // ตอนแอปปิด (PendingPush → .openSOSCase), push ตอนแอปเปิด (willPresent → .sosArrived → รีเฟรช
    // รายการ → ผู้ใช้แตะการ์ดเอง), และแตะการ์ดในหน้าแจ้งเตือนตรงๆ · ทุกทางเข้าตั้งตัวแปรนี้ตัวเดียว
    // ไม่มีทางลัดอื่นไป SOSFriendView — ทรงเดียวกับ feedbackCheckpoint ด้านบนทุกประการ
    @State private var sosFriendTarget: SOSFriendTarget?
    // เคส SOS ที่การ์ดในหน้าแจ้งเตือนสั่งให้เปิดจอต่อ — พักไว้จนกว่าชีตแจ้งเตือนจะปิดจบจริง (ทรงเดียวกับ
    // pendingFeedbackFromNoti ด้านบน เหตุผลเดียวกัน — ดูคอมเมนต์ที่ .sheet(isPresented:onDismiss:))
    @State private var pendingSOSFromNoti: Int64?
    // เคส SOS ที่ต้องไปมาร์คแจ้งเตือนว่าอ่านแล้ว แต่ตอนได้เรื่องมายังหาแถวนั้นใน noti.items ไม่เจอ —
    // ทรงเดียวกับ pendingReadCheckpoint ด้านบนทุกประการ เหตุผลเดียวกัน
    @State private var pendingReadSOSId: Int64?

    init() {
        // ดูคอมเมนต์ยาวที่ประกาศ @StateObject private var sos ด้านบนว่าทำไมต้องอ่านจากดิสก์ตรงนี้
        // แทนที่จะพึ่ง @EnvironmentObject session
        _sos = StateObject(wrappedValue: SOSStore(currentUserId: Session.currentUserIdFromDisk()))
        #if DEBUG
        _tab = State(initialValue: UserDefaults.standard.integer(forKey: "uitestTab"))
        // ตั้งเส้นทางของแท็บกลุ่มตั้งแต่ก่อนเรนเดอร์เฟรมแรก — เดิมตั้งใน `.task` ของ GroupTabView
        // ซึ่งยิงตอน root ยังเป็นหน้าจับกลุ่มอยู่ (profile ยังโหลดไม่เสร็จ) พอ profile มาถึงแล้ว root
        // สลับเป็นจอแชท NavigationStack ทิ้ง path ที่ push ไว้ ผลคือแฟลกไม่มีผลอะไรเลยแบบเงียบ ๆ
        if UserDefaults.standard.bool(forKey: "uitestGroupMembers") {
            // จอสมาชิกเข้าถึงได้สองทาง (จากหน้าจับกลุ่ม = แถบแท็บโชว์ / จากในแชท = แถบแท็บซ่อน)
            // ทางนี้คือทางที่สอง ซึ่งเป็นทางที่ระยะล่างกับแถบหัวจอต่างจากอีกทางหนึ่ง
            _groupPath = State(initialValue: [.home, .members])
        } else if UserDefaults.standard.bool(forKey: "uitestGroupHome") {
            _groupPath = State(initialValue: [.home])
        }
        #endif
    }

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                Tab(value: 0) { HomeView(noti: noti) } label: { Image(systemName: "house.fill") }
                Tab(value: 1) { Map3DScreen(isActive: tab == 1) } label: { Image(systemName: "map.fill") }
                // ลำดับแท็บตาม `HomeScaffold.kt` ของ Android: home · map · chat · activities
                // แล้วปุ่ม QR แยกออกมาข้างแถบ
                //
                // **SU RUN ออกจากแถบแท็บ** — Android ไม่มีแท็บนี้ แต่มีการ์ด "แข่งนับก้าว" ในจอ
                // กิจกรรม ซึ่งคือของสิ่งเดียวกันเป๊ะ · SU RUN จึงย้ายไปอยู่หลังการ์ดใบนั้นแทนที่จะ
                // ถูกลบทิ้ง (ดู ActivitiesTabView) — ฟีเจอร์ยังอยู่ครบ และตอบ Guideline 4.2 ได้
                // เหมือนเดิมเพราะจอยังมีของจริงให้กด
                Tab(value: 2) {
                    GroupTabView(chat: chat, path: $groupPath, onBack: { tab = 0 })
                } label: {
                    Image(systemName: profile.me?.groupId == nil ? "sharedwithyou" : "message.fill")
                }
                .badge(chat.unreadCount)
                Tab(value: 3) { ActivitiesTabView() } label: { Image(systemName: "calendar") }
                // QR แยกเป็นปุ่มเดี่ยว (role .search) — ปุ่มที่หน้าตาเป็น QR ควรผลิต QR ออกมา
                // ไม่ใช่เปิดกล้องไปอ่านของคนอื่น · ปลายทางคือ **บัตรผู้เข้าร่วม** ซึ่งมี QR อยู่บนนั้น
                // ตามที่ Android ทำ (`QrRoute = "profile"` ใน HomeScaffold.kt)
                Tab(value: 4, role: .search) {
                    // ปุ่ม SOS อยู่ในแท็บนี้แท็บเดียว ใต้การ์ดบัตร (ดูคอมเมนต์ที่ `.tint` ข้างล่าง)
                    ParticipantPassView(onBack: { tab = 0 },
                                        sos: sos,
                                        token: session.token ?? "",
                                        showSOSStatus: $showSOSStatus)
                } label: {
                    Image(systemName: "qrcode")
                }
            }
            .tint(Color.wbwGold)
            // **ปุ่ม SOS ไม่ได้ลอยอยู่ที่นี่แล้ว** ย้ายไปอยู่ใต้การ์ดบัตรในแท็บ QR แท็บเดียว
            // ตามคำขอของ Park (2026-08-21) — เดิมมันเป็น `.overlay(alignment: .bottomTrailing)`
            // บน TabView เอง จึงลอยอยู่ทั้ง 5 แท็บ
            //
            // เหตุผลเดิมที่วางไว้ตรงนี้ยังจริงทุกตัวอักษร และถูกแลกไปโดยตั้งใจ: หลังย้ายแล้ว
            // การกด SOS ต้องสลับแท็บ → เลื่อนลง (บัตรสูงกว่าจอ) → กดค้าง 3 วิ · และปุ่มเคยเป็น
            // ที่เดียวที่บอกว่ามีเคสเปิดค้างอยู่ แตะเดียวกลับเข้าจอสถานะได้จากทุกแท็บ
            // (`SOSButton.caseIsActive`) ซึ่งหายไปด้วย
            //
            // **`.fullScreenCover` ของจอสถานะยังอยู่ที่นี่ ห้ามย้ายตาม** — เคสเปิดค้างขณะผู้ใช้
            // อยู่แท็บอื่นเป็นเรื่องปกติ จอสถานะต้องทับได้ทุกแท็บ และ `.task` ข้างล่างก็เปิดมัน
            // จากตรงนี้ตอนเปิดแอปมาแล้วมีเคสค้าง
            //
            // ถ้าจะเอาทางกลับข้ามแท็บคืนโดยไม่เอาปุ่มกลับมา ทางที่ถูกคือแถบบาง ๆ ใต้หัวจอตอน
            // `sos.status?.isActive == true` ไม่ใช่เอาปุ่มมาลอยใหม่
            .task {
                // เรียกครั้งแรกตอน mount ด้วย ไม่ใช่แค่รอ onChange(of: tab) ข้างล่าง —
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

                // ขอสิทธิ์ตำแหน่งให้คนที่ "ล็อกอินค้างอยู่แล้ว" ด้วย — Session.save(_:) เป็นทางเดียวที่
                // เคยเรียก requestPermission() ซึ่งยิงตอนล็อกอินสำเร็จเท่านั้น คนที่ล็อกอินค้างอยู่ก่อน
                // อัปเดตมาเป็น build นี้ (คือเกือบทุกคนในวันงาน) จึงไม่มีทางถูกถามเลยสักครั้ง แล้ว
                // oneShot/cachedFix ทั้งคู่คืน nil เงียบๆ ตอน .notDetermined โดยไม่ขอสิทธิ์ให้ — กด SOS
                // ไปโดยไม่มีพิกัดติดไปด้วยและไม่มีอะไรบอก · เรียกทุกครั้งที่ mount ได้ปลอดภัย ขอเฉพาะ
                // ตอน .notDetermined เท่านั้น (ดู SOSLocator.requestPermissionIfNeeded)
                SOSLocator.shared.requestPermissionIfNeeded()

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
                // ชื่อฐานเปลี่ยนตอนแอดมินแก้ ซึ่งนาน ๆ ครั้ง — โหลดคู่กับ progress ที่จุดนี้พอ ไม่ต้องมีลูป poll ของตัวเอง
                await checkpoints.load(token: session.token ?? "")
                chat.configure(groupId: profile.me?.groupId, token: session.token ?? "",
                               myId: profile.me?.userId ?? "", context: context)
                // เรียกเองครั้งแรกตอน mount ด้วย — .onChange(of: chatVisible) ด้านล่างไม่ยิงให้ตอน mount
                // (ทรงเดียวกับ updateSceneGate() ด้านบน) เข้าแอปมาที่แท็บ 3 พร้อมกลุ่มอยู่แล้วเลยจะไม่มีใคร
                // บอก store ว่าจอเปิดอยู่ ถ้าไม่เรียกตรงนี้
                chat.setScreenVisible(chatVisible)
                // ความเห็นที่ค้างคิวไว้ตอนเน็ตหลุดรอบก่อน (ปิดแอปไปแล้วเปิดใหม่ = ไม่มี .active ให้จับ)
                // — ถ้าไม่ยิงตรงนี้ ของค้างจะรออีกทีตอนสลับแอปออกแล้วกลับมาเท่านั้น
                //
                // อยู่ท้ายสุดของลำดับ await ตั้งใจ: คิวมีได้ถึง ~8 ชิ้น = POST เรียงกันสูงสุด 8 รอบ
                // ถ้าวางไว้ก่อน chat.configure แชทจะเริ่มช้าตามไปด้วยทั้งที่ไม่เกี่ยวกันเลย (บนเน็ตแย่ๆ
                // ซึ่งเป็นสภาพเดียวกับที่ทำให้มีของค้างตั้งแต่แรก ยิ่งชัด)
                await feedback.flush(token: session.token ?? "")
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "uitestChat") { tab = 2 }
                // เปิดหน้าแจ้งเตือนตรงๆ โดยไม่ต้องพึ่งปุ่มกระดิ่งจริง — ทรงเดียวกับ uitestChat ด้านบน
                // เป็นทางเดียวที่เข้าถึงหน้านี้ได้โดยไม่มี tap tooling ใช้ verify การ์ดขอความเห็น (Task 10)
                if UserDefaults.standard.bool(forKey: "uitestNotifications") { showNotifications = true }
                // เปิดหน้าให้ความเห็นตรงๆ ด้วย checkpoint id ที่ส่งมา — ทรงเดียวกับ uitestChat ด้านบน
                // checkpoint id จริงเริ่มที่ 1 เสมอ ใช้ 0/ไม่ส่งมาเป็นค่า "ไม่เปิด" ได้อย่างปลอดภัย
                // เป็นทางเดียวที่เปิด FeedbackView ได้ตรงๆ โดยไม่มี tap tooling (ทางเข้าจริงทั้ง 4 ทาง
                // ต้องมีเหตุมาจากข้างนอก: push, การ์ดที่แตะ, หรือฐานใหม่จาก poll)
                let uitestFeedbackId = UserDefaults.standard.integer(forKey: "uitestFeedback")
                if uitestFeedbackId > 0 { feedbackCheckpoint = FeedbackTarget(id: uitestFeedbackId) }
                // จำลอง "แตะสลับแท็บ" แบบ headless (ไม่มี tap tooling ในสภาพแวดล้อมนี้) ใช้ verify การสลับแท็บ
                // "จริง" ในโปรเซสเดียวกัน ต่างจาก -uitestTab (ตั้งค่าเริ่มต้นตอน launch เท่านั้น) ตรงที่นี่คือ
                // transition สดๆ ระหว่างแอปรันอยู่ — จำเป็นสำหรับพิสูจน์บั๊กที่พึ่ง state ค้างข้าม transition
                // (เช่น host.enabled ก่อนแก้เป็น derived property ในรีวิวรอบนี้, และ chatVisible/heartbeat
                // ใน Task 5) เปิดแยกทีละหน้าด้วย simctl launch คนละรอบไม่มีทาง reproduce บั๊กคลาสนี้เลย
                // เพราะ host/chat ถูกสร้างใหม่ทุกรอบ ไม่มี state ค้างให้ทดสอบ
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
            // แตะ push เคส SOS ของเพื่อน (ทั้งแบบแอปปิดอยู่แล้วเล่นซ้ำจาก PendingPush และแบบรับสด) —
            // ทรงเดียวกับ .openCheckinFeedback ด้านบนทุกประการ
            .onReceive(NotificationCenter.default.publisher(for: .openSOSCase)) { note in
                guard let raw = note.userInfo?["sos_id"] as? String, let id = Int64(raw)
                else { return }   // payload ไม่มีเลขเคส = เปิดจอเปล่าไม่ได้ ทิ้งเงียบๆ ดีกว่าเปิดผิดเคส
                sosFriendTarget = SOSFriendTarget(id: id)
                // ยังไม่เจอแถวที่จะมาร์ค = จำไว้ลองใหม่ (ดูคอมเมนต์ที่ pendingReadSOSId)
                if !markSOSNotiRead(sosId: id) { pendingReadSOSId = id }
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
            // push เคส SOS ของเพื่อนมาถึงตอนแอปเปิดอยู่ — willPresent กดของระบบทิ้งไปแล้วเหมือนกัน (ดู
            // AppDelegate.willPresent) ไม่มี toast เฉพาะของ SOS แบบที่ checkin มี (toastBases/newlyPending)
            // รีเฟรชรายการแจ้งเตือนพอ ผู้ใช้เห็นการ์ดใหม่สีแดง + badge กระดิ่งขึ้นทันที แล้วแตะเข้าเอง
            // ได้ (เข้าทางการ์ดในรายการ ไม่ใช่ทางนี้เปิดจอให้ตรงๆ — เหตุผลเดียวกับ checkinFeedbackArrived
            // ด้านบน: push ที่มาถึงเฉยๆ ไม่ใช่การขออนุญาตแทรกจอที่ผู้ใช้กำลังใช้อยู่)
            .onReceive(NotificationCenter.default.publisher(for: .sosArrived)) { _ in
                Task { await noti.load(token: session.token ?? "") }
            }
            // รายการแจ้งเตือนเปลี่ยน (โหลดครั้งแรกจบ หรือโหลดใหม่แล้วได้ของเพิ่ม) — ถ้ามี push ค้างรอ
            // มาร์คอยู่ ลองใหม่ · ค้างไว้จนกว่าจะมาร์คได้จริง ไม่ล้างทิ้งตอนลองแล้วพลาด เพราะเคสที่ต้อง
            // การคือ "แถวยังมาไม่ถึง" ซึ่งแก้ด้วยการรอรอบถัดไปเท่านั้น (ดูคอมเมนต์ที่ pendingReadCheckpoint)
            .onChange(of: noti.items) { _, _ in
                if let cp = pendingReadCheckpoint, markFeedbackNotiRead(checkpointId: cp) {
                    pendingReadCheckpoint = nil
                }
                if let sid = pendingReadSOSId, markSOSNotiRead(sosId: sid) {
                    pendingReadSOSId = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNotificationsTab)) { _ in
                showNotifications = true   // noti ไม่มี tab แล้ว → เปิดเป็น sheet
                // รับสดแล้ว (มีคน subscribe อยู่จริงตอน post) — เคลียร์ของที่ hold() พักไว้ กัน mount ถัดไป
                // (เช่น login บัญชีอื่นหลัง logout) ดึงไปเล่นซ้ำทั้งที่ไม่เกี่ยวกับบัญชีนั้นเลย
                PendingPush.clear()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openGroupChat)) { _ in
                // ไม่เช็ค profile.me?.groupId ตรงนี้ — cold launch: อาจถูกเรียกก่อน profile.load() (network
                // round trip ใน .task) จะจบ เช็คแล้วจะเป็น false เสมอ ทำให้ push ถูกทิ้งไปเงียบๆ · ไม่เช็คก็
                // ปลอดภัย ถ้าไม่มีกลุ่มจริงๆ GroupTabView เองก็แค่โชว์หน้าจับกลุ่มแทนจอแชทที่แท็บ 3 อยู่ดี
                tab = 2
                groupPath = []   // เด้งกลับรากเสมอ ไม่ว่าก่อนหน้านี้จะค้าง push อยู่ที่หน้ากลุ่ม/สมาชิกแค่ไหน
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
            // โดนเอาออกจากกลุ่มระหว่าง sync (403) — เด้งกลับรากของแท็บกลุ่ม (ปิดจอย่อยที่ค้างอยู่ เช่น
            // หน้ากลุ่ม/สมาชิก ซึ่งอ้างอิงกลุ่มที่ไม่มีแล้ว) + โหลดโปรไฟล์ใหม่ (purge cache ทำใน
            // ChatSession ไปแล้วก่อนตั้ง kickedOut)
            .onChange(of: chat.kickedOut) { _, kicked in
                guard kicked else { return }
                groupPath = []
                chat.kickedOut = false
                Task { await profile.load(token: session.token ?? "") }
            }
            // เปิดฉากป่าเฉพาะแท็บที่มันเป็นพื้นหลังจริง (Home, QR) — แท็บ Map รัน MapLibre บน GPU อยู่แล้ว
            // ส่วน SU RUN กับ Group ทับเต็มจอ ปล่อยให้ฉากวิ่งอยู่ข้างหลังคือเผาแบตให้สิ่งที่ไม่มีใครเห็น
            // (host.suppressed ยังถูกตั้ง false จาก .forestBackground ของ Home/QR เองผ่าน wantsScene ด้วย
            // onAppear/onDisappear ตอนแท็บสลับ — สองตัวนี้เป็นชั้นกันซ้ำ)
            //
            // เรียกผ่าน updateSceneGate() แทนที่จะใส่นิพจน์ `host.suppressed = !(t == 0 || t == 4)` ตรงๆ ใน
            // closure ของ .onChange — ไฟล์นี้เคยพัง "unable to type-check this expression in reasonable
            // time" มาแล้วตอนนิพจน์มีเงื่อนไข chatOpen ร่วมด้วย (ก่อน Task 5 ตัด overlay/chatOpen ออก) ไม่
            // เสี่ยงลองย้ายกลับเข้า closure อีก ทิ้งไว้เป็นฟังก์ชันแยกเหมือนเดิม
            .onChange(of: tab) { _, _ in updateSceneGate() }
            // จุดเดียวที่เรียก setScreenVisible จาก MainTabView — ดูคอมเมนต์ที่ property chatVisible
            // ด้านล่างว่าทำไมต้องคำนวณเอง ไม่พึ่ง view lifecycle ของ GroupChatView
            .onChange(of: chatVisible) { _, visible in chat.setScreenVisible(visible) }

            // แบนเนอร์ในแอป — เงื่อนไขต้องเป็น !chatVisible ไม่ใช่ tab != 3 — ตั้งแต่ Task 5 แท็บ 3 มี
            // sub-navigation แล้ว (push ไปกลุ่มของฉัน/สมาชิกได้) tab == 2 ตอนนั้นไม่ได้แปลว่า "เห็นจอแชท
            // อยู่" อีกต่อไป ถ้าใช้ tab != 3 ตอนอยู่หน้ากลุ่มของฉัน/สมาชิก (tab ยังเป็น 3, chatVisible
            // false) เงื่อนไขนี้จะเป็น false ทำให้ toast ไม่โผล่ — chat.incoming ที่ตั้งไว้ (ChatSession
            // เห็นว่าจอไม่ visible แล้ว) เลยไม่มี .task(id:) มาเคลียร์ให้ ค้างเป็น latch ไปเรื่อยๆ จนกว่าจะ
            // สลับแท็บออกไปแล้วโผล่มาแบบข้อความเก่า
            if let m = chat.incoming, !chatVisible {
                VStack {
                    ChatToast(message: m, photoUrl: nil, onTap: {
                        chat.incoming = nil
                        tab = 2
                        groupPath = []
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
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: chat.incoming?.clientId)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: liveToastBases.first?.checkpointId)
        // สองชีตแขวนอยู่บน view เดียวกัน สั่งเปิดอันใหม่ในรอบเดียวกับที่เพิ่งสั่งปิดอันเก่าไม่ได้ —
        // UIKit ยังถือว่าอันเก่า present อยู่ ชีตใหม่ถูกทิ้งเงียบๆ (แตะการ์ดแล้วไม่มีอะไรเกิดขึ้นเลย)
        // ส่งไม้ต่อผ่าน onDismiss แทนการหน่วงเวลา: การ์ดแค่พักเลขฐานไว้แล้วปิดชีตตัวเอง ส่วนการเปิด
        // ฟอร์มเกิดตอน UIKit บอกเองว่าปิดจบแล้วจริง — ไม่ต้องเดาความยาว transition ซึ่งถ้าเดาพลาด
        // (iOS เปลี่ยน, ลด motion, เครื่องช้า) จะพังแบบเงียบสนิท คือแตะการ์ดแล้วไม่มีอะไรเกิดขึ้น
        .sheet(isPresented: $showNotifications, onDismiss: {
            if let id = pendingFeedbackFromNoti {
                pendingFeedbackFromNoti = nil
                feedbackCheckpoint = FeedbackTarget(id: id)
            } else if let id = pendingSOSFromNoti {
                pendingSOSFromNoti = nil
                sosFriendTarget = SOSFriendTarget(id: id)
            }
        }) {
            NotificationsView(store: noti, token: session.token ?? "", onOpenFeedback: { id in
                pendingFeedbackFromNoti = id
                showNotifications = false
            }, onOpenSOS: { id in
                pendingSOSFromNoti = id
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
                .environmentObject(checkpoints)
                .environmentObject(feedback)
        }
        // จอที่เพื่อนในกลุ่มเห็นเมื่อมีคนกด SOS — .sheet ไม่ใช่ .fullScreenCover เหมือน SOSStatusView
        // ด้านล่าง โดยตั้งใจ: นี่คือจอของ "เพื่อน" ไม่ใช่จอของตัวเองที่กำลังรอความช่วยเหลืออยู่ — อ่านแล้ว
        // ปัดปิดได้ปกติ ไม่มีปุ่มยกเลิก/โทรฉุกเฉินที่ต้องบังคับให้เต็มจอเหมือนตอนเป็นคนกดเอง (ทรงเดียวกับ
        // FeedbackView ด้านบน ซึ่งก็เป็น .sheet เหมือนกัน)
        //
        // .id(target.id) ด้วยเหตุผลเดียวกับ FeedbackView ด้านบน: กลุ่มเดียวกันมีมากกว่าหนึ่งเคสเปิดพร้อม
        // กันได้จริง (สเปกไม่ได้จำกัดไว้) เคสที่สองมาระหว่างจอของเคสแรกเปิดค้างต้องได้ @State ชุดใหม่
        // ทั้งชุด (sosCase/loadError) ไม่ใช่ของเคสแรกค้างอยู่ในจอที่ควรเป็นของเคสที่สอง
        .sheet(item: $sosFriendTarget) { target in
            SOSFriendView(sosId: target.id, token: session.token ?? "")
                .id(target.id)
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
            checkpoints.clear()
            // เคส SOS ที่ยังค้างอยู่ — ล้างหรือไม่ล้างขึ้นกับว่าออกจากระบบทางไหน ไม่ใช่ล้างเสมอ
            // (แก้จากรีวิว Task 14 รอบสอง: ที่นี่เคยเขียนว่า "ทุกทางยืนยันมาก่อนแล้ว" ซึ่งไม่จริง —
            // .wbwUnauthorized ใน Session.init ยิง logout() เองทันทีที่เจอ 401 จากไหนก็ได้ในแอป
            // โดยไม่มีการยืนยันจากผู้ใช้เลย ถ้าล้างตรงนี้แบบไม่มีเงื่อนไข คนที่มีเคสฉุกเฉินเปิดอยู่จะ
            // ถูกเด้งไปหน้า login พร้อมเคสหายไปเงียบๆ กลางเหตุฉุกเฉิน) ส่ง session.lastLogoutWasAutomatic
            // ให้ SOSStore.handleLogout(automatic:) ตัดสินใจเอง — ล็อกเอาต์ที่ผู้ใช้กดเองผ่าน
            // SettingsView (ซึ่งมี .alert("ออกจากระบบใช่หรือไม่") ถามยืนยันก่อนเรียก session.logout()
            // เสมออยู่แล้ว) ยังล้างเหมือนเดิมทุกอย่าง ดูคอมเมนต์ยาวที่ handleLogout(automatic:) สำหรับ
            // เหตุผลเต็มและความเสี่ยงที่เหลืออยู่
            sos.handleLogout(automatic: session.lastLogoutWasAutomatic)
        }
    }

    /// แปลงแท็บปัจจุบันเป็นค่า host.suppressed เดียว (ดูคอมเมนต์ที่เรียกใช้)
    /// เขียน suppressed ไม่ใช่ enabled ตรงๆ — enabled เป็น derived property แล้ว (ดูคอมเมนต์ยาว
    /// ที่ ForestSceneHost.enabled) ตรงนี้แค่บอกว่า "แท็บตอนนี้อนุญาตให้ฉากโชว์ไหม" เฉยๆ
    private func updateSceneGate() {
        host.suppressed = !(tab == 0 || tab == 4)
    }

    /// จอแชทกำลังถูกมองเห็นจริงไหม — TabView เก็บ view ไว้ตอนสลับแท็บ และ NavigationStack push
    /// ทับก็ไม่รับประกันว่า onDisappear จะยิง จึงเชื่อ lifecycle ของ view ไม่ได้ ต้องคำนวณเอง
    /// ไม่คุมตรงนี้ = heartbeat วิ่งค้างตอนผู้ใช้ไปแท็บอื่น server เข้าใจว่ายังจ้อจออยู่แล้วไม่ส่ง
    /// push ให้เลย (พังเงียบสนิท ไม่มี error ให้เห็น)
    private var chatVisible: Bool {
        tab == 2 && profile.me?.groupId != nil && groupPath.isEmpty
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

    /// toast เช็คอินโผล่ได้ไหมตอนนี้ — ไม่แทรกตอนอยู่แท็บแชท/ชีตเปิดคาอยู่ (ผู้ใช้กำลังทำอย่างอื่นค้าง และ
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
    ///
    /// ใช้ !chatVisible ไม่ใช่ tab != 3 — เหตุผลเดียวกับแบนเนอร์แชทด้านบน: ตั้งแต่มี sub-navigation ใน
    /// แท็บกลุ่ม (Task 5) ผู้ใช้ที่อยู่หน้ากลุ่มของฉัน/สมาชิก (tab == 2 แต่ chatVisible == false) ควรเห็น
    /// toast เช็คอินได้ตามปกติ ไม่ใช่ถูกกันไว้เพราะบังเอิญ tab เท่ากับ 3
    private var canShowCheckinToast: Bool {
        !chatVisible && !showNotifications && feedbackCheckpoint == nil && chat.incoming == nil
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

    /// มาร์คแจ้งเตือน SOS เคสนี้ว่าอ่านแล้ว — ทรงเดียวกับ markFeedbackNotiRead ด้านบนทุกประการ เหตุผล
    /// เดียวกัน: เส้นทาง push พาเข้าจอเพื่อนตรงๆ ไม่ผ่าน NotificationsView ซึ่งเป็นที่เดียวที่ markAllRead
    /// ทำงาน ไม่ทำตรงนี้ badge กระดิ่งจะค้างเลขของเคสที่ผู้ใช้เปิดดูไปแล้ว
    ///
    /// คืน false เมื่อยังหาแถวที่ยังไม่อ่านของเคสนี้ไม่เจอ — ผู้เรียกเก็บไว้ลองใหม่เอง (ดู pendingReadSOSId)
    @discardableResult
    private func markSOSNotiRead(sosId: Int64) -> Bool {
        guard let i = noti.items.firstIndex(where: {
            $0.sosId == sosId && $0.isUnread
        }) else { return false }
        let id = noti.items[i].id
        noti.items[i].readAt = ISO8601DateFormatter().string(from: Date())
        Task { try? await APIClient.shared.markRead(token: session.token ?? "", id: id) }
        return true
    }
}

/// ห่อ checkpoint id ให้ `.sheet(item:)` ใช้ได้ — Int ไม่ conform Identifiable เอง
/// (ดูคอมเมนต์ที่ .sheet(item:) ว่าทำไมไม่เติม conformance ให้ Int ตรงๆ)
private struct FeedbackTarget: Identifiable { let id: Int }

/// ห่อเคส SOS id ให้ `.sheet(item:)` ใช้ได้ — ทรงเดียวกับ FeedbackTarget ด้านบนทุกประการ เหตุผลเดียวกัน
/// Int64 ไม่ conform Identifiable เอง (ชนิดเดียวกับ SOSCase.id — ดู APIClient+SOS.swift)
private struct SOSFriendTarget: Identifiable { let id: Int64 }

/// พื้นป่าเปล่า (Event/Voucher ยังไม่ออกแบบเนื้อหาใน DOI-APP)
struct ForestBlank: View {
    var body: some View {
        Color.clear
            .forestBackground(day: ForestMath.dayStill)
    }
}
