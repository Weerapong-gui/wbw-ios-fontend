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
    /// ช่วงพักระหว่างรอบ poll สถานะ — แยกเป็นพารามิเตอร์ฉีดได้เหมือน callFallbackDelay เพื่อให้เทส
    /// เพดานหยุด poll (ดู maxConsecutiveEmptyPolls) ไม่ต้องรอนาทีจริง ค่าเริ่มต้น 1 วิเหมือนของเดิม
    /// ก่อนรีวิว Task 14 รอบสอง
    private let pollInterval: Duration
    private var retryTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    private var chaseTask: Task<Void, Never>?

    /// เพิ่มทุกครั้งที่ cancel()/clearForLogout() ล้างเคสทิ้ง — send() จับค่านี้ไว้ก่อน await
    /// raiseCall แล้วเทียบใหม่ตอนตื่น ถ้าไม่ตรงแปลว่ามีการล้างเกิดขึ้นระหว่างที่ค้างรอเน็ตอยู่
    /// (พบจากรีวิว Task 12: ส่งช้าแล้วเพิ่งสำเร็จหลังผู้ใช้กด cancel/logout ไปแล้ว — ผลที่มาสาย
    /// ต้องถูกทิ้ง ไม่ใช่เขียนทับสิ่งที่เพิ่งถูกล้าง เคสที่เพิ่งยกเลิก/ล็อกเอาต์ไปห้ามฟื้นกลับมา)
    private var generation = 0

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
         callFallbackDelay: Duration = .seconds(20),
         pollInterval: Duration = .seconds(1)) {
        self.locator = locator ?? SOSLocator()
        self.raiseCall = raiseCall
        self.cancelCall = cancelCall
        self.activeCall = activeCall
        self.callFallbackDelay = callFallbackDelay
        self.pollInterval = pollInterval
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
    ///
    /// จับ generation ไว้ก่อน await ตัวเดียวในฟังก์ชันนี้ (raiseCall) แล้วเทียบใหม่ทันทีที่ตื่น —
    /// ถ้า cancel()/clearForLogout() แทรกเข้ามาระหว่างที่ค้างรอเน็ตอยู่ generation จะเปลี่ยนไปแล้ว
    /// ผลที่เพิ่งได้มา (ไม่ว่าจะสำเร็จหรือพัง) ถือว่าสายเกินไป ห้ามเขียนอะไรทับสิ่งที่เพิ่งถูกล้าง
    /// (พบจากรีวิว: ไม่มีการเช็คนี้มาก่อน เคสที่เพิ่งยกเลิก/ล็อกเอาต์ไปฟื้นกลับมาได้ถ้า raiseCall
    /// ที่ค้างอยู่ดันสำเร็จทีหลัง)
    private func send(token: String) async {
        guard let d = draft else { return }
        let gen = generation
        do {
            let c = try await raiseCall(token, d)
            guard gen == generation else { return }
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
            guard gen == generation else { return }
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
    ///
    /// เก็บ handle ไว้ใน chaseTask และเช็ค Task.isCancelled ทันทีที่ตื่นจาก oneShot (เหมือนที่
    /// fallbackTask ทำ) — เดิม Task นี้เป็น bare Task { } ไม่มีใครเก็บ handle ไว้เลย finish()
    /// จึงหยุดมันไม่ได้ (พบจากรีวิว) แม้ oneShot เองจะไม่ตอบสนอง cancel ทันที (withCheckedContinuation
    /// ไม่ใช่ withTaskCancellationHandler — ดูคอมเมนต์ที่ SOSLocator.oneShot) แต่การเช็คตรงนี้ก็ยัง
    /// กัน fix เก่าที่มาถึงหลัง cancel/logout ไม่ให้เขียนทับ draft ที่เพิ่งถูกล้าง หรือปนเข้าไปในเคส
    /// ใหม่ที่เพิ่งเปิดหลังจากนั้น
    private func startLocationChase(token: String) {
        chaseTask?.cancel()
        chaseTask = Task { [weak self] in
            guard let self else { return }
            guard let fix = await self.locator.oneShot(timeout: .seconds(8)) else { return }
            guard !Task.isCancelled else { return }
            guard var d = self.draft else { return }
            // ค่าใหม่ทับก็ต่อเมื่อแม่นกว่าเดิมจริง — fix ที่หยาบกว่าไม่ใช่ข่าวดี
            if let old = d.accuracyM, old <= fix.accuracyM { return }
            d.lat = fix.lat; d.lng = fix.lng; d.accuracyM = fix.accuracyM
            self.outbox.save(d)
            self.draft = d
            await self.send(token: token)
        }
    }

    /// เพดาน poll ที่ได้ผลว่าง (nil) ติดกัน ก่อนยอมเลิก — กันเคสที่เซิร์ฟเวอร์ลืมไปแล้วจริงๆ วน
    /// ตลอดกาล (พบจากรีวิว Task 14 รอบสอง — ดูคอมเมนต์ที่ startStatusPoll ว่าทำไมเคสแบบนี้เกิดได้)
    /// เลขนี้เป็นตัวเลขกลมๆ ที่เผื่อสัญญาณหลุดจริงยังทนได้อยู่ ไม่ใช่ค่าที่วัดจากอะไรตายตัว — nil ที่นี่
    /// รวมทั้ง "ไม่มีเคสจริงๆ" และ error ที่ try? กลืนไปด้วย (activeSOS ไม่ได้แยกสองอย่างนี้ให้)
    /// จึงนับรวมกันไปก่อน เพดานสูงพอที่จะไม่ตัดเคสจริงทิ้งกลางสัญญาณหลุดสั้นๆ
    private static let maxConsecutiveEmptyPolls = 20

    /// long-poll สถานะไปเรื่อยๆ จนกว่าจะปิด · เคสจบ (resolved) ต้องล้าง **draft ที่ persist ไว้บนดิสก์**
    /// ด้วย ไม่ใช่แค่หยุด task — เดิม finish() อย่างเดียวปล่อย outbox.clear()/draft=nil ไว้ไม่ทำ ทำให้
    /// เคสที่จบไปแล้วยังเหลือ draft ค้างในเครื่อง ถ้าแอปถูกปิดแล้วเปิดใหม่ init() จะกู้ draft นั้นมาเป็น
    /// queued อีกรอบทั้งที่จบไปแล้วจริงๆ (พบจากรีวิว Task 14 รอบสอง) — serverCase/status ยังคงค่า
    /// .closed ไว้ให้จอสถานะแสดงผลจบเรื่องได้ตามปกติ สิ่งที่ต้องไม่รอดคือ draft/outbox เท่านั้น
    ///
    /// ถ้าเซิร์ฟเวอร์ไม่รู้จักเคสนี้เลย (nil ติดกันเกินเพดาน — ดู maxConsecutiveEmptyPolls) ให้เลิก
    /// poll เช่นกัน ไม่ล้าง draft ในกรณีนี้เพราะไม่รู้จริงว่าเคสจบหรือแค่เน็ตหลุด — ปล่อยให้ retryTask/
    /// ผู้ใช้กด cancel เองตัดสินใจแทน
    private func startStatusPoll(token: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var consecutiveEmpty = 0
            while !Task.isCancelled {
                guard let self else { return }
                if let c = try? await self.activeCall(token, 25) {
                    consecutiveEmpty = 0
                    self.serverCase = c
                    self.status = c.status
                    if c.resolved {
                        self.finish()
                        self.outbox.clear()
                        self.draft = nil
                        return
                    }
                } else {
                    consecutiveEmpty += 1
                    if consecutiveEmpty >= Self.maxConsecutiveEmptyPolls {
                        self.finish()
                        return
                    }
                }
                try? await Task.sleep(for: self.pollInterval)
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
            generation += 1   // ผลของ send() ที่อาจค้างรออยู่ (ถ้ามี) ต้องถูกทิ้งเมื่อกลับมา
            outbox.clear()
            draft = nil
            status = nil
            return .canceled
        }
        guard let outcome = try? await cancelCall(token, id) else { return nil }
        if outcome == .canceled {
            finish()
            generation += 1
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

    /// เรียกตอนแอปเปิดใหม่แล้ว init() เจอ draft ค้างจาก outbox (relaunch) — init เองแค่กู้ค่า
    /// draft/status ให้เห็นทันที **ไม่เริ่ม retry loop ให้อัตโนมัติ** เพราะ initializer ที่มีผลข้างเคียง
    /// ยิงเน็ต/ตั้ง timer เงียบๆ เป็นสิ่งที่ตามรอยยาก (ตรวจแล้วในสถานะปัจจุบันของไฟล์นี้ — ไม่ใช่แค่
    /// สมมติ) ผู้สร้าง store ต้องเรียกตัวนี้เองตอนพร้อมจริง (มี token ให้ใช้แล้ว) — ไม่มีอะไรเกิดขึ้น
    /// ถ้าไม่มีเคสค้าง หรือเคสที่ค้างปิดไปแล้ว (isActive == false)
    ///
    /// ทำหางเดียวกับ raise() ทุกอย่างหลังจาก outbox ถูกเซฟไปแล้ว (fallback timer ก่อนส่ง แล้วค่อย
    /// retry loop กับ location chase หลังส่ง) เพียงแต่ไม่สร้าง draft ใหม่ — อันเดิมกู้มาจาก init แล้ว
    /// ยิง send() ครั้งแรกนี้เสมอแม้ serverId จะมีอยู่แล้วก็ตาม (idempotent ด้วย clientId เดิม เหมือน
    /// ทุกจุดอื่นในไฟล์นี้) เพื่อให้จอสถานะได้ค่าจริงล่าสุดจากเซิร์ฟเวอร์ทันทีที่เปิดแอป แทนที่จะค้าง
    /// คำว่า "queued" จาก init เฉยๆ รอ poll รอบแรก (ซึ่งยังไม่ได้เริ่มด้วยซ้ำก่อนเรียกตัวนี้)
    func resumeIfNeeded(token: String) async {
        guard draft != nil, let status, status.isActive else { return }
        startFallbackTimer()
        await send(token: token)
        startRetryLoop(token: token)
        startLocationChase(token: token)
    }

    /// จุดตัดสินใจเดียวที่ MainTabView.onDisappear เรียกทุกครั้งที่ล็อกเอาต์ — ตัดสินใจแทนว่าจะล้าง
    /// เคสทิ้งหรือปล่อยไว้ ตาม automatic (ดู Session.logout(automatic:))
    ///
    /// **ล็อกเอาต์อัตโนมัติจาก 401 ต้องไม่ล้าง** (พบจากรีวิว Task 14 รอบสอง) — Session ยิง logout()
    /// เองทันทีที่เจอ 401 จากที่ไหนก็ได้ในแอป โดยไม่มีการยืนยันจากผู้ใช้เลยสักครั้ง ถ้าเรียก
    /// clearForLogout() ตรงๆ ตรงนี้ คนที่มีเคสฉุกเฉินเปิดอยู่จะถูกเด้งไปหน้า login พร้อมกับเคสหายไป
    /// เงียบๆ กลางเหตุฉุกเฉิน โดยไม่มีอะไรเตือนเลย — ขัดกับ spec ที่บอกว่า "logout ตอนมีเคสเปิดต้อง
    /// ถามยืนยันก่อน" ตรงๆ ปล่อย draft ไว้ในเครื่องแทน (ไม่เรียกอะไรเลย) ให้ resumeIfNeeded หยิบต่อ
    /// ได้ทันทีที่ล็อกอินกลับมา (SOSStore ตัวใหม่ที่ MainTabView สร้างตอน mount ใหม่จะอ่าน draft เดิม
    /// กลับมาใน init() เอง) ทรงเดียวกับ relaunch ทุกอย่าง
    ///
    /// ล็อกเอาต์ที่ผู้ใช้กดเอง (ผ่านปุ่ม "ออกจากระบบ" ใน SettingsView ซึ่งมี .alert
    /// "ออกจากระบบใช่หรือไม่" ถามยืนยันก่อนเรียก session.logout() เสมออยู่แล้ว) ถึงล้างจริงตามเดิม —
    /// ยืนยันแล้วจริงๆ ตรงตามที่คอมเมนต์ของ clearForLogout() ด้านล่างต้องการ
    ///
    /// เหลือความเสี่ยงที่รู้แล้วแต่ไม่แก้ในนี้: SOSOutbox ผูกกับ backend เท่านั้น ไม่ผูกกับ user id
    /// เลย ถ้ามีคนอื่นมา login บนเครื่องเดียวกันก่อนเจ้าของเคสตัวจริงจะกลับมา login ใหม่ คนนั้นจะ
    /// เห็น/สืบทอด draft ของคนแรกได้ — ยอมรับความเสี่ยงนี้เพราะ 401 อัตโนมัติในทางปฏิบัติแทบทั้งหมด
    /// คือคนเดิม re-authenticate ต่อ ไม่ใช่มีคนอื่นมาแย่งเครื่องใช้กลางเหตุฉุกเฉินพอดี
    func handleLogout(automatic: Bool) {
        guard !automatic else { return }
        clearForLogout()
    }

    /// ล็อกเอาต์ตอนมีเคสค้าง — ต้องล้าง ไม่งั้นเคสของคนก่อนถูกส่งด้วย token ของคนถัดไป
    /// (จอที่เรียกตัวนี้ต้องถามยืนยันก่อน ไม่ใช่ล้างเงียบๆ — ตอนนี้มีทางเข้าเดียวคือ handleLogout(automatic: false) ด้านบน)
    func clearForLogout() {
        finish()
        generation += 1   // ผลของ send() ที่อาจค้างรออยู่ (ถ้ามี) ต้องถูกทิ้งเมื่อกลับมา
        outbox.clear()
        draft = nil
        serverCase = nil
        status = nil
        showCallFallback = false
    }

    private func finish() {
        retryTask?.cancel(); pollTask?.cancel(); fallbackTask?.cancel(); chaseTask?.cancel()
    }
}
