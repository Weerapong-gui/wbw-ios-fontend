import SwiftUI
import SwiftData

private let bg = Color(red: 250 / 255, green: 247 / 255, blue: 240 / 255)

/// แชทกลุ่ม — เต็มจอ (navbar หายไป) + bubble + floating input · offline-first ผ่าน ChatSession
struct GroupChatView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var groups: GroupStore
    @ObservedObject var store: ChatSession
    let onClose: () -> Void
    @State private var draft = ""
    @State private var members: [String: GroupMember] = [:]   // senderId → member (avatar)

    var body: some View {
        VStack(spacing: 0) {
            header
            if !store.connectivity.online { offlineBanner }
            messageList
        }
        .background(bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { inputBar }
        .task {
            store.setScreenVisible(true)
            let gid = profile.me?.groupId ?? 0
            let ms = await groups.members(groupId: gid, token: session.token ?? "")
            members = Dictionary(uniqueKeysWithValues: ms.map { ($0.userId, $0) })
        }
        .onDisappear { store.setScreenVisible(false) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.wbwInk)
                    .frame(width: 40, height: 40).background(Color.white, in: Circle())
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("แชทกลุ่ม \(profile.me?.groupNumber.map(String.init) ?? "")")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(Color.wbwInk)
                Text("\(store.memberCount) คน").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        .background(bg)
    }

    private var offlineBanner: some View {
        Text("ออฟไลน์ — ข้อความจะส่งเมื่อกลับมามีสัญญาณ")
            .font(.system(size: 12)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(Color.gray)
    }

    private var rows: [ChatRow] {
        ChatRowBuilder.build(store.messages, myLastReadId: store.myLastReadId,
                             myId: profile.me?.userId ?? "")
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    switch row {
                    case let .day(d):
                        ChatDayPill(day: d)
                    case .unreadMark:
                        ChatUnreadDivider()
                    case let .message(m, layout):
                        ChatBubble(message: m, isMine: store.isMine(m), layout: layout,
                                   photoUrl: members[m.senderId]?.photoUrl,
                                   onRetry: { store.retry(m) })
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("ข้อความ", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.white, in: Capsule())
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
    }
}
