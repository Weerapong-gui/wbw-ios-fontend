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

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.messages) { m in
                        MessageBubble(message: m, isMine: store.isMine(m),
                                      photoUrl: members[m.senderId]?.photoUrl,
                                      onRetry: { store.retry(m) })
                            .id(m.clientId)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
            .onChange(of: store.messages.count) { _, _ in scrollToLast(proxy) }
            .onAppear { scrollToLast(proxy) }
        }
    }

    private func scrollToLast(_ proxy: ScrollViewProxy) {
        guard let last = store.messages.last else { return }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.clientId, anchor: .bottom) }
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

/// ฟองข้อความ
private struct MessageBubble: View {
    let message: ChatMessage
    let isMine: Bool
    let photoUrl: String?
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isMine { Spacer(minLength: 40) }
            if !isMine {
                ProfileAvatar(name: message.senderName, photoUrl: photoUrl, size: 30)
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                if !isMine {
                    Text(message.senderName).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(alignment: .bottom, spacing: 4) {
                    Text(message.body)
                        .font(.system(size: 15))
                        .foregroundStyle(isMine ? .white : Color.wbwInk)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(isMine ? Color.wbwGold : Color.white, in: RoundedRectangle(cornerRadius: 16))
                    if isMine { stateIcon }
                }
            }
            if !isMine { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder private var stateIcon: some View {
        switch message.state {
        case .pending: Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(.secondary)
        case .sent:    Image(systemName: "checkmark").font(.system(size: 10)).foregroundStyle(.secondary)
        case .failed:  Button(action: onRetry) { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 12)).foregroundStyle(.red) }
        }
    }
}
