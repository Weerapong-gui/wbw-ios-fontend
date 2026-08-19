import SwiftUI

/// ดอกไม้ halftone บนหน้า Home — บานตามจำนวนฐานที่เช็คอินแล้ว
///
/// ทำไมต้องมี: หน้า Home ของ iOS เคยเหลือแค่ avatar + คำทักทาย + กระดิ่ง (ฉากป่า 3D ถูกปิดด้วย
/// `Config.forest3D = false`) ซึ่งเป็นจอแรกที่ App Review เห็นหลังล็อกอิน และเป็นเหตุผลตรง ๆ ของ
/// Guideline 2.3.3 รอบ 1.0 (7) — สกรีนช็อตของจอนี้ไม่มีอะไรให้ดู
///
/// เรขาคณิตทั้งหมดอยู่ที่ `BloomGeometry` ไฟล์นี้รับผิดชอบแค่การ animate กับการวาด
struct BloomView: View {
    let stage: Int
    var ink: Color = .white
    var breathing: Bool = true
    /// ระยะห่างตาราง halftone หน่วย point — เป็นสมบัติของ "พื้นผิวที่พิมพ์ลงไป" ไม่ใช่ของรูป
    /// ย่อรูปแล้วต้องใช้ตารางถี่ขึ้น ไม่งั้นก้านจะบางกว่าหนึ่งช่องแล้วหายไปจากภาพทั้งเส้น
    var gridPoints: CGFloat = 6

    var body: some View {
        // หายใจแบบมีสายจูง — `paused` ทำให้จอเงียบสนิทเมื่อไม่ได้แตะมาสักพัก
        // ปล่อยให้วิ่งตลอดคือ GPU ที่ถูกปลุกทั้งวันบนเครื่องที่กำลังถูกแบกขึ้นดอย
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !breathing)) { timeline in
            BloomCanvas(openness: Double(stage),
                        breath: breathing ? Self.breathPhase(at: timeline.date) : 0,
                        kind: .plant,
                        gridPoints: gridPoints,
                        centreYFraction: 0.38,
                        ink: ink,
                        alphaScale: 1,
                        cache: cache)
        }
        // 900 มิลลิวินาที — เช็คอินหนึ่งครั้งต้อง "เปิด" ดอกไม้ ไม่ใช่กระตุกไปขั้นใหม่
        .animation(.easeInOut(duration: 0.9), value: stage)
    }

    @State private var cache = BloomFieldCache()

    /// หนึ่งรอบหายใจ 7 วินาที — คำนวณจากนาฬิกาจริง ไม่ใช่สะสมทีละเฟรม เพื่อให้จังหวะไม่เพี้ยน
    /// เวลาเครื่องหน่วงแล้วเฟรมหาย
    static func breathPhase(at date: Date) -> Double {
        let cycle = 7.0
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        return t / cycle * 2 * .pi
    }
}

// MARK: - แถบขั้น

