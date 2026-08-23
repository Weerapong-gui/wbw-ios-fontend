import SwiftUI

/// จอเปิดแอป — ดอกไม้ของแอปกำลังบาน · **ยกมาจาก `ui/intro/IntroScreen.kt` ของ Android**
///
/// เป็น `BloomView` ตัวเดียวกับที่หน้า Home วาด รันจากดอกตูมไปบานเต็มหนึ่งรอบ นั่นคือทั้งหมดของ
/// ไอเดีย: สิ่งที่ผู้เข้าร่วมจะใช้ทั้งงานปลูกให้บาน คือสิ่งแรกที่เขาเห็น พอถึงหน้า Home ดอกไม้จึง
/// คุ้นตาแล้ว และการเช็คอินให้ครบทุกฐานมีจุดหมายที่มองเห็นได้ · ภาพ splash แยกอีกใบจะกลายเป็น
/// งานศิลป์ชิ้นที่สองที่ต้องคอยทำให้ตรงกับชิ้นแรกตลอดไป
///
/// **ไม่มีปุ่ม** — จอนี้มีหน้าที่เดียว ทำเสร็จใน 2.81 วินาที ปุ่มจะมีค่าแค่ขอให้ผู้ใช้ยืนยันว่า
/// อยากให้แอปเปิดต่อ · จอต้อนรับเดิม (`WelcomeView` ชื่องาน + wordmark + ปุ่ม "เริ่มใช้งาน") ถูก
/// แทนที่ด้วยไฟล์นี้ทั้งใบเมื่อ 2026-08-23 ตามที่ Android ทำ
///
/// พื้นหลังเป็น `forestBackground(day: dayWelcome)` ตัวเดิมของจอต้อนรับ — จอถัดไป (ล็อกอิน) วาด
/// พื้นเดียวกัน สิ่งที่ fade จึงเป็นดอกไม้ให้ทางกับฟอร์มล็อกอิน โดยที่พื้นข้างล่างไม่กระตุก
struct IntroView: View {
    let onFinished: () -> Void

    /// เครื่องที่ตั้ง "ลดการเคลื่อนไหว" ไว้ — ดูเหตุผลที่ `IntroTimeline.shouldSkip`
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var stage = IntroTimeline.firstStage

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // wordmark อยู่เหนือดอกไม้ในสามส่วนบนตามต้นทาง — ไม่ใช่เพราะต้องจับคู่กับจอถัดไป
                // (หน้าล็อกอินของ iOS ไม่มี wordmark เลย มีแค่ข้อความ `login_greeting`) แต่เพราะ
                // มันคือจังหวะแบรนด์ของจอนี้ และวางไว้ใต้ดอกไม้แล้วสายตาจะถูกดึงลงจากสิ่งที่กำลังเคลื่อน
                Spacer().frame(height: geo.size.height * 0.20)

                Image("logo_wordmark")
                    .resizable().scaledToFit()
                    .frame(width: geo.size.width * 0.74)
                    .opacity(IntroTimeline.wordmarkVisible(stage: stage) ? 1 : 0)
                    // 0.7 วิ ยาวกว่าช่วงเปลี่ยนขั้น (0.45) โดยตั้งใจ — โลโก้จึงค่อย ๆ ปรากฏคร่อม
                    // สองขั้นสุดท้าย แทนที่จะกะพริบขึ้นมาพร้อมขั้นใดขั้นหนึ่ง
                    .animation(.easeInOut(duration: 0.7), value: stage)
                    .accessibilityLabel(Text("app_name"))

