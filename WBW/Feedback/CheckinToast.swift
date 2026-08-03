import SwiftUI

/// แบนเนอร์ในแอปตอนเพิ่งโดนสแกนเช็คอิน
///
/// เด้งของฐานล่าสุดตัวเดียว · ถ้ามีฐานอื่นค้างอยู่ด้วยบอกเป็นจำนวนต่อท้าย ไม่เด้งซ้อนกันหลายอัน
/// (เช็คอิน 3 ฐานตอนออฟไลน์แล้วเน็ตกลับมาพร้อมกันเกิดขึ้นได้จริง)
struct CheckinToast: View {
    let baseName: String
    /// จำนวนฐานที่ยังไม่ตอบ *นอกเหนือจาก* ฐานที่เด้งอยู่
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
