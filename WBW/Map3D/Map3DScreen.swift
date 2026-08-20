import RealityKit
import SwiftUI

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
    /// ฐานที่แตะค้างไว้อยู่ — nil = ไม่มีการ์ด
    @State private var tappedSequence: Int?

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

        ZStack {
            Color.wbwForestVoid.ignoresSafeArea()

            if !shouldRender {
                // ปิดสวิตช์อยู่ — ต้องเหลือของที่อ่านรู้เรื่อง ไม่ใช่จอว่าง
                VStack(spacing: 12) {
                    Image(systemName: "map")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("map_disabled")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            } else if loadFailed {
                VStack(spacing: 12) {
                    Text("map_failed")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("map_failed_hint")
                        .font(.system(size: 13))
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
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .transition(.opacity)
                }
            }

            if shouldRender && !isLoading {
                compass
                credit
                if let tappedSequence {
                    baseCard(sequence: tappedSequence)
                } else if showsHint {
                    hint
                }
            }
        }
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

    private var credit: some View {
        VStack {
            Spacer()
            HStack {
                Text("Satlas · Allen AI · © OpenStreetMap contributors")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
            }
            .padding(.horizontal, 20)
            // พ้นแท็บบาร์ลอย — ค่าเดียวกับที่ฉากป่าใช้ วัดจากเครื่องจริงสองรุ่นมาแล้ว
            .padding(.bottom, ForestSceneHost.tabBarClearance)
        }
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
                .padding(.bottom, ForestSceneHost.tabBarClearance + 16)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    /// การ์ดฐาน — ชื่อ/ลำดับ/สถานะเช็คอิน
    ///
    /// ชื่อจริงมีให้เฉพาะฐานที่เช็คอินไปแล้ว (backend คืนแค่ checked_in) `Map3DPins.label` จึงคืน
    /// "ฐานที่ N" สำหรับฐานที่ยังไม่ไป — **ห้ามเดาชื่อ** กติกาเดิมที่ต้องคงไว้
    private func baseCard(sequence: Int) -> some View {
        let checkedIn = progress.progress?.checkedIn ?? []
        let visited = checkedIn.first { $0.sequence == sequence }
        return VStack {
            Spacer()
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Map3DPins.label(sequence: sequence, checkedIn: checkedIn))
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let activity = visited?.activityName, !activity.isEmpty {
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
                Button { endFocus() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.8))
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
            .padding(.bottom, ForestSceneHost.tabBarClearance)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
        tappedSequence == nil ? Map3DCamera.minDistance : Map3DCamera.focusDistance
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
        poseBeforeFocus = nil
        animate(to: Map3DPose(yaw: Map3DCamera.defaultYaw, pitch: Map3DCamera.defaultPitch,
                              distance: Map3DCamera.defaultDistance, target: .zero),
                over: Map3DFocus.returnDuration)
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
        let destination = Map3DFocus.pose(forPinAt: position, currentYaw: yaw)
        focusTask = Task { @MainActor in
            await run(to: destination, over: Map3DFocus.flyDuration)
            guard !Task.isCancelled, !reduceMotion else { return }
            // หมุนวนต่อไปเรื่อย ๆ · base คือมุมตอนบินถึง ไม่ใช่ 0 ไม่งั้นภาพกระโดดตอนเริ่มหมุน
            let base = yaw
            let started = CFAbsoluteTimeGetCurrent()
            while !Task.isCancelled {
                yaw = Map3DFocus.orbitYaw(base: base, elapsed: CFAbsoluteTimeGetCurrent() - started)
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    /// ปิดการ์ดแล้วคืนท่ากล้องเดิม
    private func endFocus() {
        focusTask?.cancel()
        focusTask = nil
        tappedSequence = nil
        guard let previous = poseBeforeFocus else { return }
        poseBeforeFocus = nil
        animate(to: previous, over: Map3DFocus.returnDuration)
    }

    /// ผู้ใช้เข้ามาคุมกล้องเอง — หยุดหมุนวน แต่ยังจ้องฐานเดิมอยู่ (การ์ดยังเปิด)
    /// ปิดการ์ดไปด้วยจะเป็นการลงโทษคนที่แค่อยากเอียงกล้องดูฐานนั้นเอง
    private func stopOrbit() {
        focusTask?.cancel()
        focusTask = nil
    }

    private func animate(to pose: Map3DPose, over duration: TimeInterval) {
        focusTask = Task { @MainActor in await run(to: pose, over: duration) }
    }

    /// เดินค่าเองทีละเฟรม ไม่ใช้ withAnimation — เหตุผลเดียวกับ `playIntroIfNeeded`:
    /// ค่ากล้องถูกอ่านใน update closure ของ RealityView การพึ่งว่า SwiftUI จะ re-run closure นั้น
    /// ครบทุกเฟรมตามค่า animated เป็นข้อสมมติที่พิสูจน์ไม่ได้จากโค้ด
    @MainActor
    private func run(to pose: Map3DPose, over duration: TimeInterval) async {
        let from = Map3DPose(yaw: yaw, pitch: pitch, distance: distance, target: target)
        guard !reduceMotion else { apply(pose); return }
        let started = CFAbsoluteTimeGetCurrent()
        while !Task.isCancelled {
            let elapsed = CFAbsoluteTimeGetCurrent() - started
            let frame = Map3DFocus.frame(at: Float(min(elapsed / duration, 1)), from: from, to: pose)
            apply(frame)
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

    /// บินทะลุเมฆลงมา — ครั้งแรกต่อการเปิดแอปเท่านั้น
    ///
    /// เดินค่าเองทีละเฟรมแทน withAnimation เพราะกล้องถูกอ่านใน update closure ของ RealityView
    /// การพึ่งว่า SwiftUI จะ re-run closure นั้นตามค่า animated ให้ครบทุกเฟรมเป็นข้อสมมติที่
    /// พิสูจน์ไม่ได้จากโค้ด · ตั้งค่าเองทีละครั้งคือ state เปลี่ยนจริงทุกครั้ง update ถูกเรียกแน่นอน
    @MainActor
    private func playIntroIfNeeded() {
        guard !MapModelLoader.shared.hasPlayedIntro else { return }
        MapModelLoader.shared.hasPlayedIntro = true
        // เปิด Reduce Motion ไว้ = ข้ามการบินทะลุเมฆ ไปอยู่ท่าปลายทางเลย
        guard !reduceMotion else {
            let end = Map3DIntro.frame(at: 1)
            pitch = end.pitch
            distance = end.distance
            introFinished = true
            return
        }
        Task {
            let started = CFAbsoluteTimeGetCurrent()
            while true {
                let progress = Float(min((CFAbsoluteTimeGetCurrent() - started) / Map3DIntro.duration, 1))
                let frame = Map3DIntro.frame(at: progress)
                pitch = frame.pitch
                distance = frame.distance
                if progress >= 1 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)   // ~60 เฟรมต่อวินาที
            }
            introFinished = true
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
            // ลบตัวเก่าก่อนเสมอ — `dotParent` อยู่ใต้ `map` ซึ่งเป็น entity ตัวเดิมที่ถูกใช้ซ้ำข้าม
            // การ mount จอใหม่ (ล็อกเอาต์แล้วล็อกอินใหม่) ไม่ลบทิ้งก็ได้จุดฟ้าเพิ่มขึ้นทีละลูกทุกรอบ
            // และ `findEntity(named:)` ใน update closure ก็จับได้แค่ลูกเดียว ที่เหลือค้างอยู่กับที่
            // ตำแหน่งเก่าโดยไม่มีใครขยับหรือปิดมันอีกเลย
            dotParent.findEntity(named: "UserDot")?.removeFromParent()
            dotParent.addChild(dot)

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
                    let start = Map3DIntro.frame(at: 0)
                    pitch = start.pitch
                    distance = start.distance
                }
                isLoading = false
                playIntroIfNeeded()
            }
        } update: { content in
            guard let root = content.entities.first,
                  let map = root.findEntity(named: "Map") else { return }

            // เมฆเป็นของสำหรับ intro — ปิดเมื่อเล่นจบ ไม่งั้นมุมกล้องต่ำจะมองทะลุชั้นเมฆ
            // เห็นแผนที่เป็นสีจาง ๆ ทั้งจอ (เจอจากสกรีนช็อตรอบแรก)
            if let clouds = root.findEntity(named: Map3DSky.cloudsName) {
                clouds.isEnabled = !introFinished
            }

            if let heading = headingOverride, let content = map.children.first {
                content.orientation = simd_quatf(angle: heading * .pi / 180,
                                                 axis: SIMD3<Float>(0, 0, 1))
            }

            // หมุน "ฉาก" แทนการย้ายกล้อง — ผลทางสายตาเหมือนกันทุกประการ และเป็นวิธีเดียวที่ใช้ได้จริง
            //
            // ลองวาง PerspectiveCamera เองแล้วสั่ง content.camera = .virtual ก่อนแล้ว ไม่ได้ผล:
            // log ยืนยันว่ากล้องถูกวางถูกตำแหน่ง (eye=(0, 0.53, 2.13) ที่ pitch 14°) แต่ภาพที่ออกมา
            // ยังเป็นมุมก้มจากบนหัวเหมือนเดิมทุกพิกเซล — RealityView บน iOS เรนเดอร์ด้วยกล้องปริยาย
            // ที่จัดเฟรมให้เองโดยไม่สนใจกล้องในฉาก การหมุน root จึงเป็นทางที่เหลืออยู่
            //
            // กล้องปริยายมองลงมาจากด้านบน (ยืนยันจากภาพ: โมเดลราบเต็มเฟรม) ดังนั้น
            // pitch 90° = ไม่ต้องเอียงเลย · pitch ต่ำ = เอียงฉากเข้าหากล้องมากขึ้น
            // ⚠️ ห้ามตั้ง `content.camera = .virtual` ในฟังก์ชัน make — ลองมาแล้วและมันทำให้
            // RealityView เมินกล้องตัวนี้ทั้งดุ้น กลับไปเรนเดอร์ด้วยกล้องปริยายที่จัดเฟรมเองจากบนหัว
            // (log ยืนยันว่ากล้องถูกวางถูกตำแหน่งทุกครั้ง แต่ภาพไม่ขยับสักพิกเซล) ไม่ตั้งเลยคือถูกแล้ว
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
            // เปิดการ์ดฐานตรงๆ โดยไม่ต้องแตะจริง — ทรงเดียวกับ uitestChat/uitestFeedback ที่
            // MainTabView.swift เป็นทางเดียวที่ถ่ายรูปการ์ดได้ในสภาพแวดล้อมที่ไม่มี tap tooling
            let forced = UserDefaults.standard.integer(forKey: "uitestMapPin")
            if forced > 0 { tappedSequence = forced; showsHint = false }
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
            if isActive { location.start(); showHintOnce() }
            // บอก loader ว่าโมเดลกำลังถูกใช้อยู่ — ตอนระบบเตือนความจำมันจะได้ไม่ปล่อย entity
            // ที่แขวนอยู่ในฉากที่กำลังเรนเดอร์ทิ้ง (แผนที่จะหายไปเฉย ๆ ไม่มี error ให้เห็น)
            MapModelLoader.shared.isInUse = isActive
        }
        .onChange(of: isActive) { _, nowActive in
            nowActive ? location.start() : location.stop()
            MapModelLoader.shared.isInUse = nowActive
            if nowActive { showHintOnce() }
        }
        .onDisappear {
            location.stop()
            MapModelLoader.shared.isInUse = false
            // ไม่ยกเลิกแล้วมันหมุนวนต่ออยู่เบื้องหลังหลังออกจากแท็บไปแล้ว — งานที่เขียน @State
            // ทุก 16 มิลลิวินาทีตลอดกาล
            focusTask?.cancel()
            focusTask = nil
        }
        .ignoresSafeArea()
    }
}
