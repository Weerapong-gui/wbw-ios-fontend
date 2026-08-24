import SwiftUI


/// รายชื่อสมาชิกในกลุ่ม — แตะดูโปรไฟล์
struct GroupMembersView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var groups: GroupStore
    let groupId: Int
    let groupNumber: Int
    /// ระยะเว้นท้ายลิสต์ให้พ้นแถบแท็บลอย — **จอนี้เข้าได้สองทางที่แถบแท็บไม่เหมือนกัน**
    ///
    /// จากหน้าจับกลุ่ม แถบแท็บโชว์อยู่ ต้องเว้น · จากในแชท `GroupChatView` สั่ง
    /// `.toolbar(.hidden, for: .tabBar)` ไว้ที่รากของสแตก แถบจึงซ่อนทั้งสแตก ไม่ต้องเว้น
    /// ใส่ค่าคงที่ตายตัวไปเลยจะได้ช่องว่างตายด้าน 89pt ในสาขาแชท ส่วนไม่ใส่เลยจะได้แถวสุดท้าย
    /// โดนแถบทับในสาขาจับกลุ่ม (กลุ่มจริงมีได้ถึง 50 คน ไม่ใช่ 4 คนแบบข้อมูลเดโม่)
    var bottomInset: CGFloat = 0
    @State private var members: [GroupMember] = []
    @State private var loading = true
    @State private var selected: GroupMember?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if loading {
                    // ไม่ระบุ tint แล้วมันตกทอด `.tint(Color.wbwGold)` จาก `MainTabView`
                    // ซึ่งเป็นสีเข้มในโหมดสว่าง = spinner หายไปกับภาพพื้นหลัง
                    ProgressView().tint(Color.wbwOnBackdrop).padding(.top, 40)
                } else if members.isEmpty {
                    Text("group_members_empty").foregroundStyle(Color.wbwOnBackdropMuted).padding(.top, 40)
                } else {
                    ForEach(members) { m in
                        Button { selected = m } label: { row(m) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, bottomInset)
            .contentColumn(.card)
        }
        .clearsHostOpaqueBackground()
        .navigationBarTitleDisplayMode(.inline)
        // หัวข้อวางบนภาพพื้นหลัง จึงต้องเป็น principal item ที่กำหนดสีเอง ไม่ใช่ `.navigationTitle`
        // — ตัวนั้นเรนเดอร์ด้วย `UIColor.label` ซึ่งพลิกตามธีม แล้วหัวข้อจะเป็นสีเข้มบนภาพมืด
        // ในโหมดสว่าง (ถ่ายพิสูจน์แล้ว) · `.toolbarColorScheme(.dark)` ที่ `GroupTabView`
        // ก็ไม่ช่วย มันคุมพื้นแถบ ไม่ได้คุมสีหัวข้อ · ท่าเดียวกับ `SettingsView`
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(String(format: Loc.t("group_number"), groupNumber))
                    .font(.headline)
                    .foregroundStyle(Color.wbwOnBackdrop)
            }
        }
        .task {
            members = await groups.members(groupId: groupId, token: session.token ?? "")
            loading = false
        }
        .sheet(item: $selected) { m in
            MemberProfileSheet(member: m).presentationDetents([.medium])
        }
    }

    private func row(_ m: GroupMember) -> some View {
        HStack(spacing: 12) {
            ProfileAvatar(name: m.firstName ?? "", photoUrl: m.photoUrl, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.fullName).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.wbwInk)
                if let s = m.school { Text(s).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
            Spacer()
            if let bib = m.bib {
                Text("BIB \(bib)").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(12).background(Color.wbwSurface, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// โปรไฟล์สมาชิกย่อ
private struct MemberProfileSheet: View {
    let member: GroupMember
    @Environment(\.dismiss) private var dismiss
    /// ทางบล็อกที่**มองเห็นได้** — เมนูกดค้างบนฟองข้อความในแชททำงานเหมือนกัน แต่ผู้ตรวจ
    /// ของ Apple (และผู้ใช้ที่กำลังเดือดร้อน) หาเมนูที่ซ่อนอยู่หลังการกดค้างไม่เจอ
    /// Guideline 1.2 วัดที่ "มีทางบล็อกไหม" ไม่ใช่ "มีโค้ดบล็อกไหม"
    @StateObject private var blocked = BlockedUsers()

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 40, height: 5).padding(.top, 10)
            ProfileAvatar(name: member.firstName ?? "", photoUrl: member.photoUrl, size: 96).padding(.top, 6)
            Text(member.fullName).font(.system(size: 22, weight: .bold)).foregroundStyle(Color.wbwInk)
            VStack(spacing: 0) {
                infoRow(Loc.t("profile_row_school"), member.school)
                Divider().padding(.leading, 16)
                infoRow("BIB", member.bib.map(String.init))
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)

            Button {
                if blocked.isBlocked(member.userId) {
                    blocked.unblock(member.userId)
                } else {
                    blocked.block(member.userId, name: member.fullName)
                }
            } label: {
                Text(blocked.isBlocked(member.userId) ? "chat_unblock" : "chat_block")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.wbwDanger)
                    .frame(maxWidth: .infinity)
                    .frame(height: Config.Tap.minTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            Text("blocked_note")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func infoRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value?.isEmpty == false ? value! : "—").foregroundStyle(.primary)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}
