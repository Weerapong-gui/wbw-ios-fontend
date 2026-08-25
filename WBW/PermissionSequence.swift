import Foundation
import UserNotifications

/// ลำดับกล่องขอสิทธิ์หลังล็อกอิน — **กล่องของระบบสองใบต้องไม่ซ้อนกัน**
///
/// การขอสิทธิ์แจ้งเตือนเคยอยู่ใน `AppDelegate.didFinishLaunchingWithOptions` กล่องจึงเด้งใส่
/// คนที่ยังไม่ได้ล็อกอิน บนจอ splash ที่ไม่มีอะไรอธิบายว่าแอปนี้คืออะไรด้วยซ้ำ — รูปแบบเดียวกับ
/// ที่ `LocationPrimer` ถูกสร้างขึ้นมาแก้ (Guideline 5.1.1: ขอพร้อมบริบท) · ย้ายมาขอหลังล็อกอิน
/// สำเร็จแทน โดย **ไม่เพิ่มจออธิบายใหม่** เพราะจอแบบนั้นคือสิ่งที่เพิ่งโดน 5.1.1(iv) มาสองรอบ
///
/// พอทั้งสองอย่างมาอยู่หลังล็อกอินด้วยกัน จังหวะจึงชนกัน: `MainTabView` หน่วง 1 วิแล้วเปิด
/// `LocationPrimerSheet` ส่วนกล่องแจ้งเตือนของระบบเด้งทันทีที่ `save(_:)` จบ — ปล่อยไว้จะได้
/// กล่องของระบบทับชีตอธิบายที่เพิ่งแก้ไปตาม 5.1.1(iv) พอดี ซึ่งเท่ากับจออธิบายไม่ได้อธิบายอะไรเลย
enum PermissionSequence {

    /// เปิดจออธิบายตำแหน่งได้หรือยัง — ยังไม่ตอบกล่องแจ้งเตือน = ยังไม่เปิด
    static func mayShowLocationPrimer(pushAuthorization: UNAuthorizationStatus) -> Bool {
        pushAuthorization != .notDetermined
    }

    /// เพดานรอ — เครื่องที่ push ถูกปิดทั้งเครื่องหรือ Firebase โหลดไม่ขึ้นจะไม่มีกล่องให้ตอบเลย
    /// ปล่อยให้รอไม่จำกัดแปลว่าจออธิบายตำแหน่งไม่มีวันโผล่บนเครื่องพวกนั้น
    static let maxWaitForPushAnswer: Duration = .seconds(5)

    /// สถานะปัจจุบันของสิทธิ์แจ้งเตือน — ห่อ API ของระบบไว้ที่เดียวเพื่อให้จอเรียกสั้น ๆ
    static func pushAuthorization() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