/// รางความคืบหน้า 6 ช่อง กดได้ทุกช่องเพื่อพรีวิวขั้นนั้น
///
/// **เคยเป็นชิปรูปดอกไม้ 44pt ต่อขั้น — เปลี่ยนแล้ว 2026-08-20 ห้ามถอยกลับ** เจตนาเดิมของชิปคือ
/// ให้เห็น "รูปทรงที่กำลังปลูกไปหา" แต่ที่ 44pt ตาราง halftone ย่อลงจนอ่านเป็นเม็ดฝุ่น ไม่ใช่ดอกไม้
/// (ถ่ายจริงแล้วเห็นชัด) และขั้นที่ยังไม่ถึงซึ่งตั้ง alpha 0.28 ไว้ก็จมหายไปกับพื้นภาพป่าทั้งช่อง
/// ตัวที่โชว์รูปทรงได้จริงคือดอกไม้ 300pt ที่อยู่เหนือแถบนี้ — แถบจึงเหลือหน้าที่เดียวคือ "เลือกขั้น"
///
/// กดแล้วพรีวิวเฉย ๆ **ไม่บันทึก** กดซ้ำหรือหมดเวลาแล้วกลับไปขั้นจริงเสมอ (ปุ่มที่ดันความคืบหน้า
/// จริงได้จะเป็นการโกงเช็คอิน)
struct BloomStageStrip: View {
    let currentStage: Int
    @Binding var previewStage: Int?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<BloomStages.count, id: \.self) { s in
                Button {
                    previewStage = (previewStage == s) ? nil : s
                } label: {
                    segment(s)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(BloomStages.label(s)) ขั้นที่ \(s + 1) จาก \(BloomStages.count)")
            }
        }
    }

    /// รางหนา 6 pt แต่พื้นที่กดสูง 44 pt — ขนาดขั้นต่ำที่นิ้วกดโดนตาม HIG
    /// ไม่ห่อแบบนี้ต้องเล็งให้ตรงเส้นบาง ๆ ซึ่งพลาดแทบทุกครั้ง
    private func segment(_ s: Int) -> some View {
        let reached = s <= currentStage
        let selected = previewStage == s
        return Capsule()
            .fill(reached ? Color.wbwGold : Color.white.opacity(0.18))
            .frame(maxWidth: .infinity)
            .frame(height: 6)
            .overlay(Capsule().stroke(.white, lineWidth: selected ? 1.5 : 0))
            .frame(height: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - ตัววาด

private struct BloomCanvas: View, Animatable {
    var openness: Double
    var breath: Double
    var kind: BloomGeometry.Kind
    var gridPoints: CGFloat
    var centreYFraction: CGFloat
    var ink: Color
    var alphaScale: Double
    var cache: BloomFieldCache

    /// ทำให้ SwiftUI ไล่ค่าขั้นให้ทีละเฟรม — ถ้าไม่มีตัวนี้ `.animation(value: stage)` จะไม่มีผลกับ
    /// `Canvas` เลย เพราะเนื้อใน Canvas ไม่ใช่ property ที่ระบบรู้จักว่า animate ได้
    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let dots = cache.dots(size: size, stage: CGFloat(openness), step: gridPoints,
                                  centreYFraction: centreYFraction, kind: kind)
            for dot in dots {
                // แต่ละจุดหายใจคนละเฟส สนามจุดจะได้ระยิบ ไม่ใช่เต้นพร้อมกันทั้งก้อน
                let puff: CGFloat = breath == 0
                    ? 1
                    : 0.88 + 0.12 * CGFloat(sin(breath + Double(dot.jitter) * 2 * .pi))
                let r = dot.r * puff
                if r <= 0.25 { continue }
                let rect = CGRect(x: dot.x - r, y: dot.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect),
                             with: .color(ink.opacity(min(max(Double(dot.alpha) * alphaScale, 0), 1))))
            }
        }
    }
}

/// สนามจุดที่สร้างเสร็จแล้ว เก็บไว้ข้ามเฟรม
///
/// มีเพราะการวัด ไม่ใช่เพราะเดา: ฝั่ง Android หน้า Home เคยรันที่ ~12fps **ตอนอยู่เฉย ๆ** เพราะการ
/// หายใจสั่งวาดใหม่ทุกเฟรม และทุกเฟรมโค้ดเก่าสร้างรูปทั้งใบขึ้นใหม่ตั้งแต่ต้น — ตารางทั้ง canvas
/// คูณทุกกลีบ คูณ sin/cos ต่อกลีบต่อช่อง · รูปเปลี่ยนจริงเฉพาะตอนเช็คอินเท่านั้น
///
/// สิ่งที่เปลี่ยนทุกเฟรมจริง ๆ (การหายใจ กับความจางของชิป) จึงถูกเอาไปคูณตอนวาด ไม่ได้อบมากับจุด
/// และขั้นถูกปัดเป็นเศษ 1/16 สำหรับคีย์ cache — ช่วงบาน 900 มิลลิวินาทีจึงสร้างใหม่ราว 16 ครั้ง
/// แทนที่จะเป็นทุกเฟรม (1/16 ขั้นคือไม่กี่เปอร์เซ็นต์ของความยาวกลีบ มองไม่เห็นที่ความเร็วนั้น)
final class BloomFieldCache {
    private var dotsCache: [BloomGeometry.Dot] = []
    private var key: String = ""

    func dots(size: CGSize, stage: CGFloat, step: CGFloat,
              centreYFraction: CGFloat, kind: BloomGeometry.Kind) -> [BloomGeometry.Dot] {
        let quantised = (stage * 16).rounded() / 16
        let newKey = "\(size.width)x\(size.height)|\(quantised)|\(step)|\(centreYFraction)|\(kind)"
        if newKey != key {
            key = newKey
            dotsCache = BloomGeometry.build(size: size, stage: quantised, step: step,
                                            centreYFraction: centreYFraction, kind: kind)
        }
        return dotsCache
    }
}

#Preview {
    VStack {
        BloomView(stage: 3)
            .frame(height: 260)
        BloomStageStrip(currentStage: 3, previewStage: .constant(nil))
    }
    .padding()
    .background(Color.wbwForestVoid)
}
