import SwiftUI

/// SU RUN — จอว่างรอฟีเจอร์จริง
///
/// ของเดิมเป็นแดชบอร์ดที่ทุกตัวเลขบนจอมาจาก `SURunMock` (ก้าว/ระยะทาง/เวลา/แคลอรี/อันดับ)
/// บล็อก MAP เป็นสี่เหลี่ยมเขียวเขียนคำว่า MAP และปุ่ม "Start now!" เป็น `Button { }` ที่ไม่ทำอะไร —
/// ยังไม่มี endpoint รองรับทั้งฝั่ง Go และ Node · ปล่อยตัวเลขปลอมไว้บนแอปที่กำลังจะใช้งานจริง
/// เสี่ยงให้คนเข้าใจว่าระบบนับก้าวให้อยู่ จึงเอาออกทั้งหมดจนกว่าของจริงจะมา
///
/// ตั้งใจให้ว่างสนิทไม่มีตัวหนังสือ — ต่างจากแบบแผนที่ `Map3DScreen` ใช้ (โชว์ไอคอน + "แผนที่ 3D
/// ปิดชั่วคราว") ซึ่งเลือกไว้เพื่อไม่ให้จอดูเหมือนพัง · รอบนี้เจ้าของงานสั่งให้ว่างจริง
///
/// ต้องเป็น `.forestBackground(...)` ไม่ใช่ `AppBackdrop()` ตรง ๆ — modifier ตัวนี้พก
/// `TabRootOpaqueBackgroundRemover` มาด้วย ซึ่ง view ที่เป็น root ของแท็บต้องมี ไม่งั้นพื้นทึบขาว
/// ของ per-tab `UIHostingController` จะโผล่เป็นแถบข้าง (เคยเจอจริงที่แท็บ QR ดู
/// docs/forest-3d-off-verification.md)
struct SURunView: View {
    var body: some View {
        Color.clear
            .forestBackground(day: ForestMath.dayStill)
    }
}

#Preview { SURunView() }
