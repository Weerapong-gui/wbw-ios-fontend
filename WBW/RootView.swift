import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject private var host: ForestSceneHost
    @Environment(\.scenePhase) private var scenePhase
    @State private var splashDone = false

    init() {
        #if DEBUG
        // UI test: ข้าม splash ถ้า launch ด้วย -uitestToken หรือ -uitestLogin (โชว์ Login)
        let t = UserDefaults.standard.string(forKey: "uitestToken") ?? ""
        if !t.isEmpty || UserDefaults.standard.bool(forKey: "uitestLogin") {
            _splashDone = State(initialValue: true)
        }
        #endif
    }

    private enum Phase: Equatable { case intro, login, home }
    private var phase: Phase {
        if !splashDone { return .intro }
        return session.user != nil ? .home : .login
    }

    // staff/admin → หน้าสแกนเช็คอิน · participant → home ปกติ
    private var isStaff: Bool {
        #if DEBUG
        // จอเจ้าหน้าที่อยู่หลังบัญชี staff จริงซึ่งโหมดเดโม่ไม่ครอบ และ `-uitestToken` ปลอม
        // ก็ไปไม่ถึงเพราะ backend ตอบ 401 แล้วเด้งกลับหน้าล็อกอิน — ไม่มีทางถ่ายจอนี้ได้เลย
        // ถ้าไม่มีแฟลก · ทรงเดียวกับ `-uitestCredits`/`-uitestGroupMembers`
        if UserDefaults.standard.bool(forKey: "uitestStaffScreen") { return true }
        #endif
        let role = session.user?.role
        return role == "staff" || role == "admin"
    }

    var body: some View {
        ZStack {
            // ฉาก 3D ปิดอยู่ — พื้นทึบใต้ทุกอย่าง วางที่ชั้นเดียวกับที่ฉากเคยอยู่ (ดู Config.forest3D)
            // จำเป็นเพราะ TabRootOpaqueBackgroundRemover เจาะพื้นทึบของ per-tab container ทิ้ง สิ่งที่อยู่
            // หลังรูที่เจาะคือชั้นนี้ ไม่มีชั้นนี้จะเห็นพื้นดำของหน้าต่างแทนตรงขอบจอแท็บ QR
            if !Config.forest3D {
                AppBackdrop()
            }

            // ฉากป่า 3D ใต้ทุกอย่าง — mount ครั้งแรกที่มีหน้าขอใช้ฉาก (everEnabled) แล้วอยู่คงที่
            // ตลอดอายุแอป ไม่ถูก unmount/remount อีกเลยตอนสลับแท็บหรือเปลี่ยน phase (เดิม gate ด้วย
            // host.enabled ตรงๆ ทำให้ RealityView ถูกทำลาย+สร้างใหม่ทุกครั้งที่ enabled กลับเป็น
            // true — โหลด USDZ 571 ชิ้นซ้ำทุกรอบที่ออกจาก Home แล้วกลับมา ยืนยันด้วย log จริงใน
            // task-5-report.md: make() ถูกเรียก 2 ครั้งจากการ toggle enabled แค่รอบเดียว) ซ่อน/โชว์
            // ด้วย opacity แทน (เหมือน SceneHost.tsx ของเว็บที่คุมด้วย opacity/visibility ไม่ unmount)
            // .transition(.opacity) ที่เหลือไว้คุมเฉพาะตอน unmount จริงครั้งเดียวตอนโหลดพัง (loadFailed)
            if host.everEnabled && !host.loadFailed {
                ForestSceneView()
                    .opacity(host.enabled ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: host.enabled)
                    .transition(.opacity)

                // ชั้นทับฉาก (สครีม+เกรน+เครดิต) ต้องซ่อน/โชว์พร้อมฉากเป๊ะๆ — ไม่งั้นตอน
                // enabled=false (หน้าที่ไม่ใช้ฉาก) จะเหลือแต่สครีมทึบๆ ลอยคลุมทุกจอไว้เฉยๆ
                ForestOverlay(day: host.day, bottomClearance: host.bottomClearance)
                    .opacity(host.enabled ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: host.enabled)
                    .transition(.opacity)
            }

            switch phase {
            case .intro:
                IntroView(onFinished: { splashDone = true })
                    .transition(.opacity)
            case .login:
                LoginView()
                    .transition(.opacity)
            case .home:
                // home เผยขึ้นแบบ fade + scale เบาๆ (reveal) · แตกตามบทบาท
                //
                // StaffHomeView() (ไม่ใช่ inline หรือ computed property บน RootView เอง) โดยตั้งใจ —
                // RootView คงอยู่ตลอดอายุแอปโดยไม่เคย unmount/remount เลย (ดูคอมเมนต์ยาวที่
                // ForestSceneHost.enabled) ถ้า @StateObject ของ SOSStore/StaffSOSStore ถูกประกาศไว้บน
                // RootView ตรงๆ currentUserId ที่อ่านจากดิสก์ตอนสร้างจะถูก "แช่แข็ง" ไว้ที่ค่าแรกสุด
                // (มักเป็น "" เพราะ RootView สร้างก่อนมีใคร login ด้วยซ้ำ) ตลอดไป ไม่มีวันอัปเดตตามบัญชี
                // เจ้าหน้าที่ที่ login จริงในภายหลัง — เปิดช่องโหว่เดียวกับที่ SOSDraft.ownerId (Task 14
                // รอบสาม) มีไว้ปิด กลับมาใหม่: เจ้าหน้าที่ A ยิงเคสค้าง (เน็ตหลุด) แล้ว logout เจ้าหน้าที่ B
                // login บนเครื่องเดียวกัน — currentUserId ที่แช่แข็งไว้เท่ากันทั้งคู่ (อ่านจากจุดเดียวกัน
                // ตั้งแต่แรก) draft ของ A จะถูก B "รับเป็นของตัวเอง" แล้วยิงด้วย token ของ B ทันที
                //
                // StaffHomeView ถูกสร้างใหม่ทุกครั้งที่กิ่งนี้กลับมาแสดงผล เพราะ switch phase ทั้งก้อน
                // ออกจาก .home ก่อนเสมอเวลา logout จริง (session.user = nil → phase = .login) แล้วเพิ่ง
                // กลับมา .home ตอน login ใหม่สำเร็จ — SwiftUI ไม่ preserve identity/State ข้ามช่วงที่กิ่ง
                // หายไปแบบนี้ (คนละเรื่องกับการซ่อนด้วย opacity) init() ของมันจึงอ่าน
                // Session.currentUserIdFromDisk() สดใหม่ทุกครั้งที่เจ้าหน้าที่คนใหม่ login — ตรงกับที่
                // MainTabView.init() ทำกับผู้เข้าร่วมทุกประการ (โครงสร้างเดียวกันเป๊ะ: อยู่ใต้ switch
                // phase เดียวกัน)
                Group {
                    if isStaff {
                        StaffHomeView()
                    } else {
                        MainTabView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 1.04)),
                    removal: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
        // เริ่มถอดโมเดลแผนที่ 10 MB ทันทีที่ล็อกอินสำเร็จ — วัดจริงบน simulator ใช้เวลา 7.5 วิ
        // ยิงตอนนี้ได้เวลาหลายวินาทีก่อนผู้ใช้จะกดแท็บแผนที่ โดยไม่ไปกวนจอไหนเลย
        //
        // ไม่ยิงตอนแอป launch เพราะช่วงนั้นสแปลช/ฉากป่า/ฟอร์มล็อกอินแย่งทรัพยากรกันอยู่ และคนที่
        // ยังไม่ล็อกอินก็ไปถึงแท็บแผนที่ไม่ได้อยู่ดี · เจ้าหน้าที่ไม่โหลดเลย — `StaffScanView`
        // ไม่มีแท็บแผนที่ให้เปิด โหลดให้ก็เปล่าประโยชน์ล้วน
        //
        // ใช้ .task(id:) ไม่ใช่ .onChange — ต้องยิงตอน phase เป็น .home มาตั้งแต่เฟรมแรกด้วย
        // (เปิดแอปด้วย -uitestToken ข้ามสแปลชไปเลย ซึ่ง .onChange ไม่มี "การเปลี่ยน" ให้จับ)
        .task(id: phase) {
            guard phase == .home, !isStaff else { return }
            MapModelLoader.shared.preload()
        }
        // แอปลงพื้นหลัง — ไม่มีใครเห็นฉากอยู่ดี ไม่ว่าจะกำลังอยู่หน้าไหน · เขียน host.appActive ตรงๆ
        // ไม่ใช่ host.enabled — ต่างจากเดิมตรงที่มี branch .active ด้วย (เดิมมีแค่ "!= .active → false"
        // ไม่มีทางคืนเป็น true เลยตอนกลับมา foreground ค้าง false ถาวรจนกว่าจะบังเอิญมีจุดอื่นมา set
        // true ทับ) recompute() ที่ ForestSceneHost คำนวณ enabled จาก appActive ร่วมกับ wantsScene/
        // suppressed เองอยู่แล้ว ไม่ต้องเขียน enabled ตรงนี้อีกต่อไป (ดูคอมเมนต์ยาวที่ enabled)
        .onChange(of: scenePhase) { _, phase in
            host.appActive = (phase == .active)
        }
        // เจ้าหน้าที่: StaffScanView/StaffSOSView (ผ่าน StaffHomeView) ทับด้วยสีทึบ (Color.wbwInk) —
        // ไม่มีการรั่วของภาพฉากป่าออกมาให้เห็น แต่ RealityKit ยังคง composite ต่อเนื่องถ้า host.enabled
        // ยังเป็น true อยู่ (ยืนยันจริงตอน verify: มี session ผสมที่ participant เข้า Home มาก่อน — ตอนนั้น
        // everEnabled/enabled เป็น true ทั้งคู่ — แล้ว logout ไป login ใหม่เป็น staff แบบไม่ปิดแอป) เจ้าหน้าที่
        // เปิดจอสแกนค้างเป็นชั่วโมงในวันงาน ฉากที่วิ่งอยู่ข้างหลังกินแบตทั้งวันโดยไม่มีใครเห็นเลย — ปิดตรงนี้
        // เป็นสัญญาณตรงที่สุด ไม่ต้องพึ่ง onDisappear ของ Home/MainTabView (ซึ่งอาจไม่ทันถูกเรียกเสมอไปตาม
        // จังหวะที่ TabView สลับแท็บ ดูคอมเมนต์ที่ ForestSceneHost.swift เรื่อง per-tab root)
        //
        // เขียน host.suppressed ตรงๆ (ไม่ใช่ host.enabled) — ต่างจากเดิมตรงที่พอ staff กลับเป็น false
        // (เช่น logout จากจอเจ้าหน้าที่แล้ว login ใหม่เป็น participant) ฉากถูก "คืนสิทธิ์" ให้จริง แทนที่
        // จะค้าง false ตลอดไปเหมือนของเดิม (ของเดิมไม่มี branch คืนค่าเลย เขียนได้ทางเดียวคือ force off)
        // MainTabView.updateSceneGate() ก็เขียน suppressed ตัวเดียวกันนี้ แต่ไม่ชนกัน เพราะ MainTabView
        // ไม่ถูก mount เลยตอน isStaff เป็น true (ดูคอมเมนต์ที่ ForestSceneHost.suppressed)
        //
        // **host.suppressed เขียนเป็น staff ตรงๆ เท่านั้น ไม่มีสาขาไหนคำนวณจาก staffTab เพิ่ม** — เคย
        // พิจารณาผูก host.suppressed กับแท็บที่เลือกอยู่ของ StaffHomeView (เช่น "true เฉพาะตอนไม่ได้อยู่
        // แท็บสแกน") ด้วยความเข้าใจผิดว่านี่คือกลไกที่หยุดกล้อง แต่ host.suppressed คุมแค่ฉากป่า 3D
        // (RealityKit) เท่านั้น ไม่เกี่ยวอะไรกับ AVCaptureSession ของ StaffScanView เลย — ถ้าผูกแบบนั้นจริง
        // พอเจ้าหน้าที่สลับไปแท็บ SOS แล้วกลับมาแท็บสแกน suppressed จะกลายเป็น false ทำให้ฉากป่าที่ไม่มี
        // ใครเห็น (ถูกทับด้วย Color.wbwInk ทึบอยู่ดี) กลับมาวิ่งอีกครั้ง ขัดกับทั้งคอมเมนต์เดิมด้านบนที่บอกว่า
        // เจ้าหน้าที่ไม่ควรเห็นฉากเลยไม่ว่ากรณีใด และเป้าหมายเรื่องแบต/ความร้อนตรงๆ — comment เดิมนี้ครอบคลุม
        // ทุกจอของเจ้าหน้าที่อยู่แล้วไม่ว่าจะมีกี่แท็บ ไม่ต้องมีเงื่อนไขเพิ่มเรื่องแท็บเลย
        //
        // กล้องสแกน (แยกเรื่องกันคนละระบบ) หยุดเองผ่าน ScannerVC.viewWillDisappear (ดู
        // StaffScanView.swift) ซึ่งถูกเรียกจาก SwiftUI lifecycle ปกติตอน TabView ใน StaffHomeView
        // สลับออกจากแท็บ 0 — ทรงเดียวกับที่ ForestBackground พิสูจน์ไว้แล้วว่า onAppear ของแท็บใหม่มาก่อน
        // onDisappear ของแท็บเก่าเสมอ (ดูคอมเมนต์ยาวที่ ForestSceneHost.enabled) ไม่ต้องมีกลไกเพิ่มที่นี่
        .onChange(of: isStaff) { _, staff in
            host.suppressed = staff
        }
    }
}

/// หน้าจอเจ้าหน้าที่ทั้งหมด: สองแท็บ (สแกน QR / เคส SOS ของคนอื่น) + ปุ่ม SOS ของตัวเจ้าหน้าที่เอง
///
/// แยกเป็น struct ต่างหาก ไม่ใช่ฝัง @StateObject ไว้บน RootView ตรงๆ — ดูคอมเมนต์ยาวที่จุด mount
/// (RootView, switch phase, case .home) ว่าทำไม: ต้องมี identity ที่ถูกสร้างใหม่ทุกครั้งที่เจ้าหน้าที่
/// คนใหม่ login (เหมือนที่ MainTabView ทำกับผู้เข้าร่วม) ไม่ใช่แช่แข็ง currentUserId ไว้ค่าเดียวตลอดอายุแอป
private struct StaffHomeView: View {
    @EnvironmentObject var session: Session

    // สองแท็บ: สแกน QR (0) กับเคส SOS ของคนอื่น (1)
    //
    // เริ่มที่แท็บ SOS ได้ด้วย `-uitestStaffSOSCase` — ไม่มีตัวกดจอบนเครื่องนี้ ถ้าไม่เปิดให้ตรง
    // ก็ถ่ายจอเคสไม่ได้เลย (แฟลกเดียวกับที่ยัดเคสตัวอย่าง จะได้ไม่ต้องส่งสองตัว)
    @State private var staffTab = StaffHomeView.initialStaffTab
    // feed เคส SOS "ของคนอื่น" ที่เจ้าหน้าที่ต้องดู/รับ/ปิด — start()/stop() ผูกกับ .task/.onDisappear
    // ของจอนี้ทั้งก้อน (ด้านล่าง) ไม่ใช่ผูกกับว่าแท็บ SOS เปิดอยู่หรือเปล่า — เคสใหม่ต้องทับจอได้แม้
    // เจ้าหน้าที่กำลังก้มสแกน QR อยู่แท็บอื่น ซึ่งเป็นสถานการณ์หลักที่ฟีเจอร์นี้มีไว้รับมือ (ดูคอมเมนต์ยาวที่
    // StaffSOSStore) — สร้างใน init() ด้านล่าง ไม่ใช้ default-value ตรงนี้ เพราะต้องส่ง currentUserId
    // เข้าไปด้วย (กันเคสของตัวเจ้าหน้าที่เองไม่ให้มาเด้งจอทับซ้อนกับ SOSStatusView ของตัวเอง — ดูคอมเมนต์
    // ที่ StaffSOSStore.currentUserId และรีวิว Task 15)
    @StateObject private var sosStaff: StaffSOSStore
    // ปุ่ม SOS ของ "ตัวเจ้าหน้าที่เอง" — คนละเรื่องกับ sosStaff ข้างบนโดยสิ้นเชิง (นั่นคือ feed เคสของ
    // คนอื่น นี่คือ SOSStore ตัวเดิมจาก Task 12-14 ที่ใช้ตอนกดปุ่มของตัวเอง) เพิ่มเข้ามาตามข้อกำหนดที่ย้าย
    // มาจาก Task 14 รอบสอง: "เจ้าหน้าที่ก็ล้มบนดอยได้เหมือนผู้เข้าร่วมคนหนึ่ง" ต้องมีปุ่มลอยเดียวกันนี้ด้วย
    //
    // ต้องเป็นคนละ instance จาก sos ของ MainTabView เพราะ MainTabView ไม่ถูก mount เลยตอนเป็นเจ้าหน้าที่
    // ไม่มี SOSStore ก้อนไหนให้ใช้ร่วมกันได้อยู่แล้วโดยโครงสร้าง
    //
    // เจ้าหน้าที่ไม่มีแถว participant_profile — เคสที่ raise() ผ่านตัวนี้จะได้ group_id เป็น NULL
    // ฝั่งเซิร์ฟเวอร์ (ไม่มีกลุ่มให้แจ้งเตือน) ตรงตามสเปกที่ตั้งใจไว้ ไม่ใช่บั๊กที่ต้องแก้
    @StateObject private var staffOwnSOS: SOSStore
    // จอสถานะเต็มจอของ "เคสตัวเจ้าหน้าที่เอง" — Bool ตรงๆ ทรงเดียวกับ MainTabView.showSOSStatus
    // ทุกประการ (ดูคอมเมนต์ที่นั่นว่าทำไมต้องเป็น Bool แยก ไม่ใช่ binding ที่คำนวณจาก status)
    @State private var showStaffSOSStatus = false
    /// จออธิบายก่อนกล่องขอสิทธิ์ตำแหน่งฝั่งเจ้าหน้าที่ — ดู `LocationPrimer`
    @State private var showStaffLocationPrimer = false

    /// แท็บเริ่มต้นของจอเจ้าหน้าที่ — 1 (เคส SOS) เฉพาะตอนถ่ายภาพยืนยันด้วย `-uitestStaffSOSCase`
    static var initialStaffTab: Int {
        #if DEBUG
        let raw = UserDefaults.standard.string(forKey: "uitestStaffSOSCase") ?? ""
        if !raw.isEmpty && raw != "NO" { return 1 }
        #endif
        return 0
    }

    init() {
        // ดูคอมเมนต์ยาวที่ MainTabView.init() ว่าทำไมต้องอ่าน currentUserId จากดิสก์ตรงนี้ตรงๆ
        // แทนที่จะพึ่ง @EnvironmentObject session — เหตุผลเดียวกันเป๊ะ (@StateObject default-value
        // ถูกประเมินก่อน environment จะพร้อมใช้งานตามลำดับของ SwiftUI) สดใหม่ทุกครั้งเพราะ struct นี้
        // ทั้งก้อนถูกสร้างใหม่ทุกครั้งที่เจ้าหน้าที่คนใหม่ login (ดูคอมเมนต์ที่จุด mount ใน RootView)
        //
        // อ่านครั้งเดียวแล้วส่งให้ทั้งสอง store — sosStaff ใช้ตัดเคสของตัวเองออกจากการเด้งจอทับ (ดู
        // StaffSOSStore.currentUserId) staffOwnSOS ใช้ตราความเป็นเจ้าของ draft (ดู SOSDraft.ownerId)
        // คนละหน้าที่กันแต่ต้องเป็นค่าเดียวกัน — คนละ read สองครั้งจะเสี่ยงไม่ตรงกันถ้า UserDefaults
        // เปลี่ยนกลางอากาศระหว่างสอง read (ในทางปฏิบัติไม่เกิด แต่ไม่มีเหตุผลต้องเสี่ยงเลย)
        let uid = Session.currentUserIdFromDisk()
        _staffOwnSOS = StateObject(wrappedValue: SOSStore(currentUserId: uid))
        _sosStaff = StateObject(wrappedValue: StaffSOSStore(currentUserId: uid))
    }

    var body: some View {
        TabView(selection: $staffTab) {
            Tab(value: 0) { StaffScanView() } label: { Image(systemName: "qrcode.viewfinder") }
            Tab(value: 1) { StaffSOSView(store: sosStaff, token: session.token ?? "") }
                label: { Image(systemName: "sos") }
                .badge(sosStaff.openCount)
        }
        .tint(Color.wbwGold)
        // ปุ่ม SOS ของตัวเจ้าหน้าที่เอง — อยู่นอก TabView โดยตั้งใจ เหมือนที่ MainTabView ทำกับ
        // ผู้เข้าร่วม (ดูคอมเมนต์ที่ SOSButton และ task-14-brief: "ต้องอยู่นอก TabView ไม่งั้นหายไปตอน
        // สลับแท็บ") เหตุผลเดิมยังใช้ได้แต่จำเป็นกว่าเดิมสำหรับเจ้าหน้าที่: ถ้าฝังปุ่มนี้ไว้ใน
        // StaffSOSView (แท็บ 1) เฉยๆ เจ้าหน้าที่ที่ล้มระหว่างก้มสแกน QR (แท็บ 0) ต้องสลับแท็บเองก่อน
        // ถึงจะกดปุ่มได้ — ช้าและหาไม่เจอตอนตกใจ ตรงกับปัญหาเดิมที่ MainTabView หลีกเลี่ยงไปแล้วทุกประการ
        .overlay(alignment: .bottomTrailing) {
            SOSButton(store: staffOwnSOS, token: session.token ?? "", showStatus: $showStaffSOSStatus)
                .padding(.trailing, 20)
                .padding(.bottom, 30)
        }
        // จอสถานะของเคสตัวเจ้าหน้าที่เอง — ทรงเดียวกับ MainTabView.fullScreenCover(isPresented:
        // $showSOSStatus) ทุกประการ
        .fullScreenCover(isPresented: $showStaffSOSStatus) {
            SOSStatusView(store: staffOwnSOS, token: session.token ?? "")
        }
        // เจ้าหน้าที่มีปุ่ม SOS ของตัวเองเหมือนกัน จึงต้องเจอจออธิบายชุดเดียวกับผู้เข้าร่วม —
        // ทรงเดียวกับที่ MainTabView ทำทุกประการ (ดูคอมเมนต์ที่นั่น)
        .sheet(isPresented: $showStaffLocationPrimer) {
            LocationPrimerSheet()
                .presentationDetents([.medium, .large])
        }
        .task {
            guard LocationPrimer.shouldShowNow else { return }
            try? await Task.sleep(for: .seconds(1))
            guard LocationPrimer.shouldShowNow else { return }
            showStaffLocationPrimer = true
        }
        // เคสใหม่ของ "คนอื่น" เข้าตอนกำลังก้มสแกน QR — badge มุมจอไม่มีทางถูกเห็น ต้องทับทั้งจอ (ดู
        // คอมเมนต์ที่ StaffSOSStore.newCase) ใช้ .fullScreenCover(item:) ผูกตรงกับ $sosStaff.newCase —
        // ปิดจอนี้ (ผ่าน dismiss() ใน StaffSOSAlertView) แค่ตั้ง newCase กลับเป็น nil ไม่แตะ
        // sosStaff.cases เลย เคสยังอยู่ในแท็บ SOS ตามปกติ
        //
        // หมายเหตุที่ยอมรับไว้: ถ้าเคสของตัวเจ้าหน้าที่เอง (staffOwnSOS ด้านบน) กับเคสใหม่ของคนอื่น
        // (sosStaff) เกิดพร้อมกันพอดี fullScreenCover สองตัวนี้อาจแย่งกันเปิดในรอบเดียวกัน — SwiftUI
        // ไม่รับประกันว่าตัวที่สองจะได้เปิดถ้าตัวแรกกำลังเปิดอยู่ (ทรงเดียวกับปัญหาชีตซ้อนที่ MainTabView
        // เจอกับ showNotifications/feedbackCheckpoint) ยอมรับความเสี่ยงนี้ไว้ตรงๆ แทนที่จะรวมเป็น cover
        // เดียวด้วย enum เพราะเป็นเหตุการณ์คนละที่มาที่ไม่น่าเกิดพร้อมกันจริง และ badge/รายการเคสยังเห็น
        // ได้ปกติแม้ทับจอไม่ทัน ไม่ใช่ข้อมูลหายจริง
        //
        // .id(c.id) จำเป็น: เคสใหม่ตัวที่สองมาแทน newCase ระหว่างที่จอทับของเคสแรกยังเปิดค้างอยู่
        // (เคสสองใบเข้าใกล้กันในหน้าต่าง poll เดียวกัน) เปลี่ยนแค่ค่าที่ผูกกับ item ตัว view เองยังเป็น
        // identity เดิมถ้าไม่ผูก id ตรงๆ — StaffSOSAlertView ห่อ StaffSOSCard ซึ่งมี @State
        // showReasons (เปิด/ปิด confirmationDialog "ปิดเคสเพราะ") ค้างของเคสแรกไว้ได้ถ้า SwiftUI เลือก
        // reuse view instance แทนที่จะ dismiss+present ใหม่ (ทรงเดียวกับที่ MainTabView.sheet(item:
        // $feedbackCheckpoint) ต้องผูก .id(target.id) ไว้ก่อนแล้วด้วยเหตุผลเดียวกันเป๊ะ — ดูคอมเมนต์ที่นั่น)
        .fullScreenCover(item: $sosStaff.newCase) { c in
            StaffSOSAlertView(c: c, token: session.token ?? "", store: sosStaff)
                .id(c.id)
        }
        .task {
            // เริ่ม feed เคสของคนอื่นทันทีที่จอนี้ปรากฏ — ไม่รอให้เปิดแท็บ SOS ก่อน (ดูคอมเมนต์ที่
            // sosStaff ด้านบนว่าทำไม) ทรงเดียวกับ MainTabView.task ที่เรียก updateSceneGate()/
            // resumeIfNeeded ตั้งแต่ต้นโดยไม่รอ onChange รอบแรก
            sosStaff.start(token: session.token ?? "")
            // เคส SOS ของตัวเจ้าหน้าที่เองที่ค้างจากรอบก่อน (relaunch) — ทรงเดียวกับ MainTabView.task
            // ทุกประการ (ดูคอมเมนต์ที่นั่น)
            if staffOwnSOS.status != nil { showStaffSOSStatus = true }
            // เจ้าหน้าที่ก็กด SOS ของตัวเองได้ (ปุ่มอยู่บนจอนี้) จึงต้องถูกถามสิทธิ์ตำแหน่งเหมือนกัน
            // เมื่อยังไม่เคยถูกถาม — เหตุผลเต็มอยู่ที่ MainTabView.task ซึ่งทำแบบเดียวกันเป๊ะ
            SOSLocator.shared.requestPermissionIfNeeded()
            await staffOwnSOS.resumeIfNeeded(token: session.token ?? "")
        }
        // จอนี้หายทั้งจอ (ล็อกเอาต์เท่านั้น — RootView สลับ StaffHomeView/MainTabView ตาม role บน
        // session.user ตัวเดียวกัน ไปไม่ถึง role ใหม่ได้โดยไม่ผ่าน logout()+login ก่อน) — ทรงเดียวกับ
        // MainTabView.onDisappear ทุกประการ
        .onDisappear {
            sosStaff.stop()
            // อัตโนมัติ (401) ไม่ล้าง เคสที่เปิดอยู่รอ resumeIfNeeded ตอนล็อกอินกลับมาแทน — ส่วนที่
            // ผู้ใช้กดเอง (ปุ่มออกจากระบบใน StaffScanView) ล้างจริง (ดูคอมเมนต์ยาวที่
            // SOSStore.handleLogout(automatic:))
            staffOwnSOS.handleLogout(automatic: session.lastLogoutWasAutomatic)
        }
    }
}
