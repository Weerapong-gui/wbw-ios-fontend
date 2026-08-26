import Foundation

/// gate ให้คะแนน — คำตอบเดียวของคำถาม "ตอนนี้ต้องยึดจอด้วยฟอร์มไหน"
///
/// ยกกติกามาจาก FeedbackGate.kt ฝั่ง Android คำต่อคำ (เหตุผลเต็มอยู่ในสเปก):
/// ฐานค้างตอบมาก่อนเสมอ ทีละฐานเรียงตามเวลาที่เดินถึง · event form เฉพาะเมื่อครบทุกฐาน
/// ตอบครบ server ยังไม่เคยได้คำตอบทั้งงาน และผู้ใช้ยังไม่กดข้ามในรันนี้
enum FeedbackGateState: Equatable {
    case base(CheckinProgressItem)
    case event

    /// ตัดสินว่า gate ต้องยึดจอด้วยอะไร — nil = ปล่อยแอปทำงานปกติ
    /// pending เรียง "เก่าก่อน" (ตอบตามลำดับที่เดินถึง) — ตรงข้าม CheckinProgress.pending
    /// ของ toast ที่ใหม่ก่อน
    ///
    /// **`queuedCheckpoints` = ฐานที่คำตอบยังค้างอยู่ใน outbox และต้องนับว่า "ตอบแล้ว"**
    ///
    /// ไม่มีข้อนี้ gate จะกลายเป็นกับดักที่ออกไม่ได้ทันทีที่สัญญาณหาย: `FeedbackStore.submit`
    /// จับ `AppError.offline` เก็บ draft เข้าคิวแล้วคืน `.saved` → ฟอร์มตั้ง `sent = true`
    /// (ปุ่มส่งหายไป เหลืออ่านอย่างเดียว) → `progress.load` ที่ตามมาก็ล้มเหลวเงียบ ๆ ด้วยสาเหตุ
    /// เดียวกัน (`guard let fresh = try? ... else { return }` ใน `CheckinProgressStore`) →
    /// `answered` ยังเป็น false → decide ยกฐานเดิมขึ้นอีกรอบ · gate ไม่มีปุ่มปิด ไม่มีปุ่มข้าม
    /// และ cache ของ progress ยกฐานเดิมกลับมาให้อีกหลังปิดแอป — บนดอยที่ไม่มีสัญญาณ ผู้ใช้จะเหลือ
    /// ของที่กดได้บนจอชิ้นเดียวคือปุ่ม SOS
    ///
    /// **ความเข้มของ gate ไม่ได้ลดลง** — ผู้ใช้ยังต้องให้คะแนนและกดส่งเหมือนเดิมทุกประการ
    /// สิ่งที่เปลี่ยนคือ "จอนี้ปิดได้ไหม" เลิกขึ้นกับว่าเน็ตติดหรือเปล่า · คิวคือคำตอบที่ผู้ใช้
    /// ให้ไปแล้วจริง ๆ ไม่ใช่คำสัญญาว่าจะตอบทีหลัง
    ///
    /// ไม่มีค่าเริ่มต้นให้พารามิเตอร์นี้โดยตั้งใจ: จุดเรียกใหม่ที่ลืมส่งคิวมาคือกับดักตัวเดิม
    /// กลับมาเงียบ ๆ ให้คอมไพล์ไม่ผ่านดีกว่าให้ผ่านแล้วขังคนไว้ในฟอร์ม
    /// **`skippedCheckpoints` = ฐานที่ผู้ใช้กด "ข้ามไปก่อน" หลังส่งพังแบบถาวรในรันนี้**
    ///
    /// คนละความหมายกับ `queuedCheckpoints` โดยสิ้นเชิง แม้ผลกับ gate จะเหมือนกัน: คิวคือคำตอบ
    /// ที่ผู้ใช้ให้ไปแล้วจริงและกำลังรอส่ง ส่วนข้ามคือ server ปฏิเสธคำตอบนั้นซ้ำ ๆ (403/400/500)
    /// จนไม่เหลือทางไปต่อ · จำแค่ในหน่วยความจำเหมือน `eventDismissed` เพราะ server ยังไม่เคย
    /// ได้คำตอบ เปิดแอปใหม่ถามซ้ำคือถูกแล้ว
    ///
    /// **`now` มีไว้ตัดสินความสด** — gate ยึดจอเฉพาะฐานที่เพิ่งเช็คอินภายใน `freshWindow`
    static func decide(progress: CheckinProgress?,
                       queuedCheckpoints: Set<Int>,
                       skippedCheckpoints: Set<Int>,
                       eventDismissed: Bool,
                       now: Date = Date()) -> FeedbackGateState? {
        guard let p = progress else { return nil }
        if let first = p.checkedIn
            .filter({ !$0.answered
                      && !queuedCheckpoints.contains($0.checkpointId)
                      && !skippedCheckpoints.contains($0.checkpointId)
                      && isFresh($0, now: now) })
            .min(by: { $0.at < $1.at }) {
            return .base(first)
        }
        // **ฟอร์มทั้งงานก็ต้องสดเหมือนกัน** — เหตุผลเดียวกับฐาน: ยึดจอได้เพราะ "เพิ่งเดินจบ"
        // ไม่ใช่ "เคยเดินจบเมื่อสามวันก่อน" · ดูเช็คอิน **ล่าสุด** ไม่ใช่เก่าสุด เพราะจังหวะที่
        // ฟอร์มนี้มีไว้ถามคือตอนที่เพิ่งถึงฐานสุดท้าย
        //
        // เคสจริงที่ข้อนี้กัน: บัญชีรีวิวของ App Store เช็คอินไว้ครบ 8 ฐานตั้งแต่ 24 ส.ค. พอ
        // Zero Waste ถูกตัดออกจากการนับ (total 9 → 8) บัญชีนั้นกลายเป็น "เดินครบ" ทันที
        // ผู้ตรวจล็อกอินแล้วจะเจอฟอร์มเต็มจอ = แพทเทิร์นเดียวกับที่โดน 5.1.1(iv) มาแล้วสองรอบ
        let lastCheckin = p.checkedIn.compactMap(\.checkedInAt).max()
        let finishedRecently = lastCheckin.map { now.timeIntervalSince($0) <= freshWindow
                                                 && now.timeIntervalSince($0) >= 0 } ?? false
        if p.complete && finishedRecently && !p.eventFeedbackAnswered && !eventDismissed {
            return .event
        }
        return nil
    }

