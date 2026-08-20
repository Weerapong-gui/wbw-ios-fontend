import SwiftUI

/// หน้าหลัก (DOI-APP) — คำทักทาย "Hey! <ชื่อ>" มุมซ้ายบน บนพื้นหลังที่ .forestBackground() จัดให้
///
/// ตัวอักษรเป็นสีขาวเพราะพื้นหลังเป็นโทนเข้มเสมอ (พื้นทึบ #0A1610 ตอน Config.forest3D ปิด
/// หรือฉากป่า 3D ตอนเปิด) — ไม่ผูกกับ flag เพราะขาวอ่านออกทั้งสองโหมด
///
/// **2026-08-19: เพิ่มดอกไม้ Bloom กับแถบสภาพเส้นทาง** จอนี้เคยเหลือแค่ header กับ `Spacer()`
/// ซึ่งเป็นจอแรกที่ App Review เห็นหลังล็อกอิน และเป็นเหตุผลตรง ๆ ของ Guideline 2.3.3
/// (สกรีนช็อตไม่มีอะไรให้ดู) — **ห้ามถอยกลับไปเป็นจอที่มีแต่ header**
struct HomeView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var progress: CheckinProgressStore
    @ObservedObject var noti: NotiStore
    @StateObject private var conditions = ConditionsStore()
    @State private var showProfile = false
    /// ขั้นที่ผู้ใช้กดดูจากแถบขั้น — **ชั่วคราวเท่านั้น ไม่บันทึก** ปุ่มที่ดันความคืบหน้าจริงได้
    /// จะเป็นการโกงเช็คอิน
    @State private var previewStage: Int?
    @State private var breathing = true
    @State private var breathTimeout: Task<Void, Never>?

    private var name: String { profile.me?.displayName ?? (session.user?.username ?? "ผู้เข้าร่วม") }

    private var stage: Int {
        #if DEBUG
        // บังคับขั้นต้นไม้เพื่อถ่ายภาพยืนยัน — ทรงเดียวกับ uitestTab/uitestChat
        if UserDefaults.standard.object(forKey: "uitestProgress") != nil {
            return UserDefaults.standard.integer(forKey: "uitestProgress")
        }
        #endif
        return progress.progress?.stage ?? 0
    }

    private var total: Int {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "uitestProgress") != nil { return 8 }
        #endif
        return progress.progress?.total ?? 0
    }

    /// ขั้นการบานของดอกไม้ · พรีวิวชนะขั้นจริงชั่วคราวตอนผู้ใช้กดแถบขั้น
    private var bloomStage: Int { previewStage ?? BloomStages.stage(checkedIn: stage, total: total) }

    var body: some View {
        VStack(spacing: 0) {
            header
            // ดอกไม้ผูกกับ Config.forest3D ด้วยเหตุผลเดียวกับบรรทัดนับฐานเดิม — เปิดฉากป่ากลับ
            // เมื่อไหร่ ต้นไม้ 3D บอกความคืบหน้าเรื่องเดียวกันนี้อยู่แล้ว ไม่ควรมีสองอย่างพูดซ้ำกัน
            if !Config.forest3D {
                bloom
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .forestBackground(
            day: ForestMath.day(stage: stage, total: total),
            plantStep: stage,
            plantTotal: total)
        .task {
            // โหลด map.usdz ย้ายไปเริ่มที่ RootView ตอนล็อกอินสำเร็จแล้ว (2026-08-20) —
            // เร็วกว่าเดิมและไม่ผูกกับการที่ผู้ใช้ต้องมาถึงจอนี้ก่อน
            nudgeBreath()
            if profile.me == nil { await profile.load(token: session.token ?? "") }
            await conditions.refresh()
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "uitestProfile") { showProfile = true }
            #endif
        }
        .fullScreenCover(isPresented: $showProfile) {
            TicketView()
        }
    }

    // MARK: - หัวจอ

    private var header: some View {
        // คำทักทายมุมซ้ายบน — avatar กรอบ liquid glass กดไป Profile
        HStack(spacing: 12) {
            Button { showProfile = true } label: {
                // ringColor: .clear เพราะ GlassRing ล้อมอยู่แล้ว — ปล่อยค่าปริยายไว้จะได้วงขาว
                // ของ avatar ซ้อนกับวงกระจกอีกวง เห็นเป็นสองวงซ้อนกัน (ทรงเดียวกับที่ TicketView ทำ)
                ProfileAvatar(name: name, photoUrl: profile.photoUrl, size: 50,
                              ringColor: .clear,
                              fill: .white.opacity(0.16), initialColor: .white)
                    .padding(5)
                    .modifier(GlassRing())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text("Hey!")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                Text(name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                // สภาพบนดอยตอนนี้ — วาดลงพื้นฉากตรง ๆ ไม่มีการ์ด · ยิงไม่ได้ = ซ่อนทั้งแถว
                TrailConditionsRow(conditions: conditions.conditions)
            }
            Spacer()

            Button {
                NotificationCenter.default.post(name: .openNotificationsTab, object: nil)
            } label: {
                Image(systemName: "bell.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .modifier(GlassRing())
                    .overlay(alignment: .topTrailing) {
                        if noti.unreadCount > 0 {
                            Text("\(noti.unreadCount)")
                                .font(.caption2.weight(.bold)).foregroundStyle(.white)
                                .padding(5).background(Color.red, in: Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - ดอกไม้

    /// เดิมตรงนี้มีมาสคอต DinDin ลอยเหนือ tab bar แล้วถูกถอดออกเหลือ `Spacer()` ตัวเดียว —
    /// ตอนนี้เป็นดอกไม้ที่บานตามจำนวนฐาน ซึ่งเป็นของที่หน้านี้ควรมีมาตั้งแต่แรก
    private var bloom: some View {
        VStack(spacing: 12) {
            // Spacer ตัวเดียว **ตัวบน** — เดิมมีขนาบทั้งบนล่าง ของทั้งก้อนเลยถูกจัดกึ่งกลางพื้นที่
            // ที่เหลือ เหลือช่องว่างเปล่าใต้การ์ดลงไปถึงแถบแท็บราวหนึ่งในห้าของจอ (เห็นจาก
            // สกรีนช็อตจริง) · เหลือตัวบนตัวเดียวแล้วทุกอย่างถูกดันลงชิดล่างเอง
            Spacer(minLength: 0)

            // เงาใต้จุดยังอยู่ **แต่เบาลงแล้ว** — ตั้งแต่ AppBackdrop คลุมทึบทั้งใบ (0.35) กลางจอ
            // ไม่ใช่ช่องโหว่ที่ต้องให้ดอกไม้แบกเองอีกต่อไป เหลือไว้แค่พอแยกขอบดอกจากลำต้นที่อยู่หลัง
            // ค่าเดิม 0.5/รัศมี 6 ที่จูนไว้ตอนพื้นยังโล่ง ตอนนี้กลายเป็นคราบดำวงใหญ่รอบดอกแทน
            // ตาราง halftone 4 pt ไม่ใช่ 6 — ที่ความสูง 300 pt ก้านหนาราว 5 pt ซึ่ง "บางกว่าหนึ่งช่อง"
            // ของตาราง 6 pt แล้วหลุดหายไปทั้งเส้น เหลือหัวดอกลอยอยู่เหนือใบ (ถ่ายจริงเจอมาแล้ว)
            BloomView(stage: bloomStage, breathing: breathing, gridPoints: 4)
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                .accessibilityLabel("ดอกไม้ขั้น \(BloomStages.label(bloomStage))")

            VStack(spacing: 8) {
                Text(BloomStages.label(bloomStage))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                if let progressText = CheckinProgressLabel.text(stage: stage, total: total) {
                    Text(progressText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }

                BloomStageStrip(currentStage: BloomStages.stage(checkedIn: stage, total: total),
                                previewStage: Binding(
                                    get: { previewStage },
                                    set: { previewStage = $0; nudgeBreath() }))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(.horizontal, 20)
        // แถบแท็บลอยทับพื้นที่ล่างของจอ — ไม่เว้นไว้แล้วแถบขั้นจะโดนบังครึ่งใบ
        .padding(.bottom, ForestSceneHost.tabBarClearance)
    }

    /// การหายใจของดอกไม้หยุดเองหลังไม่มีใครแตะ 12 วินาที — จอ Home เป็นจอที่คนเปิดค้างไว้
    /// ปล่อยให้ animation วิ่งตลอดคือ GPU ที่ถูกปลุกทั้งวันบนเครื่องที่กำลังถูกแบกขึ้นดอย
    private func nudgeBreath() {
        breathing = true
        breathTimeout?.cancel()
        breathTimeout = Task {
            try? await Task.sleep(nanoseconds: 12 * 1_000_000_000)
            if !Task.isCancelled { breathing = false }
        }
    }
}

/// กรอบวงกลม liquid glass รอบ avatar (iOS 26) · fallback วงขาว
private struct GlassRing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
        }
    }
}
