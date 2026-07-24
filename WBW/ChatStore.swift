import Foundation
import SwiftData

/// เครื่องยนต์แชท offline-first — cache + outbox (SwiftData), optimistic send, poll, flush ตอน reconnect
@MainActor
final class ChatStore: ObservableObject {
    @Published var messages: [ChatMessage] = []
    let connectivity = Connectivity()

    private let context: ModelContext
    private let groupId: Int
    private let token: String
    private let myId: String
    private let cursorKey: String
    private var cursor: Int64
    private var pollTask: Task<Void, Never>?

    init(groupId: Int, token: String, myId: String, context: ModelContext) {
        self.groupId = groupId
        self.token = token
        self.myId = myId
        self.context = context
        self.cursorKey = "chat.cursor.\(groupId)"
        self.cursor = Int64(UserDefaults.standard.integer(forKey: cursorKey))
    }

    func isMine(_ m: ChatMessage) -> Bool { m.senderId == myId }

    // เปิดแชท: โหลด cache (ทันที) → flush ค้าง → เริ่ม poll
    func open() {
        loadCache()
        connectivity.onReconnect = { [weak self] in
            guard let self else { return }
            Task { await self.flushOutbox(); self.startPoll() }
        }
        Task { await flushOutbox(); startPoll() }
    }

    func close() { pollTask?.cancel(); pollTask = nil }

    // ส่งข้อความ — โชว์ทันที (pending) แล้วค่อยส่ง
    func send(_ text: String, senderName: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let msg = ChatMessage(clientId: UUID().uuidString, serverId: nil, groupId: groupId,
                              senderId: myId, body: t, deviceTime: Date(), createdAt: nil,
                              senderName: senderName, state: .pending)
        context.insert(msg)
        try? context.save()
        messages = sorted(messages + [msg])
        Task { await flushOutbox() }
    }

    // แตะข้อความที่ล้มเหลว → ลองส่งใหม่
    func retry(_ m: ChatMessage) {
        m.state = .pending
        try? context.save()
        messages = sorted(messages)
        Task { await flushOutbox() }
    }

    // ===== เครื่องยนต์ =====

    private func loadCache() {
        let gid = groupId
        let desc = FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.groupId == gid })
        messages = sorted((try? context.fetch(desc)) ?? [])
    }

    /// ส่ง pending ตามลำดับ — เน็ตล่ม=หยุด (retry รอบหน้า), 4xx=mark failed แล้วทำต่อ
    private func flushOutbox() async {
        let pending = messages.filter { $0.state == .pending }.sorted { $0.deviceTime < $1.deviceTime }
        for m in pending {
            do {
                let dto = try await APIClient.shared.sendMessage(
                    token: token, groupId: groupId, clientId: m.clientId, body: m.body, deviceTime: iso(m.deviceTime))
                m.serverId = Int64(dto.id) ?? m.serverId
                m.createdAt = parseISO(dto.createdAt)
                m.state = .sent
                if let sid = m.serverId, sid > cursor { cursor = sid; saveCursor() }
                try? context.save()
                messages = sorted(messages)
            } catch AppError.offline {
                break   // เน็ตล่ม — คงลำดับ retry รอบหน้า/ตอน reconnect
            } catch {
                m.state = .failed   // 4xx/อื่น — กันบล็อกคิว
                try? context.save()
                messages = sorted(messages)
            }
        }
    }

    private func startPoll() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.connectivity.online { await self.pollOnce() }
                // 5-8 วิ + jitter — กันทุกเครื่อง poll พร้อมกันเป๊ะ (thundering herd ตอน 2000 คน)
                try? await Task.sleep(nanoseconds: UInt64.random(in: 5_000_000_000...8_000_000_000))
            }
        }
    }

    private func pollOnce() async {
        do {
            let after = cursor > 0 ? String(cursor) : nil
            let dtos = try await APIClient.shared.messages(token: token, groupId: groupId, after: after)
            merge(dtos)
            if messages.contains(where: { $0.state == .pending }) { await flushOutbox() }
        } catch {
            // เงียบ — poll รอบหน้าลองใหม่
        }
    }

    /// รวมข้อความจาก server — dedupe ตาม clientId (ของเรา echo กลับ = upgrade ไม่ซ้ำ)
    private func merge(_ dtos: [MessageDTO]) {
        for dto in dtos {
            guard let sid = Int64(dto.id) else { continue }
            if let existing = messages.first(where: { $0.clientId == dto.clientId }) {
                if existing.serverId == nil {
                    existing.serverId = sid
                    existing.createdAt = parseISO(dto.createdAt)
                    existing.state = .sent
                }
            } else if !messages.contains(where: { $0.serverId == sid }) {
                let m = ChatMessage(clientId: dto.clientId, serverId: sid, groupId: groupId,
                                    senderId: dto.senderId, body: dto.body,
                                    deviceTime: parseISO(dto.deviceTime) ?? Date(),
                                    createdAt: parseISO(dto.createdAt), senderName: dto.senderName, state: .sent)
                context.insert(m)
                messages.append(m)
            }
            if sid > cursor { cursor = sid }
        }
        saveCursor()
        try? context.save()
        messages = sorted(messages)
    }

    // เรียงตาม serverId (นาฬิกาดอยเพี้ยน — pending ต่อท้าย)
    private func sorted(_ arr: [ChatMessage]) -> [ChatMessage] {
        arr.sorted { a, b in
            switch (a.serverId, b.serverId) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.deviceTime < b.deviceTime
            }
        }
    }

    private func saveCursor() { UserDefaults.standard.set(Int(cursor), forKey: cursorKey) }

    private let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private func iso(_ d: Date) -> String { isoFmt.string(from: d) }
    private func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoFmt.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
