import RealityKit
import SwiftUI
import simd

/// ฉากป่าจริง — RealityView ตัวเดียวของแอป
///
/// กล้องนิ่งที่ (0, 1.7, 0) มองไปทาง +Z ของฉาก (ในไฟล์ USDZ ที่ bake ไว้ แกน "ลึก"
/// คือ +Y ของ Blender ซึ่ง USD แปลงเป็น -Z ของ RealityKit ตอน import)
///
/// หมอก: RealityKit ไม่มี exponential fog · สคริปต์ bake แบ่ง material เป็น 8 แถบ
/// ตามระยะ (ชื่อลงท้าย __band0..__band7) ที่นี่ไล่สี tint ของแต่ละแถบตามเวลาของวัน
struct ForestSceneView: View {
    @EnvironmentObject var host: ForestSceneHost
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // นาฬิกาเฟรม + ต้นไม้ — ดูคอมเมนต์ที่ ForestSceneRuntime ว่าทำไมต้องเป็น class ถือด้วย
    // @StateObject แทนที่จะเป็น @State ของ Float/GrowingTree? ตรงๆ
    @StateObject private var runtime = ForestSceneRuntime()
    // ไจโรพารัลแลกซ์ (Task 7) — ดูคอมเมนต์ที่ GyroParallax.swift หน้าที่เดียวกับ pointer parallax
    // ของเว็บใน CameraRig · เก็บเป็น @StateObject แยกจาก host ตั้งใจ ไม่ใช่ property ของ
    // ForestSceneHost — host คือ "คำสั่งจากหน้าปัจจุบัน" (day/plantStep/...) ส่วน gyro คือ state
    // ภายในของฉากเองที่ไม่มีหน้าไหนต้องรู้จัก ไม่มีเหตุผลต้องผ่าน EnvironmentObject
    @StateObject private var gyro = GyroParallax()

