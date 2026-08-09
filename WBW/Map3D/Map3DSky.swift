import RealityKit
import CoreGraphics
import UIKit

/// ท้องฟ้า เมฆ และม่านปิดขอบของแท็บแผนที่
///
/// ทำไมต้องมี: RealityView วาดดำล้วนตรงที่ไม่มีเรขาคณิต ถ่ายจริงที่ `-uitestMapPitch 8` เห็น
/// **สันตัดของแผ่นภูมิประเทศ** เป็นแถบพาดกลางจอ กับพื้นดำรอบโมเดลทั้งบนและล่าง · ฉากป่าเจอ
/// ปัญหาเดียวกันและแก้ด้วยโดมทรงกลมไปแล้ว (`WBW/Scene3D/ForestSceneView.swift`) ที่นี่ใช้
/// แพทเทิร์นเดียวกันแล้วเพิ่มม่านขอบกับเมฆเข้าไป
///
/// texture ทั้งหมดวาดเองด้วย Core Graphics ไม่ได้เก็บเป็นไฟล์ — โมเดลแผนที่ก็ 10 MB อยู่แล้ว
/// และเมฆแบบนุ่ม ๆ ไม่มีรายละเอียดที่ต้องวาดมือ
enum Map3DSky {

    /// ความสูงของชั้นเมฆที่กล้องจะไต่ผ่านตอน intro — ต้องอยู่ระหว่างระยะเริ่มกับระยะจบของ
    /// `Map3DIntro` ไม่งั้นกล้องไม่ได้ทะลุอะไรเลย (เทสคุมไว้)
    static let cloudLayerHeights: [Float] = [2.9, 2.2, 1.6]

    /// รัศมีโดม — ต้องมากกว่า `Map3DCamera.maxDistance` (4.0) พอสมควรเพื่อไม่ให้กล้องทะลุออก
    /// นอกโดมตอนซูมสุด และน้อยกว่า `camera.far` (100) ที่ Map3DScreen ตั้งไว้
    static let domeRadius: Float = 20

    /// สีฟ้าของโดม — ม่านขอบใช้สีเดียวกันเป๊ะ ส่วนที่ทึบของม่านจึงกลืนไปกับท้องฟ้าสนิท
    /// ต่างกันเมื่อไหร่ม่านจะกลายเป็นแถบสีพาดขวางแทนที่จะหายไป
    static let skyColor = UIColor(red: 0.62, green: 0.78, blue: 0.88, alpha: 1)

    // MARK: - ตัววาดภาพ (ฟังก์ชันบริสุทธิ์ เทสเรียกตรงได้)

    /// ผืนขาวล้วนที่ความจางอยู่ในช่อง alpha อย่างเดียว — เขียน buffer เองไม่ผ่าน CGContext
    ///
    /// ⚠️ ห้ามกลับไปใช้ `UIGraphicsImageRenderer`/`CGContext` วาด: bitmap ที่ได้เป็น
    /// **premultiplied** เสมอ (CGBitmapContext ไม่รองรับ straight alpha เลย) ขาว alpha 0.5
    /// จึงถูกเก็บเป็น RGB 128 · RealityKit อ่านเป็น straight alpha ก็ได้ "เทา" แทน "ขาวจาง"
    /// ของจริงที่เจอ: ม่านขอบขึ้นเป็นแถบมืดพาดขวางท้องฟ้า และเมฆกลายเป็นหมอกเทาทั้งผืน
    /// ทั้งสองอย่างดูเหมือนบั๊กเรื่องแสง/ค่า opacity จนกว่าจะไปอ่านค่าพิกเซลดิบ (เทสคุมไว้แล้ว)
    private static func whiteMask(width: Int, height: Int,
                                  alphaAt: (Int, Int) -> Float) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let alpha = min(max(alphaAt(x, y), 0), 1)
                pixels[(y * width + x) * 4 + 3] = UInt8(alpha * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }

