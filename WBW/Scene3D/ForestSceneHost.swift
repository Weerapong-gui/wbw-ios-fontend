import SwiftUI

/// เจ้าของฉาก 3D ตัวเดียวของทั้งแอป
///
/// วางไว้ที่ RootView จึงไม่ถูกทำลายตอนสลับ welcome → login → home หรือสลับแท็บ
/// แต่ละหน้าไม่ได้เป็นเจ้าของฉาก แค่ "สั่งค่า" เข้ามาผ่าน .forestBackground()
/// (แนวคิดเดียวกับ SceneHost.tsx ของเว็บ ที่มี Canvas เดียวอยู่ใน layout)
@MainActor
final class ForestSceneHost: ObservableObject {
    /// false = ซ่อน + หยุด render (หน้าที่ไม่ใช้ฉาก, แอปอยู่หลัง, จอเจ้าหน้าที่)
    @Published var enabled = false {
        didSet { if enabled { everEnabled = true } }
    }
    /// true ตั้งแต่ครั้งแรกที่ enabled เป็น true แล้วไม่กลับเป็น false อีกเลย (พอร์ตจาก
    /// everEnabled ของ SceneHost.tsx) — RootView mount ForestSceneView ด้วยตัวนี้ ไม่ใช่ enabled
    /// ตรงๆ เพื่อไม่ให้ RealityView ถูกทำลาย+สร้างใหม่ทุกครั้งที่ enabled สลับ false→true (เช่น
    /// สลับแท็บออกจาก Home แล้วกลับมา) ซึ่งจะโหลด USDZ 571 ชิ้นซ้ำทุกรอบ ขัดกับทั้งจุดประสงค์ของ
    /// host ตัวนี้และกับที่เว็บกันเรื่องนี้ไว้ตั้งแต่แรก — enabled ยังใช้คุมว่าโชว์/ซ่อน (opacity)
    /// และว่าฉากควรทำงาน (update closure) อยู่เหมือนเดิม
    @Published private(set) var everEnabled = false
    /// ช่วงเวลาของวัน 0..1
    @Published var day: Float = ForestMath.dayStill
    /// ระยะขั้นต่ำจากขอบจอล่างจริงที่หน้านี้ต้องการให้เครดิตโมเดล — ForestOverlay ใช้
    /// max(safe area สดของเครื่อง, ค่านี้) ไม่ใช่บวกกัน (ดูคอมเมนต์ที่ตำแหน่งเครดิตใน
    /// ForestOverlay.swift ว่าทำไม) แต่ละหน้า "สั่งค่า" เข้ามาผ่าน .forestBackground() เหมือน
    /// day/plantStep · ค่าเริ่มต้น = ระยะที่พ้นแท็บบาร์ลอยของ MainTabView เพราะตอนนี้มีแค่ Home ที่
    /// เรียก และ Home อยู่ใต้แท็บบาร์นั้นเสมอ — จอที่ไม่มีแท็บบาร์ (Welcome, Login) ต้องส่ง
    /// bottomClearance: 0 มาเองตอน Task 9 ผูกจอเหล่านั้น (ผลคือ max(safeArea, 0) = safeArea เป๊ะ)
    @Published var bottomClearance: CGFloat = ForestSceneHost.tabBarClearance
    /// ขั้นต้นไม้ · nil = ไม่มีต้นไม้ในฉาก (ตรงกับ plantStep?: number ของเว็บ)
    @Published var plantStep: Int?
    /// จำนวนฐานทั้งหมด — คู่กับ plantStep เพื่อคำนวณความสูง
    @Published var plantTotal = 0
    /// โหลด USDZ ไม่สำเร็จ → ทุกหน้าตกกลับไปใช้รูปนิ่งเดิม
    @Published private(set) var loadFailed = false

    func markLoadFailed() { loadFailed = true }

