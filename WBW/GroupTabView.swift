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

/// หน้ากลุ่มของฉัน — เข้าถึงจากการกดหัวจอแชท · ดูสมาชิก / ดูสิทธิ์ / ออกจากกลุ่ม
struct GroupHomeView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @Binding var path: [GroupRoute]
    @State private var leaving = false
    @State private var confirmLeave = false
    @State private var error: String?

    private var groupNo: Int { profile.me?.groupNumber ?? 0 }
    /// อ่านเป็น 0 เมื่อไม่รู้ค่า — backend เก่าไม่ส่ง key นี้มา ปลอดภัยกว่าที่จะไม่โชว์ปุ่มออก
    /// (กดแล้วเจอ 409 จาก server อยู่ดี) ดีกว่าโชว์ปุ่มที่พาไปเจอทางตัน
    private var quota: Int { profile.me?.leaveQuota ?? 0 }

    var body: some View {
        ZStack {
            Color.wbwBg.ignoresSafeArea()
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("กลุ่มของฉัน").font(.system(size: 14)).foregroundStyle(.secondary)
                    Text("กลุ่ม \(groupNo)")
                        .font(.system(size: 34, weight: .heavy)).foregroundStyle(Color.wbwInk)
                    Text(GroupQuotaText.remaining(quota: quota))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
                .background(Color.wbwSurface, in: RoundedRectangle(cornerRadius: 20))

                Button { path.append(.members) } label: {
                    Label("สมาชิกในกลุ่ม", systemImage: "person.2.fill")
                        .font(.system(size: 16)).foregroundStyle(Color.wbwInk)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(Color.wbwSurface, in: RoundedRectangle(cornerRadius: 16))
                }

                Spacer()

                // สิทธิ์หมด = ไม่มีปุ่ม ไม่ใช่ปุ่มกดไม่ได้ — ไม่มีอะไรให้กดแล้วจริง ๆ
                // ปุ่มจาง ๆ ที่กดไม่ได้ชวนให้กดซ้ำแล้วสงสัยว่าแอปค้าง
                if quota > 0 {
                    Button(role: .destructive) { confirmLeave = true } label: {
                        Text(leaving ? "กำลังออก" : "ออกจากกลุ่ม")
                            .font(.system(size: 15)).foregroundStyle(.red)
                    }
                    .disabled(leaving)
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
            }
            .padding(20).padding(.top, 8)
        }
        .navigationTitle("กลุ่ม \(groupNo)")
        .navigationBarTitleDisplayMode(.inline)
        .alert("ออกจากกลุ่ม \(groupNo)?", isPresented: $confirmLeave) {
            Button("ยกเลิก", role: .cancel) {}
            Button("ออกจากกลุ่ม", role: .destructive) { Task { await leave() } }
        } message: {
            Text(GroupQuotaText.leaveWarning(groupNumber: groupNo, quota: quota))
        }
    }

    private func leave() async {
        guard let t = session.token else { return }
        error = nil
        leaving = true
        defer { leaving = false }
        do {
            try await APIClient.shared.leaveGroup(token: t)
            await profile.load(token: t)   // group_id = nil → GroupTabView สลับไปหน้าจับกลุ่มเอง
            path.removeAll()               // หน้านี้กำลังจะไม่มีกลุ่มให้แสดง เด้งกลับรากก่อน
        } catch {
            // 409 = admin ตัดสิทธิ์ระหว่างที่จอนี้เปิดค้าง หรือออกไปแล้วจากอีกเครื่อง
            // โหลดโปรไฟล์ใหม่ให้จอตรงกับความจริงทันที ไม่ใช่แค่โชว์ข้อความแล้วปล่อยค้าง
            self.error = (error as? LocalizedError)?.errorDescription ?? "ออกจากกลุ่มไม่สำเร็จ"
            await profile.load(token: t)
        }
    }
}