    /// ก้อนเมฆนุ่ม ๆ บนผืนโปร่งใส — หย่อมกลมจางออกจากศูนย์กลางหลายหย่อมทับกัน
    ///
    /// ต้องมีทั้งส่วนโปร่งและส่วนทึบ: ทึบทั้งผืน = ได้สี่เหลี่ยมขาว · โปร่งทั้งผืน = วาดไม่ติด
    /// ทั้งสองแบบขึ้นจอแล้วดูไม่ออกว่าผิดจนกว่าจะเทียบภาพ (เทสคุมไว้)
    static func cloudImage(size: Int) -> CGImage? {
        // ตำแหน่ง/รัศมีคงที่ ไม่สุ่ม — ภาพต้องเหมือนเดิมทุกครั้งที่รัน ไม่งั้นเทียบสกรีนช็อตไม่ได้
        let blobs: [(x: Float, y: Float, r: Float, a: Float)] = [
            (0.50, 0.52, 0.30, 1.00), (0.34, 0.47, 0.22, 0.90), (0.66, 0.48, 0.24, 0.92),
            (0.44, 0.40, 0.18, 0.80), (0.58, 0.62, 0.20, 0.78), (0.24, 0.58, 0.15, 0.65),
            (0.76, 0.60, 0.16, 0.68),
        ]
        return whiteMask(width: size, height: size) { px, py in
            let s = Float(size)
            let x = Float(px) / s, y = Float(py) / s
            var accumulated: Float = 0
            for blob in blobs {
                let distance = ((x - blob.x) * (x - blob.x) + (y - blob.y) * (y - blob.y)).squareRoot()
                guard distance < blob.r else { continue }
                // smoothstep ไม่ใช่เส้นตรง — เส้นตรงทำให้ความชันของ alpha หักมุมที่ขอบพอดี
                // ตาจับได้เป็น "เส้นวง" รอบก้อน และพอหลายก้อนซ้อนกันจะเห็นเป็นวงซ้อนหลายชั้น
                // (เห็นชัดมากจากสกรีนช็อตกลางแอนิเมชัน) · smoothstep ชันเป็นศูนย์ที่ปลายทั้งสอง
                let t = 1 - distance / blob.r
                let value = blob.a * t * t * (3 - 2 * t)
                accumulated += value * (1 - accumulated)
            }
            return accumulated
        }
    }

    /// สัดส่วนความสูงช่วงบนของม่านที่ยังไล่จาง — ที่เหลือด้านล่างทึบเต็ม
    ///
    /// เคยไล่จางตลอดความสูง (0 บน → 1 ล่าง) แล้วบังไม่มิด: สันตัดที่เห็นตอนกล้องต่ำอยู่ราวกึ่งกลาง
    /// ผนัง ซึ่งตรงนั้น alpha ได้แค่ ~0.5 · วัดจากจอจริงที่ `-uitestMapPitch 6`: ไม่มีม่านได้
    /// (10,22,16) เกือบดำ · ม่านไล่จางทั้งผืนได้ (80,98,108) ยังเป็นแถบมืดชัดเจน
    /// เหลือช่วงจางไว้เฉพาะขอบบนเพื่อไม่ให้รอยต่อกับผิวภูมิประเทศเป็นเส้นคม
    static let curtainFadeFraction: Float = 0.3

    /// ม่านปิดขอบ — ทึบที่ล่าง จางหายที่บน
    ///
    /// กลับด้านเมื่อไหร่มันจะไปบังภูมิประเทศแทนที่จะบังสันตัด (เทสคุมทิศไว้)
    static func edgeCurtainImage(width: Int, height: Int) -> CGImage? {
        whiteMask(width: width, height: height) { _, y in
            // y=0 คือแถวบนสุดของ CGImage
            let depth = Float(y) / Float(max(height - 1, 1))
            return min(depth / curtainFadeFraction, 1)
        }
    }

    // MARK: - เรขาคณิต

    /// ชื่อ entity แม่ — เช็คก่อนสร้างกันโดมซ้อนสองใบตอน view ถูก mount ซ้ำ
    static let rootName = "Sky"
    /// ชั้นเมฆทั้งหมดอยู่ใต้ entity นี้ — ปิดทีเดียวจบตอน intro เล่นจบ
    static let cloudsName = "Clouds"

