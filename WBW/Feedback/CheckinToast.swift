import SwiftUI

/// แบนเนอร์ในแอปตอนเพิ่งโดนสแกนเช็คอิน
///
/// เด้งของฐานล่าสุดตัวเดียว · ถ้ามีฐานอื่นค้างอยู่ด้วยบอกเป็นจำนวนต่อท้าย ไม่เด้งซ้อนกันหลายอัน
/// (เช็คอิน 3 ฐานตอนออฟไลน์แล้วเน็ตกลับมาพร้อมกันเกิดขึ้นได้จริง)
struct CheckinToast: View {
    let baseName: String
    /// จำนวนฐานที่ *เพิ่ง* กลายเป็นรอประเมินในรอบเดียวกัน นอกเหนือจากฐานที่เด้งอยู่ — ไม่ใช่ฐานที่ยัง
    /// ไม่ตอบทั้งหมด (คนที่ข้ามการให้คะแนนมา 5 ฐานแล้วเพิ่งเช็คอินฐานที่ 6 ต้องเห็น "แตะเพื่อให้คะแนน
    /// ฐานนี้" ไม่ใช่ "ยังมีอีก 5 ฐาน" — ทวงของเก่าที่เขาเลือกจะข้ามอยู่แล้วไม่ได้ช่วยอะไร) ตัวเลขนี้จึง
    /// มาจาก newlyPending.count - 1 ตรงตามเคสที่มันถูกออกแบบมาเพื่อ: เช็คอินตอนออฟไลน์ 3 ฐานติดกัน
    /// แล้วเน็ตกลับมาพร้อมกัน = เด้งอันเดียว บอกว่ายังมีอีก 2
    let remaining: Int
    let onTap: () -> Void

    var body: some View {
        Toast(onTap: onTap) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.wbwGreen)
                .frame(width: 34, height: 34)
        } content: {
            VStack(alignment: .leading, spacing: 1) {
                Text("เช็คอิน \(baseName) แล้ว")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.wbwInk)
                Text(remaining > 0
                     ? "แตะให้คะแนนฐานนี้ · ยังมีอีก \(remaining) ฐานรอประเมิน"
                     : "แตะเพื่อให้คะแนนฐานนี้")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
