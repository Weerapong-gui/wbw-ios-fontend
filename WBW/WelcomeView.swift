import SwiftUI

/// หน้าต้อนรับ / splash — แสดงตอนโหลดแอปทุกครั้ง
/// ยังไม่ login → โชว์ปุ่ม Get started (→ Login) · login แล้ว → splash แล้วเข้าแอปเอง
struct WelcomeView: View {
    @EnvironmentObject var session: Session
    let onContinue: () -> Void

    private var loggedIn: Bool { session.user != nil }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer().frame(height: geo.size.height * 0.28)

                Text("Welcome to")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 2)

                Image("logo_wordmark")
                    .resizable().scaledToFit()
                    .frame(width: geo.size.width * 0.86)
                    .padding(.top, 6)

                Spacer()

                // ยังไม่ login → ปุ่ม Get started (liquid glass) · login แล้ว → ไม่มีปุ่ม
                if !loggedIn {
                    Button { onContinue() } label: {
                        Text("Get started")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 190, height: 46)
                            .modifier(GlassButton())
                    }
                    .buttonStyle(.plain)
                }

                Spacer().frame(height: geo.size.height * 0.30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            // พื้นเต็มจอ (bg เป็น background ไม่คุม layout → ไม่มีขอบขาว)
            Image("bg_welcome").resizable().scaledToFill().ignoresSafeArea()
        }
        .task {
            // login อยู่แล้ว: splash สั้นๆ แล้วเข้าแอปเอง
            if loggedIn {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                onContinue()
            }
        }
    }
}

/// ปุ่มทรงแคปซูล liquid glass (iOS 26) · fallback .ultraThinMaterial
private struct GlassButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
        }
    }
}