                // ดอกไม้กินที่ว่างที่เหลือ — จอสูงหรือเตี้ยดอกก็อยู่กลางจอเหมือนกัน
                //
                // `breathing: true` เท่ากับหน้า Home: จอนี้ส่งต่อไปหาจอนั้น ดอกที่นิ่งสนิทตรงนี้
                // แล้วเริ่มหายใจตอนถึง Home จะอ่านเป็นดอกคนละดอก
                BloomView(stage: stage, breathing: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // ขั้นที่กำลังแสดงเปลี่ยนทุก 450ms และ VoiceOver จะไล่อ่านทุกครั้งที่เปลี่ยน —
                    // จอนี้ไม่มีอะไรให้ทำ ป้ายเดียวที่มีประโยชน์คือ wordmark ด้านบน
                    .accessibilityHidden(true)

                Spacer().frame(height: geo.size.height * 0.10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // เช้าตรู่ (day 0.20) เท่าจอต้อนรับเดิม · ไม่มีแท็บบาร์ที่จอนี้ ส่ง bottomClearance: 0
        .forestBackground(day: ForestMath.dayWelcome, bottomClearance: 0)
        .task {
            if IntroTimeline.shouldSkip(reduceMotion: reduceMotion) {
                onFinished()
                return
            }
            // ให้เห็นว่าเป็นดอกตูมก่อนกลีบแรกจะขยับ
            try? await Task.sleep(for: .milliseconds(IntroTimeline.settleMillis))

            // ไล่ทีละขั้น ไม่ใช่กระโดดไปขั้นสุดท้ายทีเดียว — `BloomView` animate ทุกการเปลี่ยนขั้น
            // ด้วยเวลาคงที่ 0.9 วิ ดังนั้น 1 → 5 รวดเดียวจะใช้เวลาเท่ากับ 1 → 2 แล้วออกมาเป็นการ
            // กระชากขั้นเดียว · เปลี่ยนเป้าทุก 450ms ทำให้แต่ละขั้นถูกเปลี่ยนทิศกลางทาง การเคลื่อน
            // จึงต่อเนื่อง และทุกขั้นได้ถูกมองเห็น
            for next in (IntroTimeline.firstStage + 1)...IntroTimeline.finalStage {
                stage = next
                try? await Task.sleep(for: .milliseconds(IntroTimeline.stageStepMillis))
            }

            try? await Task.sleep(for: .milliseconds(IntroTimeline.holdMillis))
            onFinished()
        }
    }
}

/// จังหวะของจออินโทร แยกออกมาเป็นค่ากับฟังก์ชันบริสุทธิ์ เพื่อให้ `IntroViewTests` เทสได้โดยไม่ต้อง
/// mount View ทั้งจอ (กติกาเดียวกับ `Map3DCamera.clampPitch`) — ตัวเลขพวกนี้ผิดแล้วไม่มีอะไรฟ้อง
/// นอกจากตาคนที่นั่งดูจอเปิดแอปซ้ำ ๆ
enum IntroTimeline {
    /// ดอกตูม · ขั้น 0 คือก้านเปล่าซึ่งจะเปิดแอปมาเจอจอว่างอยู่ครู่หนึ่ง
    static let firstStage = 1
    /// บานเต็ม — ขั้นสุดท้ายของ `BloomStages` (มี 6 ขั้น นับ 0)
    static let finalStage = 5

    /// หน่วงก่อนกลีบแรกขยับ
    static let settleMillis = 260
    /// ระหว่างขั้น · **ต้องสั้นกว่า 900ms ของ `BloomView`** ไม่งั้นการบานจะขาดเป็นท่อน
    static let stageStepMillis = 450
    /// ค้างบานเต็มให้ทันเห็นก่อนจอจะให้ทาง
    static let holdMillis = 750

    /// เวลาที่ผู้ใช้ต้องรอทุกครั้งที่เปิดแอป — ยาวขึ้นเมื่อไหร่ต้องเป็นการตัดสินใจ
    static var totalMillis: Int {
        settleMillis + (finalStage - firstStage) * stageStepMillis + holdMillis
    }

    /// ขั้นที่ควรเห็น ณ มิลลิวินาทีที่กำหนด — ตัวเดียวกับที่ลูปใน `.task` เดินจริง
    static func stage(atMillis ms: Int) -> Int {
        guard ms >= settleMillis else { return firstStage }
        let stepped = firstStage + 1 + (ms - settleMillis) / stageStepMillis
        return min(stepped, finalStage)
    }

    /// wordmark มากับสองขั้นสุดท้าย ไม่ใช่ตั้งแต่เฟรมแรก — ระหว่างที่ดอกไม้กำลังเคลื่อน
    /// สายตาควรอยู่ที่ดอกไม้
    static func wordmarkVisible(stage: Int) -> Bool { stage >= finalStage - 1 }

    /// เครื่องที่ขอ "ลดการเคลื่อนไหว" ต้อง **ข้าม** จอนี้ ไม่ใช่เล่นเร็วขึ้น — ทั้งจอมีเนื้อหาเดียว
    /// คือแอนิเมชัน 2.81 วิ คนที่ขอไม่ให้มีการเคลื่อนไหวจึงไม่มีอะไรให้ดูที่นี่เลย
    /// (ต้นทาง Android ตัดสินแบบเดียวกันผ่าน `ANIMATOR_DURATION_SCALE == 0`)
    static func shouldSkip(reduceMotion: Bool) -> Bool { reduceMotion }
}
