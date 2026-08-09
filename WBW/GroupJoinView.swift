import SwiftUI


/// หน้าจับกลุ่ม — ปุ่มย้อนกลับ + ค้นหา (ระนาบเดียว) + 40 กลุ่ม (xx/50, ดูสมาชิก, เข้ากลุ่ม)
struct GroupJoinView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var groups: GroupStore
    var onBack: () -> Void = {}
    @State private var joining: Int?
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.wbwBg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if !groups.matchedPeople.isEmpty { peopleSection }
                        ForEach(groups.filteredGroups) { g in
                            GroupCard(
                                group: g,
                                previews: groups.indexMembers(groupId: g.groupId),
                                joining: joining == g.groupId,
                                onJoin: { Task { await join(g) } }
                            )
                        }
                        if groups.loaded && groups.filteredGroups.isEmpty && groups.matchedPeople.isEmpty {
                            Text("ไม่พบกลุ่ม").foregroundStyle(.secondary).padding(.top, 40)
                        }
                    }
                    .padding(16)
                }
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(.white)
                    .padding(12).background(.red.opacity(0.9), in: Capsule())
                    .padding(.bottom, 30).frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .navigationBarHidden(true)
        .task { if !groups.loaded { await groups.load(token: session.token ?? "") } }
    }

    // แถวบน: ย้อนกลับ + ค้นหา
    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.wbwInk)
                    .frame(width: 40, height: 40)
                    .background(Color.wbwSurface, in: Circle())
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("ค้นหากลุ่ม หรือ ชื่อเพื่อน", text: $groups.search)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14).frame(height: 40)
            .background(Color.wbwSurface, in: Capsule())
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
    }

    // ผลค้นหาคน
    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("คนที่พบ").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(groups.matchedPeople) { p in
                HStack(spacing: 10) {
                    ProfileAvatar(name: p.firstName ?? "", photoUrl: nil, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.fullName).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.wbwInk)
                        Text("กลุ่ม \(p.groupNumber)").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12).background(Color.wbwSurface, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func join(_ g: GroupSummary) async {
        guard let t = session.token else { return }
        error = nil
        joining = g.groupId
        defer { joining = nil }
        do {
            try await groups.join(groupId: g.groupId, token: t)
            await profile.load(token: t)   // group_id ใหม่ → GroupTabView สลับไปหน้ากลุ่ม + icon เปลี่ยน
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "เข้ากลุ่มไม่สำเร็จ"
        }
    }
}

/// การ์ดกลุ่ม 1 กลุ่ม
private struct GroupCard: View {
    let group: GroupSummary
    let previews: [GroupMemberIndex]
    let joining: Bool
    let onJoin: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // แตะดูสมาชิก
            NavigationLink { GroupMembersView(groupId: group.groupId, groupNumber: group.groupNumber) } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.wbwGold.opacity(0.15)).frame(width: 46, height: 46)
                        Text("\(group.groupNumber)").font(.system(size: 18, weight: .heavy)).foregroundStyle(Color.wbwGold)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("กลุ่ม \(group.groupNumber)").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.wbwInk)
                        HStack(spacing: 6) {
                            avatarPreview
                            Text("\(group.memberCount)/\(group.capacity)")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            // ปุ่มเข้ากลุ่ม
            Button(action: onJoin) {
                Group {
                    if joining { ProgressView().tint(.white) }
                    else { Text(group.isFull ? "เต็ม" : "เข้ากลุ่ม").font(.system(size: 13, weight: .semibold)) }
                }
                .foregroundStyle(.white)
                .frame(width: 74, height: 34)
                .background(group.isFull ? Color.gray : Color.wbwGold, in: Capsule())
            }
            .disabled(group.isFull || joining)
        }
        .padding(12)
        .background(Color.wbwSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var avatarPreview: some View {
        HStack(spacing: -8) {
            ForEach(previews.prefix(4)) { m in
                ProfileAvatar(name: m.firstName ?? "", photoUrl: nil, size: 22)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
            }
        }
    }
}
