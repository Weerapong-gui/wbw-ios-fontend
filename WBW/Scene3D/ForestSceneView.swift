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
            guard let root = content.entities.first else { return }
            applySun(to: root, day: host.day)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)   // พื้นหลังล้วน ห้ามกินทัชของ UI ข้างหน้า
    }

    /// ตั้งสี/ทิศ/ความแรงของแสง + สีหมอกของทั้ง 8 แถบ ตามเวลาของวัน
    private func applySun(to root: Entity, day: Float) {
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
                pbr.baseColor.tint = mix(.white, uiColor(fog), amount)
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
