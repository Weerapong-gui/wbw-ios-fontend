import SwiftUI

/// หน้าหลัก — **ยกโครงมาจาก `HomeScreen.kt` ของแอป Android (2026-08-20)**
///
/// ลำดับบนจอตามต้นทางเป๊ะ: ปุ่มมุมสองปุ่ม → คำทักทาย → สภาพเส้นทาง → ดอกไม้ (กินที่ที่เหลือ)
/// → แถบขั้น 6 ชิป → บรรทัดนับฐาน → บรรทัดอธิบาย · **ไม่มีการ์ดกระจกครอบ** ทุกอย่างวางลงบนพื้น
/// ภาพตรง ๆ ตามที่ Android ทำ
///
/// ตัวอักษรใช้ `wbwOnBackdrop` ไม่ใช่ `wbwInk` — กฎข้อหนึ่งของ palette: พื้นเป็นภาพมืดใบเดียว
/// ทั้งสองธีม ตัวอักษรที่วางบนภาพจึงตามธีมไม่ได้ ใช้ `wbwInk` แล้วหัวข้อจะหายไปในโหมดสว่าง
///
/// **avatar หายไปจากหัวจอ** ตามต้นทาง — Android ไม่มีรูปโปรไฟล์บน Home เลย บัตรผู้เข้าร่วมเข้าจาก
/// ปุ่ม QR ข้างแถบแท็บแทน (`QrRoute = "profile"` ใน HomeScaffold.kt)
///
/// จอนี้เป็นจอแรกที่ App Review เห็นหลังล็อกอิน และเป็นเหตุผลตรง ๆ ของ Guideline 2.3.3
/// (สกรีนช็อตไม่มีอะไรให้ดู) — **ห้ามถอยกลับไปเป็นจอที่มีแต่ header**
struct HomeView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var progress: CheckinProgressStore
    @ObservedObject var noti: NotiStore
    @StateObject private var conditions = ConditionsStore()
    @State private var showProfile = false
    @State private var showSettings = false
    /// ขั้นที่ผู้ใช้กดดูจากแถบขั้น — **ชั่วคราวเท่านั้น ไม่บันทึก** ปุ่มที่ดันความคืบหน้าจริงได้
    /// จะเป็นการโกงเช็คอิน
    @State private var previewStage: Int?
    @State private var breathing = true
    @State private var breathTimeout: Task<Void, Never>?

    private var name: String { profile.me?.displayName ?? (session.user?.username ?? Loc.t("role_participant")) }

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
        VStack(alignment: .leading, spacing: 0) {
            // แถบบนแบกปุ่มมุมสองปุ่มและไม่มีอะไรอีก — คำทักทายอยู่ข้างล่างในเนื้อ เพราะมันคือ
            // เนื้อหา (บอกว่าใครและตอนนี้เป็นยังไง) จับคู่กับปุ่มแล้วมันกลายเป็น header ของจอที่
            // ไม่มี header · ประกาศอยู่ซ้าย ตั้งค่าอยู่ขวา — มุมไกลสุดสองฝั่ง อันที่เรียกร้อง
            // ความสนใจได้อยู่ฝั่งที่ตาเริ่มอ่าน
            HStack {
                cornerButton(systemImage: "bell", label: Loc.t("notifications_title"),
                             badge: noti.unreadCount > 0) {
                    NotificationCenter.default.post(name: .openNotificationsTab, object: nil)
                }
                Spacer()
                cornerButton(systemImage: "gearshape", label: Loc.t("settings_title"),
                             badge: false) {
                    showSettings = true
                }
            }
            .padding(.top, 6)

            // ช่องว่างที่ชิปทักทายเดิมเคยกิน คืนกลับเป็นอากาศ ไม่ได้ยกให้อย่างอื่น
            VStack(alignment: .leading, spacing: 12) {
                // น้ำหนักปกติ ไม่ใช่ตัวหนา — ต้นทางตั้ง `displaySmall` เป็น Sarabun Bold 34sp
                // แต่ Bold ของ Sarabun บาง พอมาเทียบกับสกรีนช็อตจริงของ Android แล้วเส้นบางกว่า
                // `.bold` ของ SF ชัดเจน · ตามที่ตาเห็นบนเครื่องจริง ไม่ใช่ตามชื่อ weight ในไฟล์
                Text(String(format: Loc.t("home_greeting"), name))
                    .font(.wbwDisplaySmall)
                    .foregroundStyle(Color.wbwOnBackdrop)

                // ใต้ชื่อและเหนือดอกไม้ เพราะอยู่ย่อหน้าเปิดเดียวกัน: คุณคือใคร แล้วข้างนอกเป็นยังไง
                // ยิงไม่ได้ = หายไปทั้งแถว ไม่เว้นรูไว้ให้เห็น (ดอกไม้กินที่คืนไปเอง)
                TrailConditionsRow(conditions: conditions.conditions)
            }
            .padding(.top, 44)

            // ดอกไม้คือเหตุผลที่จอนี้มีอยู่ — ของชิ้นเดียวบนจอที่เปลี่ยนไปตามการเดิน
            // กินที่ที่เหลือทั้งหมด ไม่ใช่ความสูงตายตัว
            // ดอกไม้กินที่ที่เหลือทั้งหมด — ยิ่งเบียดของข้างล่างลงไปใกล้แถบแท็บได้เท่าไหร่
            // ดอกไม้ก็ยิ่งใหญ่ขึ้นเท่านั้น (เทียบสัดส่วนจากสกรีนช็อตจริงของ Android)
            BloomView(stage: bloomStage, breathing: breathing, gridPoints: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 12)
                .accessibilityLabel(BloomStages.label(bloomStage))

            BloomStageStrip(currentStage: BloomStages.stage(checkedIn: stage, total: total),
                            previewStage: Binding(
                                get: { previewStage },
                                set: { previewStage = $0; nudgeBreath() }))
                .padding(.bottom, 4)

            // สองบรรทัด: จำนวน แล้วดอกไม้เกี่ยวอะไรกับมัน
            // ตอนพรีวิวทั้งคู่เปลี่ยน — ขั้นที่กำลังดู กับคำเตือนว่านั่นไม่ใช่ที่ที่คุณอยู่จริง
            // จอจึงไม่มีทางโชว์ดอกไม้ที่มันอธิบายไม่ได้
            Text(previewStage == nil
                 ? String(format: Loc.t("home_checked_in"), stage, total)
                 : BloomStages.label(bloomStage))
                .font(.wbwTitleMedium)
                .kerning(0.4)
                .foregroundStyle(Color.wbwOnBackdrop)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 2)

            // เว้นทางให้ปุ่ม SOS ที่ลอยอยู่มุมล่างขวา (MainTabView.overlay — 56pt + ขอบ 20)
            // บรรทัดนี้เป็นบรรทัดสุดท้ายของจอ จึงเป็นบรรทัดเดียวที่วิ่งไปชนปุ่มได้ · ไม่ขยับตัวปุ่ม
            // เพราะตำแหน่งมันคือสิ่งที่ต้องเดาได้ตอนตกใจ ไม่ใช่สิ่งที่ยืดหยุ่นตามจอที่มันบังเอิญลอยอยู่บน
            Text(previewStage == nil
                 ? Loc.t("home_bloom_hint")
                 : Loc.t("home_stage_preview_hint"))
                .font(.wbwBodySmall)
                .foregroundStyle(Color.wbwOnBackdropMuted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 58)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 18)
        // เว้นแค่พอพ้นแถบแท็บลอย ไม่ใช่ `tabBarClearance` เต็ม 89 — ค่านั้นเว้นไว้สำหรับของที่
        // ต้องไม่ถูกแถบบัง *เลย* ส่วนบรรทัดคำอธิบายท้ายจอเป็นตัวอักษรจาง ๆ ที่นั่งได้ใกล้กว่านั้น
        // เยอะ · ที่เหลือจากการเบียดลงไปตกเป็นของดอกไม้ ซึ่งเป็นของที่ควรได้พื้นที่มากที่สุดบนจอนี้
        // (สัดส่วนเทียบจากสกรีนช็อตจริงของ Android: ชิปขั้นอยู่เหนือแถบแท็บแค่ราวสองบรรทัด)
        .padding(.bottom, 44)
        .forestBackground(
            day: ForestMath.day(stage: stage, total: total),
            plantStep: stage,
            plantTotal: total)
        .task {
            // โหลด map.usdz ย้ายไปเริ่มที่ RootView ตอนล็อกอินสำเร็จแล้ว (2026-08-20)
            nudgeBreath()
            if profile.me == nil { await profile.load(token: session.token ?? "") }
            await conditions.refresh()
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "uitestProfile") { showProfile = true }
            // เปิดหน้าตั้งค่าตรง ๆ เพื่อถ่ายยืนยัน — เข้าได้ทางเดียวคือปุ่มมุมขวาบนซึ่งไม่มี
            // launch arg ไหนไปถึงมาก่อน (ทรงเดียวกับ -uitestProfile)
            if UserDefaults.standard.bool(forKey: "uitestSettings") { showSettings = true }
            #endif
        }
        .fullScreenCover(isPresented: $showProfile) {
            TicketView()
        }
        .sheet(isPresented: $showSettings) {
            // ต้องมี NavigationStack ครอบ — SettingsView ใช้ทั้ง .toolbar และ NavigationLink
            // ซึ่งทั้งคู่เงียบสนิทถ้าไม่มี stack ให้เกาะ (ปุ่มกลับหาย กดแถวแล้วไม่ไปไหน)
            NavigationStack { SettingsView() }
        }
    }

    /// ปุ่มมุม — **สี่เหลี่ยมมน ไม่ใช่วงกลม**
    ///
    /// ต้นทางอธิบายไว้ว่า วงกลมที่มุมจอที่กระจกเยอะขนาดนี้อ่านเป็น "avatar ที่โหลดไม่ขึ้น" —
    /// วงกลมเป็นรูปทรงที่แอปสงวนไว้ให้รูปคน · รัศมี 15 ไม่ใช่รัศมีการ์ด เพราะที่ขนาด 46
    /// รัศมีของการ์ดเกือบกลับไปเป็นวงกลมแล้ว
    private func cornerButton(systemImage: String, label: String, badge: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22))
                .foregroundStyle(Color.wbwOnBackdrop)
                .frame(width: 46, height: 46)
                .glassSurface(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    // จุดเปล่า ๆ สี ink ไม่ใช่วงกลมแดงมีเลข — ต้นทางบอกแค่ "มีของใหม่"
                    // ไม่ได้บอกจำนวน
                    if badge {
                        Circle()
                            .fill(Color.wbwOnBackdrop)
                            .frame(width: 8, height: 8)
                            .padding(7)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
