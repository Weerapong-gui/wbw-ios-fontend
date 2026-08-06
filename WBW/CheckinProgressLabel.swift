import Foundation

/// ข้อความความคืบหน้าเช็คอินบน Home — ของแทนชั่วคราวของต้นไม้ในฉากป่า 3D ที่ถูกปิดไว้
/// (Config.forest3D) เปิดฉากกลับเมื่อไหร่ ต้นไม้ทำหน้าที่นี้แทน แล้วข้อความนี้ซ่อนตัวเอง
enum CheckinProgressLabel {
    /// nil = ยังไม่มีข้อมูล (total 0) → ไม่ต้องโชว์อะไรเลย
    static func text(stage: Int, total: Int) -> String? {
        guard total > 0 else { return nil }
        return "เช็คอินแล้ว \(stage)/\(total) ฐาน"
    }
}
