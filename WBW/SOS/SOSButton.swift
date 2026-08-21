import SwiftUI

/// จังหวะการกดค้าง แยกออกจาก View เพื่อให้เทสได้จริง
/// (LongPressGesture ของ SwiftUI เทสไม่ได้ และนี่คือส่วนที่ผิดแล้วเจ็บที่สุด:
/// ส่งตอนที่ผู้ใช้ไม่ได้ตั้งใจ หรือไม่ส่งตอนที่ตั้งใจ)
struct SOSHoldProgress {
    let duration: Double
    private var startedAt: Double?
    private(set) var progress: Double = 0
    private(set) var completionCount = 0

    var didComplete: Bool { completionCount > 0 }

    init(duration: Double = 3.0) { self.duration = duration }

    mutating func start(at now: Double) {
        startedAt = now
        progress = 0
        completionCount = 0
    }

    mutating func tick(at now: Double) {
        guard let startedAt else { return }
        progress = min(1.0, (now - startedAt) / duration)
        if progress >= 1.0 && completionCount == 0 { completionCount = 1 }
    }

    mutating func release(at now: Double) {
        if completionCount == 0 { progress = 0 }
        startedAt = nil
    }
}

/// ปุ่มสีแดง 64pt · กดค้าง วงแหวนวิ่งครบ 3 วิ แล้วเปิดจอสถานะทันที
///
/// **อยู่สองที่ คนละโหมดกัน** — ฝั่งผู้เข้าร่วมอยู่ใต้การ์ดบัตรในแท็บ QR แท็บเดียว
/// (`ParticipantPassView`) ฝั่งเจ้าหน้าที่อยู่ที่ `RootView`
///
/// เดิมฝั่งผู้เข้าร่วมลอยเป็น `.overlay` บน `TabView` จึงเห็นได้ทุกแท็บ ย้ายลงมาอยู่ในหน้าเดียว
/// ตามคำขอของ Park (2026-08-21) · เหตุผลเดิมยังจริง — สลับแท็บก่อนกดคือความช้าที่จ่ายไปแล้ว
/// และเป็นสิ่งที่สเปกข้อ 1 (`2026-08-06-sos-design.md`) เขียนไว้ว่าไม่ควรมี ดูคอมเมนต์เต็มที่
/// จุดที่ถอดออกใน `MainTabView`
struct SOSButton: View {
    @ObservedObject var store: SOSStore
    let token: String
    /// จอสถานะเป็นของผู้เรียก (MainTabView ถือ fullScreenCover เดียวคุมทุกแท็บ) — ปุ่มนี้แค่สั่งเปิด
    @Binding var showStatus: Bool
    @State private var model = SOSHoldProgress()
    @State private var pressing = false
    @State private var lastHaptic = 0.0
    /// กันยิง raise() ซ้ำจากการกดค้างครั้งเดียวกัน — คนละหน้าที่กับ model.didComplete
    ///
    /// model.didComplete ค้างเป็น true ตลอดไปหลังครบ 3 วิ (จนกว่าจะมี start() รอบใหม่) ส่วน
    /// pressing = false ที่ตั้งใน tick() ก็มีผลจริงก็ต่อเมื่อ SwiftUI re-render มาลบ TimelineView
    /// ออกไปแล้วเท่านั้น — ทั้งสองไม่ใช่การ์ดที่ยืนยันได้ว่า "เพิ่งสำเร็จเป็นครั้งแรก" ถ้า TimelineView
    /// ยิง tick() มาซ้อนอีกครั้งก่อน SwiftUI จะทันลบมันออก (เช่น เฟรมถัดไปมาถึงก่อน state เก่าจะเซ็ตผล)
    /// caseIsActive เองก็ยังไม่ทันอัปเดตในช่วงนั้นด้วยซ้ำ เพราะ store.raise() เพิ่งถูกยิงผ่าน Task {}
    /// แบบ async ยังไม่ทันได้รัน — ธงนี้จึงเป็นตัวกันจริงหนึ่งเดียวที่ตั้งแบบ synchronous ในบรรทัดเดียวกับ
    /// ที่เช็ค ไม่พึ่งจังหวะ re-render หรือจังหวะ Task ใดๆ เลย รีเซ็ตกลับ false เฉพาะตอนเริ่มกดค้างรอบใหม่
    @State private var firedThisHold = false

