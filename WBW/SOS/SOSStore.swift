import Foundation

/// เคส SOS หนึ่งอันของผู้ใช้คนนี้ · ลงเครื่องก่อน ยิงทีหลัง ไม่มีทางลบทิ้ง
///
/// ต่างจาก FeedbackStore ตรงที่ไม่มี "รายชื่อ error ที่ทิ้งได้" เลยแม้แต่รายการเดียว
/// ความเห็นต่อฐานที่หายไปคือข้อมูลหนึ่งแถว เคส SOS ที่หายไปคือคนที่รออยู่บนดอย
/// โดยเชื่อว่าส่งไปแล้ว — ราคาไม่เท่ากัน การจำแนกจึงไม่เท่ากัน
@MainActor
final class SOSStore: ObservableObject {
    @Published private(set) var draft: SOSDraft?
    @Published private(set) var serverCase: SOSCase?
    @Published private(set) var status: SOSStatus?
    @Published private(set) var showCallFallback = false

    private var outbox: SOSOutbox { SOSOutbox() }
    private let locator: SOSLocator
    private let callFallbackDelay: Duration
    private var retryTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?

    /// ฉีดของปลอมเข้าได้ตอนเทสด้วย closure ตรงๆ ตามแบบเดียวกับ FeedbackStore.submitCall
    /// — โปรเจกต์นี้ไม่มี protocol ครอบ APIClient ที่ไหนเลย ไม่ต้องเพิ่มตอนนี้
    private let raiseCall: (String, SOSDraft) async throws -> SOSCase
    private let cancelCall: (String, Int64) async throws -> APIClient.SOSCancelOutcome
    private let activeCall: (String, Int) async throws -> SOSCase?

    // locator เป็น SOSLocator? = nil แทนที่จะเป็น SOSLocator = SOSLocator() ตรงๆ เพราะ SOSLocator
    // เป็น @MainActor และ default-argument expression ของ initializer ไม่ได้สืบทอด MainActor
    // isolation ของ SOSStore.init เองใน Swift 5 language mode ที่โปรเจกต์นี้ใช้ (SWIFT_VERSION 5.0
    // ใน project.yml) — ใส่ SOSLocator() ตรงๆ ในลิสต์พารามิเตอร์เจอ "Call to main actor-isolated
    // initializer 'init(provider:)' in a synchronous nonisolated context" ตอนคอมไพล์จริง (พบตอนทำ
    // Task 12) ย้ายการสร้างเข้าไปใน body ของ init ซึ่งอยู่ใน MainActor context จริงๆ แล้วแก้ปัญหานี้ได้
    // ไม่กระทบผู้เรียกที่ไหนเลย — ไม่มี call site ไหนในแผนทั้งฉบับส่ง locator: เข้ามาเอง
    // callFallbackDelay ย้ายมาเป็นพารามิเตอร์สุดท้าย (บรีฟเดิมวางไว้ก่อน raiseCall) เพราะ Swift
    // บังคับให้ argument label เรียงตามลำดับที่ประกาศไว้เท่านั้น เรียงสลับที่ call site ไม่ได้ —
    // เทส testTheCallFallbackAppearsOnlyAfterTheCaseHasBeenStuck ของบรีฟเองส่ง raiseCall: ก่อน
    // callFallbackDelay: ("argument 'callFallbackDelay' must precede argument 'raiseCall'" ตอน
    // คอมไพล์จริง — พบตอนทำ Task 12) ย้ายมาไว้ท้ายสุดแทนที่จะแก้เทส เพราะทุกเทสในไฟล์นี้ (รวมถึง
    // เทสที่ไม่ได้แตะพารามิเตอร์นี้เลย) ส่ง raiseCall: มาก่อนเสมอ เรียงแบบนี้จึงตรงกับรูปแบบการใช้งาน
    // จริงทั้งไฟล์โดยไม่ต้องแก้เทสสักตัว
    init(locator: SOSLocator? = nil,
         raiseCall: @escaping (String, SOSDraft) async throws -> SOSCase = APIClient.shared.raiseSOS,
         cancelCall: @escaping (String, Int64) async throws -> APIClient.SOSCancelOutcome = APIClient.shared.cancelSOS,
         activeCall: @escaping (String, Int) async throws -> SOSCase? = APIClient.shared.activeSOS,
         callFallbackDelay: Duration = .seconds(20)) {
        self.locator = locator ?? SOSLocator()
        self.raiseCall = raiseCall
        self.cancelCall = cancelCall
        self.activeCall = activeCall
        self.callFallbackDelay = callFallbackDelay
        self.draft = SOSOutbox().current()
        if draft != nil { status = .queued }
    }

    /// กดครบ 3 วิ · เขียนลงเครื่องก่อนแตะเน็ตแม้แต่ครั้งเดียว
    func raise(forOther: Bool, token: String) async {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var d = SOSDraft(clientId: UUID().uuidString,
                         deviceTime: iso.string(from: Date()),
                         forOther: forOther)

        // ค่าที่ระบบมีอยู่แล้วใช้ได้ทันที — ไม่รอ fix ใหม่ (ดูคอมเมนต์ที่ SOSLocator.oneShot)
        if let fix = locator.cachedFix(maxAge: 60) {
            d.lat = fix.lat; d.lng = fix.lng; d.accuracyM = fix.accuracyM
        }
        outbox.save(d)
        draft = d
        status = .queued
        startFallbackTimer()

        await send(token: token)
        startRetryLoop(token: token)
        startLocationChase(token: token)
    }

