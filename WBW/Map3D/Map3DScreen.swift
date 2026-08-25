import RealityKit
import SwiftUI
import UIKit

/// แท็บแผนที่ — โมเดล 3D ของพื้นที่งาน (map.usdz) แทน MapLibre เดิม
///
/// ไม่ใช้ ForestSceneHost: ฉากป่าต้องมี host เพราะ 4 จอใช้ฉากเดียวกันและฉากถูกวาดที่ RootView
/// ซึ่งอยู่คนละ hosting context กับจอ — แผนที่อยู่จอเดียว RealityView เกิดและตายไปกับจอนี้ได้เลย
struct Map3DScreen: View {
    /// แท็บนี้ถูกเลือกอยู่จริงหรือเปล่า — **จำเป็น ไม่ใช่ของเผื่อ**
    ///
    /// `TabView` แบบ `Tab(value:)` ของ iOS 18+ สร้างเนื้อของทุกแท็บตั้งแต่ตอน mount (ยืนยันจาก
    /// สกรีนช็อตจริง: launch ด้วย `-uitestTab 4` แล้ว dialog ขอสิทธิ์ตำแหน่งยังเด้งทับจอ QR)
    /// ผูก `location.start()` ไว้กับ `.onAppear` เฉย ๆ จึงกลายเป็น "ขอสิทธิ์ตำแหน่งทันทีที่ล็อกอิน
    /// เสร็จ โดยไม่มีบริบทอะไรเลย" ซึ่งเป็นสิ่งที่ App Review ตีกลับได้ตรง ๆ
    var isActive: Bool = true

    /// โหลดโมเดลไม่สำเร็จ — โชว์ข้อความแทนจอเปล่า (ทรงเดียวกับ ForestSceneHost.loadFailed)
    @State private var loadFailed = false
    /// ยังโหลดโมเดลไม่เสร็จ — โมเดลนี้ใช้เวลาหลายวินาที ปล่อยจอเปล่าไว้ผู้ใช้อ่านว่าแอปค้าง ไม่ใช่กำลังโหลด
    @State private var isLoading = true
    /// intro เล่นจบแล้ว — ใช้สั่งปิดชั้นเมฆ (เมฆมีไว้ให้บินทะลุตอนเข้าจอ ไม่ใช่ของถาวร)
    @State private var introFinished = MapModelLoader.shared.hasPlayedIntro

    @EnvironmentObject private var progress: CheckinProgressStore
    /// ชื่อฐานทั้งงาน — ทำให้การ์ดขึ้นชื่อจริงได้ตั้งแต่ก่อนเช็คอิน
    @EnvironmentObject private var checkpoints: CheckpointStore
    /// ฐานที่แตะค้างไว้อยู่ — nil = ไม่มีการ์ด
    @State private var tappedSequence: Int?

    /// โหมดที่กำลังแสดง — จำข้ามการเปิดแอปผ่าน `UserDefaults` และรับแฟลกถ่ายภาพ
    /// `-uitestMapMode` ตรงนี้ ไม่ใช่ใน `onAppear` (ดูเหตุผลยาวที่ `MapMode.initialForLaunch`)
    @State private var mode = MapMode.initialForLaunch()
    /// หมุดที่มี **วงแสง** อยู่ตอนนี้ — แยกจาก `tappedSequence` ซึ่งแปลว่า "หมุดที่การ์ดเปิดอยู่"
    ///
    /// เดิมตัวเดียวคุมสามอย่าง (วงแสง การ์ด พื้นระยะใกล้สุด) พอ intro ต้องพากล้องไปจอดที่ฐาน 1
    /// **พร้อมวงแสงแต่ไม่เปิดการ์ด** (คำขอของ Park 2026-08-21) สามอย่างนั้นจึงแยกออกจากกัน
    ///
    /// **ค่าคงที่:** `tappedSequence != nil` ⟹ `spotlightSequence == tappedSequence` —
    /// การ์ดเปิดโดยไม่มีวงแสงไม่มีทางเกิดขึ้นได้ ทุกจุดที่ตั้ง/ล้าง `tappedSequence` ต้องแตะตัวนี้ด้วย
    @State private var spotlightSequence: Int?

    /// ตำแหน่งผู้ใช้จริงจาก CoreLocation — nil = ไม่ให้สิทธิ์/ยังไม่รู้ตำแหน่ง (ไม่วาดจุด)
    @StateObject private var location = Map3DLocation()

    /// ด้านกว้างสุดของโมเดลหลังย่อสเกล — ทุกระยะบนจอนี้วัดเทียบเลขนี้ทั้งหมด (ระยะกล้องใน
    /// `Map3DCamera`, รัศมีจุดผู้ใช้, และรัศมีโดมฟ้า/ชั้นเมฆที่ `Map3DSky` คำนวณต่อจากมัน)
    ///
    /// ต้องเป็นสัญลักษณ์ ไม่ใช่เลข 2 ฝังไว้ในบรรทัดที่ตั้ง `map.scale` เพราะข้อผูกข้ามไฟล์นี้เคย
    /// ถูกแบกด้วยคอมเมนต์ในไฟล์อื่นล้วน ๆ — `Map3DSky` ฮาร์ดโค้ด `mapRadius = 1` ไว้บนสมมติฐานว่า
    /// ที่นี่ย่อเป็น 2 เสมอ แก้เลขที่นี่แล้วไม่มีอะไรพาไปบอกที่นั่นและไม่มีเทสตัวไหนแดง
    static let normalisedSpan: Float = 2

    /// รัศมีจุดตำแหน่งผู้ใช้ วัดหลังโมเดลถูกย่อให้พอดีกรอบ `normalisedSpan` หน่วยแล้ว
    /// ตอนสร้าง entity ต้องหารด้วย map.scale กลับเป็นเมตรจริงของ local space เสมอ
    private static let dotRadiusOnScreen: Float = 0.02

    /// ชื่อ entity ไฮไลต์หมุด — ต้องหาเจอด้วยชื่อทั้งตอนลบของเก่าตอนต้น `make` และตอนย้ายพ่อ
    /// ใน `update` จึงเก็บเป็นค่าคงที่ ไม่ใช่สตริงลอยสองที่
    private static let pinHighlightName = "PinHighlight"

    /// รัศมีจานไฮไลต์ **ในหน่วย local ของหมุด** ไม่ใช่หน่วยที่ย่อแล้ว — เป็นลูกของ `marker_N`
    /// จึงกินสเกลของหมุดไปเอง · แว่นไม้เองกว้าง ±29.5 หน่วย จาน 75 จึงกว้างกว่าราวสองเท่าครึ่ง
    /// พอให้เห็นเป็นวงแสงรอบฐาน ไม่ใช่แผ่นรองที่ใหญ่จนกลบหมุด
    private static let pinHighlightRadius: Float = 75

    /// ทิศของพื้นที่งานเทียบกับกล้อง — หมุนรอบแกนตั้ง **ของตัวโมเดลเอง (Z)** ไม่ใช่แกน Y ของโลก
    ///
    /// ⚠️ เคยหมุนรอบ Y แล้วพัง: ที่ 45° ยังดูเหมือนหมุนทิศปกติ แต่พอเพิ่มเป็น 135° โมเดลตะแคงจน
    /// กล้องมองเห็น "ก้น" ของภูมิประเทศ (แผ่นน้ำตาลเปล่า ๆ มีแท่งแดงทะลุออกมา) ซึ่งเป็นสิ่งเดียวกับ
    /// ที่ Map3DCamera กันไว้ไม่ให้ผู้ใช้ทำ — แกน Y ของโลกไม่ใช่แกนตั้งของโมเดล การหมุนรอบมัน
    /// จึงเป็นการ "พลิก" ไม่ใช่การ "หันทิศ"
    ///
    /// ค่านี้ "ไม่ใช่" ทิศเหนือจริง อย่าตีความเป็นมุม compass/bearing ใด ๆ ·
    /// ตัวเลขอยู่ที่ `WBW/Resources/map_config.json` เพราะต้องจูนใหม่ทุกครั้งที่เปลี่ยนโมเดล
    ///
    /// กติกาสำหรับใครมาต่อ: entity ที่วางตำแหน่งจากพิกัดจริง (lat/lng) เช่นจุด GPS ผู้ใช้
    /// ต้องเป็นลูกของ `map` ไม่ใช่ลูกของ `root` — ให้ transform hierarchy พาการหมุนนี้ไปเองอัตโนมัติ
    /// ถ้าจำเป็นต้องแยกไปเป็นลูกของ entity อื่น ต้องคูณการหมุนนี้เข้าไปเองด้วยมือ ไม่งั้นตำแหน่งจะเพี้ยน
    /// แบบเงียบ ๆ ไม่มี error ไม่มีเทสจับได้ (หมุดหาโหนดผ่าน findEntity(named:) บนโมเดลเองอยู่แล้ว
    /// จึงรับการหมุนนี้ไปฟรี ๆ โดยอัตโนมัติ ไม่ต้องแก้อะไร)
    private static var cameraFramingYaw: Float { Map3DConfig.current.framingYaw }

