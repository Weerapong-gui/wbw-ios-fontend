import CoreGraphics
import Foundation

/// เรขาคณิตของดอกไม้ halftone — พอร์ตมาจาก `ui/home/Bloom.kt` (Android) ทั้งชุด
///
/// **วิธีวาด:** จุดวางบนตารางคงที่แล้วปรับ "รัศมี" ตามว่าดอกไม้คลุมช่องนั้นแค่ไหน ไม่ใช่พ่นจุด
/// ตามเส้นขอบ — นั่นคือสิ่งที่ทำให้ได้ผิวแบบภาพพิมพ์ และเป็นสิ่งที่ทำให้มันอ่านออกในแวบเดียว
/// (พ่นตามขอบจะอ่านเป็นประกาย พิมพ์แบบ halftone อ่านเป็นรูปทรง)
///
/// ทุกอย่างเป็น deterministic — ความไม่เท่ากันมาจาก hash ของพิกัดช่อง ดอกไม้ขั้นเดิมจึงวาดออกมา
/// เหมือนเดิมทุกครั้ง ไม่มี state ของตัวสุ่มให้ดูแล และไม่มีการ allocate ต่อเฟรม
///
/// การคลุมคำนวณตรง ๆ ไม่ raster: จุดอยู่ในกลีบถ้าระยะตามแนวขวางของกลีบไม่เกินครึ่งความกว้าง
/// ที่ตำแหน่งนั้นตามแนวยาว — ที่ตาราง 6 pt คือการทดสอบราคาถูกไม่กี่พันครั้ง
enum BloomGeometry {

    /// จะวาดทั้งต้น (มีก้าน+ใบ) หรือเฉพาะดอก (ใช้ในชิปแถบขั้น ซึ่งไม่มีที่ให้ก้าน)
    enum Kind { case plant, head }

    /// จุดหนึ่งจุดของ halftone · `jitter` คือเฟสของการ "หายใจ" ประจำจุด
    struct Dot {
        let x: CGFloat, y: CGFloat, r: CGFloat, alpha: CGFloat, jitter: CGFloat
    }

    // MARK: - ค่าคงที่ของ "พื้นที่ดอกไม้" (หน่วยของต้นฉบับ ไม่ใช่ pixel)

    static let cx: CGFloat = 150
    static let cy: CGFloat = 176
    /// กลีบที่ยาวที่สุด = รัศมีของดอกตอนบานเต็มที่
    static let maxPetal: CGFloat = 80
    static let flowerWidth: CGFloat = 176
    static let flowerHeight: CGFloat = 206   // maxPetal 80 + stemLength 112 + เผื่ออีก 14
    static let stemLength: CGFloat = 112
    /// ระยะที่ "หัวดอกอย่างเดียว" กินจริง — ใช้ตอนไม่วาดก้าน
    static let headSpan: CGFloat = 160
    static let headFitExponent: CGFloat = 0.4

    // MARK: - โทน (ทุกตัวเป็นตัวคูณของ "การคลุม")

    /// halftone มีช่องทางเดียว: การคลุม ซึ่งคุมทั้งรัศมีจุดและความจางของจุด ไม่มีสีที่สองให้แรเงา
    /// ทุกค่าข้างล่างจึงเป็นตัวคูณของค่าเดียวกันนั้น (ยกทั้งชุดมาจาก `Bloom.kt`)

