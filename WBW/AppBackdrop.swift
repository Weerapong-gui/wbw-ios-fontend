import SwiftUI

/// พื้นหลังกลางของแอป — ภาพป่าเต็มจอ
///
/// แยกเป็นไฟล์เดียวเพราะถูกวาดสองที่ที่ต้องตรงกันเป๊ะ: `RootView` วาดไว้ใต้ทุกอย่าง และ
/// `forestBackground` วาดในกรอบของแต่ละจอ (จำเป็น ดูคอมเมนต์ TabRootOpaqueBackgroundRemover)
/// ถ้าสองที่นี้ใช้คนละภาพหรือคนละวิธีย่อ จะเห็นรอยต่อตรงขอบแท็บทันที
///
/// รูป 1440×2880 (1:2) เลือกไว้ให้อยู่ใกล้กึ่งกลางเรขาคณิตของจอที่กว้างสุด (SE 0.562) กับสูงสุด
/// (Pro Max 0.460) — `scaledToFill` ครอบเต็มแล้วตัดส่วนเกิน ออกแบบตามปลายด้านใดด้านหนึ่ง
/// จะโดนตัด 18% ด้านเดียว แบบนี้หนักสุด ~11% แนวตั้ง หรือ ~8% แนวนอน
struct AppBackdrop: View {
    /// scrim หัว-ท้าย ไม่ใช่คลุมทั้งใบ
    ///
    /// จอที่ใช้พื้นนี้ถูกออกแบบตอนพื้นหลังยังเป็น #0A1610 เข้ม ตัวหนังสือกับไอคอนจึงเป็นสีขาวหมด
    /// (คำทักทายที่ Home, หัวข้อกับกรอบมุมที่ QR) พอเปลี่ยนเป็นภาพป่าที่สว่างมาก ของพวกนั้น
    /// อ่านแทบไม่ออก — ยืนยันจากสกรีนช็อตจริงก่อนใส่ scrim
    ///
    /// คลุมทึบทั้งจอแก้ได้เหมือนกันแต่ภาพวาดจะหมดความหมาย · ไล่เฉพาะหัวกับท้ายซึ่งเป็นที่ที่ UI
    /// อยู่จริง (header ด้านบน, แถบแท็บด้านล่าง) กลางจอปล่อยให้เห็นป่าเต็ม ๆ
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.45), location: 0.00),
                .init(color: .black.opacity(0.00), location: 0.28),
                .init(color: .black.opacity(0.00), location: 0.76),
                .init(color: .black.opacity(0.40), location: 1.00),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    var body: some View {
        Image("bg_ticket")
            .resizable()
            .scaledToFill()
            // frame + clipped ก่อน ignoresSafeArea — scaledToFill ทำให้ภาพล้นกรอบจริง ไม่คลิป
            // แล้วภาพส่วนเกินจะไปดันขนาดของ container แล้วเลย์เอาต์ข้างในเพี้ยนตาม
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()
            .overlay(scrim)
    }
}