    /// มุมกวาด/เงย/ระยะของกล้องตอนนี้ — ผู้ใช้ลากและหุบนิ้วเพื่อเปลี่ยน ทุกค่าถูก clamp
    /// ด้วย Map3DCamera เสมอ โดยเฉพาะมุมเงยที่ห้ามต่ำกว่าเส้นขอบฟ้า (มองใต้โมเดลไม่ได้)
    @State private var yaw = Map3DCamera.defaultYaw
    @State private var pitch = Map3DCamera.defaultPitch
    @State private var distance = Map3DCamera.defaultDistance
    /// ค่าตั้งต้นของท่าทางที่กำลังลากอยู่ — ต้องจำไว้เพราะ DragGesture ให้ระยะสะสมจากจุดเริ่ม
    @State private var gestureStartYaw: Float?
    @State private var gestureStartPitch: Float?
    @State private var gestureStartDistance: Float?
    /// ทับค่า cameraFramingYaw ชั่วคราวตอนถ่ายเทียบมุม (ตั้งผ่าน -uitestMapHeading, DEBUG เท่านั้น)
    @State private var headingOverride: Float?

    /// จุดที่กล้องจ้องอยู่ — `.zero` = กลางแผนที่ตามปกติ · ตำแหน่งหมุด = กำลังโฟกัสฐานนั้น
    ///
    /// เดิมกล้อง `look(at: .zero)` ตายตัว การหมุนวนรอบฐานจึงเป็นไปไม่ได้เลยไม่ว่าจะตั้ง yaw ยังไง
    @State private var target = SIMD3<Float>.zero
    /// งานบิน+หมุนวนที่กำลังเล่นอยู่ — ต้อง cancel ทุกทางออก ไม่งั้นมันหมุนต่อหลังออกจากแท็บไปแล้ว
    @State private var focusTask: Task<Void, Never>?
    /// ท่ากล้องก่อนกดหมุด — เก็บไว้คืนตอนปิดการ์ด ผู้ใช้จะได้กลับมาที่มุมที่ตัวเองจัดไว้
    @State private var poseBeforeFocus: Map3DPose?
    /// คำใบ้ "แตะหมุดเพื่อดูฐาน" ยังโชว์อยู่ไหม
    @State private var showsHint = false

    /// ตัวจับการเดินรอบนี้ — เจ้าของ `CMPedometer` กับ `CLLocationManager` ของฟีเจอร์นับก้าว
    /// (คนละตัวกับ `location` ข้างบนที่มีไว้วาดจุดบนแผนที่เท่านั้น ความละเอียดคนละระดับ
    /// ดูคอมเมนต์ที่ `WalkTracker.init`)
    @StateObject private var walk = WalkTracker()

    /// ฐานที่ `-uitestMapPin` สั่งให้เปิดค้างไว้ แต่ยังบินไปหาไม่ได้เพราะโมเดลยังโหลดไม่เสร็จ
    /// (DEBUG เท่านั้น — ปลาย make เป็นคนหยิบไปใช้แล้วล้างทิ้ง)
    @State private var pendingForcedPin: Int?

    /// ความเข้มของม่านมืดตอนนี้ 0…1 — 0 = ไม่มีม่าน, 1 = เข้มเต็มที่ (`Map3DFocus.maxDim`)
    ///
    /// เดินไปพร้อมกล้องในลูปเดียวกัน (`run(to:over:dimTo:)`) ไม่ได้ใช้ `withAnimation` —
    /// จอนี้เดินค่ากล้องด้วยมือทุกเฟรมอยู่แล้ว การเอา implicit animation มาไว้บนค่าชุดเดียวกัน
    /// ในจอเดียวกันกับตัวเดินมือ 60 Hz เป็นความเสี่ยงที่ต้องมีรอบพิสูจน์ของตัวเอง
    @State private var focusProgress: Float = 0

    /// ปิดแอนิเมชันทั้งหมดเมื่อผู้ใช้เปิด Reduce Motion — กล้องกระโดดไปท่าปลายทางเลย
    /// (จอนี้มีทั้ง intro บินทะลุเมฆและการหมุนวนรอบฐาน ซึ่งเป็นการเคลื่อนไหวแบบที่ตัวเลือกนี้หมายถึงตรง ๆ)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// เทสยูนิตรันในโปรเซสเดียวกับแอป (app target เป็น test host) — ทรงเดียวกับ
    /// ForestSceneHost.isRunningUnderXCTest ที่มีเหตุผลยาวเขียนไว้แล้ว
    nonisolated static var isRunningUnderXCTest: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    /// โหลดโมเดลจริงไหม — false = โชว์การ์ดข้อความแทน ไม่แตะ RealityView เลย
    ///
    /// `nonisolated` เพื่อให้เทสยูนิตเรียกได้โดยไม่ต้องอยู่บน main actor (ฟังก์ชันนี้ไม่แตะ state ใด)
    nonisolated static func shouldRender(map3D: Bool, underTest: Bool) -> Bool {
        map3D && !underTest
    }

