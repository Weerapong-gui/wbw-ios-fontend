import Foundation
import SwiftData
import UserNotifications

/// เครื่องยนต์แชท — อายุเท่าแอป (MainTabView ถือไว้) ไม่ใช่เท่าจอแชท
/// offline-first: cache + outbox (SwiftData), optimistic send, long-poll, flush ตอน reconnect
@MainActor
final class ChatSession: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var cursors: [ReadCursor] = []
    @Published private(set) var memberCount = 0
    @Published private(set) var unreadCount = 0
    @Published private(set) var myLastReadId: Int64 = 0
    /// ค่า myLastReadId ณ วินาทีที่จอแชทเปิด — ChatRowBuilder ใช้วางเส้น "ข้อความใหม่"
    ///
    /// เริ่มที่ .max ไม่ใช่ 0 ตั้งใจ: "ยังไม่สแนป" ต้องแปลว่า "อ่านหมดแล้ว" ไม่ใช่ "ยังไม่อ่านเลย"
    /// ถ้าเริ่มที่ 0 เฟรมแรกก่อนสแนปจะมองว่าข้อความคนอื่นแทบทุกอันยังไม่อ่าน เส้นจะไปโผล่ที่
    /// ข้อความเก่าสุดก่อนวาบไปตำแหน่งจริง
    @Published private(set) var unreadLineSnapshot: Int64 = .max
    /// ข้อความล่าสุดที่เพิ่งเข้ามาตอนไม่ได้เปิดจอแชท — ใช้เด้ง toast
    @Published var incoming: ChatMessage?
    /// คนนี้ถูกบล็อกอยู่ไหม — MainTabView ผูกให้ตอน configure (อ่านจาก BlockedUsers สดทุกครั้ง
    /// เพราะรายการบล็อกแก้จากจอแชทซึ่งถือ instance คนละตัว)
    ///
    /// ใช้กรองเฉพาะ `incoming` เท่านั้น — บล็อกแล้วข้อความหายจากจอแชทจริงแต่แบนเนอร์ยังเด้ง
    /// คือบั๊กที่ hook นี้เกิดมาแก้ · ส่วน unreadCount/badge **ตั้งใจนับต่อ** ตามหลักของ
    /// ChatModeration.visible: บล็อก = ซ่อนตอนแสดงผลเท่านั้น ตัวเลขที่คนอื่นเห็นต้องตรง server
    var isBlocked: (String) -> Bool = { _ in false }
    /// โดนเอาออกจากกลุ่มระหว่าง sync (403) — MainTabView ฟังค่านี้เพื่อปิดจอแชท + โหลดโปรไฟล์ใหม่
    @Published var kickedOut = false

    let connectivity = Connectivity()
    /// สถานะเน็ตที่ **view ต้องอ่านตัวนี้** ไม่ใช่ `connectivity.online` ตรง ๆ
    ///
    /// `Connectivity` เป็น ObservableObject คนละตัวกับ `ChatSession` — `@ObservedObject var store`
    /// ของจอแชทไม่ observe nested object ให้ อ่านทะลุไปแล้วแบนเนอร์ "ออฟไลน์อยู่" จะขยับเฉพาะ
    /// ตอนมีอย่างอื่นบังเอิญมา invalidate body (เช่น sync ได้ข้อความใหม่) เน็ตหลุดตอนที่ไม่มี
    /// ข้อความไหลเข้าเลยจึงไม่ขึ้นสักที คนพิมพ์ต่อโดยไม่รู้ว่ากำลังเข้าคิว
    @Published private(set) var online = true

    init() {
        // ผูกใน init ไม่ใช่ configure() — แบนเนอร์ต้องถูกตั้งแต่ก่อนรู้ groupId ด้วย (จอแชทเปิดได้
        // ตั้งแต่ยังไม่ configure เสร็จ) และเทสหน่วยยันได้โดยไม่ต้องเรียก configure() ซึ่งลาก start()
        // ไปยิง network จริง
        connectivity.onChange = { [weak self] up in self?.online = up }
    }

    private var context: ModelContext?
    private var groupId: Int?
    private var token = ""
    private var myId = ""
    private var cursor: Int64 = 0            // serverId สูงสุดที่มีแล้ว
    private var screenVisible = false
    private var syncTask: Task<Void, Never>?
    private var syncGeneration = 0           // รอบของ syncTask ปัจจุบัน — ให้ syncLoop() เช็คก่อนเคลียร์ตัวเอง (ดู syncLoop)
    private var heartbeatTask: Task<Void, Never>?
    private var readDebounce: Task<Void, Never>?
    private var flushing = false             // กัน flushOutbox ยิงซ้อนกัน (กดส่งรัว/ทริกเกอร์หลายทางชนกัน)

    // ต่อ CacheScope.suffix ด้วยเพื่อกันข้อความจำลองของโหมดเดโม่ปนกับ cursor ของบัญชีจริง
    // (คีย์ชุดนี้ไม่ได้แยกตาม backend มาแต่ไหนแต่ไร — กับดักที่ docs/sus-test-backend.md บันทึกไว้)
    private var cursorKey: String { "chat.cursor.\(groupId ?? 0)\(CacheScope.suffix)" }
    private var readKey: String { "chat.read.\(groupId ?? 0)\(CacheScope.suffix)" }

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
            // .max ไม่ใช่ 0 — สแนปของกลุ่ม/บัญชีก่อนหน้าต้องไม่ข้ามมาโผล่ในกลุ่มถัดไป property นี้อยู่ยาว
            // เท่าแอป (ไม่ตายไปกับจอเหมือน @State เดิมของ GroupChatView) จึงต้องรีเซ็ตเองทุกจุดที่ myLastReadId รีเซ็ต
            unreadLineSnapshot = .max
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

    #if DEBUG
    /// สำหรับเทสหน่วยเท่านั้น — ตั้งค่าที่จำเป็นตรงๆ โดยไม่เรียก start() (กัน Task ยิง network จริงตอนเทส)
    /// ต่างจาก configure() ตรงที่ configure() เรียก start() เสมอเมื่อ groupId ไม่ nil
    func testSetup(groupId: Int?, myId: String = "me", token: String = "",
                   context: ModelContext? = nil) {
        if let context { self.context = context }
        self.groupId = groupId
        self.myId = myId
        self.token = token
    }

    /// สำหรับเทสหน่วยเท่านั้น — รอ flush ให้จบจริง · `send()` ปล่อย `Task` ลอยไว้ซึ่งเทสรอไม่ได้
    func testFlushOutbox() async { await flushOutbox() }

    /// สำหรับเทสหน่วยเท่านั้น — วางข้อความที่ค้างอยู่ลงใน state ตรง ๆ
    ///
    /// มีไว้สร้างสภาพที่ `send()` สร้างให้ไม่ได้ เช่น **ข้อความค้างสองอันที่เนื้อความเหมือนกัน**
    /// (ด่านกันกดซ้ำเตะตัวที่สองทิ้งถ้าห่างกันไม่ถึงวินาที และเทสหน่วงเวลาจริงไม่ได้)
    func testInsert(_ m: ChatMessage) {
        context?.insert(m)
        try? context?.save()
        messages = Self.sorted(messages + [m])
    }
    #endif

    func start() {
        guard groupId != nil, syncTask == nil else { return }
        syncGeneration += 1
        let generation = syncGeneration
        syncTask = Task { [weak self] in
            await self?.flushOutbox()
            await self?.syncLoop(generation: generation)
        }
        // กลับมา foreground ระหว่างจอแชทเปิดค้างอยู่ (screenVisible ไม่เคยถูกปิด — GroupChatView ไม่ได้หายไปไหน
        // .task เลยไม่รีรัน) heartbeat ที่ stop() ฆ่าไปตอน background ต้องถูกจุดใหม่ตรงนี้ ไม่งั้นตายไปเงียบๆ
        // จนกว่าจะปิด-เปิดจอแชทเอง ระหว่างนั้น server เข้าใจผิดว่าไม่มีใครดูอยู่แล้ว push ทับซ้ำ
        if screenVisible {
            armHeartbeat()
            let id = myLastReadId
            Task { [weak self] in await self?.postRead(id) }   // ยิง read ทันที ไม่ต้องรอ heartbeat รอบแรก 10s
        }
    }

    func stop() {
        syncTask?.cancel(); syncTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        readDebounce?.cancel(); readDebounce = nil
    }

    /// จอแชทเปิด/ปิด — คุม heartbeat, การเด้ง toast และสแนปเส้น "ข้อความใหม่"
    func setScreenVisible(_ visible: Bool) {
        screenVisible = visible
        heartbeatTask?.cancel(); heartbeatTask = nil
        guard visible else {
            unreadLineSnapshot = .max   // เปิดครั้งหน้าคำนวณจากค่า ณ ตอนนั้นใหม่ทั้งหมด (ไม่ใช่ 0 — เหตุผลเดียวกับ property ด้านบน)
            return
        }
        // ต้องสแนปก่อน markRead() บรรทัดล่างเสมอ — markRead ดัน myLastReadId ขึ้นสุดทันทีในเฟรมเดียวกัน
        // ถ้าสลับลำดับ เส้น "ข้อความใหม่" จะไม่มีวันโผล่เพราะค่าที่ใช้วางเส้นจะเท่ากับค่าล่าสุดเสมอ
        unreadLineSnapshot = myLastReadId
        UNUserNotificationCenter.current().setBadgeCount(0)   // เปิดจอแชท = เคลียร์ badge ไอคอนแอป (ของเก่าที่ server คำนวณไว้)
        markRead()
        armHeartbeat()
    }

    /// ตั้ง/จุดใหม่ heartbeat — บอก server ว่ายังจ้อจออยู่ ไม่งั้นโดน push ทั้งที่กำลังอ่าน
    /// แยกออกมาเพื่อให้ start() จุดใหม่เองได้ตอนกลับมา foreground โดยไม่ต้องผ่าน setScreenVisible อีกรอบ
    /// (setScreenVisible ทำ markRead() ด้วย ซึ่งไม่ควรเรียกซ้ำแค่เพราะแอป foreground กลับมา)
    private func armHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, !Task.isCancelled else { return }
                #if DEBUG
                NSLog("[chat] heartbeat read=\(self.myLastReadId)")   // จังหวะ ๆ นี้เท่านั้น ไม่ shipped ให้ user จริง
                #endif
                await self.postRead(self.myLastReadId)
            }
        }
    }

    // ===== ส่งข้อความ (เหมือนเดิม) =====

    /// ตัดสินว่า "ส่งได้ไหม" ผ่าน `ChatDraft` ตัวเดียวกับที่ปุ่มส่งใช้ ห้าม trimming เองที่นี่
    /// — สองที่ตัดคนละชุดคือที่มาของบั๊กข้อความหายเงียบ (ดูคอมเมนต์หัว `ChatDraft`)
    /// การกดปุ่มส่งซ้ำของเจตนาเดียว — ข้อความเดิมของ **ตัวเอง** ที่เพิ่งสร้างไปหมาด ๆ
    ///
    /// **ทำไมด่านต้องอยู่ที่นี่ ไม่ใช่ที่ปุ่ม** ปุ่มส่งกันการกดซ้ำด้วย `.disabled` ที่อ่านว่า
    /// ช่องพิมพ์ว่างหรือยัง ซึ่งพึ่งสองอย่างที่พึ่งไม่ได้: ช่องถูกล้างจริง (UITextView เขียน
    /// ข้อความเก่ากลับเข้า binding ได้ — ดูคอมเมนต์ยาวที่ `GroupChatView.send()`) และ SwiftUI
    /// re-render ทันก่อนนิ้วที่สองลง (`SOSButton.firedThisHold` เขียนบทเรียนไว้แล้วว่าการ์ดที่
    /// พึ่งจังหวะ re-render ไม่ใช่การ์ด) · ที่นี่เป็นทางผ่านเดียวของการส่งทุกทาง และเป็นชั้นเดียว
    /// ที่เขียนเทสพิสูจน์ได้ (จอแชทไม่มี tap tooling)
    ///
    /// **ราคาของการปล่อยผ่านสูงกว่าที่คิด** — การกดครั้งที่สองมินต์ `clientId` ใหม่ ซึ่ง server
    /// มองเป็นคนละข้อความ (idempotent เฉพาะ client_id เดิม ดู docs/backend-contract.md §8)
    /// ทั้งกลุ่มจึงเห็นข้อความซ้ำ ไม่ใช่แค่คนส่ง
    ///
    /// 1 วินาที: การกดสองครั้งของคนที่ตั้งใจกดครั้งเดียวห่างกันราว 100-500 มิลลิวินาที เผื่อ
    /// จังหวะที่เธรดหลักค้างเพราะ SwiftData save · ยาวกว่านี้จะเริ่มไปขวางคนที่ตั้งใจส่งข้อความ
    /// สั้นซ้ำจริง ("555" สองที) ซึ่งเป็นเจตนาที่ต้องเคารพ
    ///
    /// nonisolated: ฟังก์ชันบริสุทธิ์ ไม่แตะ state ของ actor — ให้เทสเรียกตรง ๆ ได้
    nonisolated static func isRepeatSend(_ text: String, of latestMine: ChatMessage?,
                                         myId: String, now: Date,
                                         window: TimeInterval = 1) -> Bool {
        guard let latestMine, latestMine.senderId == myId else { return false }
        guard latestMine.body == ChatDraft.trimmed(text) else { return false }
        let gap = now.timeIntervalSince(latestMine.deviceTime)
        return gap >= 0 && gap <= window
    }

    /// ข้อความของเราเองที่ "ส่งไปแล้วแต่ไม่รู้ผล" ซึ่ง echo ตัวนี้กำลังพูดถึงอยู่ — หรือ nil
    ///
    /// **เส้นทางที่พังถ้าไม่มีตัวนี้**: POST ถึง server แล้ว server สร้างแถวเรียบร้อย แต่คำตอบ
    /// หายกลางทาง (เน็ตหลุด/timeout → `.offline`/`.retryable`) ข้อความในเครื่องจึงค้าง `.pending`
    /// โดยไม่มี `serverId` · พอ long-poll ส่งแถวนั้นกลับมา **โดยไม่มี `client_id`** คีย์จึงกลายเป็น
    /// `srv-<id>` → `merge` หาไม่เจอทั้งทาง clientId และ serverId → แทรกฟองใหม่ ขณะที่ฟองเดิม
    /// ยังค้าง = สองฟองจากการส่งครั้งเดียว และตัวที่ค้างจะถูก POST ซ้ำรอบหน้าเป็นแถวที่สาม
    ///
    /// **จับคู่ด้วย `device_time` ไม่ใช่เดาจากเนื้อความอย่างเดียว** — ค่านี้แอปเป็นคนสร้างแล้วส่ง
    /// ไปกับ POST เอง (`APIClient.sendMessage`) server จึง echo ค่าเดิมกลับมา คู่ที่ถูกต้องจะห่างกัน
    /// แทบเป็นศูนย์ · เผื่อไว้ 1 วินาทีสำหรับการปัดเศษของฟอร์แมตเวลาเท่านั้น ไม่ใช่เผื่อให้จับคู่หลวม
    ///
    /// เงื่อนไขครบทุกข้อถึงจะถือว่าใช่: server ไม่ได้ส่ง client_id มา · เป็นข้อความของเราเอง ·
    /// ยังค้างไม่มี serverId · เนื้อความตรงกัน · เวลาใกล้ที่สุดและอยู่ในกรอบ
    ///
    /// nonisolated: ฟังก์ชันบริสุทธิ์ ไม่แตะ state ของ actor — ให้เทสเรียกตรง ๆ ได้
    nonisolated static func lostEchoMatch(_ dto: MessageDTO, deviceTime: Date?,
                                          in messages: [ChatMessage], myId: String,
                                          tolerance: TimeInterval = 1) -> ChatMessage? {
        guard dto.clientIdWasAssignedLocally, dto.senderId == myId, let echoedAt = deviceTime
        else { return nil }
        return messages
            .filter { $0.senderId == myId && $0.serverId == nil && $0.body == dto.body }
            .filter { abs($0.deviceTime.timeIntervalSince(echoedAt)) <= tolerance }
            .min { abs($0.deviceTime.timeIntervalSince(echoedAt))
                 < abs($1.deviceTime.timeIntervalSince(echoedAt)) }
    }

    /// คืน `false` เมื่อการกดถูกกลืนเพราะเป็นการกดซ้ำ — จอใช้ค่านี้ตัดสินใจว่าจะสั่น haptic
    /// "ส่งแล้ว" ไหม (สั่นทั้งที่ไม่มีอะไรถูกส่ง = สอนผู้ใช้ผิดว่ากดติดสองครั้ง)
    @discardableResult
    func send(_ text: String, senderName: String) -> Bool {
        let t = ChatDraft.trimmed(text)
        guard ChatDraft.canSend(text), let gid = groupId, let context else { return false }
        // เทียบกับข้อความล่าสุด **ของเราเอง** เท่านั้น — คนอื่นเพิ่งพิมพ์คำเดียวกันต้องไม่ปิดปากเรา
        guard !Self.isRepeatSend(t, of: messages.last(where: { $0.senderId == myId }),
                                 myId: myId, now: Date()) else { return false }
        let msg = ChatMessage(clientId: UUID().uuidString, serverId: nil, groupId: gid,
                              senderId: myId, body: t, deviceTime: Date(), createdAt: nil,
                              senderName: senderName, state: .pending)
        context.insert(msg)
        try? context.save()
        messages = Self.sorted(messages + [msg])
        Task { await flushOutbox() }
        return true
    }

    func retry(_ m: ChatMessage) {
        m.state = .pending
        try? context?.save()
        messages = Self.sorted(messages)
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
        messages = Self.sorted((try? context.fetch(desc)) ?? [])
        recomputeUnread()
    }

    private func syncLoop(generation: Int) async {
        // เคลียร์เฉพาะตอน generation ยังตรงกับปัจจุบัน — configure() เรียก stop() ต่อ start() ทันทีไม่มีจังหวะ
        // suspend คั่น ถ้า task เก่ายัง await ค้างตอนสลับ พอคลายตัวมาเจอ defer นี้ syncTask อาจชี้ไป task ใหม่
        // ไปแล้ว เคลียร์เปล่าๆ แบบเดิมจะเคาะ task ใหม่ (ที่ยังวิ่งอยู่จริง) ทิ้งจน orphan — cancel ไม่ได้อีกเลย
        // (ทุกทางออกยังต้องเคลียร์ตอน generation ตรงกันเหมือนเดิม ไม่งั้น start() เข้าใจผิดว่ายังวิ่งอยู่ตลอดไป)
        defer { if syncGeneration == generation { syncTask = nil } }
        var backoff: UInt64 = 1
        while !Task.isCancelled {
            guard let gid = groupId, !token.isEmpty else { return }
            guard connectivity.online else {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }
            do {
                #if DEBUG
                NSLog("[chat] sync→ group=\(gid) after=\(cursor) wait=25")   // ต่อรอบ ๆ ไม่ shipped ให้ user จริง
                #endif
                let r = try await APIClient.shared.chatSync(token: token, groupId: gid,
                                                            after: cursor, wait: 25)
                #if DEBUG
                NSLog("[chat] sync← group=\(gid) messages=\(r.messages.count) sinceId=\(r.sinceId)")
                #endif
                apply(r, for: gid)
                if messages.contains(where: { $0.state == .pending }) { await flushOutbox() }
                backoff = 1                     // สำเร็จ = วนต่อทันที (หมดเวลา = messages ว่าง ไม่ใช่ error)
            } catch AppError.notInGroup {
                // ทางพัง ไม่ใช่จังหวะปกติ — log ไว้จริงจัง (production เห็นได้ด้วย)
                NSLog("[chat] sync group=\(gid): ไม่ได้อยู่ในกลุ่มแล้ว — หยุด loop")
                purgeAll()
                kickedOut = true                // MainTabView ปิดจอแชท + โหลดโปรไฟล์ใหม่
                return                          // โดนเอาออกจากกลุ่ม — หยุด loop
            } catch {
                // ทางพัง ไม่ใช่จังหวะปกติ — log ไว้จริงจัง (production เห็นได้ด้วย)
                NSLog("[chat] sync group=\(gid) error: \(error) — backoff \(backoff)s")
                try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                backoff = min(backoff * 2, 10)
            }
        }
    }

    /// requestGroupId = กลุ่มตอนยิง request ออกไป — long-poll ค้างได้ถึง 25s ระหว่างนั้น configure()
    /// อาจสลับกลุ่มไปแล้ว (self.groupId เปลี่ยน) ถ้าไม่ตรงกันคือ response ของกลุ่มเก่า ทิ้งไปเลย
    /// ไม่งั้นข้อความกลุ่มเก่าจะถูก tag เป็นกลุ่มใหม่ผิดๆ ตอน merge
    func apply(_ r: ChatSyncResponse, for requestGroupId: Int) {
        guard requestGroupId == groupId else { return }
        if r.sinceId > 0 { purge(upTo: r.sinceId) }
        memberCount = r.memberCount
        cursors = r.cursors
        let fresh = merge(r.messages, groupId: requestGroupId)
        recomputeUnread()
        // กรองคนถูกบล็อกออกด้วย ไม่ใช่แค่ข้อความตัวเอง — และถอยไปหาตัวก่อนหน้าที่มองเห็นได้
        // ไม่ใช่เงียบทั้ง batch เพียงเพราะตัวท้ายสุดเป็นของคนถูกบล็อก
        if !screenVisible, let last = fresh.last(where: { $0.senderId != myId && !isBlocked($0.senderId) }) {
            incoming = last            // ให้ MainTabView เด้ง toast
        }
        if screenVisible { markRead() }
    }

    /// server บอกว่าเห็นได้แค่ > sinceId → ของเก่าในเครื่องลบทิ้ง (เข้ากลุ่มใหม่ = ตัดประวัติ)
    func purge(upTo sinceId: Int64) {
        let stale = messages.filter { !Self.survivesCutoff($0, sinceId: sinceId) }
        guard !stale.isEmpty, let context else { return }
        // ข้อความที่ toast กำลังโชว์อยู่อาจเป็นตัวที่กำลังจะถูกลบ — เคลียร์ก่อน ไม่งั้น MainTabView
        // ถือ reference ไปที่ @Model ที่ตายแล้วต่อ แล้วอ่าน .senderName/.body ตอน render = แอปดับ
        // (กติกาเดียวกับ purgeAll() ข้างล่าง ซึ่งเคยตกหล่นแล้วแก้ไปรอบหนึ่ง — ตัวนี้ตกหล่นตามมา)
        if let inc = incoming, !Self.survivesCutoff(inc, sinceId: sinceId) { incoming = nil }
        for m in stale { context.delete(m) }
        try? context.save()
        messages = messages.filter { Self.survivesCutoff($0, sinceId: sinceId) }
    }

    /// โดนเอาออกจากกลุ่ม — ล้าง state ทั้งหมดที่เป็นอนุพันธ์ของกลุ่มนั้น แล้วปล่อยให้ start() เริ่มใหม่ได้
    /// syncTask = nil load-bearing เสมอ (ค้างเป็น non-nil ต่อไป start() จะเข้าใจผิดว่ายังวิ่งอยู่ ไม่ยอมเริ่มลูป
    /// ใหม่) จึงอยู่นอก guard ที่คุมเฉพาะส่วนที่ต้องใช้ context จริง — เดิม guard คลุมทั้งฟังก์ชัน context เป็น nil
    /// (ไม่น่าเกิดแต่ป้องกันไว้) จะข้าม reset ที่เหลือทั้งหมดไปด้วย
    func purgeAll() {
        if let context {
            for m in messages { context.delete(m) }
            try? context.save()
        }
        messages = []; cursors = []; memberCount = 0; unreadCount = 0; myLastReadId = 0
        unreadLineSnapshot = .max   // เหมือนกับ myLastReadId ด้านบน — ล้างสแนปของกลุ่มที่เพิ่งโดนเอาออก
        incoming = nil   // ข้อความที่ toast กำลังจะโชว์อาจเป็น @Model ที่เพิ่งลบไปแล้วข้างบน — render ต่อไม่ได้
        UserDefaults.standard.removeObject(forKey: cursorKey)
        UserDefaults.standard.removeObject(forKey: readKey)
        syncTask = nil
    }

    /// เรียกตอน logout — ล้างข้อความ "ทุกกลุ่ม" ที่เคยแคชไว้ในเครื่องนี้ (ไม่ใช่แค่กลุ่มปัจจุบันแบบ purgeAll)
    /// พร้อม cursor ทุกตัว กันบัญชีที่ 2 ที่ login เครื่องเดียวกันเห็นข้อความ/สืบทอด cursor ของบัญชีก่อนหน้า
    /// (Session.logout() ไม่รู้จัก ChatSession/ModelContext เอง — เรียกจาก MainTabView.onDisappear แทน)
    func purgeForLogout() {
        stop()
        if let context {
            let all = (try? context.fetch(FetchDescriptor<ChatMessage>())) ?? []
            for m in all { context.delete(m) }
            try? context.save()
        }
        messages = []; cursors = []; memberCount = 0; unreadCount = 0; myLastReadId = 0
        unreadLineSnapshot = .max   // เหมือนกับ myLastReadId ด้านบน — ล้างสแนปของบัญชีที่เพิ่ง logout ออกไป
        incoming = nil
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("chat.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // รายชื่อคนที่บล็อกไว้ขึ้นต้นด้วย `wbw.` จึงรอดจากการกวาดข้างบนมาตลอด — บัญชีที่ 2 บนเครื่อง
        // เดียวกันสืบทอดรายการบล็อกของบัญชีก่อน และ **เห็นชื่อ** คนที่บัญชีก่อนบล็อกในหน้าตั้งค่า
        // (BlockedUsers เก็บชื่อคู่กับ id เพื่อให้จอนั้นแสดงได้) = รั่วข้ามบัญชี ไม่ใช่แค่ของค้าง
        BlockedUsers.clearAll()
    }

    /// รวมข้อความจาก server — dedupe ตาม clientId. คืนเฉพาะอันที่เพิ่งเข้ามาใหม่จริงๆ
    /// gid = requestGroupId จาก apply(_:for:) เสมอ ไม่อ่าน self.groupId สด (กันแท็กผิดกลุ่มตอนสลับกลุ่มกลางคัน)
    @discardableResult
    func merge(_ dtos: [MessageDTO], groupId gid: Int) -> [ChatMessage] {
        guard let context else { return [] }
        var fresh: [ChatMessage] = []
        for dto in dtos {
            guard let sid = Int64(dto.id) else { continue }
            if let existing = messages.first(where: { $0.clientId == dto.clientId }) {
                if existing.serverId == nil {
                    existing.serverId = sid
                    existing.createdAt = parseISO(dto.createdAt)
                    existing.state = .sent
                }
            } else if let stuck = Self.lostEchoMatch(dto, deviceTime: parseISO(dto.deviceTime),
                                                     in: messages, myId: myId) {
                // ข้อความของเราเองที่ POST ถึง server แล้วแต่คำตอบหายกลางทาง แล้ว server ยัง
                // echo กลับมาโดยไม่มี client_id — ถ้าไม่กู้ตรงนี้จะได้ฟองที่สองทับซ้อนของเดิม
                stuck.serverId = sid
                stuck.createdAt = parseISO(dto.createdAt)
                stuck.state = .sent
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
        messages = Self.sorted(messages)
        return fresh
    }

    /// ส่ง pending ตามลำดับ — เน็ตล่ม=หยุด (retry รอบหน้า), 4xx=mark failed แล้วทำต่อ
    /// flushing กัน caller หลายทาง (send/retry/start/reconnect/syncLoop) ยิงซ้อนกัน — กดส่งรัวๆ ไม่ POST ซ้ำ
    private func flushOutbox() async {
        guard groupId != nil, !token.isEmpty, let context, !flushing else { return }
        flushing = true
        defer { flushing = false }
        // สแกนซ้ำก่อนปล่อย flushing — caller คนที่ 2 (ส่งรัวๆ ชนกัน) โดน guard ด้านบนเตะออกไปเงียบๆ ตั้งแต่ต้น
        // งานของมันเลยไม่ติดอยู่ใน pending ที่ snapshot ไปแล้วรอบแรก ถ้าไม่สแกนซ้ำต้องรอ trigger รอบหน้า (ปกติ
        // คือ sync loop รอบถัดไป แต่ถ้า loop กำลัง error backoff อยู่อาจไปถึง 10 วิ)
        while true {
            // อ่าน groupId สดทุกรอบ ไม่ใช้ gid ที่ freeze ไว้ตอนเข้าฟังก์ชัน — ลูปสแกนซ้ำอยู่ได้นานตราบที่ยังมีงาน
            // ถ้า configure() สลับกลุ่มระหว่างนั้น ข้อความที่เพิ่งพิมพ์ให้กลุ่ม "ใหม่" จะถูก POST ไปกลุ่ม "เก่า"
            // (ข้อความไปผิดห้อง ไม่ใช่แค่ cursor เพี้ยน) — กลุ่มเปลี่ยน = จบรอบนี้ ให้ trigger ถัดไปส่งต่อเอง
            guard let gid = groupId else { return }
            let pending = messages.filter { $0.state == .pending }.sorted { $0.deviceTime < $1.deviceTime }
            guard !pending.isEmpty else { return }
            for m in pending {
                guard gid == groupId else { return }
                do {
                    let dto = try await APIClient.shared.sendMessage(
                        token: token, groupId: gid, clientId: m.clientId,
                        body: m.body, deviceTime: iso(m.deviceTime))
                    m.serverId = Int64(dto.id) ?? m.serverId
                    m.createdAt = parseISO(dto.createdAt)
                    m.state = .sent
                    // gid == groupId: await ข้างบนอาจค้างข้าม configure() สลับกลุ่ม (เหมือน apply(_:for:) ที่กัน
                    // merge() ไว้แล้ว) ไม่งั้น cursor ของกลุ่มเก่าจะเขียนทับ cursorKey ของกลุ่มใหม่ (คำนวณจาก
                    // self.groupId สด) — id ข้อความเป็น global ค่าที่ยกมาผิดกลุ่มอาจสูงเกินจริงจนกลุ่มใหม่ข้ามประวัติ
                    if gid == groupId, let sid = m.serverId, sid > cursor {
                        cursor = sid
                        UserDefaults.standard.set(Int(cursor), forKey: cursorKey)
                    }
                    try? context.save()
                    messages = Self.sorted(messages)
                } catch AppError.offline {
                    return
                } catch AppError.retryable {
                    // ไปถึงเซิร์ฟเวอร์แล้วแต่ตอนนี้ยังไม่ได้ (ล้น/gateway ล้ม/ทางผ่านเพี้ยน) —
                    // **คงไว้ที่ .pending** ให้ trigger ถัดไปเก็บ ไม่ใช่ขึ้นฟอง "ส่งไม่สำเร็จ"
                    // ให้ผู้ใช้ต้องกด retry เอง (ดูรายชื่อ terminal ที่ APIClient.isTerminalSendStatus)
                    //
                    // return ไม่ใช่ continue: ถ้าเซิร์ฟเวอร์กำลังล้น ข้อความถัดไปในคิวก็เจอเหมือนกัน
                    // ยิงต่อคือซ้ำเติม · sync loop รอบหน้า (~25 วิ) จะเรียกกลับมาเอง
                    return
                } catch {
                    m.state = .failed
                    try? context.save()
                    messages = Self.sorted(messages)
                }
            }
        }
    }

    private func recomputeUnread() {
        unreadCount = Self.unreadCount(messages: messages, myLastReadId: myLastReadId, myId: myId)
    }

    // เรียงตาม displayTime (เวลาเดียวกับที่ ChatRowBuilder ใช้จับกลุ่ม/ป้ายวัน) — createdAt คือเวลาที่ server
    // ประทับให้ ไม่ใช่นาฬิกาเครื่องที่เพี้ยนได้ (นาฬิกาเครื่องเหลือบทบาทแค่ deviceTime ตอนยังไม่มี createdAt)
    // เท่ากันเป๊ะค่อย tiebreak ด้วย serverId ให้เสถียร — pending (serverId เป็น nil) ต่อท้ายเสมอเหมือนเดิม
    // nonisolated: ฟังก์ชันบริสุทธิ์ ไม่แตะ state ของ actor — ให้เทสเรียกตรงๆ แบบ sync ได้ ไม่ต้อง await
    nonisolated static func sorted(_ arr: [ChatMessage]) -> [ChatMessage] {
        arr.sorted { a, b in
            switch (a.serverId, b.serverId) {
            case let (x?, y?):
                if a.displayTime != b.displayTime { return a.displayTime < b.displayTime }
                return x < y
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
