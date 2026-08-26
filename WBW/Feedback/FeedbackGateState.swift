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