    /// ระยะขั้นต่ำจากขอบจอล่างจริงที่พ้นแท็บบาร์ลอยของ MainTabView — วัดด้วยการสแกนสีพิกเซลจริง
    /// (หาแถวที่มืดต่อเนื่องยาวพอจะเป็นพื้นแพลล) หาขอบบนของแท็บบาร์บนสกรีนช็อตจริง แล้วแปลงเป็นระยะ
    /// จากขอบจอล่าง: ได้ 82pt "เท่ากันเป๊ะ" ทั้ง iPhone 17 (safe area ล่าง 34pt) และ iPhone SE รุ่น 3
    /// (safe area ล่าง 0pt) — สรุปว่าแท็บบาร์ไม่ได้อิง safe area ของเครื่องเลย เป็นระยะคงที่จากขอบจอ
    /// เสมอ ค่านี้ = 82 + กันชนอ่านง่ายราว 7pt ยืนยันด้วยสกรีนช็อตจริงว่าเครดิตอ่านออกเต็มบรรทัด ไม่ทับ
    /// แท็บบาร์ ทั้งสองเครื่อง (ดูคอมเมนต์ที่ ForestOverlay ว่าทำไมต้องใช้ max() กับ safe area สด ไม่ใช่
    /// บวกกัน — สูตรบวกเคยลองมาก่อนแล้วพัง เพราะ 34+55=89 ที่โล่งพอดีบน iPhone 17 กลายเป็น 0+55=55 บน
    /// SE ซึ่งยังทับแท็บบาร์อยู่ ส่วนขยับเป็น 34+89=123 บน 17 ก็ดันเครดิตไปทับมือ/ลำตัวมาสคอต DinDin
    /// ของ HomeView แทน — มาสคอตเป็นเรื่องชั่วคราวที่ Task 9 จะถอดทิ้ง แต่ระหว่างนี้ไม่ควรให้แย่ลง)
    /// ต่างจากค่าคงที่ตัวเดิมของบั๊กนี้ (padding-bottom 55pt เดี่ยวๆ ไม่แยกส่วน safe area เลย) ที่วัดจาก
    /// เครื่องเดียว (iPhone 17) แล้วใช้ไม่ได้พอย้ายไปเครื่องที่ safe area ล่างเป็น 0
    static let tabBarClearance: CGFloat = 89
}

/// สั่งฉากจากหน้าใดก็ได้โดยไม่ต้องรู้จัก RealityKit
///
/// ตัวกลางนี้คือเหตุผลที่สลับ implement ข้างในได้ (3D ↔ รูปนิ่ง) โดยไม่แตะ 5 จอเลย
private struct ForestBackground: ViewModifier {
    @EnvironmentObject private var host: ForestSceneHost
    let day: Float
    let plantStep: Int?
    let plantTotal: Int
    let bottomClearance: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // ดูคอมเมนต์ที่ struct ด้านล่าง — ไม่มีนี่ ฉากป่าที่ RootView โดนบังทึบขาวเสมอ
                    TabRootOpaqueBackgroundRemover().frame(width: 1, height: 1).allowsHitTesting(false)
                    // โหลดฉากไม่ได้ → รูปเดิม · ห้ามลบ asset bg_forest ทิ้ง
                    if host.loadFailed {
                        Image("bg_forest").resizable().scaledToFill().ignoresSafeArea()
                    } else {
                        Color.clear   // ฉากจริงวาดอยู่ที่ RootView ใต้ทุกอย่าง
                    }
                }
            }
            .onAppear {
                host.day = day
                host.plantStep = plantStep
                host.plantTotal = plantTotal
                host.bottomClearance = bottomClearance
                host.enabled = true
            }
            .onDisappear { host.enabled = false }
            .onChange(of: day) { _, v in host.day = v }
            .onChange(of: plantStep) { _, v in host.plantStep = v }
            .onChange(of: plantTotal) { _, v in host.plantTotal = v }
            .onChange(of: bottomClearance) { _, v in host.bottomClearance = v }
    }
}

