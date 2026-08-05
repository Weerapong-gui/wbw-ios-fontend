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

    private enum Phase: Equatable { case welcome, login, home }
    private var phase: Phase {
        if !splashDone { return .welcome }
        return session.user != nil ? .home : .login
    }

    // staff/admin → หน้าสแกนเช็คอิน · participant → home ปกติ
    private var isStaff: Bool {
        let role = session.user?.role
        return role == "staff" || role == "admin"
    }

    var body: some View {
        ZStack {
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
            case .welcome:
                WelcomeView(onContinue: { splashDone = true })
                    .transition(.opacity)
            case .login:
                LoginView()
                    .transition(.opacity)
            case .home:
                // home เผยขึ้นแบบ fade + scale เบาๆ (reveal) · แตกตามบทบาท
                Group {
                    if isStaff {
                        StaffScanView()
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
        // แอปลงพื้นหลัง — ไม่มีใครเห็นฉากอยู่ดี ไม่ว่าจะกำลังอยู่หน้าไหน · เขียน host.appActive ตรงๆ
        // ไม่ใช่ host.enabled — ต่างจากเดิมตรงที่มี branch .active ด้วย (เดิมมีแค่ "!= .active → false"
        // ไม่มีทางคืนเป็น true เลยตอนกลับมา foreground ค้าง false ถาวรจนกว่าจะบังเอิญมีจุดอื่นมา set
        // true ทับ) recompute() ที่ ForestSceneHost คำนวณ enabled จาก appActive ร่วมกับ wantsScene/
        // suppressed เองอยู่แล้ว ไม่ต้องเขียน enabled ตรงนี้อีกต่อไป (ดูคอมเมนต์ยาวที่ enabled)
        .onChange(of: scenePhase) { _, phase in
            host.appActive = (phase == .active)
        }
        // เจ้าหน้าที่: StaffScanView ทับด้วยสีทึบ (Color.wbwInk) + กล้องสแกน QR (AVCaptureSession) —
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
        .onChange(of: isStaff) { _, staff in
            host.suppressed = staff
        }
    }
}