    /// กลีบสลับหน้า-หลัง เหมือนวงกลีบจริงที่แต่ละใบซุกใต้ใบถัดไป — พัดที่ทุกกลีบโทนเดียวกัน
    /// คือพัดที่นับกลีบไม่ได้ ต่อให้มีกี่กลีบก็ตาม
    static let petalBack: CGFloat = 0.80
    static let petalFront: CGFloat = 1.0
    /// วงในนั่งอยู่ข้างในถ้วย ไม่ได้อยู่กลางแสง
    static let innerShade: CGFloat = 0.70
    /// ตาของดอก — **หม่นโดยตั้งใจ** ดูคำอธิบายที่ `rootShade`
    static let coreShade: CGFloat = 0.62
    /// ใบกับก้านอยู่ใต้หัวดอกนิดหนึ่ง ดอกจะได้เป็นของที่สว่างที่สุดเสมอ
    static let leafShade: CGFloat = 0.88
    static let stemShade: CGFloat = 0.85
    /// โคนกลีบเข้มแค่ไหน ไล่ขึ้นไปเต็มที่ตรงปลาย
    ///
    /// หัวดอกคือถ้วย ตรงกลางอยู่ในเงา ปลายกลีบคือส่วนที่รับแสง · ของเดิมให้แสงกลับด้าน
    /// (แกนกลางทึบที่การคลุม 1.0 สว่างกว่าทุกอย่างรอบตัว) และแกนที่โชนอยู่กลางพื้นที่เรียบ ๆ
    /// คือรูปร่างของ "รอยกระเด็น" เป๊ะ ๆ · การกลับไล่โทนด้านนี้คือการแก้ครั้งเดียวที่ทำให้หัวดอก
    /// อ่านว่ามีด้านใกล้กับด้านไกล
    static let rootShade: CGFloat = 0.62
    /// กลีบเข้มขึ้นแค่ไหนเมื่อเข้าใกล้ขอบของตัวเอง — เส้นนี้คือสิ่งที่แยกกลีบใบหนึ่งออกจากใบที่อยู่ใต้มัน
    static let rimShade: CGFloat = 0.30
    /// กลีบถอยไปแค่ไหนเมื่อหันขอบเข้าหาคนดู — ถ้วยเปิดขึ้นฟ้า กลีบที่ชี้ขึ้นจึงหันด้านในที่รับแสง
    /// มาให้เรา ส่วนกลีบที่ชี้ออกข้างถูกเห็นแบบเฉียงขอบ · ลำพังมันคือไล่โทนแนวตั้งธรรมดา
    /// แต่พอทาบลงบนพัดของกลีบ มันคือสิ่งที่ทำให้ถ้วยมี "ข้างใน"
    static let leanShade: CGFloat = 0.76
    /// สัดส่วนของครึ่งความกว้างที่ยกให้เป็นขอบนุ่ม ที่เหลือเป็นเนื้อแบนความเข้มเต็ม
    ///
    /// เพื่อให้กลีบ **บัง** สิ่งที่อยู่ข้างหลังจริง ๆ ไม่ใช่เฉลี่ยรวมกับมัน · หน้าตัดแบบโดมที่จางจาก
    /// สันไล่ออกไปจนถึงขอบจะประกอบกันเป็นโคลน เพราะไม่มีส่วนไหนของกลีบที่อยู่หน้าอย่างไม่กำกวมเลย
    static let petalEdge: CGFloat = 0.30
    /// ชิปในแถบขั้นถูกดันกลับขึ้นไปหาความเข้มก่อนแรเงาเท่าไหร่
    ///
    /// โมเดลความลึกยังทำงานบนชิปอยู่ (โทน *สัมพัทธ์* คือส่วนหนึ่งของสิ่งที่ทำให้ชิปอ่านเป็นดอกไม้
    /// ไม่ใช่รอยเปื้อน) แต่ระดับสัมบูรณ์ของมันถูกตั้งไว้สำหรับดอกที่สูงเท่าจอ · ที่ 50pt
    /// การแรเงาละเอียดกว่าที่ตาแยกออกอยู่แล้ว และสิ่งเดียวที่มันทำคือกดสองขั้นที่จางที่สุด
    /// (เมล็ดกับตูม) ให้ต่ำกว่าระดับที่ชิปขั้นที่ยังไม่ถึงจะมองเห็นได้เลย
    static let headGain: CGFloat = 1.4

    /// กลีบหนึ่งใบ · `shade` คือ "โทน" ของกลีบนั้น ซึ่งเป็นช่องทางเดียวที่ halftone มีให้ใช้บอก
    /// ความลึก (ไม่มีสีที่สอง มีแต่ความเข้มของการคลุม ซึ่งคุมทั้งรัศมีจุดและความจางของจุด)
    struct Petal {
        let cx: CGFloat, cy: CGFloat, ang: CGFloat, len: CGFloat, halfWidth: CGFloat
        let shade: CGFloat
    }

    private struct LeafSpec {
        let alongStem: CGFloat, angle: CGFloat, length: CGFloat, fromStage: CGFloat
    }

