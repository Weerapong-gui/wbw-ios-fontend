import RealityKit
import CoreGraphics
import UIKit

/// ท้องฟ้าและเมฆของแท็บแผนที่
///
/// ทำไมต้องมี: RealityView วาดดำล้วนตรงที่ไม่มีเรขาคณิต ซูมออกสุดแล้วไม่มีโดมจะเห็นพื้นดำรอบโมเดล ·
/// ฉากป่าเจอปัญหาเดียวกันและแก้ด้วยโดมทรงกลมไปแล้ว (`WBW/Scene3D/ForestSceneView.swift`) ที่นี่ใช้
/// แพทเทิร์นเดียวกันแล้วเพิ่มเมฆเข้าไป
///
/// texture ทั้งหมดวาดเองด้วย Core Graphics ไม่ได้เก็บเป็นไฟล์ — โมเดลแผนที่ก็ 10 MB อยู่แล้ว
/// และเมฆแบบนุ่ม ๆ ไม่มีรายละเอียดที่ต้องวาดมือ
enum Map3DSky {

    /// ความสูงของชั้นเมฆที่กล้องจะไต่ผ่านตอน intro — ต้องอยู่ระหว่างระยะเริ่มกับระยะจบของ
    /// `Map3DIntro` ไม่งั้นกล้องไม่ได้ทะลุอะไรเลย (เทสคุมไว้)
    static let cloudLayerHeights: [Float] = [2.9, 2.2, 1.6]

    /// รัศมีโดม — ต้องมากกว่า `Map3DCamera.maxDistance` พอสมควรเพื่อไม่ให้กล้องทะลุออกนอกโดม
    /// ตอนซูมสุด และน้อยกว่า `camera.far` (100) ที่ Map3DScreen ตั้งไว้
    ///
    /// ลดจาก 20 เหลือ 9 (ค่าอยู่ที่ `map_config.json`) — โดมกว้างเกินทำให้เส้นขอบฟ้าอยู่ไกลจน
    /// มีที่ว่างระหว่างขอบแผ่นกับขอบโดมให้เห็นเป็นช่องโล่ง · แคบลงแล้วฟ้าโอบเข้ามาใกล้ขอบแผ่นกว่าเดิม
    static var domeRadius: Float { Map3DConfig.current.sky.domeRadius }

    /// สีฟ้าของโดม
    static let skyColor = UIColor(red: 0.62, green: 0.78, blue: 0.88, alpha: 1)

    // MARK: - ตัววาดภาพ (ฟังก์ชันบริสุทธิ์ เทสเรียกตรงได้)

    /// ผืนขาวล้วนที่ความจางอยู่ในช่อง alpha อย่างเดียว — เขียน buffer เองไม่ผ่าน CGContext
    ///
    /// ⚠️ ห้ามกลับไปใช้ `UIGraphicsImageRenderer`/`CGContext` วาด: bitmap ที่ได้เป็น
    /// **premultiplied** เสมอ (CGBitmapContext ไม่รองรับ straight alpha เลย) ขาว alpha 0.5
    /// จึงถูกเก็บเป็น RGB 128 · RealityKit อ่านเป็น straight alpha ก็ได้ "เทา" แทน "ขาวจาง"
    /// ของจริงที่เจอ: ก้อนเมฆ intro กลายเป็นหมอกเทาทึบทั้งผืนแทนที่จะเป็นปุยขาวจาง ๆ ยิ่งชั้นซ้อน
    /// กันยิ่งเทาเข้ม ดูเหมือนบั๊กเรื่องแสงหรือค่า opacity จนกว่าจะไปอ่านค่าพิกเซลดิบ (เทสคุมไว้แล้ว)
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

    // MARK: - เรขาคณิต

    /// ชื่อ entity แม่ — มีไว้ให้อ่านชื่อออกตอนไล่ดูโครง entity ใน debugger เท่านั้น
    ///
    /// เคยถูกใช้เป็นกุญแจของ `findEntity(named:)` ที่ `Map3DScreen` เพื่อกันโดมซ้อน แต่ที่นั่นค้นบน
    /// `root` ที่สร้างใหม่ทุกรอบ จึงตอบ nil เสมอและไม่เคยกันอะไรได้ — ลบทิ้งไปแล้ว
    static let rootName = "Sky"
    /// ชั้นเมฆทั้งหมดอยู่ใต้ entity นี้ — ปิดทีเดียวจบตอน intro เล่นจบ
    static let cloudsName = "Clouds"

    /// สร้างโดม + ชั้นเมฆ intro
    ///
    /// **ไม่มีม่านขอบกับชายพื้นแล้ว** สองอย่างนั้นมีไว้ปิด "สันตัด" ของแผ่นภูมิประเทศใบเก่าที่เป็น
    /// หน้าตัดเปล่า ๆ · Map2.0 วางแผนที่ไว้บนแผ่น `stumpBase` ที่เป็นตอไม้จริง ผิวข้างเป็น
    /// เปลือกไม้ (`barkSide.png`) หนา 150 หน่วยและปิดก้นในตัว ม่านจึงกลายเป็นกระโปรงคลุมทับลายไม้
    ///
    /// ถ้าวันหลังเปลี่ยนโมเดลกลับไปเป็นแผ่นหน้าตัดเปล่าอีก ให้กู้ทั้งสองอย่างจาก git history
    /// (คอมมิตที่ลบออกอ้างเหตุผลไว้ครบ) และคำนวณความกว้างจาก `anchor.halfSpanUnits*`
    /// ไม่ใช่จาก `visualBounds` เหมือนเดิม
    @MainActor
    static func build() -> Entity {
        let sky = Entity()
        sky.name = rootName

        // ครึ่งความกว้างของแผนที่หลังย่อสเกล — คิดจาก `Map3DScreen.normalisedSpan` ตรง ๆ ไม่ใช่
        // ฮาร์ดโค้ด 1 ไว้เฉย ๆ เพราะ "โมเดลกว้าง 2 หน่วยเสมอ" เป็นข้อตกลงที่เจ้าของอยู่อีกไฟล์
        // ปล่อยเป็นเลขดิบแล้วเปลี่ยนฝั่งโน้นเมื่อไหร่ ที่นี่จะเพี้ยนเงียบ ๆ ไม่มีเทสไหนแดง
        // · Map2.0 เกือบจัตุรัส (±2292 × ±2288 หน่วย) สองแกนต่างกันไม่ถึง 0.2% ใช้ค่าเดียวได้
        let mapRadius = Map3DScreen.normalisedSpan / 2

        // โดมท้องฟ้า — faceCulling .none เพราะกล้องอยู่ "ข้างใน" ทรงกลม ถ้าปล่อย cull back-face
        // ตามค่าปริยาย กล้องจากข้างในจะเห็นแต่ด้านหลังของทุกหน้าแล้วโดน cull ทิ้งหมด กลับไปดำเหมือนเดิม
        // (เหตุผลเดียวกับโดมของฉากป่า) · UnlitMaterial เพราะต้องการสีฟ้าเรียบ ไม่ให้ทิศแสงมาไล่เฉด
        var domeMaterial = UnlitMaterial(color: skyColor)
        domeMaterial.faceCulling = .none
        let dome = ModelEntity(mesh: .generateSphere(radius: domeRadius), materials: [domeMaterial])
        dome.name = "SkyDome"
        sky.addChild(dome)

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
            // วงซ้อนหลายชั้นชัดมาก (เทียบสกรีนช็อตก่อน/หลังแล้ว)

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