    /// มีเคสเปิดอยู่จริงไหมตอนนี้ — ปิดไปแล้วหรือไม่มีเคสเลยไม่นับ กดใหม่ได้เสมอ (ดูคอมเมนต์ที่
    /// SOSStatus.isActive) เช็คสองจุด: (1) ตอนกดลง กันไม่ให้เริ่มนับถอยหลังใหม่ทับเคสที่เปิดอยู่
    /// (2) ตอนกดค้างครบจริง กันไว้อีกชั้นเผื่อเคสเพิ่ง active ขึ้นระหว่างที่กำลังนับอยู่พอดี (เช่น
    /// resumeIfNeeded ของ relaunch แทรกเข้ามาตอนนั้นพอดี) ไม่ให้ raise() ที่สองหลุดออกไปได้ทั้งสองทาง
    /// (พบจากรีวิว Task 12: raise() เองไม่มีการ์ดกันเรียกซ้ำ ผู้เรียกต้องกันเอง)
    private var caseIsActive: Bool { store.status?.isActive ?? false }

    var body: some View {
        ZStack {
            Circle().fill(.red).frame(width: 64, height: 64)
            Circle()
                .trim(from: 0, to: model.progress)
                .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 58, height: 58)
            Text("SOS").font(.headline.bold()).foregroundStyle(.white)
        }
        .overlay {
            if pressing {
                // ขับวงแหวนจากนาฬิกาจริง ไม่ใช่ animation ที่คาดเดาเวลาไม่ได้
                TimelineView(.animation) { ctx in
                    Color.clear.onChange(of: ctx.date) { _, now in tick(now) }
                }
            }
        }
        .accessibilityLabel(caseIsActive
            ? "มีเหตุฉุกเฉินกำลังดำเนินการอยู่ แตะเพื่อดูสถานะ"
            : "ขอความช่วยเหลือฉุกเฉิน กดค้างสามวินาที")
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressing else { return }
                    // มีเคสเปิดอยู่แล้ว — แตะเดียวพากลับไปจอสถานะ ไม่ต้องกดค้างสามวิใหม่ และห้ามเปิด
                    // เคสที่สองซ้อนเคสเดิมเด็ดขาด (ดูคอมเมนต์ที่ caseIsActive)
                    guard !caseIsActive else { showStatus = true; return }
                    pressing = true
                    firedThisHold = false
                    model.start(at: Date().timeIntervalSince1970)
                }
                .onEnded { _ in
                    pressing = false
                    model.release(at: Date().timeIntervalSince1970)
                }
        )
    }

    private func tick(_ now: Date) {
        let t = now.timeIntervalSince1970
        model.tick(at: t)
        // สั่นถี่ขึ้นเรื่อยๆ ให้รู้ว่ากำลังนับ ไม่ใช่ค้าง
        let interval = 0.35 - 0.25 * model.progress
        if t - lastHaptic > interval {
            lastHaptic = t
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        // model.didComplete ค้าง true ตลอดไปหลังครบ ไม่ใช่ edge-trigger — firedThisHold ต่างหากที่
        // กันไม่ให้โค้ดข้างล่างนี้รันซ้ำถ้า tick() ถูกเรียกอีกรอบก่อน pressing = false จะมีผลจริง
        // (ดูคอมเมนต์ที่ firedThisHold)
        guard model.didComplete, !firedThisHold else { return }
        firedThisHold = true
        pressing = false
        // การ์ดชั้นที่สอง (ดูคอมเมนต์ที่ caseIsActive) — ถ้าเผลอมาถึงตรงนี้ทั้งที่มีเคสเปิดอยู่แล้ว
        // แค่พาไปจอสถานะ ไม่ยิง raise() ซ้อน · ไม่เรียก model.release() ตรงนี้ — completionCount
        // เป็น 1 ไปแล้วตอนนี้ (didComplete เพิ่งผ่าน guard ด้านบน) release() จึงไม่ทำให้ progress
        // กลับไป 0 อยู่ดี (ดูเงื่อนไข `if completionCount == 0` ใน SOSHoldProgress.release) วงแหวนค้าง
        // เต็มไว้แบบเดียวกับตอนส่งสำเร็จปกติด้านล่าง ไม่ใช่บั๊ก — จอสถานะจะมาบังทันทีอยู่แล้ว
        guard !caseIsActive else {
            showStatus = true
            return
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        // เปิดจอสถานะทันที ไม่รอ raise() จบก่อน — คนกดต้องเห็นว่าเกิดอะไรขึ้นตั้งแต่วินาทีแรก
        showStatus = true
        Task { await store.raise(forOther: false, token: token) }
    }
}
