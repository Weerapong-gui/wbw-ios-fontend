import SwiftUI

/// เก็บรายการประกาศ + จำนวนที่ยังไม่อ่าน (ใช้ทำ badge ที่แท็บ)
@MainActor
final class NotiStore: ObservableObject {
    @Published var items: [NotificationItem] = []
    @Published var loaded = false
    /// รอบล่าสุดยิงไม่ถึงเซิร์ฟเวอร์ — คนละเรื่องกับ "ยิงถึงแล้วไม่มีประกาศ"
    @Published var loadFailed = false

    /// สิ่งที่ควรทับจอตอนไม่มีรายการ
    enum EmptyState { case loading, empty, failed, none }

    /// แยกเป็น static func ที่รับทุกอย่างเข้ามา เทสจึงเรียกครบทุกสาขาได้โดยไม่ต้องมีเน็ตจริง
    /// · `nonisolated` เพราะไม่แตะ state ของคลาสเลย เทสจึงไม่ต้องเป็น `@MainActor` ตามไปด้วย
    nonisolated static func emptyState(loaded: Bool, failed: Bool, isEmpty: Bool) -> EmptyState {
        guard isEmpty else { return .none }        // มีของเก่าค้างอยู่ = โชว์ของเก่าไป
        guard loaded else { return .loading }
        return failed ? .failed : .empty
    }

    var unreadCount: Int { items.filter { $0.isUnread }.count }

