import SwiftUI

/// ชั้นทับฉาก — ไล่เฉดให้ UI ที่ลอยอยู่อ่านออกทุกช่วงเวลา + เกรน + เครดิตโมเดล
///
/// พอร์ตจาก overlay ใน ~/su-wbw-website/components/ForestScene.tsx
/// เครดิตเป็นข้อบังคับของ CC BY ไม่ใช่ของประดับ ห้ามถอด
struct ForestOverlay: View {
    let day: Float

    private var scrim: LinearGradient {
        // เข้มหัวจอกับท้ายจอ กลางจอโปร่ง — ตรงกลางคือที่ต้นไม้อยู่
        LinearGradient(
            stops: [
                .init(color: Color(red: 10/255, green: 22/255, blue: 16/255).opacity(0.72), location: 0.00),
                .init(color: Color(red: 10/255, green: 22/255, blue: 16/255).opacity(0.15), location: 0.22),
                .init(color: Color(red: 10/255, green: 22/255, blue: 16/255).opacity(0.20), location: 0.62),
                .init(color: Color(red: 10/255, green: 22/255, blue: 16/255).opacity(0.75), location: 1.00),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            scrim.ignoresSafeArea()

            // เกรนฟิล์มบางๆ — กันไล่เฉดเป็นแถบ (banding) บนฟ้าเรียบๆ
            Rectangle()
                .fill(.white)
                .opacity(0.025)
                .blendMode(.overlay)
                .ignoresSafeArea()

            // padding-bottom ตามบรีฟ (3pt) เทียบกับขอบ safe area ไม่ใช่ขอบจอจริง — สกรีนช็อตจริง
            // บน Home (จอเดียวที่ผูกฉากอยู่ตอนนี้) เห็นเครดิตไปตกซ้อนอยู่หลังแท็บบาร์ลอยของ
            // MainTabView พอดี (เริ่มจาก leading ใกล้ตำแหน่งเดียวกัน) เหลือแค่ "โม" โผล่มา อ่านไม่ออก
            // ลองเพิ่ม .ignoresSafeArea() ที่ Text นี้แล้วก็ไม่ช่วย (วัดพิกเซลจริงแล้วตำแหน่งไม่ขยับ
            // เลยไม่ว่าจะปรับ padding-bottom เป็นบวกน้อยๆ หรือลบลึกแค่ไหนก็ตาม — เหมือนมี floor คง
            // ที่ค้างอยู่ ต้นตอน่าจะเกี่ยวกับ additionalSafeAreaInsets ที่ TabView ยัดเข้าไปทั้งวินโดว์
            // (อาการคนละแบบ แต่อาจเป็นต้นตอเดียวกันกับที่ TabRootOpaqueBackgroundRemover ใน
            // ForestSceneHost.swift เคยเจอมาก่อน — ยืนยันแล้วว่า MainTabView แทรกผลข้างเคียงข้าม
            // ZStack sibling ได้จริง ไม่ใช่แค่เรื่อง opaque background)
            // ทางที่ยืนยันด้วยสกรีนช็อตแล้วว่าใช้ได้จริง: ดันเครดิตขึ้นไปอยู่เหนือแท็บบาร์แทน (ช่องว่าง
            // เปิดโล่งระหว่างพุ่มหญ้ากับแท็บบาร์) ด้วย padding-bottom 55pt แทน 3pt เดิม
            Text("โมเดล 3 มิติ: ดู WBW/Resources/models/CREDITS.md · CC BY")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.40))
                .padding(.leading, 16)
                .padding(.bottom, 55)
        }
        .allowsHitTesting(false)
    }
}
