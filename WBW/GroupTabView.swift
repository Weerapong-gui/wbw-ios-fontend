import SwiftUI

private let screenBG = Color(red: 250 / 255, green: 247 / 255, blue: 240 / 255) // ครีมอ่อน

/// แท็บ 3 — ยังไม่เข้ากลุ่ม = หน้าจับกลุ่ม · เข้าแล้ว = หน้ากลุ่ม (เข้าแชท)
struct GroupTabView: View {
    @EnvironmentObject var profile: ProfileStore
    var onBack: () -> Void = {}
    var onOpenChat: () -> Void = {}

    var body: some View {
        if profile.me?.groupId == nil {
            GroupJoinView(onBack: onBack)
        } else {
            GroupHomeView(onOpenChat: onOpenChat)
        }
    }
}

/// หน้ากลุ่มของฉัน (เข้ากลุ่มแล้ว) — เข้าแชท / ดูสมาชิก / ออกจากกลุ่ม
struct GroupHomeView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var groups: GroupStore
    var onOpenChat: () -> Void = {}
    @State private var leaving = false

    private var groupNo: Int? { profile.me?.groupNumber }
    private var groupId: Int? { profile.me?.groupId }

    var body: some View {
        NavigationStack {
            ZStack {
                screenBG.ignoresSafeArea()
                VStack(spacing: 20) {
                    // การ์ดกลุ่ม
                    VStack(spacing: 6) {
                        Text("กลุ่มของฉัน").font(.system(size: 14)).foregroundStyle(.secondary)
                        Text("กลุ่ม \(groupNo.map(String.init) ?? "-")")
                            .font(.system(size: 34, weight: .heavy)).foregroundStyle(Color.wbwInk)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 28)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20))

                    // ปุ่มเข้าแชท
                    Button(action: onOpenChat) {
                        Label("เปิดแชทกลุ่ม", systemImage: "message.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(Color.wbwGold, in: RoundedRectangle(cornerRadius: 18))
                    }

                    // ดูสมาชิก
                    if let gid = groupId {
                        NavigationLink { GroupMembersView(groupId: gid, groupNumber: groupNo ?? 0) } label: {
                            Label("สมาชิกในกลุ่ม", systemImage: "person.2.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.wbwInk)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
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
    }

    private func leave() async {
        guard let t = session.token else { return }
        leaving = true
        try? await APIClient.shared.leaveGroup(token: t)
        await profile.load(token: t)   // group_id = nil → กลับไปหน้าจับกลุ่ม
        leaving = false
    }
}
