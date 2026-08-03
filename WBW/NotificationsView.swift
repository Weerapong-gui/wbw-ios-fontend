import SwiftUI

/// เก็บรายการประกาศ + จำนวนที่ยังไม่อ่าน (ใช้ทำ badge ที่แท็บ)
@MainActor
final class NotiStore: ObservableObject {
    @Published var items: [NotificationItem] = []
    @Published var loaded = false

    var unreadCount: Int { items.filter { $0.isUnread }.count }

    /// ดึงรายการล่าสุด (เงียบตอนออฟไลน์ — คงรายการเดิม)
    func load(token: String) async {
        guard !token.isEmpty else { return }
        if let list = try? await APIClient.shared.notifications(token: token) {
            items = list
        }
        loaded = true
    }

    /// อ่านทั้งหมด (เรียกตอนเปิดหน้า) — ยิง markRead แล้วอัปเดตในเครื่อง
    func markAllRead(token: String) async {
        let unread = items.filter { $0.isUnread }
        guard !token.isEmpty, !unread.isEmpty else { return }
        for n in unread { try? await APIClient.shared.markRead(token: token, id: n.id) }
        let now = ISO8601DateFormatter().string(from: Date())
        items = items.map { var m = $0; if m.isUnread { m.readAt = now }; return m }
    }
}

/// หน้าประกาศ/แจ้งเตือน (แท็บ newspaper) — participant เท่านั้น
struct NotificationsView: View {
    @ObservedObject var store: NotiStore
    let token: String
    /// แตะการ์ดขอความเห็น (checkpoint id ที่มันพูดถึง) — Task 11 ผูกว่าเปิดอะไรต่อ การ์ดประกาศทั่วไป
    /// ไม่เรียกตัวนี้เลย (feedbackCheckpointId เป็น nil)
    let onOpenFeedback: (Int) -> Void

    private let bg = Color(red: 250 / 255, green: 247 / 255, blue: 240 / 255) // ครีมอ่อน #FAF7F0

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()
                if store.loaded && store.items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.items) { item in
                                // เฉพาะการ์ดขอความเห็นกดได้ — การ์ดประกาศทั่วไปเรนเดอร์เหมือนเดิมทุกอย่าง
                                if let checkpointId = item.feedbackCheckpointId {
                                    Button { onOpenFeedback(checkpointId) } label: { NotiCard(item: item) }
                                        .buttonStyle(.plain)
                                } else {
                                    NotiCard(item: item)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
            }
            .navigationTitle("ประกาศ")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            await store.load(token: token)
            await store.markAllRead(token: token)
        }
        .refreshable { await store.load(token: token) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("ยังไม่มีประกาศ")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

/// การ์ดประกาศ 1 รายการ — แถบสีซ้ายตามระดับความสำคัญ
/// การ์ดขอความเห็น (feedbackCheckpointId != nil) มีสี/ไอคอน/เชฟรอนของตัวเอง เช็คก่อน switch ตาม
/// item.level เดิมเสมอ ไม่งั้นการ์ดประกาศทั่วไปจะเปลี่ยนหน้าตาไปด้วย — เช็คจาก feedbackCheckpointId
/// (ไม่ใช่ item.type ตรงๆ) ตัวเดียวกับที่ NotificationsView ใช้ตัดสินใจห่อ Button ด้านบน กันไม่ให้การ์ด
/// ดูกดได้ (สีเขียว+เชฟรอน) ทั้งที่แตะแล้วไม่มีอะไรเกิดขึ้นจริง
private struct NotiCard: View {
    let item: NotificationItem

    private var isFeedback: Bool { item.feedbackCheckpointId != nil }

    private var accent: Color {
        if isFeedback { return Color.wbwGreen }
        switch item.level {
        case "emergency": return Color(red: 0.84, green: 0.27, blue: 0.27) // แดง
        case "warning":   return Color.wbwGold
        default:          return Color.wbwInk
        }
    }
    private var icon: String {
        if isFeedback { return "checkmark.seal.fill" }
        switch item.level {
        case "emergency": return "exclamationmark.triangle.fill"
        case "warning":   return "exclamationmark.triangle"
        default:          return "megaphone.fill"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(accent).frame(width: 5)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.wbwInk)
                    Spacer(minLength: 4)
                    if item.isUnread {
                        Circle().fill(accent).frame(width: 8, height: 8)
                    }
                }
                if let b = item.body, !b.isEmpty {
                    Text(b)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.timeText.isEmpty {
                    Text(item.timeText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            Spacer(minLength: 0)
            // เชฟรอนบอกว่ากดได้ — เฉพาะการ์ดขอความเห็น การ์ดประกาศทั่วไปไม่ได้ห่อ Button ไว้ (ดู
            // NotificationsView) เชฟรอนเลยต้องไม่โผล่ให้เข้าใจผิดว่ากดได้
            if isFeedback {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 14)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05), lineWidth: 1))
    }
}
