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

    var body: some View {
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
            // งานทั้งหมดตอนซ่อนไปเลย ไม่ใช่แค่ไม่โชว์ผล (สำคัญตอน Task 7 ผูก gyro เข้ากับ host ที่ ~60Hz)
            guard host.enabled, let root = content.entities.first else { return }
            applySun(to: root, day: host.day)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)   // พื้นหลังล้วน ห้ามกินทัชของ UI ข้างหน้า
    }

    /// ตั้งสี/ทิศ/ความแรงของแสง + สีหมอกของทั้ง 8 แถบ ตามเวลาของวัน
    ///
    /// dirty-check: ข้ามทั้งฟังก์ชัน (รวม applyFog ที่เรียกต่อท้าย) ถ้า day เท่าเดิมกับที่ apply ไปแล้ว
    /// จำไว้ที่ root entity ผ่าน ForestLastAppliedDay ไม่ใช่ @State ของ View (เหตุผลเดียวกับ
    /// ForestOriginalTint — @State อาจถูกสร้างใหม่ได้ แต่ entity อยู่คงที่ตราบใดที่ฉากยังไม่ถูกทำลาย)
    /// จำเป็นเพราะ update ถูกเรียกทุกครั้งที่ SwiftUI re-render ไม่ใช่แค่ตอน day เปลี่ยนจริง — ถ้าไม่กัน
    /// ตรงนี้ Task 7 (gyro ~60Hz ผูกเข้ากับ host) จะไล่ applyFog ทั้งฉาก (1148 node, 586 material,
    /// UIColor allocation ทุกตัว) ทุกเฟรมทั้งที่แสง/หมอกไม่ได้เปลี่ยนเลย — เทียบ Float ตรงๆ ไม่ใช้ epsilon
    /// เพราะ day มาจากค่าที่ตั้งไม่ต่อเนื่อง (ForestMath.day/.dayStill ฯลฯ) ไม่ใช่ค่า integrate ทีละเฟรม
    /// การขยับกล้อง (Task 7) ไม่เกี่ยวกับ guard นี้ — นั่นถูกทุกเฟรมได้เพราะเบากว่ากันมาก
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
