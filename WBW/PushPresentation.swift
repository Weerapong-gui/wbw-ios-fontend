import Foundation

/// สิ่งที่แอปทำกับ push ที่มาถึง **ตอนแอปเปิดอยู่** (foreground)
///
/// ตรรกะนี้เคยฝังอยู่ใน `AppDelegate.userNotificationCenter(_:willPresent:)` ทั้งก้อน ซึ่งเรียก
/// จากเทสไม่ได้เลยเพราะต้องมี `UNNotification` จริง (สร้างเองไม่ได้) — ย้ายออกมาเป็นฟังก์ชัน
/// บริสุทธิ์ตอนต่อสวิตช์ "แจ้งเตือนแชท" ในหน้าตั้งค่าให้ทำงานจริงตาม Guideline 2.1
///
/// เจตนาเดิมของแต่ละสาขาไม่เปลี่ยน: แชทกับความเห็นต่อฐานมี "ของแทน" ในแอปอยู่แล้ว
/// (ChatToast / การรีเฟรชรายการ) จึงไม่ขึ้น banner ของระบบซ้ำ · เคส SOS ของเพื่อนตัดสินจาก
/// `sos_id` ที่อ่านได้จริง ไม่ใช่ `type == "sos"` เฉย ๆ — payload ที่พังกลางทางต้องได้ banner
/// ของระบบตามเดิม ดีกว่าเงียบหายไปโดยไม่มีอะไรแทนที่
enum PushPresentation {

    struct Decision: Equatable {
        /// ปล่อยให้ระบบขึ้น banner/เสียง/badge ตามปกติไหม
        let showsSystemBanner: Bool
        /// สัญญาณที่ต้องโพสต์ให้จอในแอปรับไปทำต่อ (nil = ไม่มี)
        let signal: Notification.Name?
    }

    static func foreground(type: String?, sosId: Int64?) -> Decision {
        switch type {
        case "chat":
            return Decision(showsSystemBanner: false, signal: nil)
        case "checkin_feedback":
            return Decision(showsSystemBanner: false, signal: .checkinFeedbackArrived)
        default:
            guard sosId != nil else { return Decision(showsSystemBanner: true, signal: nil) }
            return Decision(showsSystemBanner: false, signal: .sosArrived)
        }
    }
}
