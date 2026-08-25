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
///
/// **และต้องมีทางออกทางเดียวคือปุ่มนั้น** — ตีกลับซ้ำที่ 1.0 (12) เมื่อ 2026-08-25 ข้อเดิม:
/// *"the user can close the message and delay the permission request with the Not now button.
/// The user should always proceed to the permission request after the message."* ·
/// ปุ่ม "ไว้ทีหลัง" ถูกถอดทั้งจากจอและจากชุดคีย์ทั้งสองภาษา (คีย์ของมันห้ามกลับมาแม้ในคอมเมนต์
/// — `PermissionCopyTests` กวาดทั้งไฟล์นี้) · การปัดชีตลง
/// กับการแตะนอกกรอบชีตบน iPad คือ "ไว้ทีหลัง" คนละหน้าตา จึงปิดด้วย
/// `interactiveDismissDisabled` และซ่อนแถบลากที่เป็นคำเชิญให้ปัด
///
/// **จอนี้ไม่ใช่กับดัก** — ปุ่มเดียวที่เหลือปิดจอให้เองทันที และประตู `LocationPrimer.shouldShow`
/// ไม่ปล่อยให้มันกลับมาอีกหลังจากนั้น (ธง `LocationPrimer.asked` คุมเคสเครื่องที่ปิด Location
/// Services ทั้งเครื่อง ซึ่งเป็นทางเดียวที่สถานะไม่ขยับหลังกด)
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
                // จำว่าพาไปถึงกล่องของระบบแล้ว — กันจอนี้กลับมาทับหน้า Home ทุกครั้งที่เปิดแอป
                // บนเครื่องที่ปิด Location Services ทั้งเครื่อง (สถานะค้าง .notDetermined ตลอด
                // เพราะกล่องที่ขึ้นมาคือกล่องชวนไป Settings ไม่ใช่กล่องขอสิทธิ์) · เขียนก่อนเรียก
                // เพราะจอปิดตัวเองทันทีหลังจากนี้
                LocationPrimer.asked = true
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
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.wbwForestVoid)
        // ปิดทางออกที่ไม่ใช่ปุ่ม: ปัดชีตลง (iPhone) กับแตะนอกกรอบชีต (iPad ซึ่งเป็นเครื่องที่
        // ผู้ตรวจรอบ 1.0 (12) ใช้) — ทั้งสองทางคือการเลื่อนกล่องขอสิทธิ์ออกไป ซึ่งใบตีกลับห้ามไว้
        .interactiveDismissDisabled(true)
        // แถบลากคือคำเชิญให้ปัดทิ้ง ปัดไม่ได้แล้วก็ไม่ควรมี — ในสกรีนช็อตของใบตีกลับยังเห็นแถบนี้อยู่
        .presentationDragIndicator(.hidden)
    }
}
