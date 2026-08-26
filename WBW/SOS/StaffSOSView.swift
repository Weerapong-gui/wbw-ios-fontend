import SwiftUI
import MapKit

// SOSStaffCase ย้ายไปนิยามใน WBW/APIClient+SOS.swift แล้ว (Task 10) — staffSOSFeed
// คืนค่าเป็นชนิดนี้ตรงๆ จึงต้องมีอยู่ก่อนไฟล์นั้นจะคอมไพล์ผ่าน ไม่ต้องประกาศซ้ำที่นี่
// (field/computed property ทั้งหมด: fullName, isCoarse, accuracyLabel, positionLabel
// อยู่ที่นิยามจริงใน Task 10 ไม่ใช่ที่นี่)

/// รายการเคสของเจ้าหน้าที่ · long-poll ตอนจอเปิด พึ่ง push ตอนจอปิด
///
/// start()/stop() ผูกกับ "เป็นเจ้าหน้าที่อยู่ไหม" (ดู RootView) ไม่ใช่ผูกกับว่าแท็บ SOS เปิดอยู่
/// หรือเปล่า — เคสใหม่ต้องทับจอได้แม้เจ้าหน้าที่กำลังก้มสแกน QR อยู่แท็บอื่น (ดูคอมเมนต์ที่ newCase
/// ด้านล่าง) ถ้า poll หยุดตอนออกจากแท็บนี้ ก็ไม่มีทางรู้เลยว่ามีเคสใหม่เข้ามาจนกว่าจะสลับกลับมาเอง
@MainActor
final class StaffSOSStore: ObservableObject {
    @Published private(set) var cases: [SOSStaffCase] = []

    /// badge บนแท็บ = งานที่ยังเหลือ ไม่ใช่จำนวนแถวบนจอ
    var openCount: Int { cases.filter { !$0.resolved }.count }

    /// เคสที่เพิ่งเห็นเป็นครั้งแรก (ยังไม่ resolved) หลัง baseline — RootView ผูก .fullScreenCover(item:)
    /// กับตัวนี้ตรงๆ ผ่าน $store.newCase เพื่อทับทั้งจอทันทีที่มีเคสใหม่เข้า ไม่ใช่แค่ badge มุมจอ
    /// (สเปก: เจ้าหน้าที่กำลังก้มมองคิว QR อยู่ ตัวเลขมุมจอไม่มีทางถูกเห็น) ปิดอะไรอื่นไม่ได้นอกจาก
    /// ตัวแปรนี้เอง — ไม่แตะ cases เลย เคสยังอยู่ในลิสต์ตามปกติหลังปิดจอทับ (ดู StaffSOSAlertView)
    ///
    /// ไม่ใช่ private(set): .fullScreenCover(item: $store.newCase) ต้องการ Binding ที่เขียนได้
    /// (SwiftUI ตั้งกลับเป็น nil เองตอนปิดจอทับ ผ่าน dismiss() ในสภาพแวดล้อมของจอที่เปิดมา)
    @Published var newCase: SOSStaffCase?

    /// จำนวนรอบ poll ที่ล้มเหลวติดกัน · > 0 = ฟีดกำลังพัง จอต้องบอก (ดู StaffSOSView.header)
    ///
    /// **มีอยู่เพราะ `try?` ใน start() กลืน error ทุกชนิดโดยไม่มีใครเห็น** (พบจากรีวิวรอบสุดท้าย) —
    /// รวมถึง 500 จาก cursor ที่เซิร์ฟเวอร์ปฏิเสธ ซึ่งเป็นอาการที่ "ซ่อมตัวเองไม่ได้": cursor ถูกเขียน
    /// ใน apply() เท่านั้น ซึ่งรันเฉพาะตอนสำเร็จ ค่าที่เซิร์ฟเวอร์ไม่ยอมรับจึงถูกส่งซ้ำตลอดกาล ฟีดตาย
    /// ถาวรโดยที่จอยังโชว์ชุดที่โหลดได้ก่อนหน้าและดูปกติทุกประการ · ตัวสาเหตุถูกแก้ที่ฝั่งเซิร์ฟเวอร์
    /// แล้ว (รูปแบบ updated_at) แต่ "ฟีดตายเงียบ" เป็นคนละเรื่องกับสาเหตุใดสาเหตุหนึ่ง — เน็ตหลุด
    /// token หมดอายุ เซิร์ฟเวอร์ล่ม ก็ให้ผลเดียวกันบนจอที่ต้องเชื่อถือได้ที่สุดของงาน
    @Published private(set) var consecutiveFeedFailures = 0
    var feedIsFailing: Bool { consecutiveFeedFailures > 0 }

