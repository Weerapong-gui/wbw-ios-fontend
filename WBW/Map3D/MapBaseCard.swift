import SwiftUI

/// การ์ดฐาน — ชื่อ/กิจกรรม/สถานะเช็คอิน · **ใบเดียวกันทั้งแผนที่ 3 มิติและ 2 มิติ**
///
/// แยกออกมาจาก `Map3DScreen` ตอนเพิ่มโหมด 2 มิติ (2026-08-24) เพราะสองโหมดต้องพูดเรื่องฐาน
/// ด้วยคำเดียวกัน — การ์ดคนละใบที่หน้าตาบังเอิญเหมือนกันจะเริ่มต่างกันตอนใครสักคนแก้ใบเดียว
///
/// ชื่อกับกิจกรรมมาจาก `GET /wbw/checkpoints` จึงมีครบทุกฐานตั้งแต่ยังไม่ได้เดิน (เดิมมีเฉพาะ
/// ฐานที่เช็คอินแล้ว เพราะ `/me/progress` คืนแค่ `checked_in`) · **ห้ามเดาชื่อ** ยังเป็นกติกา —
/// ไม่มีข้อมูลก็ขึ้น "ฐานที่ N" ไม่ใช่เดาเอาเอง · สถานะเช็คอินยังมาจาก progress เหมือนเดิม
/// เพราะเป็นเรื่องของผู้ใช้คนนี้ ไม่ใช่ข้อมูลของงาน
struct MapBaseCard: View {
    let sequence: Int
    let onClose: () -> Void

    @EnvironmentObject private var progress: CheckinProgressStore
    @EnvironmentObject private var checkpoints: CheckpointStore

    var body: some View {
        let checkedIn = progress.progress?.checkedIn ?? []
        let visited = checkedIn.first { $0.sequence == sequence }
        let known = checkpoints.checkpoints
        return VStack {
            Spacer()
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Map3DPins.label(sequence: sequence, checkedIn: checkedIn,
                                         checkpoints: known))
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let activity = Map3DPins.activity(sequence: sequence, checkedIn: checkedIn,
                                                         checkpoints: known) {
                        Text(activity)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Label(visited == nil ? "map_not_checked_in" : "profile_checked_in",
                          systemImage: visited == nil ? "circle.dashed" : "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(visited == nil ? .white.opacity(0.7) : Color.wbwGold)
                }
                Spacer(minLength: 0)
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.8))
                        // ไอคอน 22pt ลอยอยู่บนแผนที่ที่ลากได้ — พลาดแล้วกลายเป็นการลากแผนที่แทน
                        // ไม่ใช่แค่ "ไม่มีอะไรเกิดขึ้น"
                        .frame(width: Config.Tap.minTarget, height: Config.Tap.minTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("action_close")
            }
            .padding(20)
            // แผ่นเข้ม ไม่ใช่กระจกใส — การ์ดนี้ลอยอยู่บน **แผนที่ดาวเทียม** ไม่ใช่บนพื้นภาพป่า
            // ถ่ายจริงตอนหมุดอยู่แถวตัวเมืองแล้วชื่อฐานกับสถานะหายไปในตึกสีขาว · นี่คือเคสที่
            // ต้นทางเขียนถึงตรง ๆ ที่ `GlassPanel`: ปัญหาคือความแปรปรวนของพื้น ไม่ใช่ระดับ
            // ฝ้าจางจึงแก้ไม่ได้ แผ่นต้องกลบอาร์ตทิ้ง
            .glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous),
                          tint: Color.glassPanel)
            .padding(.horizontal, 20)
            .tabBarClearance()
            .contentColumn(.card)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
