import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: Session
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