    /// ใบสองใบคนละความสูงคนละข้าง — ใบเดียวอ่านว่าวาดผิด สองใบสมมาตรอ่านว่าเป็นโลโก้
    /// สองใบคนละระดับคือสิ่งที่ทำให้ก้านดูงอกเองไม่ใช่ถูกเขียนขึ้น · ใบที่สองโผล่ทีหลัง
    /// ต้นไม้จะได้เพิ่มอะไรบางอย่างในช่วงขั้นกลาง ไม่ใช่แค่หัวกว้างขึ้นอย่างเดียว
    private static let leaves = [
        LeafSpec(alongStem: 0.40, angle: 150, length: 34, fromStage: 1.0),
        LeafSpec(alongStem: 0.66, angle: 32, length: 29, fromStage: 2.4),
    ]

    // MARK: - กลีบตามขั้น

    /// ทุกค่าต่อเนื่องตาม `stage` เพราะขั้นถูก animate — ค่าไหนกระโดดเป็นขั้นจะเห็นมันกระโดด
    ///
    /// สามอย่างที่เคยกระโดดใน Android แล้วแก้ไปแล้ว และพอร์ตมาแบบที่แก้แล้ว: จำนวนกลีบ
    /// (กลีบใหม่ยืดความยาวจาก 0 แทนที่จะโผล่มาเต็มความยาวพร้อมกัน), ความกว้างกลีบ
    /// (interpolate แทน branch แยกตอนมีกลีบเดียว) และ seed ของความไม่เท่ากัน (ผูกกับดัชนีกลีบ
    /// อย่างเดียว ไม่ผูกกับ stage ที่กำลังวิ่ง ไม่งั้นทั้งดอกจะระยิบระยับตลอดช่วงเปลี่ยนขั้น)
    static func petals(stage: CGFloat, withLeaves: Bool) -> [Petal] {
        let s = min(max(stage, 0), 5)
        let i = min(Int(s), 4)
        let t = s - CGFloat(i)

        // **การกางคือสิ่งที่ตัดสินว่าดอกไม้หันไปทางไหน** และเป็นเหตุผลทั้งหมดที่ขั้นท้าย ๆ
        // เคยอ่านเป็นดาวกระจายแทนที่จะเป็นดอกบาน
        //
        // กาง 166 คือการกวาด 332 องศา: กลีบพันรอบเกือบครบวง และพัดที่ปิดตัวเองได้คือนิยามของ
        // ดอกไม้ที่ถูกมองจากด้านหน้า คือหันหน้าเข้าหาคนดู · กดไว้ใต้ราว 90 แล้วพัดปิดไม่ได้ —
        // ทุกกลีบยังมีองค์ประกอบชี้ขึ้น มันบรรจบกันที่ก้านด้านล่าง และหัวดอกอ่านเป็นถ้วยที่เปิด
        // ขึ้นฟ้า นั่นคือดอกไม้ที่ตั้งใจให้เป็น: เปิดขึ้นทุกขั้นและไม่เคยหันมาหาเรา
        //
        // จำนวนกลีบลดตามลงมาด้วย ระยะห่างระหว่างกลีบคือการกางหารจำนวน การเก็บ 16 กลีบไว้
        // ในพัด 76 องศาจะอัดกันแน่นกว่าตอนอยู่ในพัด 166 องศาที่มันมา และล้างช่องว่างที่ทำให้
        // เห็นการซ้อนชั้นทิ้งไปหมด
        let counts = [0, 1, 6, 9, 12, 14]
        let lengths: [CGFloat] = [0, 30, 40, 52, 64, 80]
        let splays: [CGFloat] = [0, 0, 36, 54, 66, 76]
        // ตูมแล้วป้าน ค่อยเรียวลงตอนกลีบแยกออกจากกัน · สองค่าท้ายแคบกว่าเดิม: ที่ 0.20
        // กลีบขั้น 5 กว้างราว 46 องศาโดยมีที่ว่างคั่นแค่ 21 องศา พัดจึงปิดเป็นจานตันที่ไม่มี
        // การแรเงาระดับไหนเปิดออกได้ · กลีบที่แคบลงเหลือช่องว่างให้เห็นการซ้อนชั้น
        let ratios: [CGFloat] = [0.35, 0.35, 0.24, 0.21, 0.17, 0.17]

        let j = min(i + 1, 5)
        let fromCount = counts[i], toCount = counts[j]
        let length = lerp(lengths[i], lengths[j], t)
        let splay = lerp(splays[i], splays[j], t)
        let ratio = lerp(ratios[i], ratios[j], t)

        var out: [Petal] = []
        out.reserveCapacity(toCount + 12)

        for k in 0..<toCount {
            let jitter = 6 * (hash(CGFloat(k) * 40.7) - 0.5)
            // มุมของกลีบขึ้นกับว่ามีกี่กลีบร่วมพัด จึงต้อง interpolate ข้ามการเปลี่ยนจำนวน
            // ไม่ใช่คำนวณจากจำนวนปลายทางอย่างเดียว — แบบหลังทำให้ทุกกลีบถูกจัดพัดใหม่ในเฟรมเดียว
            let ang: CGFloat = k < fromCount
                ? lerp(fanAngle(k, fromCount, splay, jitter), fanAngle(k, toCount, splay, jitter), t)
                : fanAngle(k, toCount, splay, jitter)
            let grow: CGFloat = k < fromCount ? 1 : t
            let len = length * (0.72 + 0.28 * hash(CGFloat(k) * 70.3)) * grow
            if len <= 0.01 { continue }
            // สัญญาณความลึกสองอย่าง ทั้งคู่ส่งผ่านโทน
            //
            // การซ้อนกลีบ: กลีบสลับหน้า-หลังแบบที่วงกลีบจริงซุกแต่ละใบไว้ใต้ใบถัดไป
            //
            // การเอน: หัวดอกคือถ้วยที่เปิดขึ้น กลีบที่เล็งฟ้าจึงหันด้านในที่รับแสงมาหาเรา
            // ส่วนกลีบที่เล็งออกข้างถูกเห็นแบบเฉียงขอบและเสียแสงไป — นี่คือสิ่งที่กันไม่ให้ถ้วย
            // อ่านเป็นพัดแบน ๆ ของเส้นที่เหมือนกันหมด
            let lean = (1 - sin(ang * .pi / 180)) / 2
            let shade = (k % 2 == 0 ? petalBack : petalFront) * (leanShade + (1 - leanShade) * lean)
            out.append(Petal(cx: cx, cy: cy, ang: ang, len: len, halfWidth: len * ratio, shade: shade))
        }

        // วงใน — สั้นกว่าและชิดกว่า ทำให้ตรงกลางอ่านว่าแน่น ไม่ใช่เป็นรูตรงที่โคนกลีบมาชนกัน
        let innerGrow = min(max((s - 2.5) / 0.9, 0), 1)
        if innerGrow > 0 {
            let innerFrom = fromCount / 2, innerTo = toCount / 2
            for k in 0..<innerTo {
                let jitter = 8 * (hash(CGFloat(k) * 13.9) - 0.5)
                let ang: CGFloat = k < innerFrom
                    ? lerp(innerAngle(k, innerFrom, splay, jitter), innerAngle(k, innerTo, splay, jitter), t)
                    : innerAngle(k, innerTo, splay, jitter)
                let grow: CGFloat = k < innerFrom ? 1 : t
                let len = length * 0.5 * innerGrow * grow
                if len <= 0.01 { continue }
                out.append(Petal(cx: cx, cy: cy, ang: ang, len: len, halfWidth: len * 0.26, shade: innerShade))
            }
        }

        // ใบ — จำลองเป็นกลีบที่โคนอยู่บนก้าน ซึ่งเรขาคณิตแล้วใบก็คือแค่นั้น
        // (ตัวทดสอบการคลุมไม่สนใจว่ากลีบเริ่มจากตรงไหน)
        if withLeaves {
            for (n, leaf) in leaves.enumerated() {
                let grow = min(max((s - leaf.fromStage) / 0.9, 0), 1)
                if grow <= 0 { continue }
                let ly = cy + stemLength * leaf.alongStem
                let lx = cubic(cx, cx + 13, cx - 11, cx + 3, leaf.alongStem)
                let len = leaf.length * grow
                if len <= 0.01 { continue }
                let jitter = 5 * (hash(CGFloat(n) * 27.1) - 0.5)
                out.append(Petal(cx: lx, cy: ly, ang: leaf.angle + jitter, len: len, halfWidth: len * 0.30, shade: leafShade))
            }
        }
        return out
    }

