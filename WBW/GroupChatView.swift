import SwiftUI
import SwiftData


/// แชทกลุ่ม — เต็มจอ (navbar หายไป) + bubble + floating input · offline-first ผ่าน ChatSession
struct GroupChatView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var groups: GroupStore
    @ObservedObject var store: ChatSession
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
            header
            if !store.connectivity.online { offlineBanner }
            messageList
        }
        .navigationBarHidden(true)   // หัวจอเป็นของเราเอง (ปุ่ม NavigationLink ใน header) ไม่ใช่ของระบบ
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
            store.setScreenVisible(true)
            let gid = profile.me?.groupId ?? 0
            let ms = await groups.members(groupId: gid, token: session.token ?? "")
            members = Dictionary(uniqueKeysWithValues: ms.map { ($0.userId, $0) })
        }
        .onDisappear {
            store.setScreenVisible(false)
        }
    }

    /// หัวจอ = ทางเข้าเดียวไปหน้ากลุ่ม (ไม่มีปุ่มปิดแล้ว — แชทเป็นแท็บ ไม่ใช่จอที่ลอยทับ)
    private var header: some View {
        NavigationLink(value: GroupRoute.home) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("กลุ่ม \(profile.me?.groupNumber.map(String.init) ?? "")")
                            .font(.system(size: 17, weight: .bold)).foregroundStyle(Color.wbwInk)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    Text("\(store.memberCount) คน").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())   // แตะได้ทั้งแถบ ไม่ใช่เฉพาะบนตัวอักษร
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        .background(Color.wbwBg)
    }

    private var offlineBanner: some View {
        Text("ออฟไลน์ — ข้อความจะส่งเมื่อกลับมามีสัญญาณ")
            .font(.system(size: 12)).foregroundStyle(.white)
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
                    .font(.system(size: 12, weight: .semibold))
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
            TextField("ข้อความ", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.wbwSurface, in: Capsule())
            Button { send() } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
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
