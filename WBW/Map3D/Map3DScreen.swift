import RealityKit
import SwiftUI

/// แท็บแผนที่ — โมเดล 3D ของพื้นที่งาน (map.usdz) แทน MapLibre เดิม
///
/// ไม่ใช้ ForestSceneHost: ฉากป่าต้องมี host เพราะ 4 จอใช้ฉากเดียวกันและฉากถูกวาดที่ RootView
/// ซึ่งอยู่คนละ hosting context กับจอ — แผนที่อยู่จอเดียว RealityView เกิดและตายไปกับจอนี้ได้เลย
struct Map3DScreen: View {
    /// โหลดโมเดลไม่สำเร็จ — โชว์ข้อความแทนจอเปล่า (ทรงเดียวกับ ForestSceneHost.loadFailed)
    @State private var loadFailed = false

    @EnvironmentObject private var progress: CheckinProgressStore
    /// ฐานที่แตะค้างไว้อยู่ — nil = ไม่มีการ์ด
    @State private var tappedSequence: Int?

    /// ตำแหน่งผู้ใช้จริงจาก CoreLocation — nil = ไม่ให้สิทธิ์/ยังไม่รู้ตำแหน่ง (ไม่วาดจุด)
    @StateObject private var location = Map3DLocation()

    /// รัศมีจุดตำแหน่งผู้ใช้ วัดหลังโมเดลถูกย่อให้พอดีกรอบ 2 หน่วยแล้ว (โมเดลกว้าง 2 หน่วยเต็มจอ)
    /// ตอนสร้าง entity ต้องหารด้วย map.scale กลับเป็นเมตรจริงของ local space เสมอ
    private static let dotRadiusOnScreen: Float = 0.02