    // MARK: - สร้างสนามจุด

    /// สร้าง halftone ของดอกไม้ที่ขั้น `stage` ให้พอดีกรอบ `size`
    ///
    /// สแกนเฉพาะกรอบของดอกไม้เอง ไม่ใช่ทั้ง canvas — จอ Home ส่วนใหญ่เป็นที่ว่าง
    /// การไล่ทดสอบช่องว่างกับกลีบทั้ง ~26 กลีบก่อนจะ fail คือค่าใช้จ่ายที่ทิ้งไปเปล่า ๆ
    static func build(size: CGSize, stage: CGFloat, step: CGFloat,
                      centreYFraction: CGFloat, kind: Kind) -> [Dot] {
        let w = size.width, h = size.height
        guard w > 0, h > 0, step > 0 else { return [] }

        let ps = petals(stage: stage, withLeaves: kind == .plant)
        let fan = PetalFan(ps)
        let withStem = kind == .plant
        let coreR: CGFloat = 3.5 + 3 * stage

        // สเกลตามระยะที่ดอกไม้กินจริง ไม่ใช่ตามกรอบที่ต้นฉบับวาดไว้ — ต้นฉบับวาดในกล่อง
        // 300×300 แต่กินจริงราวหนึ่งในสาม หารด้วย 300 แล้วดอกไม้จะเป็นรูปจิ๋วกลางจอ
        let scale: CGFloat
        let refX: CGFloat, refY: CGFloat
        switch kind {
        case .head:
            let b = headBounds(ps, stage: stage)
            let bw = max(b.maxX - b.minX, 1), bh = max(b.maxY - b.minY, 1)
            // ไม่ fit เต็ม — fit เต็มแปลว่าเมล็ดใหญ่เท่าดอกบานเต็มที่ แล้วแถบขั้นจะเลิกแสดง
            // "การเติบโต" ซึ่งเป็นสิ่งเดียวที่มันมีไว้แสดง
            let fit = pow(min(max(max(bw, bh) / headSpan, 0.02), 1), headFitExponent)
            scale = min(w / bw, h / bh) * fit
            refX = (b.minX + b.maxX) / 2
            refY = (b.minY + b.maxY) / 2
        case .plant:
            scale = min(w / flowerWidth, h / flowerHeight)
            refX = cx
            refY = cy
        }

        let canvasCX = w / 2
        // จัดกึ่งกลางตามกรอบจริงของดอกไม้ ไม่ใช่กลาง canvas — หัวดอกยื่นขึ้นไปหนึ่งความยาวกลีบ
        // ก้านยื่นลงมาอีกหนึ่ง จุดกำเนิดจึงไม่ได้อยู่ตรงกลาง
        let canvasCY: CGFloat = kind == .plant
            ? h / 2 - (flowerHeight / 2 - maxPetal) * scale
            : h * centreYFraction

        let maxR = step * 0.60
        // ชิปในแถบขั้นถูกดันกลับขึ้นไปหาความเข้มก่อนแรเงา (ดูคำอธิบายที่ `headGain`)
        let gain: CGFloat = kind == .head ? headGain : 1

        var minX = min(fan.minX, cx - coreR), maxX = max(fan.maxX, cx + coreR)
        var minY = min(fan.minY, cy - coreR), maxY = max(fan.maxY, cy + coreR)
        if withStem {
            // ก้านแกว่งไปราว 13 หน่วยจากแกนกลาง ส่วนที่เรียวกว้างขึ้นบวกครึ่งความกว้างทับไปอีก
            minX = min(minX, cx - 19); maxX = max(maxX, cx + 19)
            minY = min(minY, cy - 6);  maxY = max(maxY, cy + stemLength + 4)
        }

        // แปลงกลับเป็น pixel แล้วขยายออกเป็นช่องเต็ม ๆ · ดัชนีช่องนับจากมุม canvas เหมือนเดิม
        // เพราะ hash ของความไม่เท่ากันผูกกับดัชนีนั้น เริ่มสแกนเยื้องไปจะสลับผิวทั้งใบ
        let ix0 = max(0, Int(floor(((minX - refX) * scale + canvasCX) / step)))
        let ix1 = min(Int(ceil(w / step)), Int(ceil(((maxX - refX) * scale + canvasCX) / step)))
        let iy0 = max(0, Int(floor(((minY - refY) * scale + canvasCY) / step)))
        let iy1 = min(Int(ceil(h / step)), Int(ceil(((maxY - refY) * scale + canvasCY) / step)))
        guard ix0 <= ix1, iy0 <= iy1 else { return [] }

        var dots: [Dot] = []
        dots.reserveCapacity((ix1 - ix0 + 1) * (iy1 - iy0 + 1) / 2)

        for iy in iy0...iy1 {
            let gy = CGFloat(iy) * step
            if gy >= h { break }
            for ix in ix0...ix1 {
                let gx = CGFloat(ix) * step
                if gx >= w { break }
                let fx = (gx - canvasCX) / scale + refX
                let fy = (gy - canvasCY) / scale + refY

                var cover = fan.cover(atX: fx, y: fy)

                // ก้าน — เป็นเส้นโค้ง จึงวัดระยะไปหาจุดบนเส้นที่ความสูงนั้น
                if withStem, fy > cy - 6, fy < cy + stemLength + 4 {
                    let t = min(max((fy - cy) / stemLength, 0), 1)
                    let sx = cubic(cx, cx + 13, cx - 11, cx + 3, t)
                    let d = abs(fx - sx)
                    // เรียว: หนาที่โคน บางตรงที่ไปบรรจบกับหัวดอก — แต่เรียวน้อยกว่าเดิมมาก
                    // ที่ 0.45 ของ 3.4 หน่วย ยอดก้านออกมาแคบกว่าหนึ่งช่อง halftone แล้วหลุด
                    // ออกจากภาพไปเลย เหลือหัวดอกลอยพ้นก้านของตัวเอง · ดอกเดิมกลบไว้ได้เพราะ
                    // กลีบมันพันลงมาต่ำกว่าแนวนอนแล้วคลุมรอยต่อ หัวดอกที่เปิดขึ้นฟ้าไม่คลุม
                    // ก้านจึงต้องรอดด้วยตัวเองตรงนั้น
                    let halfW: CGFloat = 4.4 * (0.70 + 0.30 * t)
                    if d < halfW { cover = max(cover, stemShade * (1 - d / halfW)) }
                }

                // แกนกลาง — จุดจะแออัดตรงที่โคนกลีบทุกใบมาชนกัน จึงวาดเป็นเนื้อทึบไปเลย
                // วาดทุกขั้นรวมขั้น 0 ที่มันคือเมล็ด — ถ้ากันไว้ที่ขั้น 1 ชิปแรกของแถบจะว่างสนิท
                // ใต้ป้ายที่เขียนว่า "เมล็ด"
                //
                // **กดไว้ด้วย `coreShade` ไม่ได้วาดเต็มความเข้ม** — ตอนเป็นของที่สว่างที่สุดบน
                // canvas มันเปลี่ยนขั้นที่บานแล้วให้กลายเป็นดาวกระจาย พอเป็นของที่หม่นที่สุด
                // มันคือตาของถ้วย และหัวดอกได้ด้านใกล้ขึ้นมา
                let dc = hypot(fx - cx, fy - cy)
                if dc < coreR { cover = max(cover, coreShade * (1 - (dc / coreR) * 0.35)) }

                if cover <= 0.02 { continue }
                if gain != 1 { cover = min(cover * gain, 1) }
                let n = hash(CGFloat(ix) * 31 + CGFloat(iy) * 57)
                // กระจายรัศมีน้อยลงกว่าเดิม · ที่ ±45% เสียงรบกวนระหว่างจุดกับจุดข้างเคียง
                // ใหญ่กว่าความต่างของโทนที่การแรเงากำลังวาดอยู่ ความลึกจึงมีอยู่ในตัวเลข
                // แต่มองไม่เห็นบนจอ · เหลือไว้พอให้ตารางแตก ไม่พอให้กลบโทน
                let r = maxR * min(cover, 1) * (0.75 + 0.25 * n)
                if r <= 0.25 { continue }
                dots.append(Dot(x: gx + (n - 0.5) * step * 0.35,
                                y: gy + (hash(n) - 0.5) * step * 0.35,
                                // จงใจไม่ใส่ "การหายใจ" ตรงนี้ — มันคือสิ่งเดียวที่เปลี่ยนทุกเฟรม
                                // จึงเอาไปคูณตอนวาดแทน สนามจุดจะได้ไม่ต้องสร้างใหม่ทุกเฟรม
                                r: r,
                                alpha: min(max(0.35 + 0.65 * cover, 0), 1),
                                jitter: n))
            }
        }
        return dots
    }

