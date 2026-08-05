import SwiftUI

/// แบนเนอร์ในแอป — เด้งตอนอยู่ในแอปแต่ไม่ได้เปิดจอแชท (แทน banner ของระบบ)
/// เปลือก (ปุ่ม/พื้นหลัง/เงา) อยู่ใน Toast.swift ร่วมกับ CheckinToast — ที่นี่ใส่แค่รูป+ข้อความของแชท
struct ChatToast: View {
    let message: ChatMessage
    let photoUrl: String?
    let onTap: () -> Void

    var body: some View {
        Toast(onTap: onTap) {
            ProfileAvatar(name: message.senderName, photoUrl: photoUrl, size: 34)
        } content: {
            VStack(alignment: .leading, spacing: 1) {
                Text(message.senderName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.wbwInk)
                Text(message.body)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