    /// ผลของ ack/resolve ครั้งล่าสุดที่ล้มเหลว **ผูกกับเคสที่กดจริง**
    ///
    /// เดิมทั้งสองเมธอดกลืน error ด้วย `try?` แล้วไม่บอกอะไรเลย — เจ้าหน้าที่กด "กำลังไป" แล้วปุ่ม
    /// ไม่เปลี่ยน จะสรุปว่าแตะไม่โดน กดซ้ำ หรือสรุปว่าสำเร็จแล้วเดินออกไปก็ได้ทั้งคู่ (พบจากรีวิว Task 15
    /// ค้างไว้เป็นรายการรอ) บนจอที่คุมความปลอดภัยของคน การกดที่ล้มเหลวเงียบๆ ยอมรับไม่ได้
    ///
    /// **ต้องมี caseId ติดมาด้วย ไม่ใช่ String ลอยๆ** (แก้จากรีวิว) — การ์ดทุกใบอ่านตัวแปรตัวเดียวกัน
    /// ข้อความ error ของเคสหนึ่งจึงไปโผล่ใต้เคสอื่นทุกใบในลิสต์ และโผล่ในจอทับเต็มจอของเคสที่ไม่เกี่ยว
    /// กันเลยด้วย — บนจอที่ต้องอ่านเร็วที่สุดของงาน นั่นคือการชี้ให้คนไปดูเคสผิดใบ
    struct ActionError: Equatable {
        let caseId: Int64
        let message: String
    }
    @Published var actionError: ActionError?

    /// ล้างทิ้งเมื่อจอที่แสดงมันปิดไป — ไม่ใช่รอให้ "ครั้งถัดไปสำเร็จ" เท่านั้น ซึ่งอาจไม่มีวันเกิด
    /// ถ้าเจ้าหน้าที่เลิกกดปุ่มนั้นไปแล้ว แล้วข้อความค้างอยู่บนจอจนดูเหมือนเป็นปัญหาที่ยังเกิดอยู่
    func clearActionError() { actionError = nil }

    /// เคส id ที่เคยเห็นแล้ว (ไม่ว่าจะ resolved หรือไม่ก็ตาม) — ใช้แยก "เพิ่งเข้ามาใหม่" ออกจาก
    /// "แค่แถวเดิมถูกอัปเดต" (เช่น มีคนกดรับเรื่อง) เพราะ apply() รวมสองเหตุการณ์นี้เข้าด้วยกันเป็น
    /// การเขียนทับ dictionary แบบเดียวกันหมด แยกไม่ออกจากกันเองถ้าไม่จำ id ที่เคยเห็นไว้ต่างหาก
    private var seenIDs: Set<Int64> = []

    /// apply() เคยถูกเรียกมาก่อนหน้านี้แล้วหรือยัง (ไม่ว่าครั้งนั้นจะมีเคสมาด้วยหรือไม่ก็ตาม) — ตัวตัดสิน
    /// "baseline" ที่ถูกต้อง ต่างจาก seenIDs.isEmpty ที่เคยใช้ผิดมาก่อน (พบจากรีวิว): ฟีดฉุกเฉินว่างเปล่า
    /// เป็นปกติเกือบทั้งวันของงาน long-poll ที่ตอบกลับมาแบบไม่มีเคสเลย (apply([])) ไม่เติมอะไรใน seenIDs
    /// สักตัว ถ้าใช้ seenIDs.isEmpty เป็นตัวเช็ค baseline เคสจริงเคสแรกที่มาถึงหลังจากช่วงเงียบนั้น (ไม่ว่า
    /// จะเงียบมากี่ตา) จะยังถูกนับเป็น "baseline" อยู่ดี เพราะ seenIDs ยังว่างอยู่จริง — จอทับเต็มจอที่
    /// ฟีเจอร์นี้มีไว้ทั้งอันจะไม่มีวันเปิดเลยแม้แต่ครั้งเดียวสำหรับเหตุฉุกเฉินจริงตัวแรกของวัน ซึ่งเป็น
    /// สถานการณ์ที่เกิดขึ้นจริงมากที่สุด (ฟีดว่างมาตลอดจนกว่าจะมีคนกด SOS จริง)
    private var hasPolledBefore = false

    /// cursor เป็นคู่ "<updated_at>|<id>" ไม่ใช่ updated_at เดี่ยวๆ — updated_at ไม่ unique สองเคสที่มี
    /// เวลาเท่ากันเป๊ะจะทำให้ตัวหนึ่งหายจากทุกรอบถัดไปถาวรถ้าตัด id ทิ้ง (ดูคอมเมนต์ที่ apply())
    /// private(set) แทนที่จะ private ล้วน เพื่อให้เทสยืนยันรูปแบบคู่นี้ได้ตรงๆ ไม่ใช่แค่เดาจากผลข้างเคียง
    private(set) var cursor: String?

