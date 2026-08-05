import SwiftUI

/// เปลือก toast กลาง — ปุ่มเต็มแถบ, ช่องไอคอนนำ + เนื้อหา, พื้นหลังเบลอ, มุมโค้ง, เงา
/// แยกออกมาจาก ChatToast ตอนเพิ่มแบนเนอร์เช็คอิน (ดู Chat/ChatToast.swift, Feedback/CheckinToast.swift) —
/// ค่าที่เห็นผล (spacing/padding/background/cornerRadius/shadow) ยกมาจาก ChatToast เดิมตรงๆ ไม่มีแก้
struct Toast<Leading: View, Content: View>: View {
    let onTap: () -> Void
    let leading: Leading
    let content: Content

    init(onTap: @escaping () -> Void,
         @ViewBuilder leading: () -> Leading,
         @ViewBuilder content: () -> Content) {
        self.onTap = onTap
        self.leading = leading()
        self.content = content()
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                leading
                content
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
