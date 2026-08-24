import SwiftUI

/// กล่องยืนยันออกจากกลุ่ม — วาดเอง ไม่ใช่ `.alert` ของระบบ
///
/// **ทำไมต้องวาดเอง:** `.alert` ของ SwiftUI รับได้แค่ `Button` กับ `Text` ใส่ `Image` ไม่ได้เลย
/// จอนี้ต้องโชว์หัวใจบอกสิทธิ์คงเหลือ จึงไม่มีทางใช้ alert ต่อได้
///
/// **ข้อความไม่ได้เขียนใหม่** — ใช้ `GroupQuotaText` ตัวเดิมทั้งสองประโยค ซึ่งถูกตรึงด้วย
/// `GroupQuotaTextTests` อยู่แล้ว และคอมเมนต์ในไฟล์นั้นอธิบายไว้ว่าทำไมเคส `quota = 0` กับ
/// `quota = 1` ต้องเป็นคนละประโยค · หัวใจเป็นของ **เพิ่ม** ไม่ใช่ของแทน
///
/// สิ่งที่ `.alert` เคยให้ฟรีแล้วต้องทำเองตรงนี้: `.isModal` ให้ VoiceOver ไม่หลุดออกไปอ่านจอ
/// ข้างหลัง และ scrim ที่กดแล้วปิดเท่ากับกดยกเลิก
struct LeaveGroupDialog: View {
    let groupNumber: Int
    /// สิทธิ์ **ก่อน** ออก — ตัวข้อความคำนวณผลหลังออกให้เอง (ดูคอมเมนต์หัว `GroupQuotaText`)
    let quota: Int
    var busy: Bool = false
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }
                .accessibilityHidden(true)

            VStack(spacing: 14) {
                QuotaHeartsRow(quota: quota, size: 26)
                    .padding(.top, 4)

                Text(GroupQuotaText.remaining(quota: quota))
                    .font(.wbwText(13, relativeTo: .footnote))
                    .foregroundStyle(.secondary)

                Text(String(format: Loc.t("group_leave_confirm"), groupNumber))
                    .font(.wbwText(18, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(Color.wbwInk)

                Text(GroupQuotaText.leaveWarning(groupNumber: groupNumber, quota: quota))
                    .font(.wbwText(14, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("group_pick_cancel")
                            .font(.wbwText(16, weight: .semibold, relativeTo: .callout))
                            .foregroundStyle(Color.wbwInk)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Color.wbwLine, in: Capsule())
                    }
                    Button(action: onConfirm) {
                        Group {
                            if busy {
                                ProgressView().tint(.white)
                            } else {
                                Text("group_leave")
                                    .font(.wbwText(16, weight: .semibold, relativeTo: .callout))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(Color.red, in: Capsule())
                    }
                    .disabled(busy)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: 320)
            .background(Color.wbwSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            .padding(.horizontal, 28)
            // ดัก VoiceOver ไว้ในกล่อง — ของที่ `.alert` ทำให้เองแล้วหายไปตอนวาดเอง
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }
}

#Preview("เหลือ 1 ครั้ง") {
    ZStack {
        Color.wbwBg.ignoresSafeArea()
        LeaveGroupDialog(groupNumber: 7, quota: 1, onCancel: {}, onConfirm: {})
    }
}

#Preview("เหลือ 3 ครั้ง") {
    ZStack {
        Color.wbwBg.ignoresSafeArea()
        LeaveGroupDialog(groupNumber: 12, quota: 3, onCancel: {}, onConfirm: {})
    }
}
