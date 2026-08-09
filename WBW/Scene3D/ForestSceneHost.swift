import SwiftUI

/// เจ้าของฉาก 3D ตัวเดียวของทั้งแอป
///
/// วางไว้ที่ RootView จึงไม่ถูกทำลายตอนสลับ welcome → login → home หรือสลับแท็บ
/// แต่ละหน้าไม่ได้เป็นเจ้าของฉาก แค่ "สั่งค่า" เข้ามาผ่าน .forestBackground()
/// (แนวคิดเดียวกับ SceneHost.tsx ของเว็บ ที่มี Canvas เดียวอยู่ใน layout)
@MainActor
final class ForestSceneHost: ObservableObject {
    /// false = ซ่อน + หยุด render (หน้าที่ไม่ใช้ฉาก, แอปอยู่หลัง, จอเจ้าหน้าที่)
    ///
    /// **derived เสมอ ห้าม set ตรงๆ จากข้างนอก** — คำนวณจาก 3 อินพุตที่เป็นอิสระจากกันด้วย
    /// recompute(): `enabled = wantsScene && appActive && !suppressed` เท่านั้น
    ///
    /// ของเดิม enabled ถูก set ตรงๆ จาก 6 จุด (ค่าเริ่มต้น, onAppear/onDisappear ของ
    /// ForestBackground, RootView ตอน scenePhase/isStaff เปลี่ยน, MainTabView.updateSceneGate())
    /// ทุกจุด "force" ค่าทับกันเฉยๆ ไม่มีจุดไหนรู้ว่าอีก 5 จุดต้องการอะไรอยู่ ผลคือจอดำล้วน (ไม่มี
    /// ท้องฟ้า/ต้นไม้/สครีม/เครดิต) สามแบบที่ reproduce ได้จริง:
    ///   1. Welcome→Home: onDisappear ของ Welcome (`enabled 1→0`) ทำงาน "หลัง" onAppear ของ Home
    ///      (`enabled 0→1`) เสมอ — SwiftUI รับประกันแค่ onAppear ของจอใหม่มาก่อน onDisappear ของ
    ///      จอเก่า ไม่ใช่กลับกัน
    ///   2. Home→QR: เหมือนกันทุกประการ (onDisappear ของ Home ทับ onAppear ของ QR)
    ///   3. background→foreground: scenePhase != .active สั่ง false แต่ไม่มี branch .active
    ///      สั่งคืนเป็น true เลย ค้าง false ถาวรจนกว่าจะบังเอิญมีจุดอื่นมา set true ให้ (เช่น สลับแท็บ)
    /// แก้ด้วยแยกอินพุตให้เป็นอิสระจากกันจริงๆ แทนที่จะให้ 6 จุดนั้น "ชนะ" กันเองตามลำดับเวลา
    @Published private(set) var enabled = false {
        didSet { if enabled { everEnabled = true } }
    }
    /// true ตั้งแต่ครั้งแรกที่ enabled เป็น true แล้วไม่กลับเป็น false อีกเลย (พอร์ตจาก
    /// everEnabled ของ SceneHost.tsx) — RootView mount ForestSceneView ด้วยตัวนี้ ไม่ใช่ enabled
    /// ตรงๆ เพื่อไม่ให้ RealityView ถูกทำลาย+สร้างใหม่ทุกครั้งที่ enabled สลับ false→true (เช่น
    /// สลับแท็บออกจาก Home แล้วกลับมา) ซึ่งจะโหลด USDZ 571 ชิ้นซ้ำทุกรอบ ขัดกับทั้งจุดประสงค์ของ
    /// host ตัวนี้และกับที่เว็บกันเรื่องนี้ไว้ตั้งแต่แรก — enabled ยังใช้คุมว่าโชว์/ซ่อน (opacity)
    /// และว่าฉากควรทำงาน (update closure) อยู่เหมือนเดิม
    @Published private(set) var everEnabled = false