    private var loop: Task<Void, Never>?
    private let feedCall: (String, String?) async throws -> [SOSStaffCase]
    /// ช่วงพักระหว่างรอบ poll — ฉีดได้เพื่อให้เทส round-trip ของ cursor ไม่ต้องรอ 1 วินาทีจริงต่อรอบ
    /// (ทรงเดียวกับ pollInterval ของ SOSStore) ค่าเริ่มต้น 1 วิเท่าของเดิมทุกประการสำหรับผู้เรียกจริง
    private let pollInterval: Duration
    /// user id ของเจ้าหน้าที่ที่ล็อกอินอยู่ตอนนี้ — ใช้กันไม่ให้เคสของตัวเองมาเด้งจอทับซ้อนกับ
    /// SOSStatusView ของตัวเอง (ดูคอมเมนต์ที่ apply() ตรง participantId == currentUserId) ค่าเริ่มต้น
    /// "" ใช้ได้กับเทสที่ไม่สนเรื่องเจ้าของเท่านั้น (ไม่มีเคสจริงไหน participantId เป็น "" อยู่แล้ว
    /// จึงไม่กรองอะไรทิ้งเลยเมื่อไม่ได้ส่งมา — ทรงเดียวกับ SOSStore.currentUserId)
    private let currentUserId: String

    init(feedCall: @escaping (String, String?) async throws -> [SOSStaffCase]
         = { token, since in try await APIClient.shared.staffSOSFeed(token: token, since: since, wait: 25) },
         pollInterval: Duration = .seconds(1),
         currentUserId: String = "") {
        self.feedCall = feedCall
        self.pollInterval = pollInterval
        self.currentUserId = currentUserId
    }

    /// รวมของใหม่เข้ากับของเดิมด้วย id · ใหม่สุดอยู่บน
    /// เคสที่ปิดแล้วยังอยู่ในลิสต์ (เซิร์ฟเวอร์ส่งย้อนหลัง 30 นาที) — หายไปเฉยๆ
    /// แยกไม่ออกจาก "โหลดไม่ขึ้น" ซึ่งเป็นคนละเรื่องกันโดยสิ้นเชิง
    #if DEBUG
    /// เคสตัวอย่างจาก launch args — `-uitestStaffSOSCase coarse` ได้พิกัดหยาบ ค่าอื่นได้พิกัดแม่น
    static func uitestSampleCase() -> SOSStaffCase? {
        let raw = UserDefaults.standard.string(forKey: "uitestStaffSOSCase") ?? ""
        guard !raw.isEmpty, raw != "NO" else { return nil }
        let coarse = raw == "coarse"
        return SOSStaffCase(
            id: 4242, forOther: false,
            lat: 20.04549, lng: 99.90280,
            accuracyM: coarse ? 450 : 12,
            locSource: "gps", checkpointId: 5,
            checkpointName: coarse ? nil : "วิหารพระเจ้าล้านทอง",
            message: "ข้อเท้าพลิก เดินต่อไม่ไหว",
            resolved: false, resolveReason: nil,
            ackedAt: nil, ackedByName: nil,
            createdAt: "2026-08-21T11:00:00Z",
            emergencyPhone: Config.emergencyPhoneDefault,
            updatedAt: "2026-08-21T11:00:00Z",
            participantId: "demo-1", firstName: "ดินดิน", lastName: "เดินดอย",
            bib: 1042, groupNumber: 7, contactPhone: "0800000002",
            emergencyContactName: "ผู้ปกครอง ตัวอย่าง", emergencyContactPhone: "0800000001",
            bloodType: "O", healthNotes: "แพ้ยาเพนนิซิลลิน",
            // เคสจำลองอยู่ชั้นแรกโดยตั้งใจ — ป้าย "ยังเห็นเฉพาะเจ้าหน้าที่ประจำกลุ่ม" กับปุ่ม
            // สรุปเคสจะได้ติดมาในสกรีนช็อตด้วย (ดู `SOSOutcome`)
            severity: nil, escalated: false)
    }
    #endif

