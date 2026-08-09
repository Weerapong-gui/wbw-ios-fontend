import SwiftUI


/// ปลายทางที่ push ต่อจากจอแชทได้ — แชทเป็นรากของแท็บ ไม่ใช่ overlay อีกต่อไป
enum GroupRoute: Hashable {
    case home       // กลุ่มของฉัน (ออกจากกลุ่ม, สิทธิ์คงเหลือ)
    case members    // รายชื่อสมาชิก
}

/// แท็บ 3 — ยังไม่เข้ากลุ่ม = หน้าจับกลุ่ม · เข้าแล้ว = จอแชทเลย (หน้ากลุ่มอยู่หลังการกดหัวจอ)
struct GroupTabView: View {
    @EnvironmentObject var profile: ProfileStore
    @ObservedObject var chat: ChatSession
    @Binding var path: [GroupRoute]
    var onBack: () -> Void = {}

    var body: some View {
        // NavigationStack ตัวเดียวของทั้งแท็บ — ทั้งสองสาขาใช้ร่วมกัน ไม่งั้น NavigationLink
        // ในหน้าจับกลุ่ม (ดูสมาชิกก่อนเข้ากลุ่ม) จะไม่มี stack ให้ push แล้วกดแล้วไม่ไปไหนเงียบ ๆ
        NavigationStack(path: $path) {
            Group {
                if profile.me?.groupId == nil {
                    GroupJoinView(onBack: onBack)
                } else {
                    GroupChatView(store: chat)
                }
            }
            .navigationDestination(for: GroupRoute.self) { route in
                switch route {
                case .home:
                    GroupHomeView(path: $path)
                case .members:
                    GroupMembersView(groupId: profile.me?.groupId ?? 0,
                                     groupNumber: profile.me?.groupNumber ?? 0)
                }
            }
        }
    }
}

/// หน้ากลุ่มของฉัน (เข้ากลุ่มแล้ว) — ดูสมาชิก / ออกจากกลุ่ม · ถูก push มาจากการแตะหัวจอแชท
/// ไม่มีปุ่มเข้าแชทแล้ว เพราะแชทเป็นรากของ stack อยู่แล้ว (หน้านี้อยู่บนแชท ไม่ใช่คนละกิ่ง)
struct GroupHomeView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var groups: GroupStore
    @Binding var path: [GroupRoute]
    @State private var leaving = false

    private var groupNo: Int? { profile.me?.groupNumber }
    private var groupId: Int? { profile.me?.groupId }

    var body: some View {
        ZStack {
            Color.wbwBg.ignoresSafeArea()
            VStack(spacing: 20) {
                // การ์ดกลุ่ม
                VStack(spacing: 6) {
                    Text("กลุ่มของฉัน").font(.system(size: 14)).foregroundStyle(.secondary)
                    Text("กลุ่ม \(groupNo.map(String.init) ?? "-")")
                        .font(.system(size: 34, weight: .heavy)).foregroundStyle(Color.wbwInk)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
                .background(Color.wbwSurface, in: RoundedRectangle(cornerRadius: 20))

                // ดูสมาชิก — push ผ่าน path แทน NavigationLink เพราะปลายทางประกาศไว้ที่
                // navigationDestination ของ GroupTabView แล้ว ไม่ใช่ของหน้านี้เอง
                if groupId != nil {
                    Button { path.append(.members) } label: {
                        Label("สมาชิกในกลุ่ม", systemImage: "person.2.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.wbwInk)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .background(Color.wbwSurface, in: RoundedRectangle(cornerRadius: 16))
                    }
                }

                Spacer()

                Button(role: .destructive) { Task { await leave() } } label: {
                    Text(leaving ? "กำลังออก" : "ออกจากกลุ่ม")
                        .font(.system(size: 15)).foregroundStyle(.red)
                }
                .disabled(leaving)
            }
            .padding(20)
            .padding(.top, 8)
        }
        .navigationTitle("กลุ่ม")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func leave() async {
        guard let t = session.token else { return }
        leaving = true
        try? await APIClient.shared.leaveGroup(token: t)
        await profile.load(token: t)   // group_id = nil → กลับไปหน้าจับกลุ่ม
        leaving = false
    }
}