    // MARK: - ตัวช่วย

    private struct PetalFan {
        private let ox: [CGFloat], oy: [CGFloat], ca: [CGFloat], sa: [CGFloat]
        private let len: [CGFloat], hw: [CGFloat], sh: [CGFloat]
        private let bx0: [CGFloat], bx1: [CGFloat], by0: [CGFloat], by1: [CGFloat]
        let minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat

        init(_ petals: [Petal]) {
            // sin/cos ต่อกลีบถูกยกออกมานอกลูปช่อง — เดิมคำนวณซ้ำทุกช่องคูณทุกกลีบ
            // เป็นบรรทัดที่แพงที่สุดในการวาดทั้งหมด
            var ox: [CGFloat] = [], oy: [CGFloat] = [], ca: [CGFloat] = [], sa: [CGFloat] = []
            var len: [CGFloat] = [], hw: [CGFloat] = [], sh: [CGFloat] = []
            var bx0: [CGFloat] = [], bx1: [CGFloat] = [], by0: [CGFloat] = [], by1: [CGFloat] = []
            var mnX = CGFloat.greatestFiniteMagnitude, mxX = -CGFloat.greatestFiniteMagnitude
            var mnY = CGFloat.greatestFiniteMagnitude, mxY = -CGFloat.greatestFiniteMagnitude

            for p in petals {
                let a = p.ang * .pi / 180
                let c = cos(a), s = sin(a)
                ox.append(p.cx); oy.append(p.cy); ca.append(c); sa.append(s)
                len.append(p.len); hw.append(p.halfWidth); sh.append(p.shade)
                // กลีบกว้างสุดที่เอว 1.1 เผื่อไหล่ของการเรียว
                let pad = p.halfWidth * 1.1
                let tipX = p.cx + p.len * c, tipY = p.cy + p.len * s
                let x0 = min(p.cx, tipX) - pad, x1 = max(p.cx, tipX) + pad
                let y0 = min(p.cy, tipY) - pad, y1 = max(p.cy, tipY) + pad
                bx0.append(x0); bx1.append(x1); by0.append(y0); by1.append(y1)
                mnX = min(mnX, x0); mxX = max(mxX, x1); mnY = min(mnY, y0); mxY = max(mxY, y1)
            }
            self.ox = ox; self.oy = oy; self.ca = ca; self.sa = sa
            self.len = len; self.hw = hw; self.sh = sh
            self.bx0 = bx0; self.bx1 = bx1; self.by0 = by0; self.by1 = by1
            if petals.isEmpty {
                minX = BloomGeometry.cx; maxX = BloomGeometry.cx
                minY = BloomGeometry.cy; maxY = BloomGeometry.cy
            } else {
                minX = mnX; maxX = mxX; minY = mnY; maxY = mxY
            }
        }