    func apply(_ incoming: [SOSStaffCase]) {
        // จับไว้ก่อนแก้ hasPolledBefore — apply() ครั้งแรกที่ store เคยถูกเรียกเลยคือ "baseline" ของ
        // เจ้าหน้าที่คนนี้ ไม่ใช่ "เคสเพิ่งเข้ามา" ในสายตาเขา (ดูคอมเมนต์ที่ newCase ว่าทำไมต้องแยกสองเรื่องนี้)
        //
        // **ใช้ hasPolledBefore ไม่ใช่ seenIDs.isEmpty** (แก้จากรีวิว) — ฟีดฉุกเฉินว่างเปล่าเป็นปกติ
        // เกือบทั้งวัน long-poll ที่ตอบกลับมาแบบไม่มีเคสเลย (apply([])) ไม่เติมอะไรใน seenIDs สักตัว
        // ถ้าเช็คจาก seenIDs.isEmpty เคสฉุกเฉินจริงเคสแรกของวันที่มาถึงหลังช่วงเงียบนั้น (ไม่ว่าจะเงียบมา
        // กี่ตา) จะยังถูกนับเป็น baseline อยู่ดี เพราะ seenIDs ยังว่างจริง — จอทับเต็มจอไม่มีวันเปิดเลย
        // สำหรับเหตุฉุกเฉินจริงตัวแรก ซึ่งเป็นสถานการณ์ทั่วไปที่สุด (พบจากรีวิว: apply([]), apply([]),
        // apply([case]) ทิ้ง newCase เป็น nil ด้วยโค้ดเดิม)
        let isBaseline = !hasPolledBefore
        // ไม่กันเคสของตัวเองออกจาก seenIDs/cases — ยังต้องเห็นในลิสต์ตามปกติ (ถูกต้องที่จะอยู่ตรงนั้น)
        // กันออกเฉพาะจากการเด้งจอทับ (freshlyArrived) เท่านั้น (ดูคอมเมนต์ที่ currentUserId ด้านบน):
        // เคสของตัวเจ้าหน้าที่เองมาจากปุ่ม SOS ของตัวเอง (StaffHomeView.staffOwnSOS) ซึ่งมี
        // SOSStatusView ของตัวเองเปิดทับจออยู่แล้วพร้อมปุ่มยกเลิก — StaffSOSAlertView ("มีเหตุฉุกเฉินใหม่"
        // แบบเพื่อนร่วมงาน ไม่มีปุ่มยกเลิก) มาแย่ง fullScreenCover กันเป็นเรื่องของคนละเหตุการณ์ที่ไม่ควร
        // เกิดกับเคสเดียวกัน (พบจากรีวิว)
        let freshlyArrived = incoming.filter {
            !seenIDs.contains($0.id) && !$0.resolved && $0.participantId != currentUserId
        }
        for c in incoming { seenIDs.insert(c.id) }
        hasPolledBefore = true

        var byID = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })
        for c in incoming { byID[c.id] = c }
        cases = byID.values.sorted {
            ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id)
        }
        // cursor เป็นคู่ "<updated_at>|<id>" — updated_at เดี่ยวๆ ไม่ unique
        // สองเคสที่มีเวลาเท่ากันเป๊ะจะทำให้ตัวหนึ่งหายจากทุกรอบถัดไปถาวร
        if let newest = cases.first { cursor = "\(newest.updatedAt)|\(newest.id)" }

        guard !isBaseline,
              let alert = freshlyArrived.max(by: { ($0.updatedAt, $0.id) < ($1.updatedAt, $1.id) })
        else { return }
        newCase = alert
    }

    /// รอบ poll ที่ล้มเหลวติดกันกี่รอบถึงจะเชื่อว่า "พังจริง" ไม่ใช่แค่สะดุด — 1 รอบพลาดเป็นเรื่องปกติ
    /// ของเน็ตบนดอย ขึ้นแบนเนอร์ทุกครั้งที่สะดุดจะกลายเป็นเสียงรบกวนที่คนเลิกมองภายในสิบนาที
    private static let feedFailuresBeforeWarning = 3

    func start(token: String) {
        #if DEBUG
        // ยัดเคสตัวอย่างไว้ถ่ายภาพยืนยัน — จอนี้อยู่หลังบัญชี staff จริงซึ่งโหมดเดโม่ไม่ครอบ
        // และ `staffSOSFeed` คืน `[]` ในโหมดเดโม่ ไม่มีทางเห็นแผนที่ในการ์ดเลยถ้าไม่มีแฟลก
        // (ทรงเดียวกับ `-uitestStaffScreen` / `-uitestCameraDenied` / `-uitestCredits`)
        //
        // ต้องมีสองแบบ: พิกัดแม่นกับพิกัดหยาบ — วงความคลาดเคลื่อนโผล่เฉพาะแบบหลัง
        // (`SOSStaffCase.isCoarse` = แม่นแย่กว่า 200 ม.) ถ่ายแบบเดียวจะไม่เห็นครึ่งหนึ่งของงาน
        if let sample = Self.uitestSampleCase() {
            apply([sample])
            return
        }
        #endif
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    self.apply(try await self.feedCall(token, self.cursor))
                    self.consecutiveFeedFailures = 0
                } catch {
                    // แยก "พลาดไปหนึ่งรอบ" ออกจาก "ตายแล้ว" ด้วยการนับ ไม่ใช่กลืนทิ้งทั้งคู่
                    self.consecutiveFeedFailures += 1
                }
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    func stop() { loop?.cancel() }

    var feedWarning: String? {
        guard consecutiveFeedFailures >= Self.feedFailuresBeforeWarning else { return nil }
        return String(format: Loc.t("sos_staff_feed_failing"), consecutiveFeedFailures)
    }

    /// คืน true เมื่อเซิร์ฟเวอร์รับจริง · false = ล้มเหลว และ actionError ถูกตั้งไว้ให้จอแสดง
    ///
    /// **ข้อความบอกว่า "คำขอไม่สำเร็จ" ไม่ใช่ "เซิร์ฟเวอร์ยังไม่ได้บันทึก"** (แก้จากรีวิว) — ฝั่ง client
    /// รู้แค่ว่าตัวเองไม่ได้คำตอบ ไม่รู้ว่าอีกฝั่งทำอะไรไปแล้วหรือยัง timeout ที่เกิดหลังเซิร์ฟเวอร์
    /// commit ไปแล้วให้ผลหน้าตาเดียวกันเป๊ะ การเขียนว่า "ยังไม่มีใครถูกบันทึกว่ารับเรื่อง" จึงเป็น
    /// คำกล่าวอ้างที่อาจผิด และผิดในทางที่แย่ที่สุด: ชวนให้เจ้าหน้าที่คนที่สองวิ่งไปซ้ำเคสที่มีคนรับแล้ว
    @discardableResult
    func ack(id: Int64, token: String) async -> Bool {
        do {
            _ = try await APIClient.shared.ackSOS(token: token, id: id)
            actionError = nil
            return true
        } catch {
            actionError = ActionError(caseId: id, message:
                Loc.t("sos_staff_ack_failed"))
            return false
        }
    }

    /// สรุปว่าพบอะไร — `major`/`urgent` ยกระดับให้ทั้งงานเห็นและเคสยังเปิดอยู่ (ดู `SOSOutcome`)
    @discardableResult
    func report(id: Int64, outcome: SOSOutcome, token: String) async -> Bool {
        do {
            _ = try await APIClient.shared.reportSOS(token: token, id: id, outcome: outcome)
            actionError = nil
            return true
        } catch {
            actionError = ActionError(caseId: id, message: Loc.t("sos_staff_report_failed"))
            return false
        }
    }

    @discardableResult
    func resolve(id: Int64, reason: String, token: String) async -> Bool {
        do {
            _ = try await APIClient.shared.resolveSOS(token: token, id: id, reason: reason)
            actionError = nil
            return true
        } catch {
            actionError = ActionError(caseId: id, message:
                Loc.t("sos_staff_resolve_failed"))
            return false
        }
    }
}

