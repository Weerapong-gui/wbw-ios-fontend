import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject private var host: ForestSceneHost
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
    }
}
