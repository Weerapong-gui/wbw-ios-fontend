import SwiftUI


/// รายชื่อสมาชิกในกลุ่ม — แตะดูโปรไฟล์
struct GroupMembersView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var groups: GroupStore
    let groupId: Int
    let groupNumber: Int
    @State private var members: [GroupMember] = []
    @State private var loading = true
    @State private var selected: GroupMember?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if loading {
                    ProgressView().padding(.top, 40)
                } else if members.isEmpty {
                    Text("ยังไม่มีสมาชิก").foregroundStyle(.secondary).padding(.top, 40)
                } else {
                    ForEach(members) { m in
                        Button { selected = m } label: { row(m) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.wbwBg)
        .navigationTitle("กลุ่ม \(groupNumber)")
        .navigationBarTitleDisplayMode(.inline)
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

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 40, height: 5).padding(.top, 10)
            ProfileAvatar(name: member.firstName ?? "", photoUrl: member.photoUrl, size: 96).padding(.top, 6)
            Text(member.fullName).font(.system(size: 22, weight: .bold)).foregroundStyle(Color.wbwInk)
            VStack(spacing: 0) {
                infoRow("สำนักวิชา", member.school)
                Divider().padding(.leading, 16)
                infoRow("BIB", member.bib.map(String.init))
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
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
