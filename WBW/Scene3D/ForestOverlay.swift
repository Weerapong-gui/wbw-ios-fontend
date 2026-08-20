import SwiftUI

/// ชั้นทับฉาก — ไล่เฉดให้ UI ที่ลอยอยู่อ่านออกทุกช่วงเวลา + เกรน + เครดิตโมเดล
///
/// พอร์ตจาก overlay ใน ~/su-wbw-website/components/ForestScene.tsx
/// เครดิตเป็นข้อบังคับของ CC BY ไม่ใช่ของประดับ ห้ามถอด
struct ForestOverlay: View {
    let day: Float
    /// ระยะขั้นต่ำจากขอบจอล่างจริงของหน้าปัจจุบัน (มาจาก host.bottomClearance) — ดูคอมเมนต์ที่
    /// ตำแหน่งเครดิตด้านล่างว่าเทียบกับ safe area สดของเครื่องยังไง (max ไม่ใช่บวก)
    let bottomClearance: CGFloat

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
        // GeometryReader ต้อง *ไม่* .ignoresSafeArea() ตัวมันเอง — ลองมาแล้วว่าถ้าใส่ geo.safeAreaInsets
        // จะรายงาน 0 เสมอทั้งสองเครื่อง (วัดจริงด้วย diagnostic text ก่อนแก้บรรทัดนี้) เพราะความหมายของ
        // ignoresSafeArea คือ "มองว่าตรงนี้ไม่มี safe area เลย" ทั้งเรื่อง layout และเรื่องค่าที่รายงาน
        // ให้ลูกๆ ต่อ ไม่ใช่แค่ "ขยาย frame แล้วยังบอกขนาด safe area จริงได้อยู่" — ต้องปล่อยให้ reader
        // เคารพ safe area แบบปริยาย (frame ที่ได้จาก root อยู่แล้วเต็มจอ เพราะไม่มี parent ไหนใน
        // RootView ที่ห่อ ignoresSafeArea) geo ถึงจะรายงานค่าจริงออกมา ส่วน scrim/เกรนที่ต้องเต็มจอจริงๆ
        // ก็ใส่ .ignoresSafeArea() แยกทีละชั้นเหมือนเดิม (ไม่เกี่ยวกับ geo)
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                scrim.ignoresSafeArea()

                // เกรนฟิล์มบางๆ — กันไล่เฉดเป็นแถบ (banding) บนฟ้าเรียบๆ
                Rectangle()
                    .fill(.white)
                    .opacity(0.025)
                    .blendMode(.overlay)
                    .ignoresSafeArea()

                // ตำแหน่งเครดิต = max(safe area ขอบล่างที่อ่านสดจาก geo, bottomClearance จาก host)
                // ไม่ใช่บวกกัน — วัดจริงด้วยสกรีนช็อตหลายค่าถึงเจอว่าขอบบนแท็บบาร์ลอยของ MainTabView
                // อยู่ห่างจากขอบจอล่างจริง "เท่ากันเป๊ะ" ทั้ง iPhone 17 (safe area ล่าง 34pt) และ
                // iPhone SE รุ่น 3 (safe area ล่าง 0pt เพราะไม่มี home indicator) คือ 82pt พอดีทั้งคู่ —
                // แท็บบาร์ไม่ได้ยึดตาม safe area ของเครื่อง เป็นระยะคงที่จากขอบจอเสมอ ลองสูตรบวก
                // (safe area + ค่าคงที่) มาก่อนแล้วพัง: ปรับให้ iPhone SE พ้นแท็บบาร์ได้ (0+89=89) กลับ
                // ดันเครดิตบน iPhone 17 สูงเกินจนไปซ้อนมือ/ลำตัวมาสคอต DinDin ของ HomeView แทน
                // (34+89=123 — มาสคอตเป็นเรื่องชั่วคราวที่ Task 9 จะถอดทิ้ง แต่ระหว่างนี้ไม่ควรให้แย่ลง)
                // ค่ากลางๆ (safe area + 72) ก็ยังพังทั้งคู่พร้อมกัน (106 ชนมาสคอตบน 17, 72 ยังไม่พ้น
                // แท็บบาร์บน SE) ยืนยันว่าบวกกันใช้ไม่ได้จริง ส่วน max() ให้ผลตรงกับที่วัดได้: ทั้งสอง
                // เครื่องต้องการ "ระยะจากขอบจอจริง" เท่ากัน (89, มีกันชนเหนือ 82pt ที่วัดได้ ~7pt) ไม่ใช่
                // ระยะที่ต้องยิ่งเยอะขึ้นตาม safe area ของเครื่อง — bottomClearance จึงควรอ่านเป็น "ระยะขั้น
                // ต่ำจากขอบจอจริงที่หน้านี้ต้องการ" ไม่ใช่ "ส่วนเพิ่มเหนือ safe area" (ดูคอมเมนต์ที่
                // ForestSceneHost.tabBarClearance) — จอที่ไม่มีแท็บบาร์ (Welcome, Login) ส่ง
                // bottomClearance: 0 มา ผลคือ max(safeArea, 0) = safeArea เป๊ะ คือพฤติกรรม "ชิดมุมจอ
                // แต่ไม่ทะลุ safe area" ที่ต้องการพอดี (รายละเอียดการวัด/ยืนยันสองเครื่องอยู่ใน
                // task-8-report.md ส่วน fix round 1)
                //
                // ประวัติที่ลองแล้วไม่ได้ผล (อย่าเสียเวลาลองซ้ำ) — คนละกลไกกับตอนนี้: รอบก่อนเคยลองเติม
                // .ignoresSafeArea() ที่ Text นี้ตรงๆ และลอง padding-bottom ติดลบ (-25 ถึง -100) ที่
                // font 9pt หวังดันเครดิตให้พ้น floor ที่เจอ — วัดพิกเซลจริงแล้วตำแหน่งไม่ขยับเลยทั้งคู่
                // (ตอนนั้นไม่มี GeometryReader พึ่ง safe-area โดยปริยายของ SwiftUI ล้วนๆ) ส่วนที่ "ยืนยัน
                // แล้วจริง" มีแค่คนละอาการ: TabRootOpaqueBackgroundRemover ใน ForestSceneHost.swift
                // ยืนยันแล้วว่า MainTabView ทำให้พื้นหลังทึบขาวของ per-tab UIHostingController ทะลุมาบัง
                // RootView ได้จริง (เรื่อง background color ไม่ใช่เรื่องตำแหน่ง) ส่วนที่ floor ของตำแหน่ง
                // เครดิตน่าจะมาจากกลไกตระกูลเดียวกันหรือเปล่า ยังเป็นแค่ข้อสงสัย ไม่มีหลักฐานตรงยืนยัน
                Text("credits_3d_models")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.40))
                    .padding(.leading, 16)
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, bottomClearance))
            }
        }
        .allowsHitTesting(false)
    }
}