        /// จุดหนึ่งจุดในพื้นที่ดอกไม้กินหมึกเท่าไหร่ 0..1
        ///
        /// กลีบถูก **ซ้อนทับ** จากหลังมาหน้า ไม่ใช่เอาค่ามากสุด · `max` คือเหตุผลทั้งหมดที่ขั้นที่
        /// บานแล้วไม่มีความลึก: มันเก็บแค่กลีบที่เข้มที่สุดของแต่ละจุดแล้วโยนข้อเท็จจริงว่ากลีบไหน
        /// อยู่หน้าทิ้งทั้งหมด กองกลีบที่ทับกันจึงออกมาค่าเดียวกับกลีบใบเดียว คืออิ่มตัวทั้งดอก
        ///
        /// การซ้อนทับเก็บลำดับนั้นไว้ แต่ละกลีบทาโทนของตัวเองลงบนของที่มีอยู่แล้ว โดยใช้หน้าตัด
        /// ของตัวเองเป็นความทึบ กลีบที่อยู่หน้าสุดจึงชนะตรงที่มันตัน และปล่อยให้กลีบข้างหลัง
        /// ทะลุออกมาตรงขอบ · **ลำดับในลิสต์คือลำดับความลึก** — `petals` ปล่อยวงนอกก่อน
        /// แล้ววงในทับ แล้วใบ จึงไม่ต้องเรียงอะไรที่นี่
        func cover(atX x: CGFloat, y: CGFloat) -> CGFloat {
            var acc: CGFloat = 0
            for i in 0..<ox.count {
                if x < bx0[i] || x > bx1[i] || y < by0[i] || y > by1[i] { continue }
                let dx = x - ox[i], dy = y - oy[i]
                // ตามแนวยาวและแนวขวางของแกนกลีบเอง
                let f = dx * ca[i] + dy * sa[i]
                if f < 0 || f > len[i] { continue }
                let s = -dx * sa[i] + dy * ca[i]
                let u = f / len[i]
                // ครึ่งความกว้างเรียวเป็นศูนย์ทั้งที่โคนและปลาย กว้างสุดเลยเอวมานิดหนึ่ง
                let halfW = hw[i] * 4 * u * (1 - u) * (1.15 - 0.15 * u)
                if halfW <= 0 { continue }
                let d = abs(s) / halfW
                if d >= 1 { continue }
                // เนื้อแบนกับขอบนุ่ม กลีบจึงบังสิ่งที่อยู่ใต้มันจริง ๆ
                let a = min(1, (1 - d) / BloomGeometry.petalEdge)
                // เข้มขึ้นเมื่อเข้าใกล้ขอบของตัวเอง (คือรอยต่อกับกลีบที่อยู่ข้างล่าง) และเข้มขึ้น
                // เมื่อเข้าใกล้โคน เพราะหัวดอกคือถ้วยที่ถูกจุดไฟจากปลายกลีบเข้ามา
                let tone = sh[i]
                    * (1 - BloomGeometry.rimShade * d * d * d)
                    * (BloomGeometry.rootShade + (1 - BloomGeometry.rootShade) * u)
                acc = a * tone + (1 - a) * acc
            }
            return acc
        }
    }