/// การ์ดเคสหนึ่งใบ — ใช้ทั้งในลิสต์ปกติ (StaffSOSView) และในจอทับเต็มจอตอนเคสใหม่เข้า (StaffSOSAlertView)
///
/// ข้อมูลสุขภาพ (healthNotes/bloodType) โชว์เฉพาะตอนเซิร์ฟเวอร์ส่งมาให้เท่านั้น — เซิร์ฟเวอร์เองเป็นคน
/// คุมเงื่อนไข (ยินยอมแล้ว + เคสยังเปิด + ไม่ใช่เคสที่แจ้งแทนคนอื่น) จอนี้ไม่เพิ่มเงื่อนไขซ้ำ และไม่โชว์
/// placeholder ตอนไม่มีข้อมูล (เช่น "ไม่มีข้อมูลสุขภาพ") เพราะแยกไม่ออกจาก "เซิร์ฟเวอร์ไม่ให้สิทธิ์" กับ
/// "มีสิทธิ์แต่ไม่มีข้อมูลกรอกไว้จริงๆ" — `if let` เฉยๆ คือพอ
struct StaffSOSCard: View {
    let c: SOSStaffCase
    let token: String
    @ObservedObject var store: StaffSOSStore
    @State private var showReasons = false
    /// กล่องเลือก "พบอะไร" — คนละชุดกับ `showReasons` ที่เป็นเหตุผลปิดเคส (ดู `SOSOutcome`)
    @State private var showOutcomes = false
    /// มีคำสั่งกำลังวิ่งอยู่ — ปุ่มต้องกดซ้ำไม่ได้และต้องบอกว่ากำลังทำงาน (พบจากรีวิว Task 15
    /// ค้างไว้เป็นรายการรอ) เดิมปุ่ม "กำลังไป" ไม่มีสถานะ disabled เลย กดรัวได้ตามใจโดยไม่มีอะไร
    /// เปลี่ยนบนจอ ซึ่งบนเน็ตที่ช้าแยกไม่ออกจาก "แตะไม่โดน"
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if c.forOther {
                Label("sos_staff_for_other", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text(c.fullName).font(.wbwText(19, weight: .bold, relativeTo: .title3))
            Text(String(format: Loc.t("sos_staff_bib_group"),
                        c.bib.map(String.init) ?? "-", c.groupNumber.map(String.init) ?? "-"))
                .foregroundStyle(Color.wbwForestVoid.opacity(0.65))

            Text(c.checkpointName.map { String(format: Loc.t("sos_staff_near_base"), $0) }
                    ?? Loc.t("sos_staff_base_unknown"))
            Text("\(c.positionLabel) · \(c.accuracyLabel)")
                .font(.wbwText(11, relativeTo: .caption))
                .foregroundStyle(c.isCoarse ? Color.orange : Color.wbwForestVoid.opacity(0.65))
            if c.isCoarse {
                Text("sos_staff_coarse_location")
                    .font(.wbwText(11, relativeTo: .caption)).foregroundStyle(.orange)
            }

            // แผนที่ในการ์ดเลย — เดิมมีแค่ตัวเลขพิกัดกับลิงก์ที่เด้งออกไปนอกแอป คนที่กำลังจะ
            // วิ่งไปหาผู้บาดเจ็บต้องออกจากแอปก่อนถึงจะรู้ว่าไปทางไหน · ไม่มีพิกัด = ไม่มีแผนที่
            // ข้อความ "ไม่ทราบตำแหน่ง" จาก positionLabel ด้านบนทำหน้าที่แทนเหมือนเดิม
            if let lat = c.lat, let lng = c.lng {
                SOSCaseMapView(lat: lat, lng: lng,
                               accuracyM: c.accuracyM, showsAccuracy: c.isCoarse)
            }

            if let notes = c.healthNotes, !notes.isEmpty {
                Text(notes).font(.wbwBodyMedium).padding(8)
                    .background(.red.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if let blood = c.bloodType { Text(Loc.t("sos_staff_blood_type", blood)).font(.wbwBodyMedium) }

            // **เคสชั้นแรกยังไม่มีใครนอกกลุ่มเห็น** — บอกให้เจ้าหน้าที่ที่ถือเคสอยู่รู้ตัว
            // ไม่งั้นจะยืนรอกำลังเสริมที่ยังไม่มีใครเรียก (ดู `SOSOutcome.showsStageOneBadge`)
            if SOSOutcome.showsStageOneBadge(escalated: c.isEscalated, resolved: c.resolved) {
                Label("sos_staff_stage_one", systemImage: "eye.slash")
                    .font(.wbwText(11, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let m = c.message { Text("\u{201c}\(m)\u{201d}").italic() }

            HStack {
                // contact_phone มาจาก DB ตรง ๆ ไม่เคยถูกตรวจรูปแบบ — เบอร์ที่มีช่องว่างทำให้
                // `URL(string:)!` เดิม crash จอเจ้าหน้าที่ทั้งใบตอนมีเคสจริงเข้ามา
                if let phone = c.contactPhone, let callURL = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") {
                    Link(destination: callURL) {
                        Label("sos_staff_call_reporter", systemImage: "phone.fill")
                    }
                }
                if let lat = c.lat, let lng = c.lng,
                   let maps = SOSMapLink.appleMaps(lat: lat, lng: lng) {
                    Link(destination: maps) { Label("sos_map_open", systemImage: "map.fill") }
                }
            }

            if c.resolved {
                Label("sos_staff_closed", systemImage: "flag.checkered")
                    .foregroundStyle(Color.wbwForestVoid.opacity(0.65))
            } else if let by = c.ackedByName {
                // เคสถูกรับไปแล้วโดยใครสักคน (อาจเป็นเจ้าหน้าที่คนอื่นที่กดก่อน) — โชว์ชื่อคนรับแทนปุ่ม
                // "กำลังไป" เสมอ ไม่ใช่แค่ตอนที่เรากดเอง จุดนี้เองที่กันเคสถูก ack ซ้ำสอง: พอ ackedByName
                // ไม่ใช่ nil ปุ่มด้านล่างก็หายไปแล้ว ไม่มีทาง POST ack ซ้ำจาก UI นี้ได้อีก
                Text(Loc.t("sos_staff_on_the_way", by))
            } else {
                // ตัวอักษรต้องสว่างเอง — `.borderedProminent` ย้อมพื้นด้วย tint ของการ์ด
                // (`wbwForestVoid` เกือบดำ) ส่วน label รับสีจาก `.foregroundStyle` ของการ์ด
                // ซึ่งเป็นสีเดียวกัน = ดำบนดำ อ่านไม่ออกเลย (ถ่ายเจอจริง 2026-08-21)
                Button { run { await store.ack(id: c.id, token: token) } } label: {
                    Text(Loc.t(busy ? "sos_staff_sending" : "sos_staff_ack"))
                        .foregroundStyle(Color.wbwOnBackdrop)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
            }

            if !c.resolved {
                Button("sos_staff_report") { showOutcomes = true }
                    .disabled(busy)
                    .confirmationDialog("sos_staff_report_why", isPresented: $showOutcomes) {
                        ForEach(SOSOutcome.allCases) { outcome in
                            Button(Loc.t(outcome.labelKey)) {
                                run { await store.report(id: c.id, outcome: outcome, token: token) }
                            }
                        }
                        Button("action_cancel", role: .cancel) {}
                    }

                Button("sos_staff_resolve") { showReasons = true }
                    .disabled(busy)
                    .confirmationDialog("sos_staff_resolve_why", isPresented: $showReasons) {
                        Button("sos_staff_resolve_helped") { run { await store.resolve(id: c.id, reason: "helped", token: token) } }
                        Button("sos_staff_resolve_false") { run { await store.resolve(id: c.id, reason: "false_alarm", token: token) } }
                        Button("sos_staff_resolve_unreachable") { run { await store.resolve(id: c.id, reason: "unreachable", token: token) } }
                        Button("action_cancel", role: .cancel) {}
                    }
            }

            // การกดที่ล้มเหลวต้องเห็น ไม่ใช่หายไปกับ try? — บนจอนี้ "ไม่มีอะไรเปลี่ยน" แปลได้ทั้ง
            // "สำเร็จแล้วแต่ยังไม่รีเฟรช" และ "ไม่มีอะไรเกิดขึ้นเลย" ซึ่งเป็นคนละเรื่องกันคนละขั้ว
            //
            // เทียบ caseId ก่อนแสดงเสมอ — ตัวแปรอยู่ที่ store ตัวเดียวซึ่งการ์ดทุกใบอ่านร่วมกัน ถ้าไม่
            // เทียบ error ของเคสหนึ่งจะไปโผล่ใต้เคสอื่นทุกใบ (และในจอทับเต็มจอของเคสที่ไม่เกี่ยวกัน)
            if let err = store.actionError, err.caseId == c.id {
                Label(err.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.wbwText(11, relativeTo: .caption)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // พื้นการ์ดขาวตายตัว ตัวอักษรจึงต้องตายตัวด้วย — ค่าปริยาย `.primary` พลิกเป็นขาว
        // ในโหมดมืด แล้วทั้งการ์ดกลายเป็นขาวบนขาว · `.tint` ด้วยเพราะปุ่มกับ `Link` บนการ์ดนี้
        // รับสีจาก tint ที่ตกทอดมา ซึ่งเป็น `wbwGold` (= #E9EEE0 ในโหมดมืด) จากแถบแท็บ
        .foregroundStyle(Color.wbwForestVoid)
        .tint(Color.wbwForestVoid)
    }

    /// ล้อม busy รอบคำสั่งเดียว — ทุกปุ่มบนการ์ดนี้ผ่านทางนี้ทางเดียว จะได้ไม่มีปุ่มไหนลืม
    private func run(_ work: @escaping () async -> Void) {
        busy = true
        Task {
            await work()
            busy = false
        }
    }
}

/// จอเจ้าหน้าที่: รายการเคส SOS ทั้งหมด — แท็บที่สองข้างแท็บสแกน QR (ดู RootView)
/// long-poll ขับเคลื่อนจาก RootView ไม่ใช่จากจอนี้เอง (ไม่มี onAppear/onDisappear เรียก
/// store.start()/stop() ที่นี่) — ดูคอมเมนต์ยาวที่ StaffSOSStore ด้านบนว่าทำไม
struct StaffSOSView: View {
    @ObservedObject var store: StaffSOSStore
    let token: String

    var body: some View {
        ZStack {
            // **พื้นตายตัว ไม่ใช่ `wbwInk`** — `wbwInk` พลิกเป็น #E9EEE0 ในโหมดมืด (ค่าปริยาย
            // ของแอป) ขณะที่จอนี้เขียนตัวอักษรเป็น `.white` ตายตัว = ขาวบนขาวทั้งจอ
            // อาการเดียวกับที่เจอใน `StaffScanView` (แก้ 2026-08-21)
            Color.wbwForestVoid.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                // ฟีดพังต้องเห็น ไม่ใช่ปล่อยให้จอโชว์ชุดเก่าค้างไว้แล้วดูปกติดี (ดูคอมเมนต์ยาวที่
                // StaffSOSStore.consecutiveFeedFailures) — วางไว้ใต้หัวจอ ก่อนรายการ เพื่อให้เห็นทั้ง
                // ตอนมีเคสและตอนไม่มี ซึ่งเป็นสองสถานะที่แยกจาก "โหลดไม่ขึ้น" ไม่ออกถ้าไม่มีบรรทัดนี้
                if let warning = store.feedWarning {
                    Label(warning, systemImage: "wifi.exclamationmark")
                        .font(.wbwText(13, relativeTo: .footnote))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.red.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
                if store.cases.isEmpty {
                    // `Spacer()` สองตัวจัด empty state ไว้กลางจอ — ห่อ `ScrollView` เฉย ๆ
                    // แล้วมันยุบ ข้อความจะไปกองชิดบน · `FitsOrScrolls` เก็บการจัดกลางไว้
                    // และให้เลื่อนได้เมื่อข้อความยาวจนไม่ลง (ตัวอักษรขนาดใหญ่สุด)
                    FitsOrScrolls {
                        VStack {
                            Spacer()
                            emptyState
                            Spacer()
                        }
                        .contentColumn(.card)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.cases) { c in
                                StaffSOSCard(c: c, token: token, store: store)
                            }
                        }
                        .padding(16)
                        .contentColumn(.card)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("sos_staff_title")
                    .font(.wbwText(22, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(.white)
                Text(store.openCount > 0
                     ? String(format: Loc.t("sos_staff_open_count"), store.openCount)
                     : Loc.t("sos_staff_none_open"))
                    .font(.wbwText(13, relativeTo: .footnote))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.35))
            Text("sos_staff_empty")
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

/// เคสใหม่เข้าตอนกำลังก้มสแกน QR — badge มุมจอไม่มีทางถูกเห็น ต้องทับทั้งจอทันที (ดูคอมเมนต์ที่
/// StaffSOSStore.newCase และที่ RootView)
///
/// ปิดได้เสมอโดยไม่เสียเคสทิ้ง — ปิด (dismiss()) แค่ทำให้ store.newCase กลับเป็น nil เท่านั้น
/// ไม่แตะ store.cases เลย เคสยังอยู่ในแท็บ SOS ตามปกติทุกประการหลังปิดจอนี้ (สองตัวแปรคนละตัวกัน
/// โดยสิ้นเชิง) — มีสองทางออกให้กด (ปุ่ม X มุมขวาบน กับปุ่มด้านล่าง) กัน "หาทางปิดไม่เจอ" ตอนตกใจ
struct StaffSOSAlertView: View {
    let c: SOSStaffCase
    let token: String
    @ObservedObject var store: StaffSOSStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // **พื้นตายตัว ไม่ใช่ `wbwInk`** — `wbwInk` พลิกเป็น #E9EEE0 ในโหมดมืด (ค่าปริยาย
            // ของแอป) ขณะที่จอนี้เขียนตัวอักษรเป็น `.white` ตายตัว = ขาวบนขาวทั้งจอ
            // อาการเดียวกับที่เจอใน `StaffScanView` (แก้ 2026-08-21)
            Color.wbwForestVoid.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("sos_staff_new_case", systemImage: "sos")
                        .font(.wbwHeadlineSmall)
                        .foregroundStyle(.red)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: Config.Tap.minTarget, height: Config.Tap.minTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("action_close")
                }

                ScrollView {
                    StaffSOSCard(c: c, token: token, store: store)
                }

                Button("sos_staff_see_all") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        // ข้อความว่ากดไม่สำเร็จต้องไม่รอดข้ามการปิดจอนี้ไป — จอนี้หายไปแล้ว ข้อความของมันก็ควรหายด้วย
        // ไม่ใช่ค้างอยู่ในลิสต์จนกว่าจะมีใครกดอะไรสำเร็จอีกครั้ง (ซึ่งอาจไม่เกิดขึ้นเลย)
        .onDisappear { store.clearActionError() }
    }
}
