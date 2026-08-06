import SwiftUI

/// หน้าหลัก (DOI-APP) — คำทักทาย "Hey! <ชื่อ>" มุมซ้ายบน บนพื้นหลังที่ .forestBackground() จัดให้
///
/// ตัวอักษรเป็นสีขาวเพราะพื้นหลังเป็นโทนเข้มเสมอ (พื้นทึบ #0A1610 ตอน Config.forest3D ปิด
/// หรือฉากป่า 3D ตอนเปิด) — ไม่ผูกกับ flag เพราะขาวอ่านออกทั้งสองโหมด
struct HomeView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var progress: CheckinProgressStore
    @ObservedObject var noti: NotiStore
    @State private var showProfile = false

    private var name: String { profile.me?.displayName ?? (session.user?.username ?? "ผู้เข้าร่วม") }

    private var stage: Int {
        #if DEBUG
        // บังคับขั้นต้นไม้เพื่อถ่ายภาพยืนยัน — ทรงเดียวกับ uitestTab/uitestChat
        if UserDefaults.standard.object(forKey: "uitestProgress") != nil {
            return UserDefaults.standard.integer(forKey: "uitestProgress")
        }
        #endif
        return progress.progress?.stage ?? 0
    }

    private var total: Int {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "uitestProgress") != nil { return 8 }
        #endif
        return progress.progress?.total ?? 0
    }

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
                        .foregroundStyle(.white)
                    Text(name)
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(.white)
                }
                Spacer()

                Button {
                    NotificationCenter.default.post(name: .openNotificationsTab, object: nil)
                } label: {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
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

            // เดิมมีมาสคอต DinDin ลอยเหนือ tab bar ตรงนี้ (Task 9 ถอดออก — ต้นไม้ในฉาก 3D ทำหน้าที่
            // แสดงความคืบหน้าแทน) เหลือ Spacer() ไว้ตัวเดียวเพื่อดันหัวข้อ/avatar ให้ค้างอยู่บนสุดเหมือนเดิม
            // — ถ้าลบ Spacer() นี้ไปด้วย VStack จะเหลือแค่ header ตัวเดียว แล้ว .frame(maxHeight: .infinity)
            // ด้านล่าง (ไม่มี alignment กำกับ = .center ตามค่าเริ่มต้น) จะดันหัวข้อไปกลางจอแทนที่จะอยู่บนสุด
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .forestBackground(
            day: ForestMath.day(stage: stage, total: total),
            plantStep: stage,
            plantTotal: total)
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
