import Foundation
import SwiftData

/// เครื่องยนต์แชท — อายุเท่าแอป (MainTabView ถือไว้) ไม่ใช่เท่าจอแชท
/// offline-first: cache + outbox (SwiftData), optimistic send, long-poll, flush ตอน reconnect
@MainActor
final class ChatSession: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var cursors: [ReadCursor] = []
    @Published private(set) var memberCount = 0
    @Published private(set) var unreadCount = 0
    @Published private(set) var myLastReadId: Int64 = 0
    /// ข้อความล่าสุดที่เพิ่งเข้ามาตอนไม่ได้เปิดจอแชท — ใช้เด้ง toast
    @Published var incoming: ChatMessage?

    let connectivity = Connectivity()

    private var context: ModelContext?
    private var groupId: Int?
    private var token = ""
    private var myId = ""
    private var cursor: Int64 = 0            // serverId สูงสุดที่มีแล้ว
    private var screenVisible = false
    private var syncTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var readDebounce: Task<Void, Never>?

    private var cursorKey: String { "chat.cursor.\(groupId ?? 0)" }
    private var readKey: String { "chat.read.\(groupId ?? 0)" }

    // ===== ค่าที่ view ใช้ =====

    func isMine(_ m: ChatMessage) -> Bool { m.senderId == myId }
    func readCount(for m: ChatMessage) -> Int { Self.readCount(for: m, cursors: cursors) }

    /// นับเฉพาะข้อความคนอื่นที่เกิน cursor เรา
    /// nonisolated: ฟังก์ชันบริสุทธิ์ ไม่แตะ state ของ actor — ให้เทสเรียกตรงๆ แบบ sync ได้ ไม่ต้อง await
    nonisolated static func unreadCount(messages: [ChatMessage], myLastReadId: Int64, myId: String) -> Int {
        messages.filter { $0.senderId != myId && ($0.serverId ?? 0) > myLastReadId }.count
    }

    /// กี่คนอ่านข้อความนี้แล้ว — cursors ไม่รวมตัวเราอยู่แล้ว (server ตัดให้)
    nonisolated static func readCount(for m: ChatMessage, cursors: [ReadCursor]) -> Int {
        guard let sid = m.serverId else { return 0 }   // ยังไม่ส่ง = ยังไม่มีใครอ่าน
        return cursors.filter { $0.lastReadId >= sid }.count
    }

    /// ข้อความนี้รอดจากจุดตัดประวัติมั้ย — ที่ยังไม่ส่ง (serverId = nil) รอดเสมอ
    nonisolated static func survivesCutoff(_ m: ChatMessage, sinceId: Int64) -> Bool {
        guard let sid = m.serverId else { return true }
        return sid > sinceId
    }

    // ===== วงจรชีวิต =====

    /// ตั้งกลุ่ม/ผู้ใช้ — เรียกซ้ำได้ ถ้าค่าเดิมจะไม่รีสตาร์ต
    func configure(groupId: Int?, token: String, myId: String, context: ModelContext) {
        self.context = context
        self.token = token
        self.myId = myId
        guard self.groupId != groupId else { return }

        stop()
        self.groupId = groupId
        guard groupId != nil else {
            messages = []; cursors = []; memberCount = 0; unreadCount = 0; myLastReadId = 0
            return
        }
        cursor = Int64(UserDefaults.standard.integer(forKey: cursorKey))
        myLastReadId = Int64(UserDefaults.standard.integer(forKey: readKey))
        loadCache()
        connectivity.onReconnect = { [weak self] in
            guard let self else { return }
            Task { await self.flushOutbox(); self.start() }
        }
        start()
    }

    func start() {
        guard groupId != nil, syncTask == nil else { return }
        syncTask = Task { [weak self] in
            await self?.flushOutbox()
            await self?.syncLoop()
        }
    }

    func stop() {
        syncTask?.cancel(); syncTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        readDebounce?.cancel(); readDebounce = nil
    }

    /// จอแชทเปิด/ปิด — คุม heartbeat และการเด้ง toast
    func setScreenVisible(_ visible: Bool) {
        screenVisible = visible
        heartbeatTask?.cancel(); heartbeatTask = nil
        guard visible else { return }
        markRead()
        // heartbeat: บอก server ว่ายังจ้อจออยู่ ไม่งั้นโดน push ทั้งที่กำลังอ่าน
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.postRead(self.myLastReadId)
            }
        }
    }

    // ===== ส่งข้อความ (เหมือนเดิม) =====

    func send(_ text: String, senderName: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let gid = groupId, let context else { return }
        let msg = ChatMessage(clientId: UUID().uuidString, serverId: nil, groupId: gid,
                              senderId: myId, body: t, deviceTime: Date(), createdAt: nil,
                              senderName: senderName, state: .pending)
        context.insert(msg)
        try? context.save()
        messages = sorted(messages + [msg])
        Task { await flushOutbox() }
    }

    func retry(_ m: ChatMessage) {
        m.state = .pending
        try? context?.save()
        messages = sorted(messages)
        Task { await flushOutbox() }
    }

    // ===== สถานะอ่าน =====

    /// อ่านถึงข้อความล่าสุด — หน่วง 500ms กันยิงรัวตอนข้อความไหลเข้า
    func markRead() {
        let maxId = messages.compactMap(\.serverId).max() ?? 0
        guard maxId > myLastReadId else { return }
        myLastReadId = maxId
        UserDefaults.standard.set(Int(maxId), forKey: readKey)
        recomputeUnread()
        readDebounce?.cancel()
        readDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.postRead(self.myLastReadId)
        }
    }

    private func postRead(_ id: Int64) async {
        guard let gid = groupId, !token.isEmpty else { return }
        await APIClient.shared.chatRead(token: token, groupId: gid, lastReadId: id)   // ไม่ throw
    }

    // ===== เครื่องยนต์ =====

    private func loadCache() {
        guard let context, let gid = groupId else { return }
        let desc = FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.groupId == gid })
        messages = sorted((try? context.fetch(desc)) ?? [])
        recomputeUnread()
    }

    private func syncLoop() async {
        var backoff: UInt64 = 1
        while !Task.isCancelled {
            guard let gid = groupId, !token.isEmpty else { return }
            guard connectivity.online else {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }
            do {
                let r = try await APIClient.shared.chatSync(token: token, groupId: gid,
                                                            after: cursor, wait: 25)
                apply(r)
                if messages.contains(where: { $0.state == .pending }) { await flushOutbox() }
                backoff = 1                     // สำเร็จ = วนต่อทันที (หมดเวลา = messages ว่าง ไม่ใช่ error)
            } catch AppError.notInGroup {
                purgeAll()
                return                          // โดนเอาออกจากกลุ่ม — หยุด loop
            } catch {
                try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                backoff = min(backoff * 2, 10)
            }
        }
    }

    private func apply(_ r: ChatSyncResponse) {
        if r.sinceId > 0 { purge(upTo: r.sinceId) }
        memberCount = r.memberCount
        cursors = r.cursors
        let fresh = merge(r.messages)
        recomputeUnread()
        if !screenVisible, let last = fresh.last(where: { $0.senderId != myId }) {
            incoming = last            // ให้ MainTabView เด้ง toast
        }
        if screenVisible { markRead() }
    }

    /// server บอกว่าเห็นได้แค่ > sinceId → ของเก่าในเครื่องลบทิ้ง (เข้ากลุ่มใหม่ = ตัดประวัติ)
    private func purge(upTo sinceId: Int64) {
        let stale = messages.filter { !Self.survivesCutoff($0, sinceId: sinceId) }
        guard !stale.isEmpty, let context else { return }
        for m in stale { context.delete(m) }
        try? context.save()
        messages = messages.filter { Self.survivesCutoff($0, sinceId: sinceId) }
    }

    private func purgeAll() {
        guard let context else { return }
        for m in messages { context.delete(m) }
        try? context.save()
        messages = []; cursors = []; unreadCount = 0
    }

    /// รวมข้อความจาก server — dedupe ตาม clientId. คืนเฉพาะอันที่เพิ่งเข้ามาใหม่จริงๆ
    @discardableResult
    private func merge(_ dtos: [MessageDTO]) -> [ChatMessage] {
        guard let context, let gid = groupId else { return [] }
        var fresh: [ChatMessage] = []
        for dto in dtos {
            guard let sid = Int64(dto.id) else { continue }
            if let existing = messages.first(where: { $0.clientId == dto.clientId }) {
                if existing.serverId == nil {
                    existing.serverId = sid
                    existing.createdAt = parseISO(dto.createdAt)
                    existing.state = .sent
                }
            } else if !messages.contains(where: { $0.serverId == sid }) {
                let m = ChatMessage(clientId: dto.clientId, serverId: sid, groupId: gid,
                                    senderId: dto.senderId, body: dto.body,
                                    deviceTime: parseISO(dto.deviceTime) ?? Date(),
                                    createdAt: parseISO(dto.createdAt),
                                    senderName: dto.senderName, state: .sent)
                context.insert(m)
                messages.append(m)
                fresh.append(m)
            }
            if sid > cursor { cursor = sid }
        }
        UserDefaults.standard.set(Int(cursor), forKey: cursorKey)
        try? context.save()
        messages = sorted(messages)
        return fresh
    }

    /// ส่ง pending ตามลำดับ — เน็ตล่ม=หยุด (retry รอบหน้า), 4xx=mark failed แล้วทำต่อ
    private func flushOutbox() async {
        guard let gid = groupId, !token.isEmpty, let context else { return }
        let pending = messages.filter { $0.state == .pending }.sorted { $0.deviceTime < $1.deviceTime }
        for m in pending {
            do {
                let dto = try await APIClient.shared.sendMessage(
                    token: token, groupId: gid, clientId: m.clientId,
                    body: m.body, deviceTime: iso(m.deviceTime))
                m.serverId = Int64(dto.id) ?? m.serverId
                m.createdAt = parseISO(dto.createdAt)
                m.state = .sent
                if let sid = m.serverId, sid > cursor {
                    cursor = sid
                    UserDefaults.standard.set(Int(cursor), forKey: cursorKey)
                }
                try? context.save()
                messages = sorted(messages)
            } catch AppError.offline {
                break
            } catch {
                m.state = .failed
                try? context.save()
                messages = sorted(messages)
            }
        }
    }

    private func recomputeUnread() {
        unreadCount = Self.unreadCount(messages: messages, myLastReadId: myLastReadId, myId: myId)
    }

    // เรียงตาม serverId (นาฬิกาเครื่องเพี้ยนได้ — pending ต่อท้าย)
    private func sorted(_ arr: [ChatMessage]) -> [ChatMessage] {
        arr.sorted { a, b in
            switch (a.serverId, b.serverId) {
            case let (x?, y?): return x < y
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return a.deviceTime < b.deviceTime
            }
        }
    }

    private let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private func iso(_ d: Date) -> String { isoFmt.string(from: d) }
    private func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoFmt.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
