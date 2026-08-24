import Foundation

/// ตัวเลขชุดเดียวที่จอนับก้าวอ่าน — ยกทรงมาจาก `WalkStats` ใน `walk/WalkTracker.kt` ของ Android
///
/// เป็น struct ไม่ใช่ property หลายตัวบน tracker เพราะสามค่านี้ต้องเปลี่ยนพร้อมกันเสมอ:
/// จอที่วาดระยะรอบใหม่คู่กับเพซรอบเก่าอ่านเป็นตัวเลขที่ขัดกันเอง
struct WalkStats: Equatable {
    var active = false
    var distanceMetres: Double = 0

    /// **nil ไม่ใช่ 0** — "เดินอยู่แต่ยังไม่ได้ก้าวสักก้าว" กับ "เครื่องนี้นับก้าวให้ไม่ได้"
    /// เป็นคนละเรื่องที่ผู้ใช้ต้องแยกออก · nil = จอโชว์ `—` ส่วน 0 = จอโชว์เลขศูนย์
    ///
    /// เกิด nil ได้สองทาง: ผู้ใช้ไม่ให้สิทธิ์ Motion & Fitness หรือเครื่องไม่มีเซ็นเซอร์นับก้าว
    /// (simulator ทุกตัวเข้าข่ายนี้ — `CMPedometer.isStepCountingAvailable()` คืน false)
    /// · Android แยกสองกรณีนี้ด้วยเหตุผลเดียวกันเป๊ะที่ `WalkTracker.kt`
    var steps: Int?

    var speedMps: Double = 0

    /// มีอะไรให้โชว์ไหม — ใช้ตัดสินว่า HUD ควรโผล่หรือยัง
    ///
    /// ไม่ใช่แค่ `active` เพราะกด "หยุด" แล้วตัวเลขต้องค้างให้อ่านต่อ ไม่ใช่หายไปทันที
    var hasData: Bool { active || distanceMetres > 0 || steps != nil }
}