    /// ดึงรายการล่าสุด (เงียบตอนออฟไลน์ — คงรายการเดิม)
    ///
    /// รักษา readAt ที่เพิ่งมาร์คในเครื่องไว้ ไม่ให้ของจากเซิร์ฟเวอร์ทับกลับเป็น unread — markFeedbackNotiRead
    /// (MainTabView) มาร์คในเครื่องก่อนแล้วยิง markRead แบบ fire-and-forget ถ้า load() รอบนี้มาถึงก่อนคำขอ
    /// นั้นจะจบที่เซิร์ฟเวอร์ รายการที่ได้กลับมาจะยังเป็น unread และ badge จะเด้งกลับ เพราะ
    /// pendingReadCheckpoint ถูกเคลียร์ไปแล้วตั้งแต่เจอแถวครั้งแรก ไม่มีอะไรลองมาร์คซ้ำให้อีก
    func load(token: String) async {
        guard !token.isEmpty else { return }
        // ต้องแยก "ยิงไม่ถึง" ออกจาก "ไม่มีประกาศ" — `try?` เดิมทำให้สองอย่างนี้หน้าตาเหมือนกัน
        // บนจอทุกประการ (ดู emptyState ข้างบน)
        #if DEBUG
        // ถ่ายจอ "ยิงไม่ถึง" ตรง ๆ — ตัดเน็ตของซิมูเลเตอร์จากข้างนอกทำไม่ได้ และโหมดเดโม่ก็ไม่
        // ยิงเน็ตเลยอยู่แล้ว จึงไม่มีทางเห็นสาขานี้ด้วยวิธีอื่น (กติกาข้อ 8: จอที่แก้ต้องมีรูป)
        if UserDefaults.standard.bool(forKey: "uitestNotiLoadFailed") {
            items = []
            loadFailed = true
            loaded = true
            return
        }
        #endif
        let list = try? await APIClient.shared.notifications(token: token)
        loadFailed = list == nil
        if let list {
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

/// หน้าประกาศ/แจ้งเตือน — เปิดเป็นชีตจากกระดิ่งที่ Home (ดู MainTabView) · participant เท่านั้น
///
/// **2026-08-20: เขียนใหม่เป็น `List` ของระบบ** เดิมเป็น `LazyVStack` + การ์ดมือทำที่มีแถบสีซ้าย
/// 5 pt กับกรอบ `stroke(.black.opacity(0.05))` — กรอบนั้นมองไม่เห็นเลยในโหมดมืด (ดำบนดำ) และ
/// การ์ดขาวเรียงติดกันเต็มจอไม่มีอะไรบอกว่าอันไหนมาวันไหน · ตอนนี้ระดับความสำคัญอยู่ที่สีไอคอน
/// และวันอยู่ที่หัวกลุ่ม (`NotificationGrouping`)
struct NotificationsView: View {
    @ObservedObject var store: NotiStore
    let token: String
    /// แตะการ์ดขอความเห็น (checkpoint id ที่มันพูดถึง) — Task 11 ผูกว่าเปิดอะไรต่อ การ์ดประกาศทั่วไป
    /// ไม่เรียกตัวนี้เลย (feedbackCheckpointId เป็น nil)
    let onOpenFeedback: (Int) -> Void
    /// แตะการ์ด SOS (เลขเคสที่มันพูดถึง) — พาไปจอเพื่อนที่กดขอความช่วยเหลือ
    /// การ์ดประกาศทั่วไป/การ์ดขอความเห็นไม่เรียกตัวนี้เลย (`sosId` เป็น nil)
    let onOpenSOS: (Int64) -> Void

    @Environment(\.dismiss) private var dismiss
    /// ตรึง "ตอนนี้" ไว้ตอนเปิดจอ ไม่ใช่เรียก `Date()` ระหว่างสร้าง body — ไม่งั้นแถวที่นั่งอยู่เฉย ๆ
    /// จะกระโดดจากกลุ่ม "วันนี้" ไป "เมื่อวาน" เองตอนนาฬิกาข้ามเที่ยงคืน ทั้งที่ผู้ใช้ไม่ได้ทำอะไร
    @State private var openedAt = Date()

    private var sections: [NotificationGrouping.Section] {
        NotificationGrouping.sections(store.items, now: openedAt)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { row($0) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.wbwBg)
            .overlay {
                switch NotiStore.emptyState(loaded: store.loaded,
                                            failed: store.loadFailed,
                                            isEmpty: store.items.isEmpty) {
                case .empty:
                    ContentUnavailableView("notifications_empty", systemImage: "bell.slash",
                                           description: Text("notifications_empty_desc"))
                case .failed:
                    ContentUnavailableView {
                        Label("error_load_announcements", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("error_network")
                    } actions: {
                        Button("action_retry") {
                            Task { await store.load(token: token) }
                        }
                        .buttonStyle(.borderedProminent)
                        // ไม่ tint แล้วได้ฟ้าของระบบ ซึ่งไม่ใช่สีของแอปนี้เลยสักที่
                        .tint(Color.wbwGreen)
                        .foregroundStyle(Color.wbwOnGreen)
                    }
                case .loading, .none:
                    EmptyView()
                }
            }
            .navigationTitle(Text("notifications_title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // จอนี้เปิดเป็น .sheet — เดิมไม่มีปุ่มปิดเลย ปัดลงอย่างเดียว
                ToolbarItem(placement: .confirmationAction) {
                    Button("action_done") { dismiss() }
                }
            }
            .refreshable { await store.load(token: token) }
        }
        .task {
            await store.load(token: token)
            await store.markAllRead(token: token)
        }
    }

    /// เฉพาะการ์ดขอความเห็นกับการ์ด SOS กดได้ — การ์ดประกาศทั่วไปเรนเดอร์เหมือนเดิมทุกอย่าง
    @ViewBuilder
    private func row(_ item: NotificationItem) -> some View {
        if let checkpointId = item.feedbackCheckpointId {
            Button { onOpenFeedback(checkpointId) } label: {
                NotiRow(item: item, now: openedAt, showsChevron: true)
            }
            .buttonStyle(.plain)
        } else if let sosId = item.sosId {
            Button { onOpenSOS(sosId) } label: {
                NotiRow(item: item, now: openedAt, showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            NotiRow(item: item, now: openedAt, showsChevron: false)
        }
    }
}

/// ประกาศ 1 แถว — ไอคอนในวงกลมสีตามระดับความสำคัญ
///
/// การ์ดขอความเห็น (feedbackCheckpointId != nil) กับการ์ด SOS (sosId != nil) มีสี/ไอคอนของตัวเอง
/// เช็คก่อน switch ตาม item.level เดิมเสมอ ไม่งั้นประกาศทั่วไปจะเปลี่ยนหน้าตาไปด้วย —
/// เช็คจาก `feedbackCheckpointId`/`sosId` ไม่ใช่ `item.type` ตรง ๆ ตัวเดียวกับที่
/// `NotificationsView.row` ใช้ตัดสินว่าจะห่อ Button ไหม สองที่จึงไม่มีทางไม่ตรงกัน
private struct NotiRow: View {
    let item: NotificationItem
    let now: Date
    /// เชฟรอนบอกว่ากดได้ — ตัดสินจากฝั่งที่ห่อ Button จริง (ดู NotificationsView.row) ไม่ใช่เดาเอง
    /// ในนี้ ไม่งั้นแถวที่แตะแล้วไม่มีอะไรเกิดขึ้นจะดูเหมือนกดได้
    let showsChevron: Bool

    private var isFeedback: Bool { item.feedbackCheckpointId != nil }
    private var isSOS: Bool { item.sosId != nil }

    private var accent: Color {
        if isFeedback { return Color.wbwGreen }
        // เคส SOS แดงเสมอ ไม่ว่า level ที่ backend ใส่มาจะเป็นอะไร
        if isSOS { return Color(red: 0.84, green: 0.27, blue: 0.27) }
        switch item.level {
        case "emergency": return Color(red: 0.84, green: 0.27, blue: 0.27) // แดง
        case "warning":   return Color.wbwGold
        default:          return Color.wbwInk
        }
    }
    private var icon: String {
        if isFeedback { return "checkmark.seal.fill" }
        if isSOS { return "sos" }   // ไอคอนเดียวกับที่จอเคสของเจ้าหน้าที่ใช้
        switch item.level {
        case "emergency": return "exclamationmark.triangle.fill"
        case "warning":   return "exclamationmark.triangle"
        default:          return "megaphone.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(.subheadline).weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.wbwTitleMedium)
                    .foregroundStyle(Color.wbwInk)
                if let b = item.body, !b.isEmpty {
                    Text(b)
                        .font(.wbwText(13, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let time = NotificationGrouping.rowTime(item, now: now)
                if !time.isEmpty {
                    Text(time)
                        .font(.wbwText(11, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if item.isUnread {
                Circle().fill(accent).frame(width: 8, height: 8).padding(.top, 12)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.caption).weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 10)
            }
        }
        .padding(.vertical, 4)
    }
}
