import SwiftUI


/// หน้าจับกลุ่ม — ปุ่มย้อนกลับ + ค้นหา (ระนาบเดียว) + 40 กลุ่ม (xx/50, ดูสมาชิก, เข้ากลุ่ม)
struct GroupJoinView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var groups: GroupStore
    var onBack: () -> Void = {}
    @State private var joining: Int?
    @State private var error: String?
    // กลุ่มที่รอการยืนยัน (nil = ไม่มี alert) — ผู้ใช้ต้องรู้ก่อนกดว่าจะเหลือสิทธิ์เท่าไร
    // ไม่ใช่รู้ทีหลังตอนอยากออกแล้วออกไม่ได้
    @State private var pendingJoin: GroupSummary?

    var body: some View {
        ZStack {
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
                                onJoin: { pendingJoin = g }
                            )
                        }
                        if groups.loaded && groups.filteredGroups.isEmpty && groups.matchedPeople.isEmpty {
                            Text("group_none_found").foregroundStyle(Color.wbwOnBackdropMuted).padding(.top, 40)
                        }
                    }
                    .padding(16)
                    // แถบแท็บลอยทับการ์ดใบสุดท้ายครึ่งใบถ้าไม่เว้น (ระยะวัดจากเครื่องจริงสองรุ่น
                    // ดูคอมเมนต์ที่ `ForestSceneHost.tabBarClearance`)
                    .padding(.bottom, ForestSceneHost.tabBarClearance)
                }
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(.white)
                    .padding(12).background(.red.opacity(0.9), in: Capsule())
                    .padding(.bottom, 30).frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .clearsHostOpaqueBackground()
        .navigationBarHidden(true)
        .task { if !groups.loaded { await groups.load(token: session.token ?? "") } }
        .alert(Text(String(format: Loc.t("group_join_confirm"), pendingJoin?.groupNumber ?? 0)),
               isPresented: Binding(get: { pendingJoin != nil },
                                    set: { if !$0 { pendingJoin = nil } }),
               presenting: pendingJoin) { g in
            Button("group_pick_cancel", role: .cancel) { pendingJoin = nil }
            Button("group_join") {
                let target = g
                pendingJoin = nil
                Task { await join(target) }
            }
        } message: { g in
            Text(GroupQuotaText.joinWarning(groupNumber: g.groupNumber,
                                            quota: profile.me?.leaveQuota ?? 0))
        }
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
                    // วงกลมยังกว้าง 40 · พื้นที่รับนิ้ว 44 ตาม HIG
                    .frame(width: Config.Tap.minTarget, height: Config.Tap.minTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("action_back")
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("group_search_placeholder", text: $groups.search)
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
            // หัวข้อ section วางบนภาพพื้นหลัง ไม่ใช่บนการ์ด (แถวข้างล่างเท่านั้นที่มีพื้น)
            Text("group_people_found").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.wbwOnBackdropMuted)
            ForEach(groups.matchedPeople) { p in
                HStack(spacing: 10) {
                    ProfileAvatar(name: p.firstName ?? "", photoUrl: nil, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.fullName).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.wbwInk)
                        Text(String(format: Loc.t("group_number"), p.groupNumber)).font(.system(size: 12)).foregroundStyle(.secondary)
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
            // 409 "ท่านอยู่ในกลุ่มอยู่แล้ว" = เข้ากลุ่มไปแล้วจากอีกเครื่อง · โหลดโปรไฟล์ใหม่
            // ให้แท็บสลับไปจอแชทเอง แทนที่จะค้างอยู่หน้าลิสต์พร้อม error ที่ผู้ใช้แก้ไม่ได้
            self.error = (error as? LocalizedError)?.errorDescription ?? Loc.t("error_join_failed")
            await profile.load(token: t)
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
            // ทางเข้านี้แถบแท็บยังโชว์อยู่ (ดูคอมเมนต์ที่ `GroupMembersView.bottomInset`)
            NavigationLink {
                GroupMembersView(groupId: group.groupId, groupNumber: group.groupNumber,
                                 bottomInset: ForestSceneHost.tabBarClearance)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        // `wbwAccent` ไม่ใช่ `wbwGold` — ค่าเท่ากันเป๊ะ (ตัวหลังเป็น alias) แต่ชื่อเดิม
                        // ถูกประกาศไว้ใน `Config.swift` ว่าโค้ดใหม่ห้ามใช้ · วงนี้อยู่บนการ์ดทึบ
                        // ที่มี ink ของตัวเอง จึงอ่านออกทั้งสองธีมอยู่แล้ว ไม่ต้องเปลี่ยนสี
                        Circle().fill(Color.wbwAccent.opacity(0.15)).frame(width: 46, height: 46)
                        Text("\(group.groupNumber)").font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Color.wbwAccent)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: Loc.t("group_number"), group.groupNumber)).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.wbwInk)
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

            // ปุ่มเข้ากลุ่ม — ทึบเทาเข้ม ตัวหนังสือสีอ่อน คงที่ทั้งสองธีม
            //
            // ของเดิมคือ `wbwGold` + `.white` ซึ่งเขียนไว้ตอน `wbwGold` ยังเป็นสีทองจริง
            // ตอนนี้มันเป็น alias ของ `wbwAccent` = #E9EEE0 ในโหมดมืด = **ขาวบนขาว**
            //
            // เส้นขอบผมไม่ใช่ของประดับ: ในโหมดมืด `wbwSolid` (#2F3B2B) ต่างจากการ์ด
            // `wbwSurface` (#1A2318) แค่ราว 1.3:1 เส้นขอบคือสิ่งที่บอกว่าตรงนี้มีปุ่มอยู่
            // (ท่าเดียวกับทุกแผ่นใน `GlassSurface.swift`)
            Button(action: onJoin) {
                Group {
                    if joining { ProgressView().tint(Color.wbwOnBackdrop) }
                    else { Text(group.isFull ? "group_full" : "group_join").font(.system(size: 13, weight: .semibold)) }
                }
                .foregroundStyle(group.isFull ? Color.wbwOnBackdropMuted : Color.wbwOnBackdrop)
                .frame(width: 74, height: 34)
                // พื้นทึบเต็มทั้งสองสถานะ หรี่แค่ตัวอักษร — ลดความทึบของพื้นแล้วสีการ์ดจะซึมขึ้นมา
                // ผสม ทำให้ตัวอักษร muted บนการ์ดสีอ่อนในโหมดสว่างจางจนอ่านไม่ออก (ถ่ายเจอจริง)
                .background(Color.wbwSolid, in: Capsule())
                .overlay(Capsule().stroke(Color.glassSheerBorder, lineWidth: 1))
                // แคปซูลยังสูง 34 ตามดีไซน์ · ขยายเฉพาะพื้นที่รับนิ้วเป็น 44 ตาม HIG
                .frame(width: 74, height: Config.Tap.minTarget)
                .contentShape(Rectangle())
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
