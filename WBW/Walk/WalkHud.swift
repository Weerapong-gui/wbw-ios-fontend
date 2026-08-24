import SwiftUI

/// แถบตัวเลขสามช่องตอนกำลังเดิน — ระยะ / ก้าว / เพซ
///
/// ยกจาก `WalkHud` ใน `ui/map/MapScreen.kt` ของ Android: กระจกใบเดียว สามคอลัมน์กว้างเท่ากัน
/// ป้ายตัวเล็กถ่างตัวอักษรอยู่บน ตัวเลขอยู่ล่าง · เรียงตามลำดับที่คนอ่าน — ระยะคือคำตอบของ
/// "ไปได้ไกลแค่ไหนแล้ว" ซึ่งเป็นคำถามหลัก ส่วนก้าวกับเพซเป็นของแถม
///
/// **ใช้ `Font.wbw*` ไม่ใช่ `.system(size:)`** — จอแผนที่ทั้งจอยังไม่ใช้ token ของแอปเลยสักจุด
/// (ของเดิมเป็น `.title3`/`.subheadline` ล้วน) ของใหม่ไม่ควรก่อหนี้เพิ่ม และ token พวกนี้
/// ผูก `relativeTo:` ไว้แล้วจึงยืดตามขนาดตัวอักษรของเครื่อง
struct WalkHud: View {
    let stats: WalkStats

    var body: some View {
        HStack(spacing: 0) {
            cell(Loc.t("walk_stat_distance"), WalkMath.distanceText(stats.distanceMetres))
            cell(Loc.t("walk_stat_steps"), WalkMath.stepsText(stats.steps))
            cell(Loc.t("walk_stat_pace"), WalkMath.paceText(speedMps: stats.speedMps))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// สามช่องกว้างเท่ากันด้วย `maxWidth: .infinity` ไม่ใช่ `Spacer()` คั่น — ตัวเลขยาวไม่เท่ากัน
    /// ("8 ม." กับ "12.34 กม.") ถ้าปล่อยให้กว้างตามเนื้อหา เส้นแบ่งจะขยับทุกครั้งที่ตัวเลขเปลี่ยนหลัก
    private func cell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.wbwKicker)
                .kerning(1.8)
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.wbwNumeral(17, relativeTo: .body))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
