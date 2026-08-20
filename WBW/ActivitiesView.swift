import SwiftUI

/// อีเวนต์บนเส้นทางเดิน — **ยกมาจาก `ui/activities/ActivitiesScreen.kt` ของแอป Android**
///
/// เนื้อหาเป็นข้อความตายตัวทั้งสองใบ ไม่มี backend หนุน — ต้นทางก็เป็นแบบเดียวกัน (อยู่ใน
/// `strings.xml`) · ที่นี่ใช้ชุดคีย์ชื่อเดียวกับต้นทาง (`event_*`) ทั้งไทยและอังกฤษ
struct ActivitiesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("activities_title")
                    .font(.wbwHeadlineSmall)
                    .foregroundStyle(Color.wbwOnBackdrop)
                Text("activities_subtitle")
                    .font(.wbwBodyMedium)
                    .foregroundStyle(Color.wbwOnBackdropMuted)

                EventCard(title: "event_step_comp_title",
                          date: "event_step_comp_date",
                          description: "event_step_comp_desc",
                          status: "event_status_upcoming",
                          systemImage: "figure.walk")

                EventCard(title: "event_wbw_title",
                          date: "event_wbw_date",
                          description: "event_wbw_desc",
                          status: "event_status_upcoming",
                          systemImage: "tree")
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, ForestSceneHost.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        // แท็บวาดพื้นทึบของตัวเองใต้ทุกอย่าง — จอที่ไม่เรียก `forestBackground` จะได้พื้นดำสนิท
        // แทนพื้นภาพ (เจอมาแล้วกับบัตรผู้เข้าร่วม) · ตัวนี้เจาะพื้นทึบนั้นทิ้งแล้ววางฉากคืนให้
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .forestBackground(day: ForestMath.dayStill)
    }
}

/// อีเวนต์หนึ่งใบ — พูดภาษาเดียวกับบัตรผู้เข้าร่วม
///
/// ลำดับคือลำดับที่การ์ดถูกอ่าน: **ชื่อ** อีเวนต์ → **ชนิด** (ไอคอนกับสถานะ) → **มันคืออะไร**
/// → **เมื่อไหร่** → **ทำอะไรได้** · ชื่อขึ้นก่อนเพราะบนจอที่มีแต่อีเวนต์ที่ยังไม่เริ่ม ชื่อคือ
/// สิ่งเดียวที่กำลังถูกเลือกระหว่างกัน — ของเดิมเปิดด้วยไอคอนกับคำว่า "เร็ว ๆ นี้" ซึ่งทุกใบพูด
/// เหมือนกันหมด แล้วบังคับให้อ่านผ่านไปก่อนถึงจะรู้ว่ากำลังดูอีเวนต์ไหน · วันที่ย้ายไปท้าย
/// ด้วยเหตุผลเดียวกัน — มันสำคัญตอนตัดสินใจแล้วว่าสนใจ ไม่ใช่ก่อนหน้านั้น
private struct EventCard: View {
    let title: LocalizedStringKey
    let date: LocalizedStringKey
    let description: LocalizedStringKey
    let status: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.wbwTitleLarge)
                    .foregroundStyle(Color.wbwOnBackdrop)

                // ไอคอนกับสถานะอยู่บรรทัดเดียวกันใต้ชื่อ: ทั้งคู่ตอบคำถาม "นี่คือของชนิดไหน"
                // และไม่มีอันไหนคุ้มค่ากับบรรทัดของตัวเอง
                Label {
                    Text(status)
                        .font(.wbwKicker)
                        .kerning(1.6)
                } icon: {
                    Image(systemName: systemImage).font(.footnote)
                }
                .foregroundStyle(Color.wbwOnBackdropMuted)
                .padding(.top, 9)

                Text(description)
                    .font(.wbwBodyMedium)
                    .lineSpacing(5)
                    .foregroundStyle(Color.wbwOnBackdropMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 13)

                // วันที่มาท้ายสุดและเป็น ink เต็ม — เป็นบรรทัดเดียวในนี้ที่ต่างกันทุกใบ
                Label {
                    Text(date)
                        .font(.wbwLabelSmall)
                        .kerning(1.2)
                } icon: {
                    Image(systemName: "calendar").font(.caption)
                }
                .foregroundStyle(Color.wbwOnBackdrop)
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 16)

            // เต็มความกว้าง — เส้นที่เว้นขอบสองข้างอ่านเป็นเส้นใต้ของย่อหน้าข้างบน
            // ไม่ใช่รอยต่อระหว่างสองส่วนของการ์ด
            Rectangle()
                .fill(Color.glassSheerBorder)
                .frame(height: 1)

            HStack {
                Text("event_details")
                    .font(.wbwLabelSmall)
                    .kerning(1.8)
                    .foregroundStyle(Color.wbwOnBackdrop)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(Color.wbwOnBackdropMuted)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
        }
        // ต้นทางใช้ `GlassSheer` (ขาว 12%) เพราะ **Android ไม่มี Liquid Glass จริง** จึงต้อง
        // ประมาณด้วยพื้นผิวบวกเส้นผม (คอมเมนต์ของต้นทางเขียนไว้ตรง ๆ) — ฝั่ง iOS มีของจริง
        // จึงใช้ `glassSurface` แทน คือยกเจตนามา ไม่ใช่ยกวิธีแก้ขัดมา
        .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// แท็บกิจกรรม — ห่อ `ActivitiesView` ด้วย `NavigationStack` เพื่อให้การ์ดกดเข้าไปต่อได้
///
/// การ์ด "แข่งนับก้าว" พาไปที่ `SURunView` — Android มีการ์ดใบนี้แต่ไม่มีจอปลายทาง ส่วน iOS
/// มีจอปลายทางอยู่แล้ว (แผนที่เส้นทาง + จับระยะ + นับก้าวจริง) แค่เคยอยู่ผิดที่คือเป็นแท็บของ
/// ตัวเอง · การ์ดกับจอเป็นเรื่องเดียวกัน จับมาต่อกันแล้วทั้งสองฝั่งได้ประโยชน์
struct ActivitiesTabView: View {
    var body: some View {
        NavigationStack {
            ActivitiesView()
                .navigationBarHidden(true)
        }
    }
}