    /// มีจอที่เรียก .forestBackground() โชว์อยู่จริงไหม — เขียนได้เฉพาะผ่าน claimScene()/
    /// releaseScene() ด้านล่าง ไม่มีใครนอกเหนือจาก ForestBackground modifier ในไฟล์นี้เขียนตัวนี้ตรงๆ
    /// (เจ้าของเดียว ตามที่รีวิวขอ — เดิมมันคือครึ่งหนึ่งของ enabled ที่ปนกับอีก 2 อินพุตด้านล่างจนแยกไม่ออก)
    private var wantsScene = false { didSet { recompute() } }
    /// แอปอยู่ scenePhase .active ไหม — RootView เขียนตัวเดียว (onChange(of: scenePhase))
    /// ค่าเริ่มต้น true ให้ตรงกับ scenePhase จริงตอน launch (ไม่มีจอไหน "ขอ" ฉากได้ก่อนหน้านั้นอยู่แล้ว
    /// เพราะ wantsScene เริ่ม false — ค่าเริ่มต้นของตัวนี้จึงไม่มีผลจนกว่าจะมีจอ claim จริง)
    var appActive = true { didSet { recompute() } }
    /// บังคับปิดจากเหตุผลอื่นที่ไม่ใช่ 2 ตัวบน — RootView (จอเจ้าหน้าที่) และ MainTabView.
    /// updateSceneGate() (แท็บที่ไม่ใช้ฉาก/จอแชททับเต็มจอ) เขียนตัวเดียวกันนี้ร่วมกัน คนละเงื่อนไข
    /// แต่ไม่ชนกันจริงเพราะ MainTabView ไม่ถูก mount เลยตอนเป็นเจ้าหน้าที่ (RootView สลับ
    /// StaffScanView/MainTabView แยกกันตาม role บน session.user ตัวเดียวกัน)
    var suppressed = false { didSet { recompute() } }

    private func recompute() {
        enabled = wantsScene && appActive && !suppressed
    }

    /// token ของจอที่ claim ฉากอยู่ปัจจุบัน — กัน onDisappear ของจอที่กำลังจะออกไปเคลียร์ wantsScene
    /// ทับจอใหม่ที่ onAppear claim ไปก่อนแล้ว (ลำดับที่ SwiftUI รับประกัน: onAppear ของจอที่เข้ามาก่อน
    /// เสมอ ตามด้วย onDisappear ของจอที่ออก ไม่ใช่กลับกัน) — นี่คือกลไกที่แก้ manifestation #1/#2 ด้านบน
    private var currentClaim = UUID()