    /// โน้ตที่พิมพ์จากจอสถานะระหว่างรอ — ไปทางเดียวกับการยิงปกติ client_id เดิม
    func attachNote(_ text: String, token: String) async {
        guard var d = draft else { return }
        d.message = text
        outbox.save(d)
        draft = d
        await send(token: token)
    }

    /// ยิงหนึ่งครั้ง · **ทุกทางที่ผิดพลาดจบลงที่ "เก็บไว้ ลองใหม่" ไม่มีข้อยกเว้น**
    private func send(token: String) async {
        guard let d = draft else { return }
        do {
            let c = try await raiseCall(token, d)
            var updated = d
            updated.serverId = c.id
            outbox.save(updated)
            draft = updated
            serverCase = c
            status = c.status
            showCallFallback = false
            if let phone = c.emergencyPhone { Config.cacheEmergencyPhone(phone) }
            // เริ่ม poll ตอนนี้เท่านั้น — ก่อนหน้านี้เซิร์ฟเวอร์ยังไม่รู้จักเคสนี้เลย
            // ถามไปก็ได้ค่าว่าง เปลืองแบตและเปลืองเน็ตที่มีน้อยอยู่แล้ว
            startStatusPoll(token: token)
        } catch {
            // ไม่มี catch สาขาไหนเรียก outbox.clear() — ตั้งใจ และมีเทสไล่ทุก error ค้ำไว้
            status = .queued
        }
    }

    private func startRetryLoop(token: String) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            let schedule: [Duration] = [.seconds(2), .seconds(5), .seconds(10),
                                        .seconds(20), .seconds(30), .seconds(60)]
            var i = 0
            while !Task.isCancelled {
                let delay = i < schedule.count ? schedule[i] : .seconds(60)
                i += 1
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                // ถึงเซิร์ฟเวอร์แล้วและเคสยังเปิดอยู่ = ไม่ต้องยิงซ้ำ ปล่อยให้ poll ทำงานแทน
                if self.draft?.serverId != nil { return }
                await self.send(token: token)
            }
        }
    }

    /// ไล่ตาม GPS คู่ขนานกับการส่ง · ได้ fix แล้วยิงอัปเดตด้วย client_id เดิม
    private func startLocationChase(token: String) {
        Task { [weak self] in
            guard let self else { return }
            guard let fix = await self.locator.oneShot(timeout: .seconds(8)) else { return }
            guard var d = self.draft else { return }
            // ค่าใหม่ทับก็ต่อเมื่อแม่นกว่าเดิมจริง — fix ที่หยาบกว่าไม่ใช่ข่าวดี
            if let old = d.accuracyM, old <= fix.accuracyM { return }
            d.lat = fix.lat; d.lng = fix.lng; d.accuracyM = fix.accuracyM
            self.outbox.save(d)
            self.draft = d
            await self.send(token: token)
        }
    }

    private func startStatusPoll(token: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let c = try? await self.activeCall(token, 25) {
                    self.serverCase = c
                    self.status = c.status
                    if c.resolved { self.finish(); return }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func startFallbackTimer() {
        fallbackTask?.cancel()
        showCallFallback = false
        fallbackTask = Task { [weak self] in
            try? await Task.sleep(for: self?.callFallbackDelay ?? .seconds(20))
            guard let self, !Task.isCancelled else { return }
            // ค้างอยู่ใน queued แปลว่ายังไม่ถึงเซิร์ฟเวอร์ — ให้ทางออกด้วยการโทร
            if self.status == .queued { self.showCallFallback = true }
        }
    }

    func cancel(token: String) async -> APIClient.SOSCancelOutcome? {
        guard let id = draft?.serverId else {
            // ยังไม่เคยถึงเซิร์ฟเวอร์ — ยกเลิกได้ในเครื่องล้วน ไม่มีใครเคยรู้ว่ามีเคสนี้
            finish()
            outbox.clear()
            draft = nil
            status = nil
            return .canceled
        }
        guard let outcome = try? await cancelCall(token, id) else { return nil }
        if outcome == .canceled {
            finish()
            outbox.clear()
            draft = nil
            status = .closed(reason: "canceled_by_user")
        }
        return outcome
    }

    func flush(token: String) async {
        guard draft != nil else { return }
        await send(token: token)
    }

    /// ล็อกเอาต์ตอนมีเคสค้าง — ต้องล้าง ไม่งั้นเคสของคนก่อนถูกส่งด้วย token ของคนถัดไป
    /// (จอที่เรียกตัวนี้ต้องถามยืนยันก่อน ไม่ใช่ล้างเงียบๆ)
    func clearForLogout() {
        finish()
        outbox.clear()
        draft = nil
        serverCase = nil
        status = nil
        showCallFallback = false
    }

    private func finish() {
        retryTask?.cancel(); pollTask?.cancel(); fallbackTask?.cancel()
    }
}
