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

    /// จอสถานะโชว์แบนเนอร์ "หยุดเช็คแล้ว" + ปุ่มลองใหม่เมื่อค่านี้เป็น true (ดู retryStatusCheck และ
    /// คอมเมนต์ที่ maxConsecutiveEmptyPolls) — พบจากรีวิว Task 14 รอบสาม: เดิม poll หยุดแบบเงียบๆ
    /// ไม่มีสัญญาณอะไรให้จอเห็นเลยว่าหยุดไปแล้ว
    @Published private(set) var statusCheckStopped = false

    #if DEBUG
    /// ยัดเคสที่ "เจ้าหน้าที่รับแล้ว" เข้าไปตรงๆ เพื่อถ่ายจอสถานะ — คู่กับ `-uitestSOSStatus`
    ///
    /// ทางเข้าจริงคือกดปุ่มค้าง 3 วินาที ซึ่งถ่ายไม่ได้เลยที่นี่ (ไม่มี tap tooling) และ `raise()`
    /// ตัวจริงก็ยิงเน็ต · เลือกสถานะ `.received` เพราะเป็นสถานะที่ทำให้ปุ่มยกเลิกหายไปตามกติกา
    /// 15 วินาที = สถานะที่เคย **ขังผู้ใช้ไว้ในจอนี้ถาวร** ซึ่งคือสิ่งที่ต้องพิสูจน์ว่าแก้แล้ว
    func raiseForScreenshot() {
        draft = SOSDraft(clientId: "screenshot", deviceTime: "2026-08-21T09:00:00Z",
                         forOther: false, ownerId: "demo-user")
        status = .received
        // เคสจำลองที่เซิร์ฟเวอร์ "ยังไม่รู้พิกัด" — `loc_source = last_checkin` คือสาขาที่บรรทัด
        // บอกตำแหน่ง (`SOSWhere`) มีอะไรให้พูดจริง ๆ และเป็นสาขาที่ต้องมีคนดูด้วยตาว่าอ่านรู้เรื่อง
        // ไหม เพราะมันคือคำสัญญาที่แย่ที่สุดที่จอนี้ต้องบอกคนที่กำลังรอความช่วยเหลือ
        serverCase = SOSCase(id: 1, forOther: false, lat: nil, lng: nil, accuracyM: nil,
                             locSource: "last_checkin", checkpointId: 5, checkpointName: "จุดปลูก",
                             message: nil, resolved: false, resolveReason: nil,
                             ackedAt: nil, ackedByName: nil,
                             createdAt: "2026-08-21T09:00:00Z", emergencyPhone: nil)
    }
    #endif

    private var outbox: SOSOutbox { SOSOutbox() }
    private let locator: SOSLocator
    private let callFallbackDelay: Duration
    /// ช่วงพักระหว่างรอบ poll สถานะ — แยกเป็นพารามิเตอร์ฉีดได้เหมือน callFallbackDelay เพื่อให้เทส
    /// เพดานหยุด poll (ดู maxConsecutiveEmptyPolls) ไม่ต้องรอนาทีจริง ค่าเริ่มต้น 1 วิเหมือนของเดิม
    /// ก่อนรีวิว Task 14 รอบสอง
    private let pollInterval: Duration
    /// ถอยเมื่อ activeCall throw จริง (เน็ตหลุด/timeout) — คนละสิ่งกับ "เซิร์ฟเวอร์ตอบว่าไม่มีเคส"
    /// (ดูคอมเมนต์ที่ startStatusPoll) ฉีดได้เหมือน pollInterval เพื่อให้เทส "error รัวๆ ไม่ทำให้หยุด"
    /// ไม่ต้องรอถอยจริงเป็นสิบวิ ดัชนีเกินความยาว array ใช้ตัวสุดท้ายซ้ำไปเรื่อยๆ (ทรงเดียวกับ
    /// startRetryLoop ด้านล่าง)
    private let errorBackoffSchedule: [Duration]
    /// เจ้าของเครื่อง SOSStore นี้ — user id ที่ raise() ใหม่ทุกครั้งจะ stamp ลง draft และเป็นค่าที่
    /// init()/resumeIfNeeded() เทียบกับ draft ที่ค้างอยู่ก่อนจะยอมรับมาเป็นของ session นี้ (ดูคอมเมนต์
    /// ยาวที่ init และที่ SOSDraft.ownerId — พบจากรีวิว Task 14 รอบสาม)
    private let currentUserId: String
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
    /// currentUserId ไม่มีดีฟอลต์ที่มีความหมาย (ค่าเริ่มต้น "" ใช้ได้กับเทสที่ไม่สนเรื่องเจ้าของเท่านั้น
    /// — ดูคอมเมนต์ที่ SOSDraft.ownerId) ผู้เรียกจริงจากแอป (MainTabView) ต้องส่งค่าจริงเสมอ อ่านจาก
    /// UserDefaults ตรงๆ ผ่าน Session.currentUserIdFromDisk() เพราะ @StateObject ของ MainTabView
    /// ถูกสร้างก่อนที่ @EnvironmentObject session จะพร้อมใช้งานตามลำดับของ SwiftUI (ดูคอมเมนต์ที่นั่น)
    init(currentUserId: String = "",
         locator: SOSLocator? = nil,
         raiseCall: @escaping (String, SOSDraft) async throws -> SOSCase = APIClient.shared.raiseSOS,
         cancelCall: @escaping (String, Int64) async throws -> APIClient.SOSCancelOutcome = APIClient.shared.cancelSOS,
         activeCall: @escaping (String, Int) async throws -> SOSCase? = APIClient.shared.activeSOS,
         callFallbackDelay: Duration = .seconds(20),
         pollInterval: Duration = .seconds(1),
         errorBackoffSchedule: [Duration] = [.seconds(1), .seconds(2), .seconds(5), .seconds(10), .seconds(30)]) {
        self.currentUserId = currentUserId
        self.locator = locator ?? SOSLocator()
        self.raiseCall = raiseCall
        self.cancelCall = cancelCall
        self.activeCall = activeCall
        self.callFallbackDelay = callFallbackDelay
        self.pollInterval = pollInterval
        self.errorBackoffSchedule = errorBackoffSchedule
        // เจ้าของไม่ตรง (login บัญชีอื่นบนเครื่องเดียวกันหลัง logout อัตโนมัติ) ต้องไม่รับ draft ของ
        // บัญชีก่อนมาเป็นของตัวเอง (พบจากรีวิว Task 14 รอบสาม — ดูคอมเมนต์ยาวที่ SOSDraft.ownerId)
        // ล้างทิ้งตรงนี้เลยแทนที่จะปล่อยค้าง เพราะ SOSOutbox มีที่เก็บได้ทีละหนึ่งเคสต่อ backend เท่านั้น
        // ปล่อยของบัญชีอื่นค้างไว้เฉยๆ ก็ไม่มีวันมีใครมาเคลียร์ให้ (ไม่ใช่ draft ของ session ปัจจุบัน
        // ไม่มี flow ไหนในแอปจะไปแตะมันอีกเลย)
        let restored = SOSOutbox().current()
        if let restored, restored.ownerId == currentUserId {
            self.draft = restored
            self.status = .queued
        } else if restored != nil {
            SOSOutbox().clear()
        }
    }

    /// กดครบ 3 วิ · เขียนลงเครื่องก่อนแตะเน็ตแม้แต่ครั้งเดียว
    func raise(forOther: Bool, token: String) async {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var d = SOSDraft(clientId: UUID().uuidString,
                         deviceTime: iso.string(from: Date()),
                         forOther: forOther,
                         ownerId: currentUserId)

        // ค่าที่ระบบมีอยู่แล้วใช้ได้ทันที — ไม่รอ fix ใหม่ (ดูคอมเมนต์ที่ SOSLocator.oneShot)
        if let fix = locator.cachedFix(maxAge: 60) {
            d.lat = fix.lat; d.lng = fix.lng; d.accuracyM = fix.accuracyM
        }
        outbox.save(d)
        draft = d
        status = .queued
        startFallbackTimer()

        // **สามอย่างนี้ต้องเริ่มก่อน await send() ไม่ใช่หลัง** (แก้จากรีวิวรอบสุดท้าย) — เดิม
        // await send(...) มาก่อน แล้วค่อยเริ่ม retry loop กับการไล่ตาม GPS ซึ่งกลับหัวกฎข้อแรกของ
        // สเปกทั้งฉบับ ("อย่ารอ GPS — การกดกับการได้พิกัดเป็นสองเส้นขนานกัน") พอดีในสถานการณ์
        // เดียวที่ฟีเจอร์นี้มีไว้รับมือ: ในจุดอับสัญญาณ request แรกกิน timeout เต็ม (ตอนนี้ตั้งไว้
        // ชัดเจนที่ 20 วิใน raiseSOS เดิมใช้ค่าเริ่มต้น 60 วิของ URLSession) ตลอดช่วงนั้น oneShot
        // ยังไม่ถูกเรียกเลยแม้แต่ครั้งเดียว และ retry ครั้งแรกไปตกที่ ~62 วิแทนที่จะเป็น 2 วิ
        //
        // ยิงซ้อนกันไม่เป็นไร: ทุกเส้นทางใช้ clientId เดิมเสมอ เซิร์ฟเวอร์ตอบแถวเดิมกลับมา
        // (idempotent) และ retry loop ออกทันทีที่เห็น draft.serverId ไม่ nil
        startLocationChase(token: token)
        startRetryLoop(token: token)
        await send(token: token)
    }

    /// โน้ตที่พิมพ์จากจอสถานะระหว่างรอ — ไปทางเดียวกับการยิงปกติ client_id เดิม
    ///
    /// คืน true ก็ต่อเมื่อเซิร์ฟเวอร์สะท้อนข้อความนั้นกลับมาจริงในเคส (sosSelect คืน s.message
    /// เสมอ) ไม่ใช่แค่ "เรียกไปแล้ว" — จอสถานะใช้ค่านี้บอกความจริงว่าเจ้าหน้าที่ได้เห็นข้อความ
    /// หรือยัง แทนที่จะขึ้นว่าส่งแล้วทั้งที่ยังไม่ถึงไหน
    @discardableResult
    func attachNote(_ text: String, token: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var d = draft, !trimmed.isEmpty else { return false }
        d.message = trimmed
        outbox.save(d)
        draft = d
        await send(token: token)
        return serverCase?.message == trimmed
    }

    /// "คนที่เจ็บคือคนอื่น ไม่ใช่ฉัน" — ยิงซ้ำด้วย clientId เดิม พร้อม for_other = true
    ///
    /// เซิร์ฟเวอร์ OR ค่านี้เข้ากับของเดิมเสมอ (`for_other = for_other OR $8` ใน Raise) กดครั้งเดียว
    /// จึงพอ และไม่มีทางถอนกลับได้ที่ฝั่งเซิร์ฟเวอร์ — ซึ่งถูกต้อง: ถ้ามีคนบอกว่ามีคนเจ็บอยู่ ทีมที่
    /// ไปถึงต้องเตรียมตัวแบบนั้นไว้ก่อนเสมอ · ค่านี้สั่งงานจริงสามอย่างฝั่งเซิร์ฟเวอร์/เจ้าหน้าที่:
    /// ข้อความ push ของกลุ่มเปลี่ยนเป็น "แจ้งว่ามีคนเจ็บ" การ์ดเจ้าหน้าที่ขึ้นแบนเนอร์ "คนอื่นเจ็บ"
    /// และประวัติสุขภาพของ "คนกด" ถูกปิดไม่ให้เจ้าหน้าที่เห็น (SQL gate มีเงื่อนไข NOT s.for_other)
    ///
    /// **ธงในเครื่องต้องถอนกลับเมื่อส่งไม่ถึง** (แก้จากรีวิว) — เดิมเขียน draft.forOther = true ทิ้งไว้
    /// ก่อนยิงเสมอไม่ว่าผลจะเป็นอย่างไร ทำให้เกิดสามเรื่องพร้อมกัน: จอเปลี่ยนเป็น "แจ้งไว้แล้ว" ทั้งที่
    /// ยังไม่ถึงใคร · guard `!d.forOther` ปิดทางกดซ้ำไปเลย · และไม่มีอะไรมายิงต่อให้ในรอบนั้น (retry
    /// loop จบไปแล้วตั้งแต่ serverId ถูกตั้ง ส่วน flush(token:) ไม่มีผู้เรียกที่ไหนในแอปเลย) ค่าจึงไป
    /// ถึงเซิร์ฟเวอร์เร็วสุดตอนเปิดแอปครั้งถัดไป ระหว่างนั้นเจ้าหน้าที่ไม่เห็นแบนเนอร์ เห็นประวัติสุขภาพ
    /// ของคนกดแทน และกลุ่มได้ข้อความผิด โดยที่คนกดเชื่อว่าบอกไปแล้ว — ทรงเดียวกับ attachNote ข้างบน
    /// ที่รายงานผลจากค่าที่เซิร์ฟเวอร์สะท้อนกลับมาเท่านั้น
    ///
    /// ถอนแบบระวัง: แตะเฉพาะฟิลด์ forOther ของ draft "ตัวปัจจุบัน" ไม่ใช่เขียนทับทั้งก้อนด้วยสำเนาที่
    /// จับไว้ก่อน await — ระหว่างนั้น location chase อาจเพิ่งเขียนพิกัดที่แม่นกว่าลงไป และถ้า
    /// cancel()/clearForLogout() แทรกเข้ามา draft จะเป็น nil หรือกลายเป็นเคสอื่นไปแล้ว ห้ามเขียนอะไร
    /// กลับลงไปทั้งสิ้น (เหตุผลเดียวกับ generation guard ใน send())
    ///
    /// ปลอดภัยแม้ในกรณีที่ request ถึงเซิร์ฟเวอร์แล้วแต่คำตอบหายระหว่างทาง: เซิร์ฟเวอร์ OR ค่าไว้แล้ว
    /// การถอนธงในเครื่องไม่ย้อนอะไรที่นั่น และ poll รอบถัดไปจะได้ for_other = true กลับมาเอง
    @discardableResult
    func markForOther(token: String) async -> Bool {
        guard let original = draft, !original.forOther else { return false }
        var d = original
        d.forOther = true
        outbox.save(d)
        draft = d
        await send(token: token)

        // ยืนยันจากค่าที่เซิร์ฟเวอร์สะท้อนกลับมาเท่านั้น ไม่ใช่จากการที่เราเพิ่งเขียน draft ไปเอง
        if serverCase?.forOther == true { return true }
        if var current = draft, current.clientId == original.clientId, current.forOther {
            current.forOther = false
            outbox.save(current)
            draft = current
        }
        return false
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

    /// เพดาน poll ที่ "เซิร์ฟเวอร์ตอบสำเร็จว่าไม่มีเคส" ติดกัน ก่อนยอมเลิก — กันเคสที่เซิร์ฟเวอร์ลืม
    /// ไปแล้วจริงๆ วนตลอดกาล (พบจากรีวิว Task 14 รอบสอง — ดูคอมเมนต์ที่ startStatusPoll ว่าทำไมเคส
    /// แบบนี้เกิดได้) เลขนี้เป็นตัวเลขกลมๆ ที่เผื่อสัญญาณหลุดจริงยังทนได้อยู่ ไม่ใช่ค่าที่วัดจากอะไร
    /// ตายตัว
    ///
    /// **นับเฉพาะคำตอบ "ไม่มีเคส" ที่ยืนยันแล้วเท่านั้น — request ที่ throw (เน็ตหลุด/timeout) ไม่นับ**
    /// (แก้จากรีวิว Task 14 รอบสาม: เดิมใช้ `try?` รวมสองกรณีเป็นก้อนเดียว ทำให้ dead zone ธรรมดาไม่กี่
    /// สิบวินาที ซึ่งเป็นสิ่งที่ฟีเจอร์นี้ทั้งอันมีไว้ทนอยู่แล้ว ชนเพดานได้ก่อนที่คอมเมนต์เดิมจะพูดถึงด้วยซ้ำ
    /// — URLSession ไม่ได้ตั้ง waitsForConnectivity ไว้ที่ไหนเลยใน APIClient ทำให้ request ล้มเหลวเกือบ
    /// ทันทีในจุดอับสัญญาณจริง ไม่ใช่รอจน timeout 35 วิ)
    private static let maxConsecutiveEmptyPolls = 20

    /// long-poll สถานะไปเรื่อยๆ จนกว่าจะปิด · เคสจบ (resolved) ต้องล้าง **draft ที่ persist ไว้บนดิสก์**
    /// ด้วย ไม่ใช่แค่หยุด task — เดิม finish() อย่างเดียวปล่อย outbox.clear()/draft=nil ไว้ไม่ทำ ทำให้
    /// เคสที่จบไปแล้วยังเหลือ draft ค้างในเครื่อง ถ้าแอปถูกปิดแล้วเปิดใหม่ init() จะกู้ draft นั้นมาเป็น
    /// queued อีกรอบทั้งที่จบไปแล้วจริงๆ (พบจากรีวิว Task 14 รอบสอง) — serverCase/status ยังคงค่า
    /// .closed ไว้ให้จอสถานะแสดงผลจบเรื่องได้ตามปกติ สิ่งที่ต้องไม่รอดคือ draft/outbox เท่านั้น
    ///
    /// ถ้าเซิร์ฟเวอร์ยืนยันว่าไม่มีเคสนี้จริงๆ ติดกันเกินเพดาน (ดู maxConsecutiveEmptyPolls) ให้เลิก
    /// poll เช่นกัน ไม่ล้าง draft ในกรณีนี้เพราะไม่รู้จริงว่าเคสจบหรือเซิร์ฟเวอร์แค่ตอบผิด — ปล่อยให้
    /// retryTask/ผู้ใช้กด cancel เองตัดสินใจแทน แต่ **ต้องบอกจอสถานะว่าเลิกแล้ว** (statusCheckStopped)
    /// พร้อมทางกลับมา poll ต่อ (retryStatusCheck) — พบจากรีวิว Task 14 รอบสาม: เดิมหยุดแบบเงียบๆ คนที่
    /// เคสค้างอยู่ที่ .received/.onTheWay จะนั่งมองจอที่ค้างสถานะเก่าโดยไม่รู้ว่าไม่มีใครเช็คให้อีกแล้ว
    ///
    /// request ที่ throw (เน็ตหลุด/timeout จริง ไม่ใช่คำตอบว่าไม่มีเคส) ไม่นับเข้าเพดานเลย — ถอยห่างขึ้น
    /// เรื่อยๆ ตาม errorBackoffSchedule แทนที่จะยิงรัวทุก pollInterval ทับซ้ำ dead zone เดียวกัน (ทรง
    /// เดียวกับ startRetryLoop) แล้วกลับมายิงถี่ปกติทันทีที่สำเร็จอีกครั้ง (ไม่ว่าจะมีเคสหรือไม่ก็ตาม)
    private func startStatusPoll(token: String) {
        pollTask?.cancel()
        statusCheckStopped = false
        pollTask = Task { [weak self] in
            var consecutiveEmpty = 0
            var errorBackoffIndex = 0
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let c = try await self.activeCall(token, 25)
                    errorBackoffIndex = 0
                    if let c {
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
                            self.statusCheckStopped = true
                            return
                        }
                    }
                    try? await Task.sleep(for: self.pollInterval)
                } catch {
                    guard !Task.isCancelled else { return }
                    let schedule = self.errorBackoffSchedule
                    let delay = errorBackoffIndex < schedule.count
                        ? schedule[errorBackoffIndex] : (schedule.last ?? self.pollInterval)
                    errorBackoffIndex += 1
                    try? await Task.sleep(for: delay)
                }
            }
        }
    }

    /// เรียกจากปุ่ม "เช็คสถานะอีกครั้ง" ใน SOSStatusView — poll เดิมหยุดไปแล้วเพราะชนเพดาน "ไม่มีเคส"
    /// ติดกัน (ดู maxConsecutiveEmptyPolls) ไม่มีอะไรมาเริ่มมันต่อเองถ้าไม่มีทางนี้ (พบจากรีวิว Task 14
    /// รอบสาม) — เงียบๆ ถ้าไม่มีอะไรให้ poll แล้วจริงๆ (เคสยังไม่เคยถึงเซิร์ฟเวอร์ หรือปิดไปแล้ว)
    func retryStatusCheck(token: String) {
        guard draft?.serverId != nil, let status, status.isActive else { return }
        startStatusPoll(token: token)
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
    ///
    /// เช็ค draft.ownerId == currentUserId ซ้ำอีกชั้นตรงนี้ (พบจากรีวิว Task 14 รอบสาม) — เผื่อไว้เท่านั้น
    /// เพราะตามโครงสร้างจริงของไฟล์นี้ draft ที่เจ้าของไม่ตรงไม่มีวันรอดจาก init() มาถึงจุดนี้ได้อยู่แล้ว
    /// (init() ล้างทิ้งไปตั้งแต่ตอนสร้าง ส่วน raise() เองก็ stamp currentUserId ของ store เดียวกันเสมอ
    /// ไม่มีทางได้ค่าอื่น) แต่เป็นการ์ดที่ราคาถูกและตรงกับที่รีวิวขอเป็นชั้นที่สอง ไม่ใช่พึ่ง init() แค่ที่เดียว
    func resumeIfNeeded(token: String) async {
        guard let draft, draft.ownerId == currentUserId, let status, status.isActive else { return }
        startFallbackTimer()
        // ลำดับเดียวกับ raise() เป๊ะ และด้วยเหตุผลเดียวกัน — ดูคอมเมนต์ยาวที่นั่น
        startLocationChase(token: token)
        startRetryLoop(token: token)
        await send(token: token)
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
    /// **เดิมมีความเสี่ยงที่ยอมรับไว้แบบไม่แก้: บัญชีอื่น login บนเครื่องเดียวกันก่อนเจ้าของตัวจริงจะ
    /// กลับมา จะสืบทอด draft ของบัญชีแรกได้ (SOSOutbox ผูกกับ backend เท่านั้น ไม่ผูกกับ user id)**
    /// รีวิวรอบสามตามไปจนสุด: ถ้า draft นั้นยังไม่เคยถึงเซิร์ฟเวอร์ (serverId เป็น nil — เกิดขึ้นได้จริง
    /// เมื่อ 401 ที่ทำให้ล็อกเอาต์อัตโนมัติคือคำตอบของการยิง SOS เอง) resumeIfNeeded ของบัญชีที่สองจะ
    /// ยิงมันด้วย token ของตัวเอง แล้วเซิร์ฟเวอร์ INSERT เคสใหม่ที่ผูกกับ participant_id ของบัญชีที่สอง
    /// แต่มีพิกัด/ข้อความของบัญชีแรก — เคสฉุกเฉินจริงที่ผูกกับคนผิดคน เกิดขึ้นเองแค่เพราะ login ไม่ใช่
    /// ความเสี่ยงที่ยอมรับได้เลย แก้แล้วด้วย SOSDraft.ownerId + เช็คที่ init()/resumeIfNeeded() —
    /// บัญชีที่ไม่ตรงเจ้าของไม่มีวันได้ draft ของบัญชีก่อนหน้ามาเลย ไม่ว่า serverId จะมีหรือไม่ก็ตาม
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
        // เคลียร์ธง "หยุดเช็คแล้ว" ทุกครั้งที่ finish() ถูกเรียก (cancel/logout/resolved) — ยกเว้นตอน
        // startStatusPoll ชนเพดานเอง ซึ่งตั้ง statusCheckStopped = true ทับกลับทันทีหลัง finish()
        // คืนค่าในบรรทัดถัดไป (ดูโค้ดที่นั่น) ไม่งั้นเคสที่ถูกยกเลิก/ล็อกเอาต์ไปแล้วอาจเหลือแบนเนอร์
        // "เช็คสถานะอีกครั้ง" ค้างอยู่ทั้งที่ไม่มีอะไรให้เช็คแล้ว (ในทางปฏิบัติแทบไม่มีทางเกิดจริง เพราะ
        // หน้าต่างยกเลิก 15 วิสั้นกว่าเวลาที่ต้องใช้ถึงจะชนเพดานเสมอ — แก้ไว้เผื่อค่าคงที่พวกนั้นเปลี่ยน)
        statusCheckStopped = false
    }
}
