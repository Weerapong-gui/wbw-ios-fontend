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

/// แถบขั้นการบาน 6 ช่อง กดได้ทุกช่อง
///
/// ขั้นที่ยังไม่ถึงเป็นเงาจาง ๆ **แต่ยังเป็นรูปดอกไม้ขั้นนั้นจริง** ไม่ใช่จุดหรือตัวเลข — นั่นคือสิ่งเดียว
/// ที่แถบนี้มีไว้ทำ: ให้เห็นรูปทรงที่กำลังปลูกไปหา · กดแล้วพรีวิวเฉย ๆ **ไม่บันทึก**
/// ปล่อยมือแล้วกลับไปขั้นจริงเสมอ (ปุ่มที่เปลี่ยนความคืบหน้าจริงได้จะเป็นการโกงเช็คอิน)
struct BloomStageStrip: View {
    let currentStage: Int
    @Binding var previewStage: Int?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<BloomStages.count, id: \.self) { s in
                Button {
                    previewStage = (previewStage == s) ? nil : s
                } label: {
                    chip(s)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(BloomStages.label(s)) ขั้นที่ \(s + 1) จาก \(BloomStages.count)")
            }
        }
    }

    private func chip(_ s: Int) -> some View {
        let reached = s <= currentStage
        let selected = previewStage == s
        return BloomChipCanvas(stage: s, ink: .white,
                               alphaScale: reached ? 1 : 0.28)
            .frame(width: 44, height: 44)
            .padding(6)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(selected ? 0.85 : 0.22), lineWidth: selected ? 2 : 1)
                    .padding(6)
            )
    }
}

/// ดอกไม้ขั้นเดียวขนาดเล็กสำหรับชิป — ไม่มีก้าน ไม่มีใบ (ใบอยู่บนก้าน เอาหัวดอกมาอย่างเดียว
/// แล้วยังเก็บใบไว้จะได้เส้นสองเส้นลอยอยู่ใต้ดอก กับกล่องที่สูงเกินไปครึ่งเท่า) และไม่หายใจ
private struct BloomChipCanvas: View {
    let stage: Int
    let ink: Color
    let alphaScale: Double

    @State private var cache = BloomFieldCache()

    var body: some View {
        BloomCanvas(openness: Double(stage), breath: 0, kind: .head,
                    gridPoints: 3, centreYFraction: 0.5,
                    ink: ink, alphaScale: alphaScale, cache: cache)
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
