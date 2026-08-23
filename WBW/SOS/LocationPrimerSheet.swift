import SwiftUI

/// จออธิบายที่คั่นก่อนกล่องขอสิทธิ์ตำแหน่งของระบบ
///
/// ประตูว่าจะโชว์เมื่อไหร่อยู่ที่ `LocationPrimer` (เทสได้ครบทุกสาขาที่นั่น) จอนี้ไม่ตัดสินใจเอง
///
/// **ปุ่มบนจอนี้ไม่ได้ให้สิทธิ์เอง** — มันเรียกกล่องของระบบต่ออีกที คนที่กดปุ่มนี้จึงเห็นกล่อง
/// ของ iOS ตามมาทันที ซึ่งเป็นลำดับที่ Apple อยากให้เป็น: แอปอธิบายก่อน ระบบถามทีหลัง
///
/// **คำบนปุ่มต้องเป็นคำกลาง ห้ามเขียนว่า "อนุญาต"** — App Review ตีกลับ 1.0 (11) เมื่อ
/// 2026-08-24 ตาม Guideline 5.1.1(iv) เพราะปุ่มนี้เคยเขียนว่า "อนุญาตตำแหน่ง" / "Allow location"
/// ซึ่งนับเป็นการชี้นำให้ผู้ใช้กดอนุญาต · ใบตีกลับยกคำที่ใช้ได้มาเองว่า "Continue" หรือ "Next"
/// จึงเป็น `action_continue` ตอนนี้ (`WBWTests/PermissionCopyTests` คุมไว้ทั้งสองภาษา)
struct LocationPrimerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.wbwGreen)
                .accessibilityHidden(true)

            Text("location_primer_title")
                .font(.wbwHeadlineSmall)
                .foregroundStyle(Color.wbwOnBackdrop)

            Text("location_primer_body")
                .font(.wbwBodyLarge)
                .foregroundStyle(Color.wbwOnBackdrop)
                .fixedSize(horizontal: false, vertical: true)

            Text("location_primer_why_now")
                .font(.wbwBodySmall)
                .foregroundStyle(Color.wbwOnBackdropMuted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button {
                SOSLocator.shared.requestPermission()
                // ปิดจอทันทีไม่ต้องรอคำตอบ — กล่องของระบบซ้อนขึ้นมาข้างบนอยู่แล้ว และผลลัพธ์
                // ไม่ว่าทางไหนก็ทำให้ `shouldShow` เป็น false ตลอดไป (สถานะเลิกเป็น .notDetermined)
                dismiss()
            } label: {
                Text("action_continue")
                    .font(.wbwTitleMedium)
                    .frame(maxWidth: .infinity)
                    .frame(height: Config.Tap.minTarget)
            }
            .buttonStyle(.borderedProminent)
            // `.borderedProminent` เอาสีจาก accentColor ของระบบ (ฟ้า) ซึ่งไม่ใช่สีของแอปนี้เลย
            // — ทั้งจอเป็นโทนป่าแล้วมีปุ่มฟ้าของ iOS โผล่มาใบเดียว
            .tint(Color.wbwGreen)
            .foregroundStyle(Color.wbwOnGreen)

            Button {
                // ต้องจำว่ากดไว้ทีหลัง — สถานะฝั่งระบบยังเป็น .notDetermined อยู่ ถ้าไม่จำ
                // จอนี้จะเด้งใส่หน้าเดิมทุกครั้งที่เปิดแอป
                LocationPrimer.dismissed = true
                dismiss()
            } label: {
                Text("location_primer_later")
                    .font(.wbwBodyLarge)
                    .frame(maxWidth: .infinity)
                    .frame(height: Config.Tap.minTarget)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.wbwOnBackdropMuted)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.wbwForestVoid)
    }
}