    /// มุมหมุนรอบแกน Y ที่ใส่ให้ `map` เพื่อจัดทิศของพื้นที่งานให้ตรงกับที่กล้องเริ่มต้นมอง
    /// ค่านี้ "ไม่ใช่" ทิศเหนือจริง อย่าตีความเป็นมุม compass/bearing ใด ๆ
    ///
    /// กติกาสำหรับใครมาต่อ: entity ที่วางตำแหน่งจากพิกัดจริง (lat/lng) เช่นจุด GPS ผู้ใช้
    /// ต้องเป็นลูกของ `map` ไม่ใช่ลูกของ `root` — ให้ transform hierarchy พาการหมุนนี้ไปเองอัตโนมัติ
    /// ถ้าจำเป็นต้องแยกไปเป็นลูกของ entity อื่น ต้องคูณการหมุนนี้เข้าไปเองด้วยมือ ไม่งั้นตำแหน่งจะเพี้ยน
    /// แบบเงียบ ๆ ไม่มี error ไม่มีเทสจับได้ (หมุดหาโหนดผ่าน findEntity(named:) บนโมเดลเองอยู่แล้ว
    /// จึงรับการหมุนนี้ไปฟรี ๆ โดยอัตโนมัติ ไม่ต้องแก้อะไร)
    private static let cameraFramingYaw: Float = .pi / 4

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
                    Text("แผนที่ 3D ปิดชั่วคราว")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            } else if loadFailed {
                VStack(spacing: 12) {
                    Text("เปิดแผนที่ไม่ได้")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("ลองเข้าใหม่อีกครั้ง")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                mapView
            }

            if shouldRender {
                VStack {
                    Spacer()
                    HStack {
                        Text("Satlas · Allen AI · © OpenStreetMap contributors")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    // พ้นแท็บบาร์ลอย — ค่าเดียวกับที่ฉากป่าใช้ วัดจากเครื่องจริงสองรุ่นมาแล้ว
                    .padding(.bottom, ForestSceneHost.tabBarClearance)
                }
                .allowsHitTesting(false)
            }

            if let tappedSequence {
                VStack {
                    Spacer()
                    HStack {
                        Text(Map3DPins.label(sequence: tappedSequence,
                                             checkedIn: progress.progress?.checkedIn ?? []))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Button {
                            self.tappedSequence = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                    .padding(.bottom, ForestSceneHost.tabBarClearance)
                }
            }
        }
    }

    private var mapView: some View {
        RealityView { content in
            let root = Entity()
            content.add(root)

            let map: Entity
            do {
                map = try await Entity(named: "map")
            } catch {
                // NSLog ไม่ใช่ print — print() ไม่โผล่ใน unified log ของ simulator
                // (ยืนยันมาแล้วตอน debug จอขาวของฉากป่า) ต้องใช้ NSLog ถึงจะ grep เจอผ่าน
                // `xcrun simctl spawn booted log stream`
                NSLog("[Map3DScreen] Entity(named: \"map\") threw: %@", String(describing: error))
                await MainActor.run { loadFailed = true }
                return
            }
            map.name = "Map"

            // โมเดลเป็นเมตรจริง รัศมีราว 1.9 กม. — ย่อให้ทั้งก้อนพอดีกรอบ 2 หน่วย
            // ก่อนค่อยให้ camera controls จัดการระยะ ไม่งั้นกล้องเริ่มต้นจะอยู่ในเนื้อโมเดล
            let bounds = map.visualBounds(relativeTo: nil)
            let widest = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
            if widest > 0 { map.scale = SIMD3<Float>(repeating: 2 / widest) }
            map.position = -bounds.center * map.scale.x

            // usdz นี้ประกาศ upAxis = "Z" จริง (ตรวจด้วย usdcat) แต่ Entity(named:) ของ
            // RealityKit แปลงให้เป็น Y-up ให้เองตั้งแต่โหลด — วัดจาก visualBounds ก่อนตัวโค้ด
            // นี้แตะต้องอะไรเลย: แกน Y (สูง 664 ม.) เตี้ยกว่า X/Z (กว้าง 4470×5162 ม.) มาก
            // ตรงกับความสูงภูมิประเทศจริง ไม่ใช่ด้านกว้างของพื้นที่ จึงไม่ต้องหมุนแก้ Z-up/Y-up
            // ที่ต้องหมุนจริงคือ cameraFramingYaw — เหตุผลเต็มอยู่ที่คอมเมนต์ของตัวแปรด้านบน
            map.orientation = simd_quatf(angle: Self.cameraFramingYaw, axis: SIMD3<Float>(0, 1, 0))

            root.addChild(map)

            // ให้แท่งแดงแตะได้ — ต้องมีทั้งสองคอมโพเนนต์ ขาดตัวใดตัวหนึ่ง tap ไม่เข้า
            for name in Map3DPins.entityNames {
                guard let pin = map.findEntity(named: name) else {
                    NSLog("[Map3DScreen] ไม่พบหมุดชื่อ %@ ในโมเดล", name)
                    continue
                }
                let bounds = pin.visualBounds(relativeTo: pin)
                pin.components.set(CollisionComponent(shapes: [
                    .generateBox(size: bounds.extents).offsetBy(translation: bounds.center)
                ]))
                pin.components.set(InputTargetComponent())
            }

            // จุดตำแหน่งผู้ใช้ — สร้างไว้ก่อนแล้วซ่อน ค่อยย้ายตอนมีพิกัดจริง
            // (สร้างทีหลังใน update closure ไม่ได้ เพราะ closure นั้นถูกเรียกทุกเฟรม)
            //
            // ต้องอยู่ในสาย transform hierarchy เดียวกับโมเดล ไม่ใช่ของ `root` — ตามกติกาที่
            // คอมเมนต์ของ cameraFramingYaw เขียนไว้ ไม่งั้นจุดจะไม่หมุนตามโมเดลตอนที่ map ถูกหมุน
            // cameraFramingYaw (45°)
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
            let dot = ModelEntity(
                mesh: .generateSphere(radius: Self.dotRadiusOnScreen / map.scale.x),
                materials: [UnlitMaterial(color: .systemBlue)]
            )
            dot.name = "UserDot"
            dot.isEnabled = false
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
        } update: { content in
            guard let root = content.entities.first,
                  let map = root.findEntity(named: "Map") else { return }

            if let heading = headingOverride {
                map.orientation = simd_quatf(angle: heading * .pi / 180,
                                             axis: SIMD3<Float>(0, 1, 0))
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
                                               distance: distance, target: .zero)
                camera.look(at: .zero, from: eye, relativeTo: nil)
            }

            guard let dot = map.findEntity(named: "UserDot") else { return }
            guard let coordinate = location.coordinate,
                  let point = Map3DGeo.modelPoint(latitude: coordinate.latitude,
                                                  longitude: coordinate.longitude,
                                                  in: Map3DGeo.eventArea) else {
                dot.isEnabled = false
                return
            }
            dot.isEnabled = true
            // จุดต้องอยู่ใน local space ของ map เอง (เมตรจริงก่อนย่อ/หมุน) ไม่ใช่ช่วง -1…1 ที่
            // Map3DGeo คืนมาตรงๆ — หา extents/center จริงของโมเดลด้วย visualBounds(relativeTo:
            // map) แล้วคูณสัดส่วน -1…1 เข้ากับครึ่งหนึ่งของ extents แต่ละแกนเอง (ไม่ใช่แกนเดียวกัน
            // หมดแบบ "widest" ตอนย่อสเกล เพราะกรอบ eventArea ไม่ได้เป็นสี่เหลี่ยมจัตุรัส)
            //
            // ⚠️ ยืนยันด้วย NSLog แล้วว่า visualBounds(relativeTo: map) ตอบแกน Y/Z "สลับกัน" กับที่
            // โมเดลเรนเดอร์จริงบนจอ (ตัว X ไม่กระทบ): self-relative ตอบ Y ~2581 (แกนแนวนอน) และ
            // Z ~332 (แกนสูง) สวนทางกับ visualBounds(relativeTo: nil) ที่ยิงตอนโหลด (ดูตัวแปร
            // `bounds` ด้านบนในฟังก์ชัน make) ซึ่ง Y ~332 (สูง) Z ~2581 (แนวนอน) — ตรงกับภาพที่เห็น
            // จริงบนจอ (โมเดลราบ ไม่ตะแคง) สาเหตุที่แท้จริงไม่ทราบ แก้โดยอ่านสลับแกน: ใช้ z ของ
            // ผลลัพธ์เป็นความสูง และ y เป็นแกนเหนือ-ใต้ ตัว x ใช้ตรงๆ ปกติ (ไม่กระทบ)
            let localBounds = map.visualBounds(relativeTo: map)
            let half = localBounds.extents / 2
            let dotRadius = Map3DScreen.dotRadiusOnScreen / map.scale.x
            // Map3DGeo คืน point.y เป็นแกนเหนือ-ใต้ จึงต้องกลับเครื่องหมาย (แกนแนวนอนที่สองของ
            // RealityKit ชี้เข้าหากล้อง = ทิศใต้) ไม่ต้องคูณ cameraFramingYaw เองตรงนี้ เพราะจุด
            // อยู่ในสาย transform เดียวกับโมเดลแล้ว — hierarchy พาการหมุนไปเองอัตโนมัติ (เหมือน
            // หมุดจาก Task 3)
            //
            // ลำดับแกนตรงนี้คือ local space ของโมเดล ซึ่งเป็น Z-up ตามที่ usdz เขียนมา (usdcat:
            // upAxis = "Z") — ตัวแปลง Z-up→Y-up ของ RealityKit ถูกอบไว้ใน transform ของ entity
            // ตัวนอกที่ Entity(named:) คืนมา ไม่ได้แก้พิกัดของเนื้อโมเดลข้างใน ดังนั้นในนี้
            // x = ตะวันออก-ตะวันตก · y = เหนือ-ใต้ · z = ความสูง (ตรงกับ extents ที่วัดได้:
            // y ~2581 แนวนอน, z ~332 ความสูง)
            //
            // ความสูง: วางไว้เหนือยอดสูงสุดของโมเดลเล็กน้อย ไม่ใช่กึ่งกลางความสูง — กึ่งกลางจมอยู่
            // ใต้ภูมิประเทศในหลายจุด จุดจะหายไปโดยไม่มีอะไรฟ้อง
            dot.position = SIMD3<Float>(
                localBounds.center.x + point.x * half.x,
                localBounds.center.y - point.y * half.y,
                localBounds.center.z + half.z + dotRadius
            )
        }
        // ลากนิ้ว = กวาด/เงย · หุบนิ้ว = ระยะ · ทุกค่าผ่าน clamp ของ Map3DCamera ก่อนเสมอ
        // simultaneousGesture เพื่อให้ไม่ไปแย่ง SpatialTapGesture ของหมุดด้านล่าง
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    let startYaw = gestureStartYaw ?? yaw
                    let startPitch = gestureStartPitch ?? pitch
                    if gestureStartYaw == nil { gestureStartYaw = startYaw }
                    if gestureStartPitch == nil { gestureStartPitch = startPitch }
                    // 0.004 เรเดียนต่อพอยต์ — กวาดสุดช่วง (110°) ใช้ระยะลากราวครึ่งจอครึ่ง
                    yaw = Map3DCamera.clampYaw(startYaw - Float(value.translation.width) * 0.004)
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
                    let start = gestureStartDistance ?? distance
                    if gestureStartDistance == nil { gestureStartDistance = start }
                    // หุบนิ้วออก (magnification > 1) = เข้าใกล้ ระยะจึงหารไม่ใช่คูณ
                    distance = Map3DCamera.clampDistance(start / Float(value.magnification))
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
                            tappedSequence = sequence
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
            if forced > 0 { tappedSequence = forced }
            // ลองมุมกล้องหลายค่าแล้วถ่ายเทียบกับภาพอ้างอิงโดยไม่ต้อง build ใหม่ทุกครั้ง
            // (หน่วยเป็นองศา · หมุนโมเดล ไม่ใช่หมุนกล้อง เพราะทิศของพื้นที่งานอบอยู่ในโมเดล)
            if UserDefaults.standard.object(forKey: "uitestMapHeading") != nil {
                headingOverride = Float(UserDefaults.standard.integer(forKey: "uitestMapHeading"))
            }
            // ลองมุมเงยหลายค่าแล้วถ่ายเทียบภาพอ้างอิง โดยไม่ต้อง build ใหม่ทุกครั้ง (หน่วยองศา)
            if UserDefaults.standard.object(forKey: "uitestMapPitch") != nil {
                pitch = Map3DCamera.clampPitch(
                    Float(UserDefaults.standard.integer(forKey: "uitestMapPitch")) * .pi / 180)
            }
            #endif
            location.start()
        }
        .onDisappear { location.stop() }
        .ignoresSafeArea()
    }
}
