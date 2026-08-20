import SwiftUI
import SwiftData


/// แชทกลุ่ม — nav bar ของระบบ (ปุ่มกลับ + ชื่อห้องที่กดเข้าหน้ากลุ่มได้) ไม่มีแถบแท็บ
/// + ฟองข้อความ + ช่องพิมพ์ลอยท้ายจอ · offline-first ผ่าน ChatSession
struct GroupChatView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var groups: GroupStore
    @ObservedObject var store: ChatSession
    /// กลับไปแท็บ Home — `MainTabView` ส่ง `{ tab = 0 }` มาให้ (ผ่าน `GroupTabView`)
    var onBack: () -> Void = {}
    @State private var draft = ""
    @State private var members: [String: GroupMember] = [:]   // senderId → member (avatar)
    @State private var atBottom = true
    @State private var reveal: CGFloat = 0
    @State private var sentTick = 0
    /// จำนวนข้อความที่เข้ามาระหว่างเรากำลังเลื่อนอ่านย้อนหลัง
    ///
    /// นับเองแทนที่จะใช้ store.unreadCount เพราะ ChatSession เรียก markRead() ทุกครั้งที่
    /// sync ได้ของใหม่ตอนจอแชทเปิดอยู่ (ตั้งใจ — "เปิดจออยู่ = อ่านแล้ว" ตาม spec และเป็นค่า
    /// ที่คนอื่นเอาไปคิด "อ่านแล้ว N") unreadCount จึงถูกกดเป็น 0 ทันทีและ pill จะไม่มีวันโผล่
    @State private var newBelow = 0

    var body: some View {
        VStack(spacing: 0) {
            if !store.connectivity.online { offlineBanner }
            messageList
        }
        // แถบแท็บลอยไม่ควรอยู่บนจอแชท — จอนี้เป็นจอที่คนอยู่ค้างแล้วพิมพ์ ไม่ใช่จอที่แวะดู
        // ปุ่มกลับที่มุมซ้ายบนทำหน้าที่แทน
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { onBack() } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                }
                .accessibilityLabel("กลับ")
            }
            // หัวจอ = ทางเข้า**เดียว**ของหน้ากลุ่ม (ออกจากกลุ่ม/ดูสมาชิก/ดูสิทธิ์คงเหลือ)
            // ห้ามทำหายตอนไปแตะอย่างอื่น · แตะชื่อห้องแล้วเข้าหน้าข้อมูลกลุ่มเป็นท่าที่แอปแชท
            // ทั่วไปใช้อยู่แล้ว ผู้ใช้จึงเดาถูกโดยไม่ต้องมีป้ายบอก
            //
            // ไม่ใช้ `.navigationTitle` เพราะต้องการสองบรรทัด — `.navigationSubtitle` เพิ่งมีใน
            // iOS 26 แต่ deployment target ของโปรเจกต์คือ 18
            ToolbarItem(placement: .principal) {
                NavigationLink(value: GroupRoute.home) {
                    VStack(spacing: 1) {
                        HStack(spacing: 4) {
                            Text("กลุ่ม \(profile.me?.groupNumber.map(String.init) ?? "")")
                                .font(.headline).foregroundStyle(Color.wbwInk)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        // ยังไม่รู้จำนวน = ไม่โชว์ ไม่ใช่โชว์ "0 คน" — memberCount มาจากผลลัพธ์
                        // ของ sync (ChatSession:260) ซึ่งยังไม่กลับมาตอนเปิดจอครั้งแรก หรือ
                        // ไม่กลับมาเลยตอนออฟไลน์ ทั้งที่ข้อความจากแคชขึ้นครบแล้ว · "0 คน"
                        // ในห้องที่มีคนคุยกันอยู่อ่านว่าแอปพัง (กติกาเดียวกับ TrailConditionsRow)
                        if store.memberCount > 0 {
                            Text("\(store.memberCount) คน")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.wbwBg.ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .light), trigger: sentTick)
        // overload closure แทน .error ตรงๆ — ตัวเดิมสั่นทุกครั้งที่ค่าเปลี่ยนไม่ว่าทิศไหน แม้แต่ retry สำเร็จ
        // (1 ล้มเหลว → 0) ก็นับว่า "เปลี่ยน" เหมือนกัน สั่น error ทั้งที่จริงๆ ส่งสำเร็จแล้ว
        .sensoryFeedback(trigger: store.messages.filter { $0.state == .failed }.count) { old, new in
            new > old ? .error : nil
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: newBelow > 0)
        // ของเดิมมีแค่ตัวข้างบน ซึ่งผูกกับ newBelow > 0 — ค่านั้นเปลี่ยนเฉพาะตอนเลื่อนขึ้นไปอ่านประวัติแล้วมี
        // ข้อความใหม่เข้ามา กรณีปกติ (อยู่ล่างสุด) newBelow ค้างที่ 0 ทั้งก่อนและหลังข้อความมาถึง (markRead()
        // กดกลับเป็น 0 ทันทีในเฟรมเดียวกัน) ค่าที่ .animation(value:) เฝ้าดูเลยไม่ขยับ ฟองใหม่จึง pop เข้ามา
        // ทันทีไม่มี transition เลย ยืนยันด้วยตาจริงบนซิมูเลเตอร์แล้ว (เทียบ 2 ชุดภาพ burst: ไม่มี animation
        // ผูกกับ count ฟองมาถึงสถานะสุดท้ายภายใน ~260ms เฟรมแรกหลังข้อความมาถึงกับเฟรมสุดท้ายพิกเซลเหมือนกันเป๊ะ
        // ส่วนที่มี ฟองจางแล้วค่อยชัดขึ้นระหว่างทางชัดเจน) — ผูกกับจำนวนข้อความเพิ่มเพื่อให้ครอบกรณีอยู่ล่างสุด
        // (กรณีปกติ) ด้วย ใช้สปริงตัวเดียวกับที่ scrollToBottom ใช้ ให้ความรู้สึกเป็นการเคลื่อนไหวชุดเดียวกัน
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: store.messages.count)
        .safeAreaInset(edge: .bottom) { inputBar }
        .task {
            // setScreenVisible ย้ายออกไปให้ MainTabView คุมแล้ว (Task 5) — TabView เก็บ view นี้ไว้ตอนสลับ
            // แท็บ ไม่เรียก onDisappear จริง ถ้ายังยิงจากที่นี่ heartbeat จะค้างวิ่งทั้งที่ผู้ใช้ไปแท็บอื่นแล้ว
            // (ดูคอมเมนต์ที่ MainTabView.chatVisible)
            #if DEBUG
            // เติมข้อความในช่องพิมพ์ตรง ๆ เพื่อถ่ายทรงช่องตอนหลายบรรทัด — ไม่มี tap tooling
            // ในสภาพแวดล้อมนี้ พิมพ์เองไม่ได้ (ทรงเดียวกับ -uitestMapPin ที่ Map3DScreen)
            if let prefill = UserDefaults.standard.string(forKey: "uitestChatDraft"), !prefill.isEmpty {
                draft = prefill
            }
            #endif
            let gid = profile.me?.groupId ?? 0
            let ms = await groups.members(groupId: gid, token: session.token ?? "")
            members = Dictionary(uniqueKeysWithValues: ms.map { ($0.userId, $0) })
        }
    }

    private var offlineBanner: some View {
        Text("ออฟไลน์ — ข้อความจะส่งเมื่อกลับมามีสัญญาณ")
            .font(.footnote).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(Color.gray)
    }

    private var rows: [ChatRow] {
        ChatRowBuilder.build(store.messages, myLastReadId: store.unreadLineSnapshot,
                             myId: profile.me?.userId ?? "")
    }

    /// clientId ของข้อความล่าสุดที่เราส่งและส่งสำเร็จแล้ว — จุดที่โชว์สถานะอ่าน
    private var statusAnchorId: String? {
        store.messages.last { store.isMine($0) && $0.state == .sent }?.clientId
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case let .day(d):
                            ChatDayPill(day: d)
                        case .unreadMark:
                            ChatUnreadDivider()
                        case let .message(m, layout):
                            VStack(spacing: 0) {
                                ChatBubble(message: m, isMine: store.isMine(m), layout: layout,
                                           photoUrl: members[m.senderId]?.photoUrl,
                                           onRetry: { store.retry(m) },
                                           revealOffset: reveal)
                                if m.clientId == statusAnchorId {
                                    ChatReadStatusLine(
                                        text: ChatReadStatus.text(readCount: store.readCount(for: m),
                                                                  memberCount: store.memberCount))
                                }
                            }
                            .id(m.clientId)
                            .transition(.move(edge: .bottom).combined(with: .opacity)
                                            .combined(with: .scale(scale: 0.92, anchor: .bottom)))
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { g in
                g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 40
            } action: { _, isBottom in
                atBottom = isBottom
                if isBottom { newBelow = 0 }
            }
            // ปัดซ้ายค้าง = เผยเวลาทุกฟอง ปล่อยแล้วสปริงกลับ
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in
                        guard abs(v.translation.width) > abs(v.translation.height) else { return }
                        reveal = min(max(-v.translation.width, 0), 56)
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { reveal = 0 }
                    }
            )
            .overlay(alignment: .bottom) { newMessagePill(proxy) }
            .onChange(of: store.messages.count) { old, new in
                guard let last = store.messages.last else { return }
                // ข้อความที่เราเพิ่งส่งเอง ตามลงไปเสมอ ไม่งั้นพิมพ์เสร็จแล้วไม่เห็นของตัวเอง
                // อยู่ล่างสุดอยู่แล้วก็ตามลงไป — กำลังเลื่อนอ่านย้อนหลังห้ามกระชาก นับใส่ pill แทน
                if store.isMine(last) || atBottom {
                    scrollToBottom(proxy)
                } else if new > old {
                    newBelow += new - old
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = store.messages.last else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            proxy.scrollTo(last.clientId, anchor: .bottom)
        }
        newBelow = 0
    }

    @ViewBuilder
    private func newMessagePill(_ proxy: ScrollViewProxy) -> some View {
        if !atBottom && newBelow > 0 {
            Button { scrollToBottom(proxy) } label: {
                Label("ข้อความใหม่ \(newBelow)", systemImage: "arrow.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.wbwGold, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            }
            .padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            // สี่เหลี่ยมขอบมน ไม่ใช่ Capsule — ที่บรรทัดเดียวสองทรงนี้แยกกันแทบไม่ออก แต่พอ
            // lineLimit ขยายเป็น 4 บรรทัด แคปซูลกลายเป็นทรงยาปลายโค้งเกินจริง (เห็นจากสกรีนช็อต)
            TextField("ข้อความ", text: $draft, axis: .vertical)
                .font(.body)
                .lineLimit(1...4)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.wbwSurface,
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Button { send() } label: {
                Image(systemName: "paperplane.fill")
                    .font(.body.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.wbwGold, in: Circle())
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func send() {
        store.send(draft, senderName: profile.me?.displayName ?? "ฉัน")
        draft = ""
        sentTick += 1
    }
}