    /// true เมื่อโปรเซสนี้ถูก XCTest harness รันอยู่ (unit test host) — project.yml ผูก WBWTests
    /// (`dependencies: - target: WBW`) ทำให้ WBWTests ไม่ได้รันแยกโปรเซสจากแอป แต่โหลดเข้าไปในโปรเซส
    /// เดียวกับแอป WBW เอง (แอปคือ "test host") ผลคือทุกครั้งที่รัน `xcodebuild test` แอปทั้งตัว boot
    /// ขึ้นจริง รวมถึง RootView ที่จะ mount ฉากป่าด้วยถ้าไม่กันตรงนี้ไว้ — ฉากเริ่มโหลด forest.usdz
    /// แบบ async บน background queue ของ RealityKit (com.apple.realityio.live-scene-update-queue) แต่
    /// ชุดเทส 79 ตัวเป็น pure unit test ล้วนๆ ไม่แตะ UI เลย จบใน ~0.2 วินาที — เร็วกว่าที่ USDZ จะโหลด
    /// เสร็จมาก `_XCTestMain` เรียก `exit()` ทันทีที่เทสครบ ทำลาย static ของ libusd_ms (ผ่าน
    /// `__cxa_finalize_ranges`) พร้อมๆ กับที่ queue หลังบ้านของ RealityKit ยังอ้างถึงมันอยู่ →
    /// segfault ที่ `realityio::hasInvalidTextures` → `getFileResolvedPath` → `ArResolverContextBinder`
    /// (dereference 0xa1) ทุกครั้งหลังเทสผ่านหมดแล้ว (`** TEST SUCCEEDED **` ถูกพิมพ์ไปก่อน crash
    /// จะเกิด ดังนั้น xcodebuild ไม่ fail แต่ทิ้ง WBW-*.ips ใหม่ไว้ใน DiagnosticReports ทุกรอบ)
    ///
    /// `XCTestConfigurationFilePath` คือสัญญาณมาตรฐานที่ XCTest harness set ไว้ในสภาพแวดล้อมของ
    /// โปรเซสตอนรัน unit test เท่านั้น — ไม่มีใน launch ปกติของแอปจริงไม่ว่าจะจาก Xcode run, หน้าจอ
    /// โฮม, หรือ `xcrun simctl launch` (รวมถึง launch ที่ส่ง -uitestToken/-uitestUser/... สำหรับเทส
    /// มือ/สกรีนช็อต — พวกนั้นเป็นแค่ UserDefaults argument ธรรมดา ไม่เกี่ยวอะไรกับ XCTest harness เลย
    /// ดู RootView.init()) เช็คครั้งเดียวพอเพราะค่านี้ไม่เปลี่ยนระหว่างอายุของโปรเซส
    ///
    /// กันที่ claimScene() (ไม่ใช่ที่ recompute() หรือเงื่อนไข mount ที่ RootView) เพราะ claimScene()
    /// คือจุดเดียวที่ตั้ง wantsScene = true — ปล่อยให้คืน token ออกไปตามปกติ (releaseScene() เรียกด้วย
    /// token นั้นได้เฉยๆ ไม่มีผลอะไรต่อ แค่ไม่แตะ wantsScene เลย) ผลคือ enabled/everEnabled ค้าง false
    /// ตลอดอายุโปรเซสเทส RootView (`if host.everEnabled && !host.loadFailed`) จึงไม่ mount
    /// ForestSceneView() เองโดยธรรมชาติ ไม่ต้องแก้เงื่อนไข mount หรือสูตร recompute() (`enabled =
    /// wantsScene && appActive && !suppressed` เท่านั้น ตามคอมเมนต์ที่ enabled ด้านบน) เลยสักบรรทัด
    private static let isRunningUnderXCTest: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// จอขอฉากแล้วต้องให้จริงไหม — false = claimScene() ปล่อย token คืนเฉยๆ ไม่แตะ wantsScene
    ///
    /// `nonisolated` ไม่ใช่ของประดับ: คลาสนี้เป็น @MainActor ทั้งก้อน static member จึงเป็น
    /// main-actor isolated ตามไปด้วย เทสยูนิตจะเรียกไม่ได้ถ้าไม่ประกาศ (ฟังก์ชันนี้ไม่แตะ state ใดเลย)
    nonisolated static func shouldClaim(forest3D: Bool, underTest: Bool) -> Bool {
        forest3D && !underTest
    }

    /// จอที่ใช้ฉากเรียกตอน onAppear (ผ่าน ForestBackground) — คืน token ไว้ยื่นคืนตอน onDisappear
    /// claim ใหม่เสมอทุกครั้งที่ onAppear แม้จะมี token เก่าค้างอยู่ก็ตาม (เช่น สลับแท็บออกจาก Home
    /// แล้วกลับมาแท็บเดิม) — token เก่าอาจถูกจอที่คั่นกลางแย่ง claim แล้วปล่อยคืนไปแล้วด้วยซ้ำ claim
    /// ใหม่ทุกรอบตัดปัญหานั้นทิ้งไปเลยแทนที่จะพยายาม reuse token เดิม
    fileprivate func claimScene() -> UUID {
        let token = UUID()
        currentClaim = token
        // สองเหตุผลที่จอขอฉากแล้วไม่ได้: Config.forest3D ปิดอยู่ (ฉากกินเครื่อง ดู spec
        // 2026-08-07-forest-3d-off-design.md) หรือกำลังรันเทสยูนิต (ดูคอมเมนต์ที่
        // isRunningUnderXCTest ด้านบนว่าปล่อยให้ wantsScene เป็น true ตอนนั้นถึงพังยังไง)
        guard Self.shouldClaim(forest3D: Config.forest3D,
                               underTest: Self.isRunningUnderXCTest) else { return token }
        wantsScene = true
        return token
    }