    /// ขอบเขตจริงของ "หัวดอกอย่างเดียว" — วัดเอา ไม่ได้จดเป็นตาราง เพราะตารางกลีบถูกปรับบ่อย
    /// พอที่ค่าที่จดไว้จะผิดภายในรอบเดียว และผิดแบบเงียบ ๆ (เห็นเป็นชิปที่ล้นวงนิดหน่อย)
    static func headBounds(_ petals: [Petal], stage: CGFloat)
        -> (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
        let coreR: CGFloat = 3.5 + 3 * stage
        var minX = cx - coreR, maxX = cx + coreR
        var minY = cy - coreR, maxY = cy + coreR
        for p in petals {
            let a = p.ang * .pi / 180
            // สุ่มที่เอวกับปลาย: ครึ่งความกว้างเรียวเป็นศูนย์ทั้งสองปลาย ปลายจึงแม่นพอดี
            // ส่วนเอวคือจุดที่กลีบกว้างที่สุด
            for u in [CGFloat(0.5), 1] {
                let halfW = p.halfWidth * 4 * u * (1 - u) * (1.15 - 0.15 * u)
                let px = p.cx + p.len * u * cos(a), py = p.cy + p.len * u * sin(a)
                minX = min(minX, px - halfW); maxX = max(maxX, px + halfW)
                minY = min(minY, py - halfW); maxY = max(maxY, py + halfW)
            }
        }
        return (minX, minY, maxX, maxY)
    }

    static func fanAngle(_ k: Int, _ count: Int, _ splay: CGFloat, _ jitter: CGFloat) -> CGFloat {
        let f: CGFloat = count <= 1 ? 0.5 : CGFloat(k) / CGFloat(count - 1)
        return -90 - splay + 2 * splay * f + jitter
    }

    static func innerAngle(_ k: Int, _ count: Int, _ splay: CGFloat, _ jitter: CGFloat) -> CGFloat {
        let f: CGFloat = count <= 1 ? 0.5 : CGFloat(k) / CGFloat(count - 1)
        return -90 - splay * 0.5 + splay * f + jitter
    }

    static func cubic(_ p0: CGFloat, _ p1: CGFloat, _ p2: CGFloat, _ p3: CGFloat, _ t: CGFloat) -> CGFloat {
        let u = 1 - t
        return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    /// 0..1 แบบ deterministic จาก seed — ไม่ต้องมี state ของตัวสุ่ม ดอกเดิมจึงวาดออกมาเหมือนเดิม
    static func hash(_ seed: CGFloat) -> CGFloat {
        let x = sin(seed * 12.9898) * 43758.5453
        return x - floor(x)
    }
}
