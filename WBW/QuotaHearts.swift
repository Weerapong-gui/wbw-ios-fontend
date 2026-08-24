import SwiftUI

/// สิทธิ์ออกจากกลุ่มคงเหลือ วาดเป็นหัวใจ — ตรรกะแยกจาก view ให้เทสจับได้
///
/// ทำไมไม่ใช่ `ForEach(0..<quota)` ตรง ๆ: สองเคสขอบพังเงียบ ๆ ทั้งคู่
///   - `quota = 0` ได้แถวว่าง ซึ่งบนจอจริงอ่านเหมือนโหลดไม่ขึ้น ไม่ใช่ "สิทธิ์หมดแล้ว"
///   - `quota` เยอะ ๆ เกิดได้จริง — admin เติมสิทธิ์รายคนได้ (`quota_adjust` ใน migration
///     `000016_group_leave_quota`) ไม่มีเพดานกันไว้ทั้งใน DB และใน API · เรียงกันไปเรื่อย ๆ
///     จะล้นบรรทัดบนจอแคบ
enum QuotaHearts {
    /// วาดเป็นดวงได้มากสุดกี่ดวงก่อนสลับไปใช้ตัวเลข — เท่านี้ยังนับด้วยตาได้ในแวบเดียว
    static let maxDrawn = 5

    enum Layout: Equatable {
        /// สิทธิ์หมด — วาดหัวใจจางหนึ่งดวง ไม่ใช่ไม่วาดอะไรเลย
        case none
        case hearts(Int)
        /// `♥ ×N` สำหรับค่าที่เยอะเกินจะเรียง
        case counted(Int)
    }

    static func layout(quota: Int) -> Layout {
        guard quota > 0 else { return .none }
        return quota <= maxDrawn ? .hearts(quota) : .counted(quota)
    }
}

/// แถวหัวใจ · ใช้ทั้งบนการ์ด "กลุ่มของฉัน" และในกล่องยืนยันออกจากกลุ่ม
///
/// สีทองไม่ใช่แดง — แดงบนจอนี้จองไว้ให้ปุ่มออกจากกลุ่มซึ่งเป็นการกระทำที่ย้อนไม่ได้ ถ้าหัวใจแดงด้วย
/// สองอย่างจะอ่านเป็นระดับความอันตรายเดียวกัน ทั้งที่อันหนึ่งคือของที่ถืออยู่ อีกอันคือการใช้มันทิ้ง
struct QuotaHeartsRow: View {
    let quota: Int
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: 6) {
            switch QuotaHearts.layout(quota: quota) {
            case .none:
                Image(systemName: "heart")
                    .foregroundStyle(Color.wbwMuted)
            case let .hearts(n):
                ForEach(0..<n, id: \.self) { _ in
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Color.wbwGold)
                }
            case let .counted(n):
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color.wbwGold)
                Text("×\(n)")
                    .font(.wbwText(size * 0.8, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(Color.wbwGold)
                    .monospacedDigit()
            }
        }
        .font(.system(size: size))
        // อ่านออกเสียงเป็นประโยคเดียว ไม่ใช่ "หัวใจ หัวใจ หัวใจ" — VoiceOver ต้องได้ความหมาย
        // เดียวกับที่ตาเห็น ซึ่งคือจำนวนครั้งที่ยังออกจากกลุ่มได้
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GroupQuotaText.remaining(quota: max(quota, 0)))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 14) {
        ForEach([0, 1, 3, 5, 7], id: \.self) { q in
            HStack(spacing: 12) {
                QuotaHeartsRow(quota: q)
                Text(GroupQuotaText.remaining(quota: q))
                    .font(.wbwText(13, relativeTo: .footnote)).foregroundStyle(.secondary)
            }
        }
    }
    .padding(24)
    .background(Color.wbwSurface)
}
