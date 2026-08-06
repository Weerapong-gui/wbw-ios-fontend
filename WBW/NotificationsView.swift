import SwiftUI

/// เก็บรายการประกาศ + จำนวนที่ยังไม่อ่าน (ใช้ทำ badge ที่แท็บ)
@MainActor
final class NotiStore: ObservableObject {
    @Published var items: [NotificationItem] = []
    @Published var loaded = false

    var unreadCount: Int { items.filter { $0.isUnread }.count }

    /// ดึงรายการล่าสุด (เงียบตอนออฟไลน์ — คงรายการเดิม)
    ///
    /// รักษา readAt ที่เพิ่งมาร์คในเครื่องไว้ ไม่ให้ของจากเซิร์ฟเวอร์ทับกลับเป็น unread — markFeedbackNotiRead
    /// (MainTabView) มาร์คในเครื่องก่อนแล้วยิง markRead แบบ fire-and-forget ถ้า load() รอบนี้มาถึงก่อนคำขอ
    /// นั้นจะจบที่เซิร์ฟเวอร์ รายการที่ได้กลับมาจะยังเป็น unread และ badge จะเด้งกลับ เพราะ
    /// pendingReadCheckpoint ถูกเคลียร์ไปแล้วตั้งแต่เจอแถวครั้งแรก ไม่มีอะไรลองมาร์คซ้ำให้อีก
    func load(token: String) async {
        guard !token.isEmpty else { return }
        if let list = try? await APIClient.shared.notifications(token: token) {
            let readLocally = items.reduce(into: [String: String]()) { dict, item in
                if let r = item.readAt { dict[item.id] = r }
            }
            items = list.map { item in
                guard item.readAt == nil, let keep = readLocally[item.id] else { return item }
                var m = item; m.readAt = keep; return m
            }
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
    /// แตะการ์ด SOS ของเพื่อนในกลุ่ม (case id ที่มันพูดถึง) — ทรงเดียวกับ onOpenFeedback ทุกประการ
    /// การ์ดประกาศทั่วไป/การ์ดขอความเห็นไม่เรียกตัวนี้เลย (sosId เป็น nil)
    let onOpenSOS: (Int64) -> Void

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
                                // เฉพาะการ์ดขอความเห็น/การ์ด SOS กดได้ — การ์ดประกาศทั่วไปเรนเดอร์เหมือนเดิมทุกอย่าง
                                if let checkpointId = item.feedbackCheckpointId {
                                    Button { onOpenFeedback(checkpointId) } label: { NotiCard(item: item) }
                                        .buttonStyle(.plain)
                                } else if let sosId = item.sosId {
                                    Button { onOpenSOS(sosId) } label: { NotiCard(item: item) }
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
/// การ์ดขอความเห็น (feedbackCheckpointId != nil) และการ์ด SOS (sosId != nil) มีสี/ไอคอน/เชฟรอนของ
/// ตัวเอง เช็คก่อน switch ตาม item.level เดิมเสมอ ไม่งั้นการ์ดประกาศทั่วไปจะเปลี่ยนหน้าตาไปด้วย —
/// เช็คจาก feedbackCheckpointId/sosId (ไม่ใช่ item.type ตรงๆ) ตัวเดียวกับที่ NotificationsView ใช้
/// ตัดสินใจห่อ Button ด้านบน กันไม่ให้การ์ดดูกดได้ (สี+เชฟรอน) ทั้งที่แตะแล้วไม่มีอะไรเกิดขึ้นจริง
private struct NotiCard: View {
    let item: NotificationItem

    private var isFeedback: Bool { item.feedbackCheckpointId != nil }
    private var isSOS: Bool { item.sosId != nil }
    /// การ์ดที่ห่อด้วย Button จริงใน NotificationsView — ใช้ตัดสินใจโชว์เชฟรอน ไม่งั้นการ์ดกดได้
    /// (SOS) แต่ไม่มีเชฟรอนบอกจะดูเหมือนกดไม่ได้ ซึ่งเป็นบั๊กคนละทิศกับ "ดูกดได้แต่กดไม่ได้" ที่เคย
    /// พบในหน้า login (ดูคอมเมนต์ที่ LoginView) — แต่ผลลัพธ์เสียหายแบบเดียวกันคือผู้ใช้พลาดทางเข้า
    private var isTappable: Bool { isFeedback || isSOS }

    private var accent: Color {
        if isFeedback { return Color.wbwGreen }
        // SOS ใช้สีแดงเดียวกับ "emergency" — เคสฉุกเฉินจริงของเพื่อน ต้องเด่นกว่าประกาศทั่วไปเสมอ
        // ไม่ว่า server จะส่ง level มาเป็นอะไร (ปัจจุบันคือ "urgent" ซึ่งไม่มีอยู่ใน switch ด้านล่าง)
        if isSOS || item.level == "emergency" { return Color(red: 0.84, green: 0.27, blue: 0.27) } // แดง
        switch item.level {
        case "warning":   return Color.wbwGold
        default:          return Color.wbwInk
        }
    }
    private var icon: String {
        if isSOS { return "sos" } // ไอคอนเดียวกับที่ StaffSOSAlertView ใช้อยู่แล้ว
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
            // เชฟรอนบอกว่ากดได้ — เฉพาะการ์ดขอความเห็น/การ์ด SOS การ์ดประกาศทั่วไปไม่ได้ห่อ Button ไว้ (ดู
            // NotificationsView) เชฟรอนเลยต้องไม่โผล่ให้เข้าใจผิดว่ากดได้
            if isTappable {
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
