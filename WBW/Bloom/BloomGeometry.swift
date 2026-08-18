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

    private struct Petal {
        let cx: CGFloat, cy: CGFloat, ang: CGFloat, len: CGFloat, halfWidth: CGFloat
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
    private static func petals(stage: CGFloat, withLeaves: Bool) -> [Petal] {
        let s = min(max(stage, 0), 5)
        let i = min(Int(s), 4)
        let t = s - CGFloat(i)

        // ขั้น 5 เคยเป็น 18 กลีบกาง 180° ซึ่งปิดพัดจนกลายเป็นจาน ไม่เหลือเส้นรอบรูปให้ดู
        // แล้วอ่านว่าแย่กว่าขั้น 4 · กลีบน้อยลง กางไม่สุด แต่ยาวขึ้น
        let counts = [0, 1, 6, 9, 13, 16]
        let lengths: [CGFloat] = [0, 30, 40, 52, 64, 80]
        let splays: [CGFloat] = [0, 0, 42, 96, 140, 166]
        // ตูมแล้วป้าน ค่อยเรียวลงตอนกลีบแยกออกจากกัน
        let ratios: [CGFloat] = [0.35, 0.35, 0.24, 0.21, 0.20, 0.20]

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
            out.append(Petal(cx: cx, cy: cy, ang: ang, len: len, halfWidth: len * ratio))
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
                out.append(Petal(cx: cx, cy: cy, ang: ang, len: len, halfWidth: len * 0.26))
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
                out.append(Petal(cx: lx, cy: ly, ang: leaf.angle + jitter, len: len, halfWidth: len * 0.30))
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

        var minX = min(fan.minX, cx - coreR), maxX = max(fan.maxX, cx + coreR)
        var minY = min(fan.minY, cy - coreR), maxY = max(fan.maxY, cy + coreR)
        if withStem {
            minX = min(minX, cx - 17); maxX = max(maxX, cx + 17)
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
                    // เรียว: หนาที่โคน บางตรงที่ไปบรรจบกับหัวดอก
                    let halfW: CGFloat = 3.4 * (0.45 + 0.55 * t)
                    if d < halfW { cover = max(cover, 1 - d / halfW) }
                }

                // แกนกลาง — จุดจะแออัดตรงที่โคนกลีบทุกใบมาชนกัน จึงวาดเป็นเนื้อทึบไปเลย
                // วาดทุกขั้นรวมขั้น 0 ที่มันคือเมล็ด — ถ้ากันไว้ที่ขั้น 1 ชิปแรกของแถบจะว่างสนิท
                // ใต้ป้ายที่เขียนว่า "เมล็ด"
                let dc = hypot(fx - cx, fy - cy)
                if dc < coreR { cover = max(cover, 1 - (dc / coreR) * 0.35) }

                if cover <= 0.02 { continue }
                let n = hash(CGFloat(ix) * 31 + CGFloat(iy) * 57)
                let r = maxR * min(cover, 1) * (0.55 + 0.45 * n)
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
        private let len: [CGFloat], hw: [CGFloat]
        private let bx0: [CGFloat], bx1: [CGFloat], by0: [CGFloat], by1: [CGFloat]
        let minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat

        init(_ petals: [Petal]) {
            // sin/cos ต่อกลีบถูกยกออกมานอกลูปช่อง — เดิมคำนวณซ้ำทุกช่องคูณทุกกลีบ
            // เป็นบรรทัดที่แพงที่สุดในการวาดทั้งหมด
            var ox: [CGFloat] = [], oy: [CGFloat] = [], ca: [CGFloat] = [], sa: [CGFloat] = []
            var len: [CGFloat] = [], hw: [CGFloat] = []
            var bx0: [CGFloat] = [], bx1: [CGFloat] = [], by0: [CGFloat] = [], by1: [CGFloat] = []
            var mnX = CGFloat.greatestFiniteMagnitude, mxX = -CGFloat.greatestFiniteMagnitude
            var mnY = CGFloat.greatestFiniteMagnitude, mxY = -CGFloat.greatestFiniteMagnitude

            for p in petals {
                let a = p.ang * .pi / 180
                let c = cos(a), s = sin(a)
                ox.append(p.cx); oy.append(p.cy); ca.append(c); sa.append(s)
                len.append(p.len); hw.append(p.halfWidth)
                // กลีบกว้างสุดที่เอว 1.1 เผื่อไหล่ของการเรียว
                let pad = p.halfWidth * 1.1
                let tipX = p.cx + p.len * c, tipY = p.cy + p.len * s
                let x0 = min(p.cx, tipX) - pad, x1 = max(p.cx, tipX) + pad
                let y0 = min(p.cy, tipY) - pad, y1 = max(p.cy, tipY) + pad
                bx0.append(x0); bx1.append(x1); by0.append(y0); by1.append(y1)
                mnX = min(mnX, x0); mxX = max(mxX, x1); mnY = min(mnY, y0); mxY = max(mxY, y1)
            }
            self.ox = ox; self.oy = oy; self.ca = ca; self.sa = sa
            self.len = len; self.hw = hw
            self.bx0 = bx0; self.bx1 = bx1; self.by0 = by0; self.by1 = by1
            if petals.isEmpty {
                minX = BloomGeometry.cx; maxX = BloomGeometry.cx
                minY = BloomGeometry.cy; maxY = BloomGeometry.cy
            } else {
                minX = mnX; maxX = mxX; minY = mnY; maxY = mxY
            }
        }

        func cover(atX x: CGFloat, y: CGFloat) -> CGFloat {
            var cover: CGFloat = 0
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
                if d < 1 { cover = max(cover, (1 - d * d) * 0.9 + 0.1) }
            }
            return cover
        }
    }

    /// ขอบเขตจริงของ "หัวดอกอย่างเดียว" — วัดเอา ไม่ได้จดเป็นตาราง เพราะตารางกลีบถูกปรับบ่อย
    /// พอที่ค่าที่จดไว้จะผิดภายในรอบเดียว และผิดแบบเงียบ ๆ (เห็นเป็นชิปที่ล้นวงนิดหน่อย)
    private static func headBounds(_ petals: [Petal], stage: CGFloat)
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