    /// เช็คอินยังสดพอที่จะยึดจอไหม
    ///
    /// **เหตุผลทั้งหมดที่ยอมให้ฟอร์มนี้ยึดจอคือผู้ใช้ยังยืนอยู่ที่ฐานตรงนั้น** เห็นของที่กำลัง
    /// ให้คะแนนอยู่ตรงหน้า — เช็คอินที่ค้างมาข้ามวันไม่เข้าเงื่อนไขนั้นแล้ว การยกฟอร์มที่ปิดไม่ได้
    /// ขึ้นมาขวางคนที่เพิ่งเปิดแอปวันหลังคือกับดักล้วน ๆ และคำตอบที่ได้ก็เป็น "ความทรงจำของ
    /// ความทรงจำ" ตามที่สเปกยกเหตุผลมาจาก Android เอง · ของเก่ายังตอบได้ทางแจ้งเตือนกับชีต
    /// ที่ปัดปิดได้เหมือนเดิม ไม่ได้หายไปไหน
    ///
    /// **เจอจริงบน production 2026-08-27**: บัญชีรีวิวของ App Store ถูก staff สแกนเข้า 8 ฐาน
    /// ไว้ตั้งแต่ 24 ส.ค. แล้วไม่เคยให้คะแนน ผู้ตรวจล็อกอินจะเจอฟอร์มปิดไม่ได้แปดใบติดกันทันที
    /// = แพทเทิร์นเดียวกับที่โดน Guideline 5.1.1(iv) มาแล้วสองรอบ
    ///
    /// 12 ชั่วโมงเพราะงานเป็นงานวันเดียว: กว้างพอให้คนที่ถูกสแกนตอนเช้าแล้วเปิดแอปตอนเย็นยังเจอ
    /// ฟอร์ม แต่ไม่กว้างจนกินข้ามวัน · `at` parse ไม่ออก = ถือว่าไม่สด ทิศนี้ปลอดภัยกว่าอีกทิศ
    /// ชัดเจน (แย่สุดคือกลับไปใช้ทางเดิมที่ยังเก็บคำตอบได้ ไม่ใช่ขังทุกคนไว้ในฟอร์ม)
    static let freshWindow: TimeInterval = 12 * 60 * 60

    private static func isFresh(_ item: CheckinProgressItem, now: Date) -> Bool {
        guard let at = item.checkedInAt else { return false }
        let age = now.timeIntervalSince(at)
        return age >= 0 && age <= freshWindow
    }
}

extension CheckinProgressItem {
    /// เวลาเช็คอินเป็น `Date` — `at` จาก backend คือ `at.UTC().Format(time.RFC3339)`
    /// (ไม่มีเศษวินาที ลงท้าย Z) · ลองตัวที่มีเศษวินาทีด้วยเผื่อฝั่ง server เปลี่ยนฟอร์แมต
    var checkedInAt: Date? {
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: at) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: at)
    }
}

/// ห่อ `FeedbackGateState` ให้ `.fullScreenCover(item:)` ใช้ได้ (ทรงเดียวกับ `FeedbackTarget`
/// ของ sheet เดิมใน MainTabView) — enum ไม่ conform Identifiable เอง และเติม conformance ให้
/// enum ตรง ๆ ก็ไม่ได้เพราะ `id` ที่ต้องการเป็นคนละความหมายกับตัว state
///
/// **`id` คือหัวใจของตัวห่อนี้ ไม่ใช่พิธีกรรมของ API** — cover ตัวเดียวถูกใช้ซ้ำต่อเนื่อง: ตอบฐาน 1
/// เสร็จ progress รอบใหม่ทำให้ item กลายเป็นฐาน 2 ทันทีโดย cover ไม่ได้ปิดคั่นเลย · id ที่เท่าเดิม
/// แปลว่า SwiftUI ถือว่าเป็น view เดิม @State ข้างใน (rating/comment/sent/sendError) ไม่ถูกรีเซ็ต
/// = คะแนนที่ให้ฐาน 1 ค้างอยู่ในฟอร์มของฐาน 2 (กับดักเดียวกับที่ Android จดไว้ที่ `viewModel(key:)`
/// และเดียวกับที่ `.sheet(item:)` เดิมต้องใส่ `.id(target.id)` กำกับ)
struct FeedbackGateItem: Identifiable, Equatable {
    let state: FeedbackGateState

    var id: String {
        switch state {
        case .base(let item): return "base-\(item.checkpointId)"
        case .event: return "event"
        }
    }

    /// รับผลของ `decide` มาตรง ๆ — nil เข้า nil ออก ผู้เรียกจึงไม่ต้องแตก optional สองชั้นเอง
    init?(state: FeedbackGateState?) {
        guard let state else { return nil }
        self.state = state
    }
}