    var body: some View {
        // TimelineView ใช้เป็นแหล่งเวลาต่อเฟรมเท่านั้น (ให้ RealityView update: ถูกเรียกรัวๆ ตอนฉาก
        // โชว์อยู่) ไม่ได้ถือ state ของฉากเอง — pause ทันทีที่ไม่มีอะไรต้องขยับต่อเฟรมเลย เงื่อนไข pause
        // อยู่ที่ sceneShouldTick ด้านล่าง (ย้ายออกมาจาก inline ตอน Task 7 เพิ่มเงื่อนไขที่สอง — อ่านที่นั่น
        // สำหรับเหตุผลเต็มๆ ว่าทำไมต้องมีสองเงื่อนไข) วัดจริงตั้งแต่ Task 6 แล้วว่าต้นทุน CPU ต่างจาก
        // pre-task-6 ชัดเจนตอนไม่มีอะไรขยับเลย (19/19 sample จาก `top` สูงกว่า, ~45% vs ~40%) เพราะ
        // TimelineView ที่ไม่ pause ทำให้ SwiftUI invalidate + RealityKit composite ทุกเฟรมทั้งที่ไม่
        // จำเป็น (ดู fix-round-1 ใน task-6-report.md) การเปลี่ยน plantStep เอง (nil ↔ มีค่า) ไม่ต้องพึ่ง
        // schedule นี้ตื่นเลย — @EnvironmentObject ส่ง objectWillChange ทำให้ update: ถูกเรียกอย่างน้อย
        // หนึ่งครั้งเสมอไม่ว่า schedule จะ pause อยู่หรือไม่ (ยืนยันด้วย log จริงใน fix-round-1) ครั้งเดียว
        // นั้นพอสำหรับ Reduce Motion ด้วย เพราะ setStage+tick ครั้งแรกที่ต้นไม้ถูกสร้าง snap ไปเป้าหมายเลย
        // ในเฟรมเดียว
        TimelineView(.animation(paused: !sceneShouldTick)) { timeline in
            RealityView { content in
                ForestOriginalTint.registerComponent()
                ForestLastAppliedDay.registerComponent()

                let root = Entity()
                content.add(root)

                let forest: Entity
                do {
                    forest = try await Entity(named: "forest")
                } catch {
                    // TODO(task-5 diagnosis): พิมพ์ error จริงตอนหา root cause ของจอขาว — ลบ catch แบบพิมพ์ error
                    // ทิ้งได้ถ้าจะกลับไปใช้ `try?` แบบในบรีฟ แต่ข้อมูลนี้มีประโยชน์มากพอจะเก็บไว้ debug ต่อ
                    #if DEBUG
                    // ใช้ NSLog ไม่ใช่ print — print() ไม่โผล่ใน unified log ของ simulator เลย (ยืนยันแล้ว
                    // ด้วย log stream ระหว่าง debug จอขาว) NSLog โผล่แน่นอน ใช้เช็คผ่าน `simctl spawn ... log
                    // stream` ได้จริง
                    NSLog("[ForestSceneView] Entity(named: \"forest\") threw: %@", String(describing: error))
                    #endif
                    await MainActor.run { host.markLoadFailed() }
                    return
                }
                forest.name = "Forest"
                root.addChild(forest)
                #if DEBUG
                // เช็คตำแหน่งจริงของโมเดลเทียบกล้อง — forest.usdz ไม่เคยผ่าน USD renderer ใดมาก่อนไฟล์นี้
                // (qlmanage เปิดไม่ได้ในเครื่องที่ bake) ถ้าจอดำ ให้เทียบเลขนี้กับตำแหน่งกล้องก่อนแก้โค้ด
                NSLog("[ForestSceneView] forest.visualBounds(relativeTo: nil) = %@",
                      String(describing: forest.visualBounds(relativeTo: nil)))
                NSLog("[ForestSceneView] forest.children.count = %d", forest.children.count)
                #endif

                let camera = PerspectiveCamera()
                camera.camera.fieldOfViewInDegrees = 55
                camera.camera.near = 0.1
                camera.camera.far = 900
                camera.name = "Camera"
                camera.position = SIMD3<Float>(0, 1.7, 0)
                camera.look(at: SIMD3<Float>(0, 1.4, -16), from: camera.position, relativeTo: nil)
                root.addChild(camera)

                let sun = DirectionalLight()
                sun.name = "Sun"
                sun.light.isRealWorldProxy = false
                root.addChild(sun)

                // ไฟเติมจากตรงข้ามดวงอาทิตย์ — แทน hemisphere light ของ three.js
                // ที่ RealityKit ไม่มี · ทำให้ด้านเงาไม่ดำสนิท
                let fill = DirectionalLight()
                fill.name = "Fill"
                root.addChild(fill)

                applySun(to: root, day: host.day)
            } update: { content in
                // ฉากอยู่คงที่ตลอดอายุแอปแล้ว (ดูคอมเมนต์ที่ RootView) แม้ตอนซ่อน (enabled=false, opacity 0)
                // update closure นี้ก็ยังถูกเรียกได้ทุกครั้งที่ SwiftUI re-render ต้นไม้ที่ฉากอยู่ใต้ — ข้าม
                // งานทั้งหมดตอนซ่อนไปเลย ไม่ใช่แค่ไม่โชว์ผล (สำคัญตอน Task 7 ที่ gyro tick ต่อเนื่อง ~60Hz)
                guard host.enabled, let root = content.entities.first else { return }

                // เลื่อนกล้องตามไจโร (Task 7) "ก่อน" apply แสง/หมอก — set position + look(at:) ของ
                // entity เดียว เบามากเทียบกับ applySun/applyFog ด้านล่าง (586 material) จึงไม่ผ่าน
                // dirty-check guard ของ applySun เลย ปล่อยรันได้ทุกเฟรมตรงๆ อย่างปลอดภัย (ดูคอมเมนต์ที่
                // applySun) reduceMotion บังคับ offset เป็น 0 ซ้ำอีกชั้นตรงนี้ (เผื่อ gyro ยังไม่ทัน stop()
                // ตาม) — ไม่ได้ผูก .onChange(of: reduceMotion) เพิ่มต่างหาก ตั้งใจพึ่ง mechanism เดียวกับ
                // ที่ทำให้ plantStep transition ปลุก schedule ที่ pause อยู่ได้ (ดูคอมเมนต์ที่
                // sceneShouldTick) แต่เส้นทางนี้ไม่ได้ถูกทดสอบจริงในซิม — offset เป็น 0 อยู่แล้วตลอดที่นั่น
                // (ไม่มี motion hardware) ไม่มีอะไรให้เห็นความต่าง ต้องเครื่องจริงเท่านั้นที่พิสูจน์ได้
                if let camera = root.findEntity(named: "Camera") {
                    let o = reduceMotion ? SIMD2<Float>(0, 0) : gyro.offset
                    let eye = SIMD3<Float>(o.x, 1.7 - o.y, 0)
                    camera.position = eye
                    camera.look(at: SIMD3<Float>(0, 1.4, -16), from: eye, relativeTo: nil)
                }

                applySun(to: root, day: host.day)

                // ต้นไม้ผู้เข้าร่วม — สร้างแบบ lazy ตอน plantStep เปลี่ยนจาก nil เป็นมีค่าครั้งแรกเท่านั้น
                // (ไม่สร้างใน make ด้านบน เพราะ make ถูกเรียกครั้งเดียวตลอดอายุแอปตามคอมเมนต์ที่ RootView —
                // เช็ค plantStep ตรงนั้นจะตัดสินใจตายตัวจากค่าตอน launch ทั้งที่ Task 9 ผูกค่าจริงจาก
                // network เข้ามาทีหลังแบบ async เสมอ (plantStep เป็น nil ก่อนเสมอในเฟรมแรก)) ลบทิ้งถ้า
                // plantStep กลับเป็น nil ให้ตรงกับความหมายของ optional (nil = ไม่มีต้นไม้ในฉาก ตาม
                // คอมเมนต์ที่ ForestSceneHost.plantStep)
                let dt = runtime.tick(now: timeline.date.timeIntervalSinceReferenceDate)
                if let step = host.plantStep {
                    // ลองโหลดแค่ครั้งเดียว — เหมือน host.markLoadFailed() ของ forest 25 บรรทัดข้างบน
                    // ไม่งั้นถ้า Entity.load(named: "tree") พังจริง (เจอมาแล้วรอบ verify: stale
                    // DerivedData ทำ forest resourceNotFound) init? คืน nil, runtime.tree ยังเป็น nil
                    // ต่อไป แล้วบรรทัดนี้จะพยายามโหลดใหม่ทุกเฟรมตราบใดที่ plantStep ยังมีค่า — โหลดแบบ
                    // synchronous บล็อก main thread ด้วย ไม่ใช่แค่เปลืองเปล่าๆ
                    if runtime.tree == nil && !runtime.treeLoadFailed {
                        runtime.tree = GrowingTree(target: root)
                        if runtime.tree == nil { runtime.treeLoadFailed = true }
                    }
                    let total = max(host.plantTotal, 1)
                    runtime.tree?.setStage(step, total: total)
                    runtime.tree?.tick(deltaTime: dt, elapsed: runtime.elapsed, reduceMotion: reduceMotion)
                } else if runtime.tree != nil {
                    runtime.tree?.removeFromScene()
                    runtime.tree = nil
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)   // พื้นหลังล้วน ห้ามกินทัชของ UI ข้างหน้า
        .onAppear { if !reduceMotion { gyro.start() } }
        .onDisappear { gyro.stop() }
        // host.enabled สลับ false→true ทุกครั้งที่กลับมาที่หน้าที่ใช้ฉากนี้ (ฉากเองไม่ถูก unmount/remount
        // อีกแล้วตั้งแต่ Task 5 — ดูคอมเมนต์ที่ RootView — onAppear/onDisappear ข้างบนเลยไม่ refire ตอน
        // สลับแท็บออกแล้วกลับมา) นี่คือสัญญาณเดียวที่เหลือให้ start/stop เซนเซอร์ตามจริงว่าฉากกำลังโชว์
        // อยู่หรือเปล่า
        .onChange(of: host.enabled) { _, on in on && !reduceMotion ? gyro.start() : gyro.stop() }
    }

    /// true = TimelineView schedule ต้องไม่ pause เฟรมนี้ (ใช้ที่ `paused:` ใน body ด้านบน)
    ///
    /// เงื่อนไขเดิมของ Task 6: `host.enabled && plantStep != nil && !reduceMotion` (มีต้นไม้กำลังโต/
    /// ไหวลมอยู่) Task 7 (ไจโรพารัลแลกซ์) เพิ่มเงื่อนไข OR ตัวที่สอง: `gyro.isAvailable` — เพราะกล้อง
    /// ต้องขยับตามการเอียงเครื่องทุกเฟรม "ไม่ว่าจะมีต้นไม้ในฉากหรือไม่" ซึ่งคือ Home ก่อน Task 9 ผูกค่า
    /// จริง และทุกจอที่เหลือที่จะใช้ฉากนี้ในอนาคต (ตอนนี้มีแค่ Home ที่เรียก .forestBackground)
    ///
    /// ต้องประกาศเงื่อนไขนี้ตรงๆ แทนที่จะพึ่งกลไก "@Published ปลุก schedule ที่ pause อยู่" ตัวเดียวกับที่
    /// plantStep ใช้ (คอมเมนต์ที่ TimelineView ด้านบน) เพราะกล้อง (Task 7) อ่าน `gyro.offset` อยู่ "ใน
    /// update: closure" เท่านั้น ไม่ได้อ่านตรงๆ ใน body เหมือนที่ `paused:` อ่าน `host.plantStep` — ไม่มี
    /// อะไรยืนยันว่าการ publish ของ gyro.offset ที่ ~60Hz จะปลุก schedule ที่ pause อยู่ได้ต่อเนื่องแบบ
    /// เดียวกับการปลุกครั้งเดียวตอน plantStep เปลี่ยนสถานะ (nil ↔ มีค่า) ที่ยืนยันแล้วจริงใน fix-round-1
    /// ของ task-6-report.md — วิธีที่รับประกันได้แน่นอนคือ unpause schedule ไปเลยตรงๆ ตอนกล้องต้องขยับ
    /// ไม่พึ่งกลไกที่ไม่เคยวัด/ไม่เคยพิสูจน์ว่าทำงานถี่ขนาดนั้นได้จริง
    ///
    /// ใช้ `gyro.isAvailable` (เช็ค CMMotionManager.isDeviceMotionAvailable เฉยๆ) ไม่ใช่ gyro กำลัง
    /// running อยู่จริงหรือเปล่า — isAvailable เป็นข้อเท็จจริงของฮาร์ดแวร์ รู้ได้ตั้งแต่เฟรมแรกของ body
    /// โดยไม่ต้องรอ onAppear เรียก start() ก่อน (ดูเหตุผลเต็มๆ ที่ GyroParallax.isAvailable)
    ///
    /// ยังคง pause จริงตอน: Reduce Motion เปิด, ฉากถูกซ่อน (host.enabled false), หรือไม่มีต้นไม้ +
    /// เครื่องไม่มี motion hardware (เช่นในซิมูเลเตอร์ — isAvailable เป็น false เสมอที่นั่น เงื่อนไขนี้
    /// จึงพฤติกรรมเหมือนของเดิมของ Task 6 ทุกประการในซิม กิ่ง gyro ไม่ถูกใช้งานเลย ตรงกับที่ parallax
    /// เทสจริงในซิมไม่ได้ — ต้องเครื่องจริงเท่านั้น)
    private var sceneShouldTick: Bool {
        host.enabled && !reduceMotion && (host.plantStep != nil || gyro.isAvailable)
    }

    /// ตั้งสี/ทิศ/ความแรงของแสง + สีหมอกของทั้ง 8 แถบ ตามเวลาของวัน
    ///
    /// dirty-check: ข้ามทั้งฟังก์ชัน (รวม applyFog ที่เรียกต่อท้าย) ถ้า day เท่าเดิมกับที่ apply ไปแล้ว
    /// จำไว้ที่ root entity ผ่าน ForestLastAppliedDay ไม่ใช่ @State ของ View (เหตุผลเดียวกับ
    /// ForestOriginalTint — @State อาจถูกสร้างใหม่ได้ แต่ entity อยู่คงที่ตราบใดที่ฉากยังไม่ถูกทำลาย)
    /// จำเป็นเพราะ update ถูกเรียกทุกครั้งที่ SwiftUI re-render ไม่ใช่แค่ตอน day เปลี่ยนจริง — ตั้งแต่
    /// Task 6 แล้ว (TimelineView ขับ update ต่อเนื่อง ~60Hz จริงทุกครั้งที่มีต้นไม้กำลังโต/ไหวลม) ถ้าไม่กัน
    /// ตรงนี้ จะไล่ applyFog ทั้งฉาก (1148 node, 586 material, UIColor allocation ทุกตัว) ทุกเฟรมทั้งที่
    /// แสง/หมอกไม่ได้เปลี่ยนเลย — Task 7 (gyro เป็น ObservableObject แยกที่ publish offset ที่ ~60Hz
    /// คล้ายกัน — ดูคอมเมนต์ที่ sceneShouldTick) จะพึ่ง guard นี้ต่อ —
    /// เทียบ Float ตรงๆ ไม่ใช้ epsilon เพราะ day มาจากค่าที่ตั้งไม่ต่อเนื่อง (ForestMath.day/.dayStill
    /// ฯลฯ) ไม่ใช่ค่า integrate ทีละเฟรม การขยับกล้อง (Task 7) ไม่เกี่ยวกับ guard นี้ — นั่นถูกทุกเฟรมได้
    /// เพราะเบากว่ากันมาก
    private func applySun(to root: Entity, day: Float) {
        if let last = root.components[ForestLastAppliedDay.self], last.day == day { return }
        root.components.set(ForestLastAppliedDay(day: day))

        let s = SunCycle.state(at: day)
        let dir = SunCycle.direction(s)

        if let sun = root.findEntity(named: "Sun") as? DirectionalLight {
            sun.light.color = uiColor(s.sun)
            sun.light.intensity = s.sunIntensity * 1_500
            sun.look(at: .zero, from: dir * 40, relativeTo: nil)
        }
        if let fill = root.findEntity(named: "Fill") as? DirectionalLight {
            fill.light.color = uiColor(s.skyColor)
            fill.light.intensity = s.ambientIntensity * 700
            fill.look(at: .zero, from: SIMD3<Float>(-dir.x, 0.6, -dir.z) * 40, relativeTo: nil)
        }

        guard let forest = root.findEntity(named: "Forest") else { return }
        applyFog(to: forest, fog: s.fog, density: s.fogDensity)
    }

    /// ผสมสีวัสดุเข้าหาสีหมอกตามแถบระยะ — แถบไกลผสมมาก แถบใกล้แทบไม่ผสม
    ///
    /// บั๊กที่เจอระหว่าง diagnosis (ไม่ได้อยู่ในบรีฟ): ของเดิม `mix(.white, fog, amount)` ผสมจาก
    /// ขาวล้วนเสมอ ไม่ใช่จากสีต้นฉบับของวัสดุ — ใช้ได้กับวัสดุที่มี texture (ต้นไม้ ผูกกับ tree_texture.png
    /// เห็นสีจากรูปอยู่แล้ว tint ขาว = ไม่คูณเปลี่ยนอะไร) แต่วัสดุที่ไม่มี texture (หญ้า/หิน ใช้ diffuseColor
    /// เดียวล้วน เช่น mat9__band3 เขียว (0.27,0.55,0.07), Stone__band3 เทาอมน้ำตาล) เก็บสีอยู่ใน .tint
    /// ตรงๆ พอ amount≈0 (แถบใกล้กล้อง แถบ 0-4 ส่วนใหญ่ที่ dayStill) tint ถูกเขียนทับเป็นขาวเกือบสนิท
    /// ลบสีเดิมทิ้งทันที — เห็นจริงใน screenshot: หญ้าหน้าจอ (ควรเขียวตาม task-1-report) กลายเป็นขาวล้วน
    /// แก้โดยจำ tint ต้นฉบับไว้ที่ entity (ครั้งแรกที่เจอ ก่อนโดนแก้) แล้วผสมจากอันนั้นเสมอ — ไม่ใช้ @State
    /// ของ View เพราะ update closure ถูกเรียกซ้ำได้ทุกครั้งที่ SwiftUI re-render ไม่ใช่แค่ตอน day เปลี่ยน
    /// ถ้าจำผิดที่ (เช่นอ่านจาก tint ปัจจุบันที่โดนผสมไปแล้วรอบก่อน) จะทบเข้าใกล้สีหมอกขึ้นเรื่อยๆ ทุกรอบ
    private func applyFog(to entity: Entity, fog: SIMD3<Float>, density: Float) {
        #if DEBUG
        // ตัวนับชั่วคราวสำหรับ diagnosis ครั้งแรก — ลบได้เมื่อยืนยันแล้วว่า pbr.name อ่าน band ได้จริง
        var dbgNodes = 0, dbgModels = 0, dbgPBR = 0, dbgBanded = 0
        #endif
        entity.forEachDescendant { node in
            #if DEBUG
            dbgNodes += 1
            #endif
            guard var model = node.components[ModelComponent.self] as ModelComponent? else { return }
            #if DEBUG
            dbgModels += 1
            #endif

            let original: [UIColor]
            if let cached = node.components[ForestOriginalTint.self] {
                original = cached.tints
            } else {
                original = model.materials.map { ($0 as? PhysicallyBasedMaterial)?.baseColor.tint ?? .white }
                node.components.set(ForestOriginalTint(tints: original))
            }

            var changed = false
            for i in model.materials.indices {
                #if DEBUG
                if model.materials[i] is PhysicallyBasedMaterial { dbgPBR += 1 }
                #endif
                guard var pbr = model.materials[i] as? PhysicallyBasedMaterial,
                      let band = Self.band(of: pbr.name) else { continue }
                #if DEBUG
                dbgBanded += 1
                #endif
                // ระยะกลางของแถบ (แบ่งแบบ log ตอน bake) → ปริมาณหมอกแบบ exp2 เหมือน three.js
                let distance = powf(260, (Float(band) + 0.5) / 8)
                let amount = 1 - expf(-powf(density * distance, 2))
                pbr.baseColor.tint = mix(original[i], uiColor(fog), amount)
                model.materials[i] = pbr
                changed = true
            }
            if changed { node.components.set(model) }
        }
        #if DEBUG
        NSLog("[ForestSceneView] applyFog: nodes=%d modelComponents=%d pbrMaterials=%d bandedMatches=%d",
              dbgNodes, dbgModels, dbgPBR, dbgBanded)
        #endif
    }

    /// อ่านเลขแถบจากชื่อวัสดุที่สคริปต์ bake ตั้งไว้ (`<ชื่อเดิม>__band3`)
    static func band(of name: String?) -> Int? {
        guard let name, let r = name.range(of: "__band", options: .backwards) else { return nil }
        return Int(name[r.upperBound...])
    }

    private func uiColor(_ v: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(v.x), green: CGFloat(v.y), blue: CGFloat(v.z), alpha: 1)
    }

    private func mix(_ a: UIColor, _ b: UIColor, _ t: Float) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let k = CGFloat(min(max(t, 0), 1))
        return UIColor(red: ar + (br - ar) * k, green: ag + (bg - ag) * k,
                       blue: ab + (bb - ab) * k, alpha: 1)
    }
}