    var body: some View {
        // ประเมินครั้งเดียวแล้วใช้ซ้ำ — เดิมเรียก Self.shouldRender(...) ซ้ำสองที่ในฟังก์ชันนี้
        let shouldRender = Self.shouldRender(map3D: Config.map3D, underTest: Self.isRunningUnderXCTest)

        // แผนที่ 3 มิติถูกปิดด้วย `Config.map3D` เมื่อไหร่ ตกมาที่ 2 มิติเสมอ ไม่ใช่การ์ด
        // "แผนที่ปิดอยู่" แบบเดิม — MapKit เบากว่าโมเดล 10 MB มาก และยังตอบคำถามเรื่องเส้นทางได้ครบ
        let mode = MapMode.effective(stored: self.mode, map3DEnabled: Config.map3D)

        return ZStack {
            Color.wbwForestVoid.ignoresSafeArea()

            if mode == .flat {
                Map2DView(selectedSequence: $tappedSequence,
                          userCoordinate: location.coordinate)
                if let tappedSequence {
                    MapBaseCard(sequence: tappedSequence, userLocation: location.coordinate,
                                onClose: { self.tappedSequence = nil })
                }
            } else if !shouldRender {
                // ปิดสวิตช์อยู่ — ต้องเหลือของที่อ่านรู้เรื่อง ไม่ใช่จอว่าง
                VStack(spacing: 12) {
                    Image(systemName: "map")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("map_disabled")
                        .font(.wbwText(17, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(.white)
                }
            } else if loadFailed {
                VStack(spacing: 12) {
                    Text("map_failed")
                        .font(.wbwText(17, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(.white)
                    Text("map_failed_hint")
                        .font(.wbwText(13, relativeTo: .footnote))
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                mapView

                // ทับบน RealityView ระหว่างที่โมเดลยังไม่ขึ้น — RealityView ต้องถูก mount ไปแล้ว
                // ตั้งแต่ต้นถึงจะเริ่มโหลด จึงซ้อนทับแทนที่จะสลับ if/else กัน
                if isLoading {
                    ZStack {
                        Color.wbwForestVoid.ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView().tint(.white)
                            Text("map_loading")
                                .font(.wbwText(15, weight: .semibold, relativeTo: .subheadline))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .transition(.opacity)
                }
            }

            if shouldRender && !isLoading {
                focusScrim
                compass
                if let tappedSequence {
                    MapBaseCard(sequence: tappedSequence, userLocation: location.coordinate,
                                onClose: { endFocus() })
                } else if showsHint {
                    hint
                }
            }

            // ปุ่มสลับโหมด — โผล่ก็ต่อเมื่อมีสองโหมดให้เลือกจริง ปิด 3 มิติไว้แล้วปุ่มนี้จะเป็น
            // ปุ่มที่กดแล้วไม่มีอะไรเกิดขึ้น
            //
            // หลบให้การ์ดฐาน: การ์ดกินความกว้างเต็มจอที่ขอบล่าง ปุ่มกลม ๆ ที่ลอยทับมันอยู่
            // อ่านเป็นปุ่มของการ์ด ไม่ใช่ปุ่มของแผนที่ (ถ่ายเจอจริงตอนยืนยันโหมด 2 มิติ)
            // ซ่อนตอนกำลังเดิน — ตรงกับ Android (`MapScreen.kt:674`) ที่ซ่อนปุ่ม 3D ระหว่างเดิน
            // ด้วยเหตุผลเดียวกัน: มุมล่างเป็นที่ของปุ่มหยุด ปุ่มอื่นข้าง ๆ ทำให้กดผิดตอนเหนื่อย
            if Config.map3D && tappedSequence == nil && !walk.stats.active {
                modeToggle(current: mode)
            }

            // ปุ่มเริ่ม/หยุดเดิน — **ซ้ายล่าง** ระดับเดียวกับปุ่มสลับโหมดที่อยู่ขวาล่าง
            // ตรงกับที่ Android วางไว้ (`MapScreen.kt:663` ใช้ `Alignment.BottomStart`)
            if tappedSequence == nil {
                walkButton
            }
        }
        // แถบตัวเลขตอนเดิน — ใช้ `safeAreaInset` ไม่ใช่วางซ้อนใน ZStack เพราะ **เข็มทิศอยู่ขวาบน
        // ที่ `.padding(.top, 8)` เหมือนกัน** ทับกันแน่ถ้าวางซ้อน · `safeAreaInset` ดันของที่เหลือ
        // ในจอลงมาให้เอง ไม่ต้องไปวัดความสูงของ HUD มาบวก padding ของเข็มทิศเอง ซึ่งเป็นเลขที่
        // เพี้ยนทันทีที่ผู้ใช้ขยายขนาดตัวอักษร (ยืนยันตำแหน่งจริงด้วยสกรีนช็อต ไม่ใช่อ่านโค้ดเอา)
        .safeAreaInset(edge: .top) {
            if walk.stats.hasData {
                WalkHud(stats: walk.stats)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: walk.stats.hasData)
        // ออกจากแท็บ = หยุดจับ · ตัวจับกิน GPS ความละเอียดสูงสุดตลอดเวลา ปล่อยให้วิ่งต่อ
        // ตอนผู้ใช้ไปอยู่แท็บอื่นคือเผาแบตให้สิ่งที่ไม่มีใครดู (ทรงเดียวกับ `location.stop()`)
        .onChange(of: isActive) { _, nowActive in
            if !nowActive && walk.stats.active { walk.stop() }
        }
        // **ผูกกับรากของจอ ไม่ใช่กับ `mapView`** — `mapView` คือ `RealityView` ของโหมด 3 มิติ
        // ซึ่งไม่ถูก mount เลยเมื่อแท็บเปิดมาที่โหมด 2 มิติ และ 2 มิติคือค่าเริ่มต้นตั้งแต่
        // 2026-08-24 · ของที่แขวนไว้บนนั้นจึงถูกกลืนเงียบ ๆ ไม่มี error ให้เห็น รอยเดียวกับที่
        // `-uitestMapMode` เคยโดน (ดู `MapMode.initialForLaunch`) — ที่หลุดไปจริงสองอย่าง:
        // จุดตำแหน่งของผู้ใช้ไม่เคยขึ้นบนแผนที่ 2 มิติเพราะไม่มีใครสั่งเริ่มอ่านพิกัด และ
        // `-uitestMapPin` ไม่เปิดการ์ดตอนถ่าย `02-map` ทั้งที่มีสาขาโหมด 2 มิติเขียนรออยู่แล้ว
        .onAppear {
            #if DEBUG
            // เปิดการ์ดฐานตรงๆ โดยไม่ต้องแตะจริง — ทรงเดียวกับ uitestChat/uitestFeedback ที่
            // MainTabView.swift เป็นทางเดียวที่ถ่ายรูปการ์ดได้ในสภาพแวดล้อมที่ไม่มี tap tooling
            // ตั้งเฉพาะการ์ดตรงนี้ไม่พอในโหมด 3 มิติ — ม่านมืดกับกล้องผูกกับ `focus(on:at:)`
            // ซึ่งต้องรู้ตำแหน่งหมุดในฉาก และตำแหน่งนั้นมีให้ก็ต่อเมื่อโมเดลโหลดเสร็จแล้ว
            // จึงฝากไว้ที่ `pendingForcedPin` ให้ปลาย make มาหยิบไปแทน
            // ถ่ายจอตอนกำลังเดิน — ดูคอมเมนต์ที่ `WalkTracker.fillForScreenshot()`
            if UserDefaults.standard.bool(forKey: "uitestWalk") {
                showsHint = false
                walk.fillForScreenshot()
            }
            let forced = UserDefaults.standard.integer(forKey: "uitestMapPin")
            if forced > 0 {
                showsHint = false
                if mode == .flat {
                    tappedSequence = forced
                } else {
                    pendingForcedPin = forced
                }
            }
            #endif
            if isActive { location.start() }
        }
        .onChange(of: isActive) { _, nowActive in
            nowActive ? location.start() : location.stop()
        }
        .onDisappear { location.stop() }
    }

    // MARK: - ชั้นบนแผนที่

    /// เข็มทิศมุมขวาบน — โผล่เฉพาะตอนกล้องไม่ได้อยู่ท่าเริ่มต้น (พฤติกรรมเดียวกับ Apple Maps)
    /// โผล่ตลอดเวลาแปลว่าปุ่มที่กดแล้วไม่มีอะไรเกิดขึ้นนั่งอยู่บนจอถาวร
    @ViewBuilder
    private var compass: some View {
        if isOffDefaultAngle {
            VStack {
                HStack {
                    Spacer()
                    Button { resetAngle() } label: {
                        Image(systemName: "location.north.line.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            // หมุนตามมุมกวาดจริง — เข็มที่ไม่หมุนตามคือของประดับ ไม่ใช่เข็มทิศ
                            .rotationEffect(.radians(Double(-yaw)))
                            .frame(width: 44, height: 44)
                            .glassSurface(Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("map_reset_camera")
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .transition(.opacity)
        }
    }

    /// ปุ่มสลับ 2 มิติ ↔ 3 มิติ มุมขวาล่าง เหนือแถบแท็บ — ตำแหน่งเดียวกับที่ Android วางไว้
    ///
    /// อยู่ล่างขวาไม่ใช่บนขวาเพราะบนขวาเป็นที่ของเข็มทิศอยู่แล้ว และปุ่มนี้เป็นของที่กดบ่อยกว่า
    /// จึงควรอยู่ใต้นิ้วโป้งมากกว่า
    private func modeToggle(current: MapMode) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    let next = current.toggled()
                    next.store()
                    // ปิดการ์ดฐานตอนสลับ — ฐานที่เลือกไว้ในโหมดหนึ่งไม่ได้แปลว่ากล้องอีกโหมด
                    // กำลังจ้องมันอยู่ การ์ดที่ค้างข้ามโหมดจึงอ่านเป็นการ์ดที่ลืมปิด
                    tappedSequence = nil
                    withAnimation(.easeInOut(duration: 0.25)) { mode = next }
                } label: {
                    Image(systemName: current.toggleSystemImage)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .glassSurface(Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizedStringKey(current.toggleLabelKey))
            }
        }
        .padding(.horizontal, 20)
        .tabBarClearance(extra: 12)
    }

    /// ปุ่มเริ่ม/หยุดเดิน มุมซ้ายล่าง — แคปซูลกระจกทรงเดียวกับที่ Android ใช้
    ///
    /// กดเริ่มแล้ว **ซ่อนคำใบ้ทันที** ไม่ปล่อยให้ค้าง — คำใบ้อยู่กลางล่างที่ระยะใกล้กันมาก
    /// (`tabBarClearance + 16` เทียบกับปุ่มที่ `+12`) ทับกันแล้วอ่านไม่ออกทั้งคู่
    private var walkButton: some View {
        VStack {
            Spacer()
            HStack {
                Button {
                    showsHint = false
                    walk.toggle()
                } label: {
                    let running = walk.stats.active
                    HStack(spacing: 9) {
                        Image(systemName: running ? "stop.fill" : "play.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(running ? Color.wbwGreen : .white)
                        Text(Loc.t(running ? "walk_stop" : "walk_start").uppercased())
                            .font(.wbwLabelMedium)
                            .kerning(1.8)
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 18)
                    .padding(.trailing, 22)
                    .frame(minHeight: Config.Tap.minTarget)
                    .glassSurface(Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .tabBarClearance(extra: 12)
    }

    /// ม่านมืดรอบ ๆ ตอนจ้องหมุด — ใสตรงกลาง เข้มที่ขอบ
    ///
    /// เป็นวงไล่สีไม่ใช่ม่านทึบทั้งจอ เพราะม่านทึบจะหรี่หมุดที่เลือกไปด้วย ซึ่งสวนทางกับสิ่งที่ต้องการ ·
    /// หมุดที่โฟกัสอยู่กลางเฟรมเสมอโดยไม่ต้องคำนวณอะไรเลย เพราะกล้อง `look(at: target)` วาง
    /// target ไว้บนแกนหน้าของกล้องพอดี
    ///
    /// เยื้องรูใสขึ้นเล็กน้อย (0.46) เพราะ `focus(on:at:)` ส่งตำแหน่ง **ฐาน** ของแว่นไม้
    /// (local z = 0) ไม่ใช่กึ่งกลาง ตัวหมุดกับเลขจึงอยู่เหนือจุดที่กล้องจ้องขึ้นไป
    ///
    /// สร้างที่ความเข้มเต็มครั้งเดียวแล้วอนิเมตแค่ `.opacity()` ของกล่องนอก — ให้ระบบเลื่อนค่า alpha
    /// แทนที่จะไล่วาด gradient เต็มจอใหม่ทุกเฟรมตลอด 84 เฟรมของการบิน
    private var focusScrim: some View {
        RadialGradient(colors: [.clear, .black],
                       center: UnitPoint(x: 0.5, y: 0.46),
                       startRadius: 90, endRadius: 420)
            .ignoresSafeArea()
            .opacity(Map3DFocus.dimOpacity(focusProgress))
            .allowsHitTesting(false)
    }

    /// บอกครั้งเดียวว่าแท่งแดงกดได้ — ไม่มีอะไรบนจอบอกเลยว่าโมเดลนี้โต้ตอบได้
    private var hint: some View {
        VStack {
            Spacer()
            Text("map_tap_pin_hint")
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassSurface(Capsule())
                .tabBarClearance(extra: 16)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }


    // MARK: - โฟกัสหมุด

    /// คำใบ้โผล่ครั้งเดียวต่อการเปิดแอป แล้วจางไปเอง
    ///
    /// **ต้องผูกกับ `isActive` ไม่ใช่ `onAppear`** — `TabView` แบบ `Tab(value:)` ของ iOS 18+
    /// สร้างเนื้อของทุกแท็บตั้งแต่ตอน mount `onAppear` จึงยิงตั้งแต่ผู้ใช้ยังอยู่หน้า Home
    /// คำใบ้จะโชว์แล้วหมดเวลาไปก่อนที่ใครจะได้เห็น (ถ่ายจริงเจอแล้ว)
    private func showHintOnce() {
        guard !MapModelLoader.shared.hasShownPinHint else { return }
        MapModelLoader.shared.hasShownPinHint = true
        showsHint = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            showsHint = false
        }
    }

    /// ระยะใกล้สุดที่ยอมให้ตอนนี้ — ตอนจ้องหมุดเข้าใกล้ได้กว่าปกติ (ดู Map3DCamera.clampDistance)
    private var distanceFloor: Float {
        // ผูกกับ **วงแสง** ไม่ใช่การ์ด — `focusDistance` (0.55) ต่ำกว่า `minDistance` (0.8)
        // ตอน intro พาไปจอดที่ฐาน 1 โดยไม่เปิดการ์ด ถ้าพื้นยังผูกกับ `tappedSequence`
        // กล้องจะถูกดีดจาก 0.55 ขึ้น 0.8 ทันทีที่ผู้ใช้แตะจอครั้งแรก
        spotlightSequence == nil ? Map3DCamera.minDistance : Map3DCamera.focusDistance
    }

    /// กล้องอยู่ท่าอื่นที่ไม่ใช่ท่าเริ่มต้นหรือเปล่า — เกณฑ์หยาบ ๆ พอให้เข็มทิศโผล่ตอนที่ควรโผล่
    private var isOffDefaultAngle: Bool {
        abs(yaw - Map3DCamera.defaultYaw) > 0.05
            || abs(pitch - Map3DCamera.defaultPitch) > 0.05
            || tappedSequence != nil
    }

    private func resetAngle() {
        focusTask?.cancel()
        focusTask = nil
        tappedSequence = nil
        spotlightSequence = nil
        poseBeforeFocus = nil
        animate(to: Map3DPose(yaw: Map3DCamera.defaultYaw, pitch: Map3DCamera.defaultPitch,
                              distance: Map3DCamera.defaultDistance, target: .zero),
                over: Map3DFocus.returnDuration, dimTo: 0)
    }

    /// บินเข้าไปหาหมุดแล้วหมุนวนรอบมันจนกว่าผู้ใช้จะสั่งหยุด
    private func focus(on sequence: Int, at position: SIMD3<Float>) {
        focusTask?.cancel()
        showsHint = false
        // เก็บท่าเดิมไว้ครั้งแรกเท่านั้น — กดสลับหมุดไปมาแล้วเก็บทับทุกครั้ง ปิดการ์ดจะได้กลับไป
        // ท่า "จ้องหมุดอันก่อน" แทนที่จะเป็นมุมมองรวมที่ผู้ใช้จัดไว้ก่อนเริ่มกด
        if poseBeforeFocus == nil {
            poseBeforeFocus = Map3DPose(yaw: yaw, pitch: pitch, distance: distance, target: target)
        }
        tappedSequence = sequence
        spotlightSequence = sequence
        let destination = Map3DFocus.pose(forPinAt: position, currentYaw: yaw)
        focusTask = Task { @MainActor in
            await run(to: destination, over: Map3DFocus.flyDuration, dimTo: 1)
            await orbitForever()
        }
    }

    /// หมุนวนรอบสิ่งที่กล้องจ้องอยู่จนกว่าจะถูกยกเลิก
    ///
    /// อยู่ที่เดียวเพราะมีสองคนเรียก — ตอนแตะหมุด กับตอน intro พาไปจอดที่ฐาน 1
    /// · `base` คือมุมตอนบินถึง ไม่ใช่ 0 ไม่งั้นภาพกระโดดตอนเริ่มหมุน
    @MainActor
    private func orbitForever() async {
        guard !Task.isCancelled, !reduceMotion else { return }
        let base = yaw
        let started = CFAbsoluteTimeGetCurrent()
        while !Task.isCancelled {
            yaw = Map3DFocus.orbitYaw(base: base, elapsed: CFAbsoluteTimeGetCurrent() - started)
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    /// ปิดการ์ดแล้วคืนท่ากล้องเดิม
    private func endFocus() {
        focusTask?.cancel()
        focusTask = nil
        tappedSequence = nil
        spotlightSequence = nil
        // ม่านต้องหายแม้ไม่มีท่าเดิมให้บินกลับ — ไม่งั้นกดปิดการ์ดแล้วจอยังมืดค้างอยู่
        guard let previous = poseBeforeFocus else { focusProgress = 0; return }
        poseBeforeFocus = nil
        animate(to: previous, over: Map3DFocus.returnDuration, dimTo: 0)
    }

    /// ผู้ใช้เข้ามาคุมกล้องเอง — หยุดหมุนวน แต่ยังจ้องฐานเดิมอยู่ (การ์ดยังเปิด)
    /// ปิดการ์ดไปด้วยจะเป็นการลงโทษคนที่แค่อยากเอียงกล้องดูฐานนั้นเอง
    private func stopOrbit() {
        focusTask?.cancel()
        focusTask = nil
        // ม่านต้องกระโดดไปเข้มเต็มทันที — ลากจอกลางทางบินแล้วปล่อยม่านค้างครึ่งทางทั้งที่การ์ด
        // ยังเปิดอยู่ อ่านเป็นจอค้าง ไม่ใช่โฟกัส (ลูปที่กำลังไล่ค่าให้เพิ่งถูก cancel ไปเมื่อกี้)
        //
        // **เฉพาะตอนมีการ์ดเปิดอยู่** — ตอน intro พาไปจอดที่ฐาน 1 ไม่มีการ์ดและไม่มีม่าน
        // ลากจอตอนนั้นแล้วสั่งม่านเต็มจะได้จอมืดสนิทโดยไม่มีอะไรอธิบายว่าทำไม
        guard tappedSequence != nil else { return }
        focusProgress = 1
    }

    private func animate(to pose: Map3DPose, over duration: TimeInterval, dimTo: Float) {
        focusTask = Task { @MainActor in await run(to: pose, over: duration, dimTo: dimTo) }
    }

    /// เดินค่าเองทีละเฟรม ไม่ใช้ withAnimation — เหตุผลเดียวกับ `playIntroIfNeeded`:
    /// ค่ากล้องถูกอ่านใน update closure ของ RealityView การพึ่งว่า SwiftUI จะ re-run closure นั้น
    /// ครบทุกเฟรมตามค่า animated เป็นข้อสมมติที่พิสูจน์ไม่ได้จากโค้ด
    ///
    /// `dimTo` = ความเข้มม่านปลายทาง 0…1 — ม่านเกาะลูปนี้ไปด้วยแทนที่จะมีตัวขับของตัวเอง
    /// จะได้ถึงที่หมายพร้อมกล้องเสมอ ไม่ใช่ "เกือบพร้อม"
    @MainActor
    private func run(to pose: Map3DPose, over duration: TimeInterval, dimTo: Float) async {
        let from = Map3DPose(yaw: yaw, pitch: pitch, distance: distance, target: target)
        let dimFrom = focusProgress
        guard !reduceMotion else { apply(pose); focusProgress = dimTo; return }
        let started = CFAbsoluteTimeGetCurrent()
        while !Task.isCancelled {
            let elapsed = CFAbsoluteTimeGetCurrent() - started
            let progress = Float(min(elapsed / duration, 1))
            apply(Map3DFocus.frame(at: progress, from: from, to: pose))
            focusProgress = Map3DFocus.dim(at: progress, from: dimFrom, to: dimTo)
            if elapsed >= duration { return }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    private func apply(_ pose: Map3DPose) {
        yaw = pose.yaw
        pitch = pose.pitch
        distance = pose.distance
        target = pose.target
    }

    /// บินทะลุเมฆลงมาจอดที่ฐาน 1 แล้ววนรอบ — ครั้งแรกต่อการเปิดแอปเท่านั้น
    ///
    /// **ปลายทางเปลี่ยนจากกลางแผนที่เป็นฐานที่ 1 เมื่อ 2026-08-21** ตามคำขอของ Park ·
    /// ของเดิมร่อนลงมาแล้วนิ่งอยู่กลางแผนที่เฉย ๆ ไม่มีการวนรอบเลย (การวนรอบมีที่เดียวคือ
    /// ตอนแตะหมุด) · ตอนนี้ใช้ท่าปลายทางตัวเดียวกับตอนแตะหมุด (`Map3DFocus.pose`) แล้วต่อด้วย
    /// ลูปวนรอบตัวเดียวกัน — เปิดแอปมาจึงได้ภาพเดียวกับที่ผู้ใช้จะได้ถ้าแตะหมุดฐาน 1 เอง
    ///
    /// **ไม่มีม่านมืดและไม่เปิดการ์ด** (`dimTo: 0`, ไม่แตะ `tappedSequence`) — Park ขอให้เห็น
    /// แผนที่เต็มตา มีแค่วงแสงบอกว่ากำลังดูฐานไหน ส่วนการ์ดเปิดต่อเมื่อผู้ใช้แตะหมุดเอง
    ///
    /// `destination` เป็น nil เมื่อหาหมุดฐาน 1 ในโมเดลไม่เจอ (โมเดลถูกเปลี่ยนใบ หรือ
    /// `map_config.json` เพี้ยน) → ถอยไปร่อนลงจบกลางแผนที่แบบเดิม ไม่ใช่ค้างเหนือเมฆ
    ///
    /// เดินค่าเองทีละเฟรมแทน withAnimation เพราะกล้องถูกอ่านใน update closure ของ RealityView
    /// การพึ่งว่า SwiftUI จะ re-run closure นั้นตามค่า animated ให้ครบทุกเฟรมเป็นข้อสมมติที่
    /// พิสูจน์ไม่ได้จากโค้ด — `run(to:over:dimTo:)` ทำแบบนั้นอยู่แล้ว จึงยืมมาทั้งดุ้น
    @MainActor
    private func playIntroIfNeeded(to destination: Map3DPose?) {
        guard !MapModelLoader.shared.hasPlayedIntro else { return }
        MapModelLoader.shared.hasPlayedIntro = true

        let target = destination ?? Map3DPose(yaw: Map3DCamera.defaultYaw,
                                              pitch: Map3DCamera.defaultPitch,
                                              distance: Map3DCamera.defaultDistance,
                                              target: .zero)
        if destination != nil { spotlightSequence = 1 }

        // เปิด Reduce Motion ไว้ = ข้ามการบิน ไปอยู่ท่าปลายทางเลย และไม่วนรอบ
        // (ตรงกับที่ `focus(on:at:)` ทำอยู่)
        guard !reduceMotion else {
            apply(target)
            introFinished = true
            return
        }
        // **ต้องเป็น `focusTask` ตัวเดิม** — `focus()`, `endFocus()`, `resetAngle()` และ
        // `stopOrbit()` ทั้งสี่ยกเลิกงานผ่านตัวนี้ · มีตัวที่สองเมื่อไหร่ ลากจอตอน intro
        // ยังบินอยู่จะได้กล้องสองแรงแย่งกันทุกเฟรม
        focusTask = Task { @MainActor in
            await run(to: target, over: Map3DIntro.duration, dimTo: 0)
            introFinished = true
            await orbitForever()
        }
    }

    private var mapView: some View {
        RealityView { content in
            let root = Entity()
            content.add(root)

            // เอาของที่ Home สั่งโหลดล่วงหน้าไว้ — ถ้ายังไม่เสร็จก็รอรอบเดิม ไม่เริ่มโหลดใหม่ซ้อน
            // (ดู MapModelLoader ว่าทำไมต้องโหลดล่วงหน้า และทำไมไม่ clone)
            guard let map = await MapModelLoader.shared.model() else {
                await MainActor.run { loadFailed = true; isLoading = false }
                return
            }
            // ถูกแขวนอยู่กับ root ของรอบก่อนได้ถ้า view ถูก mount ซ้ำ — ปลดก่อนเสมอ
            // ไม่งั้นจะได้โมเดลค้างอยู่สองที่หรือ addChild ซ้ำ
            map.removeFromParent()
            map.name = "Map"

            // โมเดลเป็นเมตรจริง รัศมีราว 1.9 กม. — ย่อให้ทั้งก้อนพอดีกรอบ `normalisedSpan` หน่วย
            // ก่อนค่อยให้ camera controls จัดการระยะ ไม่งั้นกล้องเริ่มต้นจะอยู่ในเนื้อโมเดล
            //
            // ⚠️ ต้องล้าง scale/position ให้กลับสภาพเดิม "ก่อน" วัด — `make` ถูกเรียกซ้ำกับ entity
            // ตัวเดิมได้จริง (ล็อกเอาต์แล้วล็อกอินใหม่ในโปรเซสเดียว ดูคอมเมนต์ของ MapModelLoader)
            // และ `visualBounds(relativeTo: nil)` นับ transform ของตัว entity เองเข้าไปด้วย
            // รอบสองจึงได้ extents ที่ย่อไปแล้ว (≈2) กลับมา widest กลายเป็น ≈2 แล้วสเกลถูกตั้งใหม่
            // เป็น ≈1 — โมเดลโตขึ้น 2,584 เท่าในเฟรมเดียว กล้องไปจมอยู่ในเนื้อภูมิประเทศ ได้จอ
            // สีน้ำตาลทึบทั้งจอโดยไม่มี error สักบรรทัด (พิสูจน์ด้วยการรันจริง ไม่ใช่การอ่านโค้ด:
            // log รอบสองตอบ extents ≈ 2.00 × 0.57 × 2.00 — ดู docs/map-2-0-verification.md)
            //
            // ล้างแค่สองตัวนี้พอ เพราะเป็นสองตัวเดียวที่โค้ดก้อนนี้เขียนลง `map` · orientation
            // ห้ามแตะ RealityKit ตั้งค่าแปลง Z-up→Y-up ไว้ให้ตั้งแต่ตอนโหลดแล้ว
            map.scale = .one
            map.position = .zero
            // การหมุนหันทิศพื้นที่งานก็ค้างข้ามรอบเหมือนกัน — มันถูกตั้งไว้ที่ "โหนดเนื้อโมเดล"
            // (ลูกตัวเดียวของ `map` ดูคอมเมนต์ยาวที่ `dotParent` ข้างล่าง) ตอนท้ายของ make
            // ไม่ล้างก่อนวัด รอบสองจะได้ extents ที่แกน x/z สลับกัน `widest` เท่าเดิมก็จริง
            // (แผ่นเกือบจัตุรัส) แต่ `bounds.center` สลับตาม จุดกึ่งกลางเลื่อนไปราว 11 px บนจอ
            // — วัดจากภาพสองรอบแล้ว ไม่ใช่การคาดเดา
            (map.children.first ?? map).orientation =
                simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
            // ลบ entity ที่ **เราแขวนเพิ่มเอง** รอบก่อนทิ้งก่อนวัด — สองตัวนี้ไม่ได้มากับไฟล์โมเดล
            // แต่แขวนอยู่ใต้ `map` ซึ่งเป็น entity ตัวเดิมข้ามการ mount ถ้าไม่ลบก่อน มันถูกนับเข้าไป
            // ใน extents ที่ใช้คำนวณสเกล · จุดฟ้าเคยถูกลบทีหลังบรรทัดนี้ ซึ่งไม่มีอาการเพราะบังเอิญ
            // มันอยู่ในกรอบพอดี ไม่ใช่เพราะออกแบบไว้ — ไฮไลต์หมุดอยู่ที่ขอบนอกของหมุดซึ่งเข้าใกล้
            // ขอบแผ่นกว่ามาก ย้ายมาลบพร้อมกันตรงนี้ให้การวัดพิสูจน์ได้ว่าไม่ถูกกวน
            //
            // `map.findEntity(named:)` ค้นทั้งซับทรี จึงเจอไฮไลต์แม้มันถูกย้ายไปแขวนใต้ `marker_N` แล้ว
            map.findEntity(named: "UserDot")?.removeFromParent()
            map.findEntity(named: Self.pinHighlightName)?.removeFromParent()

            let bounds = map.visualBounds(relativeTo: nil)
            let widest = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
            if widest > 0 { map.scale = SIMD3<Float>(repeating: Self.normalisedSpan / widest) }
            map.position = -bounds.center * map.scale.x

            // usdz นี้ประกาศ upAxis = "Z" จริง (ตรวจด้วย usdcat) แต่ Entity(named:) ของ
            // RealityKit แปลงให้เป็น Y-up ให้เองตั้งแต่โหลด — วัดจาก visualBounds ก่อนตัวโค้ด
            // นี้แตะต้องอะไรเลย: แกน Y (สูง 664 ม.) เตี้ยกว่า X/Z (กว้าง 4470×5162 ม.) มาก
            // ตรงกับความสูงภูมิประเทศจริง ไม่ใช่ด้านกว้างของพื้นที่ จึงไม่ต้องหมุนแก้ Z-up/Y-up

            root.addChild(map)

            // เมฆของ Map2.0 มีคีย์แอนิเมชันของ Blender ติดมา (stage 1…280 เฟรม ที่ 24 fps)
            // RealityKit ไม่เล่นให้เอง ต้องสั่ง · ไล่ทั้งต้นเพราะ Blender ยัดคีย์ไว้ที่ `cloud_*`
            // ทีละก้อน ไม่ใช่คลิปเดียวที่ราก — เรียกแค่ที่ `map` ตัวเดียวจะได้เมฆค้างนิ่งทั้งฟ้า
            //
            // ถ้า RealityKit ไม่แปลง timeSamples ให้เป็น availableAnimations ลูปนี้ก็ไม่ทำอะไรเลย
            // เมฆค้างนิ่ง แผนที่ยังใช้ได้ทุกอย่าง — เป็นข้อจำกัดที่ยอมรับไว้แล้ว ไม่ต้องเขียน
            // แอนิเมชันเองมาแทน (ดู docs/superpowers/specs/2026-08-20-map-2-0-design.md §8)
            //
            // เช็คธงก่อนไล่ต้น: MapModelLoader คืน entity ตัวเดิมทุกครั้ง ไม่ clone แต่ make closure
            // นี้ถูกเรียกซ้ำได้กับ entity ตัวเดิมนั้น — **ไม่ใช่ตอนสลับแท็บ** (TabView ของ iOS 18
            // ถือ view ของทุกแท็บไว้ สลับไปกลับแล้ว make ไม่ถูกเรียกซ้ำ) แต่ตอน **ล็อกเอาต์แล้ว
            // ล็อกอินใหม่ในโปรเซสเดียว**: RootView แขวน MainTabView ไว้เฉพาะตอน session อยู่ที่
            // .home จอนี้จึงถูกทำลายและสร้างใหม่ ขณะที่ MapModelLoader.shared เป็น singleton
            // อายุเท่าแอป ไม่มีอะไรในเส้นทาง logout ล้างมันเลย · ถ้าไล่ต้นซ้ำจะสั่ง playAnimation
            // ทับแอนิเมชันที่กำลังเล่นอยู่ ทำให้เมฆกระตุกกลับไปเฟรม 0 แล้วซ้อน playback controller
            // ตัวใหม่ทับตัวเดิมที่ไม่มีใครหยุด (ดูธงที่ MapModelLoader)
            if !MapModelLoader.shared.hasStartedCloudAnimations {
                var pending = [map]
                while let entity = pending.popLast() {
                    for animation in entity.availableAnimations {
                        entity.playAnimation(animation.repeat())
                    }
                    pending.append(contentsOf: entity.children)
                }
                MapModelLoader.shared.hasStartedCloudAnimations = true
            }

            // โดมฟ้า + ชั้นเมฆ — แขวนใต้ root ไม่ใช่ใต้ map เพราะไม่ควรหมุนตาม
            // cameraFramingYaw ที่ใช้หันทิศพื้นที่งาน (ท้องฟ้าไม่มีทิศ)
            //
            // ไม่ต้องเช็คว่ามีโดมอยู่แล้วหรือยัง: `root` ถูก `Entity()` ขึ้นใหม่ที่หัวของ make ทุกรอบ
            // ของซ้อนกันจึงเกิดไม่ได้ — เคยมี `if root.findEntity(named:) == nil` คร่อมอยู่ตรงนี้
            // ซึ่งค้นบน root ที่เพิ่งสร้างเปล่า ๆ เลยตอบ nil เสมอ ไม่เคยกันอะไรได้เลยสักครั้ง
            // ของที่ซ้อนได้จริงคือของที่แขวนใต้ `map` ต่างหาก เพราะ map เป็น entity ตัวเดิมที่ถูก
            // ใช้ซ้ำข้ามรอบ (ดูจุดที่ลบ UserDot ตัวเก่าทิ้งก่อนสร้างใหม่)
            root.addChild(Map3DSky.build())

            // ให้ทั้งแท่งหมุดและเลขที่ปั้นติดหมุดแตะได้ — ต้องมีทั้งสองคอมโพเนนต์ ขาดตัวใดตัวหนึ่ง
            // tap ไม่เข้า
            //
            // สรุปเป็นบรรทัดเดียวว่า "ได้กี่จากกี่ชื่อ" แทนการ log เฉพาะชื่อที่หาย: รอบก่อนสรุปว่า
            // ชื่อครบทั้ง 16 จากการที่ตัวกรอง log stream ไม่พิมพ์อะไรออกมาเลย ทั้งที่การรันรอบเดียวกัน
            // นั้นพิสูจน์แล้วว่า unified log กลืนบรรทัดที่ยิงจริงไปแปดบรรทัด — "ไม่เห็นอะไร" ผ่าน
            // เครื่องมือที่ทำหลุดเป็นปกติไม่ใช่หลักฐานว่าไม่มีอะไร แต่ "16 จาก 16" เป็นหลักฐาน
            //
            // และธงแดงจริงอยู่ที่ assertionFailure: ชื่อที่หายไปแปลว่าฐานนั้นแตะไม่ติดทั้งฐาน ซึ่ง
            // อ่านจากจอไม่ออกเลยว่าพัง (หมุดยังขึ้นครบ แค่กดแล้วเงียบ) ต้องให้มันหยุดคนที่รัน Debug
            let pinNames = Map3DPins.entityNames
            var missingPinNames: [String] = []
            for name in pinNames {
                guard let pin = map.findEntity(named: name) else {
                    missingPinNames.append(name)
                    continue
                }
                let bounds = pin.visualBounds(relativeTo: pin)
                pin.components.set(CollisionComponent(shapes: [
                    .generateBox(size: bounds.extents).offsetBy(translation: bounds.center)
                ]))
                pin.components.set(InputTargetComponent())
            }
            NSLog("[Map3DScreen] ติดปุ่มแตะให้หมุดได้ %d จาก %d ชื่อ",
                  pinNames.count - missingPinNames.count, pinNames.count)
            #if DEBUG
            if !missingPinNames.isEmpty {
                assertionFailure("ไม่พบชื่อหมุดในโมเดล: \(missingPinNames.joined(separator: ", "))")
            }
            #endif

            // จุดตำแหน่งผู้ใช้ — สร้างไว้ก่อนแล้วซ่อน ค่อยย้ายตอนมีพิกัดจริง
            // (สร้างทีหลังใน update closure ไม่ได้ เพราะ closure นั้นถูกเรียกทุกเฟรม)
            //
            // ต้องอยู่ในสาย transform hierarchy เดียวกับโมเดล ไม่ใช่ของ `root` — ตามกติกาที่
            // คอมเมนต์ของ cameraFramingYaw เขียนไว้ ไม่งั้นจุดจะไม่หมุนตามโมเดลตอนที่ map ถูกหมุน
            // ตาม cameraFramingYaw (ค่าจาก map_config.json)
            //
            // ⚠️ พิสูจน์แล้วด้วยการทดลองจริง (ไม่ใช่แค่คาดเดา) ว่า `map.addChild(dot)` ตรงๆ ใช้
            // ไม่ได้ — entity ที่เป็นลูกโดยตรงของ `map` (ตัว wrapper ที่ Entity(named:) คืนมา)
            // ไม่ถูกวาดเลย ทั้งที่ isEnabled = true, ตำแหน่ง/ขนาดสมเหตุสมผล และ transform
            // hierarchy ถูกต้องทุกอย่าง (ทดสอบแล้ว: ก้อนทรงกลมลอยอยู่กลางฟ้าเหนือโมเดล ไม่โผล่มา
            // เลย) แต่พอแตะเป็นลูกของ `map.children.first` (entity ชื่อ "root" ที่ Entity(named:)
            // แนบไว้เป็นลูกเดียวของ map ตรงกับ defaultPrim = "root" ที่ usdcat ยืนยันไว้ตอน Task 1
            // — เป็นที่ที่เนื้อโมเดลจริง (ภูมิประเทศ + แท่งแดงทั้ง 8) อาศัยอยู่) กลับเรนเดอร์ปกติทันที
            // สาเหตุที่แท้จริงไม่ทราบ (อาจเป็น RealityKit ไม่รวม direct child ใหม่ของ entity ที่
            // โหลดจากไฟล์เข้า render/cull pass เดียวกับเนื้อหาเดิม) แนบใต้ "root" นี้ปลอดภัยเพราะ
            // transform ของมันเป็น identity เทียบกับ map พอดี (position/scale/orientation
            // ยืนยันด้วย NSLog แล้ว) พิกัด local ที่คำนวณเทียบกับ map จึงใช้ได้ตรงๆ ไม่ต้องแปลงซ้ำ
            let dotParent = map.children.first ?? map
            // หันทิศพื้นที่งาน — หมุนโหนดเนื้อโมเดลรอบแกนตั้งของตัวเอง (Z) ดูคอมเมนต์ที่
            // cameraFramingYaw ว่าทำไมหมุนที่นี่ ไม่ใช่หมุน `map` รอบแกน Y ของโลก
            dotParent.orientation = simd_quatf(angle: Self.cameraFramingYaw,
                                               axis: SIMD3<Float>(0, 0, 1))
            let dot = ModelEntity(
                mesh: .generateSphere(radius: Self.dotRadiusOnScreen / map.scale.x),
                materials: [UnlitMaterial(color: .systemBlue)]
            )
            dot.name = "UserDot"
            dot.isEnabled = false
            // ตัวเก่าถูกลบไปแล้วตอนต้น make (ก่อนวัด visualBounds) — ไม่ลบทิ้งก็ได้จุดฟ้าเพิ่มขึ้น
            // ทีละลูกทุกรอบที่ mount ใหม่ และ `findEntity(named:)` ใน update ก็จับได้แค่ลูกเดียว
            // ที่เหลือค้างอยู่ตำแหน่งเก่าโดยไม่มีใครขยับหรือปิดมันอีกเลย
            dotParent.addChild(dot)

            // ไฮไลต์หมุดที่เลือก — จานกลมแบนสีทองวางที่โคนหมุด
            //
            // ทำไมเป็น entity แยกที่ย้ายพ่อ ไม่ใช่การสลับ material ของหมุดเอง: `MapModelLoader`
            // คืน entity ตัวเดิมตลอดอายุแอปและไม่เคย clone การสลับวัสดุจึงเป็นการแก้ของที่ใช้ร่วมกัน
            // ต้องรับประกันคืนค่าครบทุกทางออก ซึ่งจอนี้มีอย่างน้อยหกทาง (ปิดการ์ด, กดเข็มทิศ,
            // ลากจอ, ออกจากแท็บ, ล็อกเอาต์แล้วล็อกอินใหม่, ระบบเตือนความจำ) พลาดทางเดียว
            // หมุดค้างสีผิดถาวรโดยไม่มี error ไม่มีเทส · แบบนี้ย้อนกลับด้วยการปิดสวิตช์ตัวเดียว
            //
            // ⚠️ `generatePlane(width:height:)` ให้ระนาบใน **XY** normal +Z ซึ่งใต้ `dotParent`
            // ยังเป็นสเปซ USD ที่เป็น **Z-up** อยู่ (ตัวแปลง Z-up→Y-up อบไว้ที่ entity ตัวนอก)
            // จานจึงราบกับพื้นโดยไม่ต้องหมุนเลย · ห้ามใช้ `generatePlane(width:depth:)` ซึ่งเป็น
            // ระนาบ XZ normal +Y — อันนั้นจะตั้งจานขึ้นมาตะแคง
            // สีเขียนตรง ๆ ไม่ใช้โทเคนจาน สี — แพทเทิร์นเดียวกับจุดผู้ใช้ (`.systemBlue`) และโดมฟ้า
            // (`Map3DSky.skyColor`) เพราะนี่คือของในฉาก 3D ไม่ใช่ chrome ของ UI ที่ต้องปรับตามธีม ·
            // เคยลอง `Color.wbwGold` แล้วได้จานสีขาวนวล: โทเคนนั้นถูกชี้ไป `wbwAccent` ตั้งแต่รอบ
            // ที่พาเลตต์ตัดเฉดทองออก (`Config.swift:212` และคอมเมนต์เหนือมันบอกไว้ว่าโค้ดใหม่ห้ามใช้)
            // ในโหมดมืดมันคือ #E9EEE0 · อำพันอ่านออกบนพื้นเขียวทั้งกลางวันกลางคืน
            var highlightMaterial = UnlitMaterial(
                color: UIColor(red: 1.0, green: 0.84, blue: 0.35, alpha: 1))
            highlightMaterial.blending = .transparent(opacity: 0.9)
            highlightMaterial.faceCulling = .none
            let highlight = ModelEntity(
                mesh: .generatePlane(width: Self.pinHighlightRadius * 2,
                                     height: Self.pinHighlightRadius * 2,
                                     cornerRadius: Self.pinHighlightRadius),
                materials: [highlightMaterial])
            highlight.name = Self.pinHighlightName
            highlight.isEnabled = false
            dotParent.addChild(highlight)

            #if DEBUG
            NSLog("[Map3DScreen] map.visualBounds = %@", String(describing: bounds))
            NSLog("[Map3DScreen] map.children.count = %d", map.children.count)
            #endif

            let sun = DirectionalLight()
            sun.light.intensity = 4000
            sun.look(at: .zero, from: SIMD3<Float>(2, 4, 2), relativeTo: nil)
            root.addChild(sun)

            // ไฟเติมจากฝั่งตรงข้าม — ด้านเงาของอาคารไม่ดำสนิท (ทรงเดียวกับ ForestSceneView)
            let fill = DirectionalLight()
            fill.light.intensity = 1200
            fill.look(at: .zero, from: SIMD3<Float>(-3, 2, -3), relativeTo: nil)
            root.addChild(fill)

            // กล้องของเราเอง ไม่ใช่ .realityViewCameraControls(.orbit) — ตัวนั้นปล่อยให้ผู้ใช้
            // มุดลงไปมองใต้โมเดล (เห็นก้นภูมิประเทศเป็นแผ่นตัดเปล่า) และไม่มี API จำกัดมุมหรือ
            // ตั้งทิศเริ่มต้น ขอบเขตทั้งหมดอยู่ที่ Map3DCamera
            let camera = PerspectiveCamera()
            camera.name = "Camera"
            camera.camera.fieldOfViewInDegrees = 50
            camera.camera.near = 0.01
            camera.camera.far = 100
            root.addChild(camera)

            await MainActor.run {
                // ตั้งกล้องไว้ที่จุดเริ่มของ intro "ก่อน" ปิดจอโหลด ไม่งั้นจะเห็นภาพมุมปกติแวบนึง
                // แล้วค่อยกระโดดขึ้นไปเหนือเมฆ
                if !MapModelLoader.shared.hasPlayedIntro {
                    apply(Map3DIntro.startPose)
                }
                isLoading = false
                // ปลายทางของ intro = หมุดฐาน 1 · อ่านตำแหน่งที่นี่เพราะเป็นจุดแรกที่ทั้งโมเดลพร้อม
                // และยังอยู่บน main actor (ที่เดียวกับที่ `-uitestMapPin` ใช้อยู่แล้วข้างล่าง)
                let firstBase = Map3DPins.primaryEntityName(for: 1)
                    .flatMap { map.findEntity(named: $0) }
                    .map { Map3DFocus.pose(forPinAt: $0.position(relativeTo: nil),
                                           currentYaw: Map3DCamera.defaultYaw) }
                playIntroIfNeeded(to: firstBase)

                #if DEBUG
                // บินไปหาหมุดที่ -uitestMapPin สั่งไว้ ทำที่นี่เพราะเป็นจุดแรกที่ทั้งโมเดลพร้อมและ
                // ยังอยู่บน main actor · ตำแหน่งอ่านใน scene space ตัวเดียวกับที่ตัวจัดการแตะใช้
                if let forced = pendingForcedPin {
                    pendingForcedPin = nil
                    if let name = Map3DPins.primaryEntityName(for: forced),
                       let marker = map.findEntity(named: name) {
                        focus(on: forced, at: marker.position(relativeTo: nil))
                    } else {
                        tappedSequence = forced
                    }
                }
                #endif
            }
        } update: { content in
            guard let root = content.entities.first,
                  let map = root.findEntity(named: "Map") else { return }

            // ไฮไลต์หมุด — อ่านจาก `tappedSequence` ตรง ๆ ไม่ได้สั่งจาก `focus()`
            //
            // ทางเข้า/ออกของการเลือกหมุดมีสี่ทาง (แตะหมุด, ปิดการ์ด, กดเข็มทิศ, สลับไปหมุดอื่น)
            // แต่ทั้งสี่ไหลผ่าน `@State` ตัวเดียวกันนี้ ผูกกับมันจึงคุมครบโดยไม่ต้องเขียนอะไรเพิ่ม —
            // รวมถึงกรณีที่ `stopOrbit()` **ตั้งใจ**ไม่เคลียร์ค่า (ลากจอแล้วการ์ดยังเปิด) ซึ่งไฮไลต์
            // ก็ต้องอยู่ต่อ ถ้าสั่งจาก focus() ต้องไปจำกรณีนี้เองอีกที
            //
            // ธงใน MapModelLoader กันไม่ให้ไล่ `findEntity(named:)` บนต้นไม้ 2,201 ก้อนทุกเฟรม —
            // เข้าเฉพาะเฟรมที่ฐานที่เลือกเปลี่ยนจริง
            if MapModelLoader.shared.highlightedSequence != spotlightSequence {
                MapModelLoader.shared.highlightedSequence = spotlightSequence
                if let highlight = map.findEntity(named: Self.pinHighlightName) {
                    if let sequence = spotlightSequence,
                       let markerName = Map3DPins.primaryEntityName(for: sequence),
                       let marker = map.findEntity(named: markerName) {
                        // ย้ายพ่อ (idempotent — RealityKit ถอดออกจากพ่อเดิมให้เอง) เพื่อรับตำแหน่ง
                        // กับการเอียงตามภูมิประเทศของหมุดมาฟรี ๆ ไม่ต้องคำนวณเอง
                        marker.addChild(highlight)
                        // สูงจากฐานหมุดพอให้พ้นผิวภูมิประเทศที่ไม่เรียบ · แกน Z คือขึ้น เพราะข้างใน
                        // โมเดลยังเป็นสเปซ USD ที่เป็น Z-up · เคยตั้งไว้ 1 แล้วจานจมอยู่ในเนินดิน
                        // เห็นโผล่มาแค่เสี้ยวเดียวตรงที่พื้นเว้าลง (ถ่ายเทียบแล้ว ไม่ใช่การคาดเดา) ·
                        // 6 ยังต่ำกว่าความสูงหมุด (34) มาก จึงยังอ่านเป็นแสงกองที่โคน ไม่ใช่จานลอย
                        highlight.position = SIMD3<Float>(0, 0, 6)
                        highlight.isEnabled = true
                    } else {
                        highlight.isEnabled = false
                    }
                }
            }

            // เมฆเป็นของสำหรับ intro — ปิดเมื่อเล่นจบ ไม่งั้นมุมกล้องต่ำจะมองทะลุชั้นเมฆ
            // เห็นแผนที่เป็นสีจาง ๆ ทั้งจอ (เจอจากสกรีนช็อตรอบแรก)
            if let clouds = root.findEntity(named: Map3DSky.cloudsName) {
                clouds.isEnabled = !introFinished
            }

            if let heading = headingOverride, let content = map.children.first {
                content.orientation = simd_quatf(angle: heading * .pi / 180,
                                                 axis: SIMD3<Float>(0, 0, 1))
            }

            // ขยับกล้องที่เราวางเอง — `PerspectiveCamera` ชื่อ "Camera" ที่สร้างไว้ในฟังก์ชัน make
            //
            // ⚠️ ห้ามตั้ง `content.camera = .virtual` — ลองมาแล้วและมันทำให้ RealityView เมินกล้อง
            // ตัวนี้ทั้งดุ้น กลับไปเรนเดอร์ด้วยกล้องปริยายที่จัดเฟรมเองจากบนหัว (log ยืนยันว่ากล้องถูกวาง
            // ถูกตำแหน่งทุกครั้ง แต่ภาพไม่ขยับสักพิกเซล) **ไม่ตั้งเลยคือถูกแล้ว**
            //
            // เคยมีคอมเมนต์ตรงนี้เขียนไว้ว่า "RealityView บน iOS เมินกล้องในฉาก ต้องหมุน root แทน"
            // ซึ่งเน่าไปแล้ว: โค้ดไม่ได้หมุน `root` เลย มีแต่ `camera.look(...)` บรรทัดล่างนี้ และ
            // ตอนปรับระยะกล้องรอบ 2026-08-21 พิสูจน์ด้วยการฉายภาพแล้วว่ากล้องตัวนี้คือตัวที่เรนเดอร์จริง —
            // คำนวณตำแหน่งบนจอของ `markerNum_5` จากสูตรกล้องแล้วตรงกับพิกเซลในสกรีนช็อตจริง
            if let camera = root.findEntity(named: "Camera") {
                let eye = Map3DCamera.position(yaw: yaw, pitch: pitch,
                                               distance: distance, target: target)
                camera.look(at: target, from: eye, relativeTo: nil)
            }

            guard let dot = map.findEntity(named: "UserDot") else { return }
            let anchor = Map3DConfig.current.anchor
            guard let coordinate = location.coordinate,
                  let point = Map3DGeo.modelUnits(latitude: coordinate.latitude,
                                                  longitude: coordinate.longitude,
                                                  in: anchor) else {
                dot.isEnabled = false
                return
            }
            dot.isEnabled = true
            // จุดอยู่ใน local space ของโมเดล ซึ่งเป็น Z-up ตามที่ usdz เขียนมา (usdcat: upAxis = "Z")
            // และเป็นเมตร Web Mercator ตรง ๆ — ตัวแปลง Z-up→Y-up ของ RealityKit ถูกอบไว้ใน
            // transform ของ entity ตัวนอกที่ Entity(named:) คืนมา ไม่ได้แก้พิกัดของเนื้อโมเดลข้างใน
            // ดังนั้นในนี้ x = ตะวันออก-ตะวันตก · y = เหนือ-ใต้ · z = ความสูง
            //
            // **ไม่พึ่ง visualBounds อีกแล้ว** ใบก่อนคูณสัดส่วน −1…1 เข้ากับครึ่ง extents ของทั้ง
            // โมเดล พอ Map2.0 มีเมฆลอยสูง 1160 หน่วยเข้ามา ครึ่ง extents ก็โตตาม จุดจะไปลอย
            // เหนือเมฆทันทีโดยไม่มีอะไรฟ้อง · ผูกกับ anchor แล้วใส่อะไรเพิ่มในโมเดลก็ไม่ขยับจุด
            //
            // ⚠️ เครื่องหมายของ y พิสูจน์ด้วยภาพจริง ไม่ใช่ด้วยเหตุผล — ใบก่อนต้องกลับเครื่องหมาย
            // พร้อมคอมเมนต์ว่าแกน Y/Z ที่ visualBounds ตอบสลับกับที่เห็นบนจอ และ "สาเหตุที่แท้จริง
            // ไม่ทราบ" · รอบนี้ตรวจด้วยการป้อนพิกัดของหมุดฐานที่ 5 (20.04454, 99.90955) เป็น
            // ตำแหน่งปลอมแล้วดูว่าจุดทับหมุดเลข 5 ไหม (docs/map-2-0-verification.md ข้อ 4)
            dot.position = SIMD3<Float>(point.x, point.y, anchor.userDotHeightUnits)
        }
        // ลากนิ้ว = กวาด/เงย · หุบนิ้ว = ระยะ · ทุกค่าผ่าน clamp ของ Map3DCamera ก่อนเสมอ
        // simultaneousGesture เพื่อให้ไม่ไปแย่ง SpatialTapGesture ของหมุดด้านล่าง
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    // ผู้ใช้เข้ามาคุมเอง — หยุดหมุนวนทันที ไม่งั้นกล้องสองแรงแย่งกันทุกเฟรม
                    stopOrbit()
                    let startYaw = gestureStartYaw ?? yaw
                    let startPitch = gestureStartPitch ?? pitch
                    if gestureStartYaw == nil { gestureStartYaw = startYaw }
                    if gestureStartPitch == nil { gestureStartPitch = startPitch }
                    // 0.004 เรเดียนต่อพอยต์ — ลากเต็มความกว้างจอ (~390 pt) ได้ราว 90°
                    // หมุนครบรอบใช้สี่ครั้ง ซึ่งพอดีกับการ "กวาดดูรอบ ๆ" ไม่ใช่ปั่นจนเวียนหัว
                    yaw = Map3DCamera.wrapYaw(startYaw - Float(value.translation.width) * 0.004)
                    // ลากขึ้น = เงยขึ้นมองจากสูงลงมา (ทิศเดียวกับที่แอปแผนที่ทั่วไปทำ)
                    pitch = Map3DCamera.clampPitch(startPitch + Float(value.translation.height) * 0.004)
                }
                .onEnded { _ in
                    gestureStartYaw = nil
                    gestureStartPitch = nil
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    stopOrbit()
                    let start = gestureStartDistance ?? distance
                    if gestureStartDistance == nil { gestureStartDistance = start }
                    // หุบนิ้วออก (magnification > 1) = เข้าใกล้ ระยะจึงหารไม่ใช่คูณ
                    //
                    // ตอนโฟกัสหมุดอยู่ ปล่อยให้อยู่ใกล้ได้เท่าที่โค้ดพาเข้ามา — ใช้ minDistance ตรง ๆ
                    // แล้วนิ้วแรกที่แตะจะดีดกล้องถอยออกทันที ทั้งที่ผู้ใช้แค่อยากเอียงดูฐานนั้น
                    distance = Map3DCamera.clampDistance(start / Float(value.magnification),
                                                         floor: distanceFloor)
                }
                .onEnded { _ in gestureStartDistance = nil }
        )
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // ไต่ขึ้นหา entity ที่อยู่ในตาราง — collision อาจโดนลูกของแท่ง ไม่ใช่ตัวแท่งเอง
                    var node: Entity? = value.entity
                    while let current = node {
                        if let sequence = Map3DPins.sequence(forEntityNamed: current.name) {
                            // โฟกัสที่ "แท่งหลัก" เสมอ ไม่ใช่ entity ที่นิ้วโดน — แตะเลขที่ปั้นลอย
                            // อยู่เหนือแท่งแล้วกล้องจะไปจ้องกลางอากาศ ไม่ใช่ตัวฐาน
                            //
                            // ไต่ขึ้นไปหาโหนดบนสุดก่อนแล้วค่อย findEntity เพราะ `map` ไม่ได้อยู่ใน
                            // สโคปของ gesture closure และ markerNum_N เป็นพี่น้องของ marker_N
                            // ไม่ใช่ลูก — หาจาก parent ตรง ๆ ไม่เจอ
                            var top = current
                            while let parent = top.parent { top = parent }
                            let anchorEntity = Map3DPins.primaryEntityName(for: sequence)
                                .flatMap { top.findEntity(named: $0) } ?? current
                            // อ่านตำแหน่งหมุดใน scene space ตรงนี้เลย — เป็นสเปซเดียวกับที่กล้องใช้
                            // (`camera.look(at:from:relativeTo: nil)`) ไม่ต้องแปลงอะไรอีก
                            focus(on: sequence, at: anchorEntity.position(relativeTo: nil))
                            return
                        }
                        node = current.parent
                    }
                }
        )
        .onAppear {
            #if DEBUG
            // ลองมุมกล้องหลายค่าแล้วถ่ายเทียบกับภาพอ้างอิงโดยไม่ต้อง build ใหม่ทุกครั้ง
            // (หน่วยเป็นองศา · หมุนโมเดล ไม่ใช่หมุนกล้อง เพราะทิศของพื้นที่งานอบอยู่ในโมเดล)
            if UserDefaults.standard.object(forKey: "uitestMapHeading") != nil {
                headingOverride = Float(UserDefaults.standard.integer(forKey: "uitestMapHeading"))
            }
            // ลองมุมเงยหลายค่าแล้วถ่ายเทียบภาพอ้างอิง โดยไม่ต้อง build ใหม่ทุกครั้ง (หน่วยองศา)
            //
            // ต้องปิด intro ไปด้วย ไม่งั้นค่าที่ตั้งตรงนี้ไร้ผล: intro เดินค่า pitch/distance ทับทุก
            // เฟรมแล้วจบที่ defaultPitch เสมอ · เจอจริงตอนถ่ายเทียบ — สั่ง -uitestMapPitch 8 แล้วได้
            // ภาพเหมือนมุมปกติเป๊ะทุกพิกเซล ไม่มีอะไรฟ้องว่าแฟลกถูกกลืน
            if UserDefaults.standard.object(forKey: "uitestMapPitch") != nil {
                MapModelLoader.shared.hasPlayedIntro = true
                introFinished = true
                pitch = Map3DCamera.clampPitch(
                    Float(UserDefaults.standard.integer(forKey: "uitestMapPitch")) * .pi / 180)
            }
            // ระยะกล้องสำหรับถ่ายเทียบตอนซูมสุดสองทาง · หน่วยเป็น "ร้อยเท่า" เพราะ launch arg
            // ที่ simctl ส่งมาอ่านเป็น Int ได้อย่างเดียว (0.8 ส่งไม่ได้ ต้องส่ง 80)
            // กวาดมุมรอบตัวเพื่อถ่ายเทียบว่าไม่มีทิศไหนเห็นขอบโมเดล (หน่วยองศา 0-359)
            if UserDefaults.standard.object(forKey: "uitestMapYaw") != nil {
                MapModelLoader.shared.hasPlayedIntro = true
                introFinished = true
                yaw = Map3DCamera.wrapYaw(
                    Float(UserDefaults.standard.integer(forKey: "uitestMapYaw")) * .pi / 180)
            }
            if UserDefaults.standard.object(forKey: "uitestMapDistance") != nil {
                MapModelLoader.shared.hasPlayedIntro = true
                introFinished = true
                distance = Map3DCamera.clampDistance(
                    Float(UserDefaults.standard.integer(forKey: "uitestMapDistance")) / 100)
            }
            #endif
            if isActive { showHintOnce() }
            // บอก loader ว่าโมเดลกำลังถูกใช้อยู่ — ตอนระบบเตือนความจำมันจะได้ไม่ปล่อย entity
            // ที่แขวนอยู่ในฉากที่กำลังเรนเดอร์ทิ้ง (แผนที่จะหายไปเฉย ๆ ไม่มี error ให้เห็น)
            MapModelLoader.shared.isInUse = isActive
        }
        .onChange(of: isActive) { _, nowActive in
            MapModelLoader.shared.isInUse = nowActive
            if nowActive { showHintOnce() }
        }
        .onDisappear {
            MapModelLoader.shared.isInUse = false
            // ไม่ยกเลิกแล้วมันหมุนวนต่ออยู่เบื้องหลังหลังออกจากแท็บไปแล้ว — งานที่เขียน @State
            // ทุก 16 มิลลิวินาทีตลอดกาล
            focusTask?.cancel()
            focusTask = nil
        }
        .ignoresSafeArea()
    }
}