    /// สร้างโดม + ม่านขอบ + ชั้นเมฆ · `halfX`/`halfZ` = ครึ่งความกว้างจริงของโมเดลหลังย่อสเกลแล้ว
    ///
    /// ต้องรับสองแกนแยกกัน ไม่ใช่ "รัศมี" ค่าเดียว — พื้นที่งานเป็นสี่เหลี่ยมผืนผ้า (4470×5162 ม.)
    /// ใช้ค่าเดียวแล้ววงม่านจะพอดีแค่แกนกว้าง ส่วนแกนแคบม่านจะลอยห่างขอบจนเห็นเป็นวงแยกกลางฟ้า
    @MainActor
    static func build(halfX: Float, halfZ: Float, slabDepth: Float) -> Entity {
        let sky = Entity()
        sky.name = rootName
        let mapRadius = max(halfX, halfZ)

        // โดมท้องฟ้า — faceCulling .none เพราะกล้องอยู่ "ข้างใน" ทรงกลม ถ้าปล่อย cull back-face
        // ตามค่าปริยาย กล้องจากข้างในจะเห็นแต่ด้านหลังของทุกหน้าแล้วโดน cull ทิ้งหมด กลับไปดำเหมือนเดิม
        // (เหตุผลเดียวกับโดมของฉากป่า) · UnlitMaterial เพราะต้องการสีฟ้าเรียบ ไม่ให้ทิศแสงมาไล่เฉด
        var domeMaterial = UnlitMaterial(color: skyColor)
        domeMaterial.faceCulling = .none
        let dome = ModelEntity(mesh: .generateSphere(radius: domeRadius), materials: [domeMaterial])
        dome.name = "SkyDome"
        sky.addChild(dome)

        // ม่านขอบ — ผนังรอบวงที่ประกอบจากระนาบเรียงกัน **ไม่ใช่ generateCylinder**
        //
        // เคยใช้ generateCylinder แล้วพัง: mesh ตัวนั้นมีฝาบน-ล่างมาด้วย ฝาบนที่โปร่งแสงเลย
        // คลุมแผนที่ทั้งผืนกลายเป็นหมอกเทาสม่ำเสมอทั้งจอ (เห็นชัดจากสกรีนช็อต) และ RealityKit
        // ไม่มีตัวเลือกสร้างทรงกระบอกแบบเปิดหัวท้าย จึงต้องเรียงระนาบเอง
        //
        // สูงแค่ความหนาของแผ่นบวกนิดหน่อย — ม่านนี้มีหน้าที่ปิด "สันตัด" ด้านข้างเท่านั้น
        // สูงเกินเมื่อไหร่จะเลยขึ้นมาบังผิวภูมิประเทศ
        if let curtain = edgeCurtainImage(width: 8, height: 64),
           let texture = try? TextureResource(image: curtain, options: .init(semantic: .color)) {
            var material = UnlitMaterial()
            material.color = .init(tint: skyColor, texture: .init(texture))
            material.opacityThreshold = 0
            material.blending = .transparent(opacity: 1.0)
            material.faceCulling = .none

            let ring = Entity()
            ring.name = "EdgeCurtain"
            let segments = 32
            // 1.02 = อยู่ "นอก" ขอบแผ่นเล็กน้อย · เคยตั้ง 0.995 (ในเนื้อ) แล้วสันตัดบังม่านเสียเอง
            let a = halfX * 1.02, b = halfZ * 1.02
            let height = slabDepth * 1.05
            func point(_ index: Int) -> SIMD2<Float> {
                let angle = 2 * .pi * Float(index) / Float(segments)
                return SIMD2<Float>(a * sin(angle), b * cos(angle))
            }
            for index in 0..<segments {
                let start = point(index), end = point(index + 1)
                let chord = end - start
                // ความกว้าง = ความยาวคอร์ด ไม่ใช่ส่วนโค้ง ไม่งั้นแผ่นเกยกันเป็นสัน
                // (คูณ 1.02 กันช่องแสงลอดตามรอยต่อ — วงรีทำให้คอร์ดยาวไม่เท่ากันทุกช่วง)
                let panel = ModelEntity(
                    mesh: .generatePlane(width: length(chord) * 1.02, height: height),
                    materials: [material])
                let mid = (start + end) / 2
                panel.position = SIMD3<Float>(mid.x, 0, mid.y)
                // ระนาบของ generatePlane(width:height:) หันหน้าไป +Z และกว้างตามแกน X ของตัวเอง
                // หมุนรอบ Y ให้แกน X ทาบไปตามคอร์ด หน้าจึงหันออกนอกวงพอดี
                panel.orientation = simd_quatf(angle: atan2(-chord.y, chord.x),
                                               axis: SIMD3<Float>(0, 1, 0))
                ring.addChild(panel)
            }
            sky.addChild(ring)
        }

        // ชั้นเมฆที่กล้องจะทะลุลงมา — เป็นของสำหรับ intro เท่านั้น ปิดทิ้งเมื่อเล่นจบ
        // ปล่อยเปิดไว้แล้วมุมกล้องต่ำ ๆ จะมองทะลุชั้นเมฆเห็นแผนที่เป็นสีจาง ๆ ทั้งจอ
        let clouds = Entity()
        clouds.name = cloudsName
        sky.addChild(clouds)
        if let cloud = cloudImage(size: 512),
           let texture = try? TextureResource(image: cloud, options: .init(semantic: .color)) {
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(texture))
            material.blending = .transparent(opacity: .init(floatLiteral: 0.9))
            material.faceCulling = .none
            // ⚠️ ห้ามใส่ `opacityThreshold` ให้ material นี้ — ค่านั้นสั่งให้ RealityKit ใช้
            // alpha test แทน alpha blend ผลคือขอบก้อนไล่เฉดเป็นขั้น ๆ พอหลายก้อนซ้อนกันเห็นเป็น
            // วงซ้อนหลายชั้นชัดมาก (เทียบสกรีนช็อตก่อน/หลังแล้ว) · ม่านขอบยังต้องใช้อยู่เพราะมัน
            // ทึบเกือบทั้งผืน ไม่มีบริเวณไล่เฉดกว้างให้เห็นขั้น

            // ก้อนย่อยกระจายกัน **ไม่ใช่ระนาบใหญ่แผ่นเดียวต่อชั้น**
            //
            // เคยทำเป็นระนาบเดียวกว้าง 2.6-4.4 เท่าของรัศมีแผนที่ แล้วมันคลุมเต็มเฟรมตลอด
            // แอนิเมชันเลยกลายเป็น "ฝ้าขาวทั้งจอค่อย ๆ จาง" ไม่ใช่ "บินผ่านก้อนเมฆ" (เห็นชัดจาก
            // สกรีนช็อตกลางแอนิเมชัน: แผนที่ทั้งผืนถูกฟอกเป็นสีเทาเรียบ ไม่มีรูปทรงก้อนเลย)
            // ต้องมีช่องว่างระหว่างก้อนให้เห็นแผนที่ลอด ตาถึงจะอ่านว่ากำลังเคลื่อนที่ผ่านอะไรอยู่
            let puffsPerLayer = 6
            for (layerIndex, height) in cloudLayerHeights.enumerated() {
                for puffIndex in 0..<puffsPerLayer {
                    let seed = Float(layerIndex * puffsPerLayer + puffIndex)
                    // มุมทองคำ (2.39996 เรเดียน) — กระจายก้อนไม่ให้เรียงเป็นวงหรือซ้อนกันเป็นแถว
                    // ใช้ค่าคำนวณจาก index ไม่ใช่ค่าสุ่ม ภาพจะได้เหมือนเดิมทุกครั้งที่รัน เทียบสกรีนช็อตได้
                    let angle = seed * 2.399963
                    let radius = mapRadius * (0.2 + 0.24 * Float(puffIndex))
                    let span = mapRadius * (0.9 + 0.3 * Float((puffIndex + layerIndex) % 3))
                    let puff = ModelEntity(mesh: .generatePlane(width: span, height: span),
                                           materials: [material])
                    puff.name = "Cloud\(layerIndex)-\(puffIndex)"
                    // หันหน้าเข้ากล้องเสมอ — กล้อง intro บินทะลุชั้นเมฆ ระนาบแบนที่ตรึงทิศไว้จะถูก
                    // มองแบบเฉียงจนเกือบขนานสายตา แล้วขอบสี่เหลี่ยมของแผ่นโผล่เป็นเส้นตรงพาดท้องฟ้า
                    // (เห็นชัดจากสกรีนช็อต) · billboard ทำให้ไม่มีมุมไหนที่เห็นแผ่นเป็นแผ่น
                    puff.components.set(BillboardComponent())
                    // เยื้องความสูงเล็กน้อยกันก้อนในชั้นเดียวกัน z-fight ตอนขอบซ้อนกัน
                    puff.position = SIMD3<Float>(cos(angle) * radius,
                                                 height + Float(puffIndex) * 0.02,
                                                 sin(angle) * radius)
                    puff.orientation = simd_quatf(angle: seed * 0.9, axis: SIMD3<Float>(0, 1, 0))
                    clouds.addChild(puff)
                }
            }
        }

        return sky
    }
}
