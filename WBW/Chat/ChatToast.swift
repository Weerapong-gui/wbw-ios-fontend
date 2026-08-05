import SwiftUI

/// แบนเนอร์ในแอป — เด้งตอนอยู่ในแอปแต่ไม่ได้เปิดจอแชท (แทน banner ของระบบ)
struct ChatToast: View {
    let message: ChatMessage
    let photoUrl: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ProfileAvatar(name: message.senderName, photoUrl: photoUrl, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(message.senderName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.wbwInk)
                    Text(message.body)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
}
