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
    static func decide(progress: CheckinProgress?, eventDismissed: Bool) -> FeedbackGateState? {
        guard let p = progress else { return nil }
        if let first = p.checkedIn.filter({ !$0.answered }).min(by: { $0.at < $1.at }) {
            return .base(first)
        }
        if p.complete && !p.eventFeedbackAnswered && !eventDismissed { return .event }
        return nil
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
