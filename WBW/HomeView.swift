import SwiftUI

/// หน้าหลัก (DOI-APP) — พื้นป่า + คำทักทาย "Hey! <ชื่อ>" มุมซ้ายบน + มาสคอต DinDin กลางล่าง
struct HomeView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @ObservedObject var noti: NotiStore
    @State private var showProfile = false

    private var name: String { profile.me?.displayName ?? (session.user?.username ?? "ผู้เข้าร่วม") }

    var body: some View {
        VStack(spacing: 0) {
            // คำทักทายมุมซ้ายบน — avatar กรอบ liquid glass กดไป Profile
            HStack(spacing: 12) {
                Button { showProfile = true } label: {
                    ProfileAvatar(name: name, photoUrl: profile.photoUrl, size: 50)
                        .padding(5)
                        .modifier(GlassRing())
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hey!")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.wbwInk)
                    Text(name)
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(Color.wbwInk)
                }
                Spacer()

                Button {
                    NotificationCenter.default.post(name: .openNotificationsTab, object: nil)
                } label: {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.wbwInk)
                        .frame(width: 44, height: 44)
                        .modifier(GlassRing())
                        .overlay(alignment: .topTrailing) {
                            if noti.unreadCount > 0 {
                                Text("\(noti.unreadCount)")
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                    .padding(5).background(Color.red, in: Circle())
                                    .offset(x: 4, y: -4)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)

            Spacer()

            // มาสคอต DinDin เหนือ tab bar
            Image("dindin")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 34)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // พื้นป่าเต็มจอ (bg เป็น background ไม่คุม layout)
            Image("bg_forest")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        }
        .task {
            if profile.me == nil { await profile.load(token: session.token ?? "") }
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "uitestProfile") { showProfile = true }
            #endif
        }
        .fullScreenCover(isPresented: $showProfile) {
            TicketView()
        }
    }
}

/// กรอบวงกลม liquid glass รอบ avatar (iOS 26) · fallback วงขาว
private struct GlassRing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
        }
    }
}