extension View {
    /// ใช้ฉากป่า 3D เป็นพื้นหลังของหน้านี้
    /// - plantStep: nil = ไม่มีต้นไม้ · มีค่า = ต้นไม้โตตามขั้น (มีแค่ Home ที่ส่ง)
    /// - bottomClearance: ระยะขั้นต่ำจากขอบจอล่างจริงที่หน้านี้ต้องการให้เครดิตโมเดล — ForestOverlay
    ///   เทียบกับ safe area จริงของเครื่องด้วย max() ไม่ใช่บวก (ดูคอมเมนต์ที่นั่น) ค่าเริ่มต้น = ระยะที่
    ///   พ้นแท็บบาร์ลอยของ MainTabView เพราะตอนนี้มีแค่ Home ที่เรียก และ Home อยู่ใต้แท็บบาร์เสมอ —
    ///   จอที่ไม่มีแท็บบาร์ (Welcome, Login) ต้องส่ง 0 มาเอง
    func forestBackground(day: Float, plantStep: Int? = nil, plantTotal: Int = 0,
                           bottomClearance: CGFloat = ForestSceneHost.tabBarClearance) -> some View {
        modifier(ForestBackground(day: day, plantStep: plantStep, plantTotal: plantTotal,
                                   bottomClearance: bottomClearance))
    }
}

/// แก้บั๊กที่ไม่ได้อยู่ในบรีฟ พบระหว่างเทส Step 6: MainTabView ใช้ TabView แบบ value-based ของ iOS 18+
/// (`Tab(value:) { ... }`) ซึ่งแต่ละแท็บกลายเป็น "root" ของตัวเอง (UIHostingController แยกจากกันจริงๆ
/// ไม่ใช่แค่ node ในต้นไม้เดียวกับ RootView) ยืนยันด้วยการไต่ view.superview จริงแล้ว log ออกมา: ไม่มี
/// UITabBarController อยู่ในสายเลย มีแต่ `_UIHostingView<ModifiedContent<AnyView, RootModifier>>` ที่
/// backgroundColor = systemBackgroundColor ทึบ, isOpaque = true เป็นค่าเริ่มต้นเสมอ ผลคือฉากป่า 3D ที่
/// RootView (อยู่หลัง MainTabView ใน ZStack ของแอปเดียวกัน) โดนบังทึบขาวทั้งจอ **ไม่ว่าฉากจะ render ถูก
/// แค่ไหนก็ตาม** — ยืนยันแยกสาเหตุจาก RealityKit ด้วยการเอา Color.red มาแทน ForestSceneView ชั่วคราว
/// (ก็โดนบังเหมือนกัน) ก่อนไล่หาเลเยอร์ทึบตัวจริงเจอ
///
/// SwiftUI เวอร์ชันนี้ไม่มี API เปิดให้เคลียร์ background ของ per-tab root ตรงๆ (ลอง .background(.clear)
/// บน TabView เอง — makeUIViewController ไม่ถูกเรียกด้วยซ้ำ แปลว่า background modifier บน TabView โดยตรง
/// ไม่ถูกสร้างจริง) ต้องแทรกเป็น sibling view ในต้นไม้ของแต่ละแท็บเอง (ที่นี่คือใน .background ของ
/// forestBackground) แล้วไต่ view.superview chain ขึ้นไปเคลียร์ backgroundColor เอง — ไม่ผูกกับชื่อ type
/// ที่เป็น SwiftUI internal (เปลี่ยนได้ทุก OS version) เช็คแค่ "มี backgroundColor ที่ไม่ใช่ nil ไหม" ตรงๆ
private struct TabRootOpaqueBackgroundRemover: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        DispatchQueue.main.async { [weak vc] in
            var v: UIView? = vc?.view.superview
            while let cur = v, !(cur is UIWindow) {
                if cur.backgroundColor != nil {
                    cur.backgroundColor = .clear
                    cur.isOpaque = false
                }
                v = cur.superview
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