    /// จอที่ใช้ฉากเรียกตอน onDisappear — เคลียร์ wantsScene เฉพาะตอนยังเป็นเจ้าของ claim ปัจจุบันจริงๆ
    /// เท่านั้น ไม่ตรง = มีจอใหม่ claim ไปแล้วก่อนหน้านี้ ปล่อยผ่านเฉยๆ ไม่แตะ wantsScene เลย
    fileprivate func releaseScene(_ token: UUID) {
        guard token == currentClaim else { return }
        wantsScene = false
    }

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
    /// token ที่ host คืนมาตอน claim — ต้อง @State (ไม่ใช่ local var) เพราะต้องอยู่รอดข้าม onAppear
    /// ไปถึง onDisappear ของ "จอเดียวกัน" (identity เดียวกัน) แม้ modifier struct เองจะถูกสร้างใหม่
    @State private var claimToken: UUID?
    let day: Float
    let plantStep: Int?
    let plantTotal: Int
    let bottomClearance: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                if Config.forest3D {
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
                } else {
                    // ฉาก 3D ปิดอยู่ — ใช้ภาพป่าเป็นพื้นแทน (เดิมเป็นพื้นทึบสีเดียวรอรูปอยู่)
                    //
                    // ยังต้องมี TabRootOpaqueBackgroundRemover เหมือนทางฉากเปิด แม้สีนี้จะถูกวาดในกรอบ
                    // ของจอเอง: แท็บ QR (Tab role .search ของ iOS 26) วาง content ไว้ใน container ที่
                    // แคบกว่าจอจริง พื้นทึบขาวของ per-tab UIHostingController จึงโผล่เป็นแถบสองข้าง
                    // (เห็นจริงในสกรีนช็อตรอบแรก ดู docs/forest-3d-off-verification.md) พอเคลียร์แล้ว
                    // สิ่งที่โผล่แทนคือพื้นทึบสีเดียวกันที่ RootView วาดไว้ใต้ทุกอย่าง — ไม่ใช่ขาวและไม่ใช่ดำ
                    ZStack {
                        TabRootOpaqueBackgroundRemover().frame(width: 1, height: 1).allowsHitTesting(false)
                        AppBackdrop()
                    }
                }
            }
            .onAppear {
                host.day = day
                host.plantStep = plantStep
                host.plantTotal = plantTotal
                host.bottomClearance = bottomClearance
                claimToken = host.claimScene()
            }
            .onDisappear {
                // ปล่อยคืนเฉพาะตอนยังเป็นเจ้าของ claim ปัจจุบันจริง — ถ้าจอถัดไป (เช่น Home ตอนออกจาก
                // Welcome, หรือ QR ตอนออกจาก Home) claim ไปแล้วก่อนที่ onDisappear นี้จะถูกเรียก (ลำดับ
                // ที่ SwiftUI รับประกัน: onAppear ของจอใหม่มาก่อนเสมอ) ปล่อยผ่านเฉยๆ ไม่งั้นจะไปเคลียร์
                // wantsScene ของจอใหม่ทับทั้งที่จอใหม่ยังโชว์อยู่จริง — นี่คือสาเหตุของจอดำเดิมตอน
                // Welcome→Home และ Home→QR (ดูคอมเมนต์ยาวที่ ForestSceneHost.enabled)
                if let claimToken { host.releaseScene(claimToken) }
            }
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