extension Entity {
    /// เดินทุก descendant รวมตัวเอง
    func forEachDescendant(_ body: (Entity) -> Void) {
        body(self)
        for child in children { child.forEachDescendant(body) }
    }
}

/// จำสี tint ต้นฉบับของวัสดุแต่ละชิ้นไว้ ณ ครั้งแรกที่เจอ (ดูเหตุผลที่ applyFog ใน ForestSceneView.swift)
private struct ForestOriginalTint: Component {
    var tints: [UIColor]
}

/// จำค่า day ล่าสุดที่ apply ไปแล้ว ไว้ที่ root entity — ใช้ทำ dirty-check ใน applySun (ดูคอมเมนต์ที่นั่น)
private struct ForestLastAppliedDay: Component {
    var day: Float
}

/// สถานะที่เปลี่ยนทุกเฟรมของฉาก (นาฬิกาเวลา + ต้นไม้ผู้เข้าร่วม)
///
/// ต้องเป็น class ถือด้วย @StateObject ไม่ใช่ @State ของ Float/GrowingTree? ตรงๆ เพราะ `update`
/// closure ของ RealityView เขียนค่าพวกนี้ทุกเฟรม — assign ค่าใหม่ให้ตัวแปร @State ระหว่าง view
/// update คือ pattern ที่ SwiftUI เตือนว่า undefined behavior พอดี ("Modifying state during view
/// update") ย้ายมาเป็น property ของ instance เดียวแทน — view แค่ถือ reference คงที่ไว้ (ไม่เคย
/// reassign ตัวแปร @StateObject เองหลังถูกสร้าง) การแก้ property ของ instance จึงไม่ตกปัญหานั้น
/// conform ObservableObject เพราะ @StateObject ต้องการ แต่ไม่มี @Published เลยสักตัวโดยตั้งใจ — ไม่
/// ต้องการให้ SwiftUI สั่ง re-render ตามค่าพวกนี้ (การ tick ทุกเฟรมขับเคลื่อนโดย TimelineView อยู่แล้ว
/// ไม่ใช่โดย Combine publish)
///
/// `tree` อยู่ในนี้ด้วย (ไม่ใช่แค่นาฬิกา) เพราะเหตุผลเดียวกัน: ต้องสร้าง/ลบระหว่าง `update` เมื่อ
/// `host.plantStep` เปลี่ยนสถานะ nil ↔ มีค่า — ถ้าเก็บเป็น @State แยกอีกตัว การ reassign ตอนสร้าง/ลบ
/// ต้นไม้ก็จะตกปัญหาเดียวกัน แม้จะเกิดไม่บ่อยเท่าตัวนาฬิกาก็ตาม
private final class ForestSceneRuntime: ObservableObject {
    var lastTick: TimeInterval = 0
    var elapsed: Float = 0
    /// nil = ยังไม่มีต้นไม้ในฉาก (ตรงกับ host.plantStep == nil) — ดู logic สร้าง/ลบที่ body ด้านบน
    var tree: GrowingTree?
    /// true = เคยลองสร้าง GrowingTree แล้วโหลดพัง (tree == nil หลัง init?) — เลิกลองอีกตลอดอายุ scene
    /// นี้ (เหมือน host.loadFailed ของ forest) กันไม่ให้ retry ทุกเฟรมตราบใดที่ plantStep ยังมีค่า
    var treeLoadFailed = false

    /// คืน deltaTime (วินาที) ของเฟรมนี้ พร้อมสะสม elapsed ไว้ให้ต้นไม้ไหวตามลม
    ///
    /// กัน dt ติดลบด้วย (ไม่ใช่แค่เพดานบน 0.05) เผื่อ timeline.date ไม่ monotonic — ติดลบแล้วต้นไม้จะ
    /// หดวูบหนึ่งเฟรมทันที (height += (target-height)*dt*1.7 ติดลบเมื่อ target > height)
    func tick(now: TimeInterval) -> Float {
        let dt = lastTick == 0 ? 1.0 / 60 : max(0, min(0.05, now - lastTick))
        lastTick = now
        elapsed += Float(dt)
        return Float(dt)
    }
}
