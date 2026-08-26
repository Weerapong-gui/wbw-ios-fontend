import SwiftUI

/// หน้าให้ความเห็น — สองโหมด: ต่อฐาน (`base`) กับทั้งงาน (`event`)
///
/// การ์ดขาวบนพื้นครีมชุดเดียวกับหน้าแจ้งเตือน · ตอบไปแล้วจะแสดงคำตอบเดิมแบบอ่านอย่างเดียว — เติมค่าแบบ
/// reactive ทุกครั้งที่ item เปลี่ยน (ดู syncFromServerIfNeeded) ไม่ใช่ sample ครั้งเดียวตอน onAppear
/// เพราะเข้าหน้านี้จากแจ้งเตือนเก่าได้ ไม่ได้มาจากการเช็คอินสดเสมอไป — ยังไม่ทัน progress โหลดเสร็จก็เปิด
/// หน้านี้ได้ (Task 11: PendingPush.consume() ทำงานก่อน progress.load() เสมอ) sample ครั้งเดียวเคยทำให้
/// เคสนี้เห็นฟอร์มเปล่าที่ยังกดส่งซ้ำได้ทั้งที่ตอบไปแล้ว — แก้ในรอบรีวิวที่ 1 ของ Task 8 (ดู task-8-report.md)
///
/// **`kind`/`blocking` เพิ่มใน Task 4** เพื่อให้ gate เต็มจอ (Task 5) ใช้จอเดียวกันนี้ทั้งสองแบบ:
/// ต่อฐานเดิม (ปิดเองได้) กับความเห็นทั้งงานตอนจบทริป (gate ยึดจอ ไม่มีปุ่มปิด — ถอยเองเมื่อข้อมูล
/// เปลี่ยนหรือผู้ใช้กดข้าม) ทางเรียกเดิม 4 ทางใน MainTabView ยังคอมไพล์ผ่านไม่ต้องแก้ ผ่าน init สะดวก
/// ด้านล่างที่ผูก `.base` + `blocking: false` ให้อัตโนมัติ
struct FeedbackView: View {
    enum Kind: Equatable {
        case base(checkpointId: Int)
        case event
    }

    let kind: Kind
    /// true = ไม่มีปุ่มปิดบน toolbar (gate เป็นคนถอยเองด้วยข้อมูล ไม่ใช่ผู้ใช้กดปิด)
    let blocking: Bool
    /// `.base`: เรียกตอนผู้ใช้กดปิดเอง (ไม่มีผลถ้า blocking) · `.event`: เรียกตอนส่งสำเร็จ หรือกดข้าม
    let onClose: () -> Void

    init(kind: Kind, blocking: Bool, onClose: @escaping () -> Void) {
        self.kind = kind
        self.blocking = blocking
        self.onClose = onClose
    }

    /// ทางเรียกเดิมทั้ง 4 ทางใน MainTabView ก่อน Task 4 — คงหน้าตาไว้ไม่ต้องแก้จุดเรียก
    init(checkpointId: Int, onClose: @escaping () -> Void) {
        self.init(kind: .base(checkpointId: checkpointId), blocking: false, onClose: onClose)
    }

    @EnvironmentObject var session: Session
    @EnvironmentObject var progress: CheckinProgressStore
    @EnvironmentObject var feedback: FeedbackStore

    @State private var rating: Int?
    /// สามข้อที่ยกมาจากฝั่ง Android — ไม่บังคับตอบ (ดู `FeedbackDraft.canSubmit`) · ใช้เฉพาะ `.base`
    @State private var ratingScenery: Int?
    @State private var ratingArea: Int?
    @State private var ratingStaff: Int?
    /// ข้อกิจกรรม — ย้ายมาจากฟอร์มต่อฐานแล้ว (ดู `EventFeedbackDraft.swift`) กลับมาโผล่เฉพาะ `.event`
    @State private var ratingActivity: Int?
    @State private var comment = ""
    @State private var sent = false
    // ข้อความ error ตอนส่งไม่สำเร็จแบบถาวร (retry ด้วย draft เดิมไม่มีทางสำเร็จ) — nil = ไม่มี error ค้าง
    // ใช้ร่วมกันทั้งสองโหมด เพราะ view หนึ่งตัวเป็นได้แค่โหมดเดียวตลอดอายุของมัน
    @State private var sendError: String?
    /// clientId ของ draft ทั้งงาน — สร้างครั้งเดียวตอนกดส่งครั้งแรกแล้วเก็บไว้ใช้ซ้ำตอน retry
    /// (ห้ามสร้างใหม่ทุกครั้งที่กดส่งเหมือน `.base` เพราะ event feedback ไม่มี outbox คอย
    /// dedupe ด้วย checkpointId — ถ้า clientId เปลี่ยนทุกครั้ง retry จะกลายเป็นสองแถวที่ server)
    @State private var eventClientId: String?
    /// true หลังส่ง `.event` แล้วพังแบบถาวร — โผล่ปุ่ม "ข้ามไปก่อน" ให้ผู้ใช้เดินต่อได้โดยไม่ต้องรอ
    @State private var eventSendFailed = false
    @State private var eventSubmitting = false
    private let errorRed = Color(red: 0.84, green: 0.27, blue: 0.27) // แดง — เฉดเดียวกับ NotificationsView (emergency)

    private var item: CheckinProgressItem? {
        guard case .base(let checkpointId) = kind else { return nil }
        return progress.item(checkpointId: checkpointId)
    }
    private var answered: Bool { item?.answered == true || sent }
    private var isSubmitting: Bool {
        switch kind {
        case .base(let checkpointId): return feedback.submitting.contains(checkpointId)
        case .event: return eventSubmitting
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.wbwBg.ignoresSafeArea()
                ScrollView {
                    card.padding(.horizontal, 16).padding(.top, 12)
                        .contentColumn(.form)
                }
            }
            .navigationTitle(Text("feedback_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // blocking = gate เต็มจอ ไม่มีทางปิดเอง (ถอยเองเมื่อข้อมูลเปลี่ยนหรือกดข้ามในฟอร์ม)
                if !blocking {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("action_close", action: onClose).foregroundStyle(Color.wbwInk)
                    }
                }
            }
        }
        .onAppear {
            syncFromServerIfNeeded()
            if case .base(let checkpointId) = kind {
                // จองฐานนี้ไว้ตลอดที่ฟอร์มเปิด — กัน flush ส่ง draft เก่าของฐานเดียวกันขึ้นไปลับหลัง
                // แล้วคำตอบจริงจาก server ย้อนกลับมาทับสิ่งที่ผู้ใช้กำลังพิมพ์ (ดู FeedbackStore.editingCheckpoint)
                feedback.beginEditing(checkpointId: checkpointId)
            }
        }
        .onDisappear {
            if case .base(let checkpointId) = kind {
                feedback.endEditing(checkpointId: checkpointId)
            }
        }
        // progress อาจโหลดเสร็จ "หลัง" หน้านี้ปรากฏ (ดูคอมเมนต์หัวไฟล์) — เรียกซ้ำทุกครั้งที่ item
        // เปลี่ยนค่า ไม่ใช่แค่ครั้งเดียวตอน appear เพื่อจับจังหวะนั้นด้วย
        .onChange(of: item) { _, _ in syncFromServerIfNeeded() }
    }

    /// เติม rating/comment จากคำตอบจริงที่ server เก็บไว้ — เรียกซ้ำได้ปลอดภัย ไม่มีผลถ้ายังไม่ตอบ
    /// (`.event` ไม่มี item เลยจึงไม่มีผลอะไรกับโหมดนั้น)
    ///
    /// **ไม่มีข้อยกเว้นให้ของที่ผู้ใช้เพิ่งพิมพ์เอง** เดิมมี flag `userEdited` กันไว้ ตั้งใจกัน "progress
    /// reload พื้นหลังมาทับระหว่างกำลังพิมพ์" — แต่ guard `it.answered` กันเคสนั้นอยู่แล้ว (ยังไม่ตอบ =
    /// ไม่มีอะไรจาก server ให้ทับ) สิ่งที่ flag นั้นกันได้จริงจึงเหลือเคสเดียว: ฐานนี้ถูกตอบจาก "ทางอื่น"
    /// (อีกเครื่อง/คนละ client) ระหว่างที่ฟอร์มนี้เปิดค้างพร้อม draft ที่ยังไม่ได้ส่ง — พอ answered พลิก
    /// เป็น true ทั้งจอกลายเป็นโหมดอ่านอย่างเดียวพร้อมป้าย "ส่งความเห็นแล้ว ขอบคุณ" แต่ตัวเลข/ข้อความ
    /// ที่โชว์คือ draft ในเครื่องที่ไม่เคยถูกบันทึก = โกหกผู้ใช้ว่าส่งของที่ไม่ได้ส่งไป (Task 8 เจอแล้วตัดสิน
    /// ว่ายังไปไม่ถึง เพราะตอนนั้นไม่มีอะไร reload progress ระหว่างฟอร์มเปิด — poll 60 วิของ Task 11
    /// ทำให้ไปถึงได้แล้ว) คำตอบจริงต้องชนะเสมอ
    private func syncFromServerIfNeeded() {
        guard let it = item, it.answered else { return }
        rating = it.rating
        comment = it.comment ?? ""
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(spacing: 14) { questionRows }
                .padding(.top, 16)

            TextEditor(text: $comment)
                .font(.wbwText(14, relativeTo: .subheadline))
                .foregroundStyle(Color.wbwInk)
                .scrollContentBackground(.hidden)
                .frame(height: 110)
                .padding(8)
                .background(Color.wbwBg, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.wbwInk.opacity(0.12), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if comment.isEmpty {
                        Text("feedback_note_hint")
                            .font(.wbwText(14, relativeTo: .subheadline))
                            .foregroundStyle(Color.wbwInk.opacity(0.35))
                            .padding(.horizontal, 13).padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .disabled(answered)
                .padding(.top, 14)

            Text("feedback_named")
                .font(.wbwText(11, relativeTo: .caption2))
                .foregroundStyle(Color.wbwInk.opacity(0.5))
                .padding(.top, 8)

            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // **`wbwSurface` ไม่ใช่ขาวตายตัว** — ตัวอักษรบนการ์ดใบนี้ใช้ `wbwInk` ซึ่งเป็นขาวเกือบขาว
        // (#E9EEE0) ในโหมดมืด วางบนแผ่นขาวแล้วได้ขาวบนขาว: หัวข้อฐาน คำโปรย และปุ่มส่งหายไป
        // กับพื้นทั้งหมด (เห็นจริงในสกรีนช็อต `08-feedback` ที่เตรียมส่ง App Store)
        // การ์ดใบนี้ไม่ใช่ "กระดาษ" แบบบัตรผู้เข้าร่วม จึงต้องเดินตามธีมเหมือนการ์ดใบอื่น
        .background(Color.wbwSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.wbwInk.opacity(0.07), lineWidth: 1))
    }

    /// หัวการ์ด — `.base` โชว์ชื่อฐาน (+ ชื่อกิจกรรมถ้ามี) เหมือนเดิม `.event` ไม่มีฐานให้โชว์
    /// จึงใช้ชื่อคงที่ "ตลอดเส้นทาง" แทน (ไม่มี activityName ให้ต่อท้าย)
    @ViewBuilder
    private var header: some View {
        switch kind {
        case .base:
            Text(item?.name ?? Loc.t("feedback_base_fallback"))
                .font(.wbwText(19, weight: .bold, relativeTo: .title3))
                .foregroundStyle(Color.wbwInk)
            if let activity = item?.activityName, !activity.isEmpty {
                Text(activity)
                    .font(.wbwText(13, relativeTo: .footnote))
                    .foregroundStyle(Color.wbwInk.opacity(0.55))
                    .padding(.top, 2)
            }
        case .event:
            Text(Loc.t("feedback_event_name"))
                .font(.wbwText(19, weight: .bold, relativeTo: .title3))
                .foregroundStyle(Color.wbwInk)
        }
    }

    /// **สี่คำถาม ไม่ใช่คำถามเดียว** — ยกมาจากฝั่ง Android (`3011729`) พร้อมเหตุผลของมัน:
    /// "ฐานนี้เป็นอย่างไรบ้าง" คำถามเดียวยุบทุกอย่างที่ฐานหนึ่งเป็นให้เหลือเลขตัวเดียว
    /// แล้วผู้จัดเอาไปทำอะไรต่อไม่ได้ · ฐานที่วิวดีแต่กิจกรรมน่าเบื่อกับฐานที่ตรงข้ามกัน
    /// ได้คะแนนเท่ากันทั้งที่ต้องแก้คนละเรื่อง
    ///
    /// ชุดคำถามต้องตรงกับ Android เป๊ะ ไม่งั้นผู้จัดรวมคะแนนสองแอปไม่ได้: ข้อกิจกรรม
    /// ถูกย้ายไปถามระดับงานตอนจบ (ยืนอยู่ที่ฐานตอบเรื่องกิจกรรมทั้งวันไม่ได้จริง)
    /// แล้ว "พื้นที่" — ที่ว่าง ร่มเงา ที่นั่ง — เข้ามาแทน ซึ่งเป็นคนละแกนกับวิว
    ///
    /// เรียงภาพรวมไว้บนสุดเพราะเป็นข้อเดียวที่บังคับ — คนที่จะตอบข้อเดียวแล้วปิดจะได้
    /// เจอข้อที่ใช่ก่อน ไม่ต้องเลื่อนหาผ่านสามข้อที่ข้ามได้
    ///
    /// `.event`: เหลือสองข้อ — ภาพรวมทั้งเดิน (คีย์ `_event` แยกจาก `.base` เพราะ Android ใช้ถ้อยคำ
    /// คนละชุดสำหรับสองบริบทนี้) กับข้อกิจกรรมที่ย้ายมาจาก `.base` (ใช้หัวข้อเดิม คู่กับ hint ใหม่)
    @ViewBuilder
    private var questionRows: some View {
        switch kind {
        case .base:
            questionRow("feedback_q_overall", "feedback_q_overall_hint", $rating)
            questionRow("feedback_q_scenery", "feedback_q_scenery_hint", $ratingScenery)
            questionRow("feedback_q_area", "feedback_q_area_hint", $ratingArea)
            questionRow("feedback_q_staff", "feedback_q_staff_hint", $ratingStaff)
        case .event:
            questionRow("feedback_q_overall_event", "feedback_q_overall_event_hint", $rating)
            questionRow("feedback_q_activity", "feedback_q_activity_event_hint", $ratingActivity)
        }
    }

    /// ส่วนท้ายการ์ด — ต่างกันตามโหมดเพราะ "ตอบแล้ว" มีความหมายต่างกัน: `.base` มีสถานะอ่านอย่างเดียว
    /// ถาวร (server จำคำตอบต่อฐานไว้) ส่วน `.event` ส่งสำเร็จแล้วปิดฟอร์มไปเลยผ่าน onClose() ไม่มีจังหวะ
    /// ที่ต้องโชว์การ์ดในสถานะ "ตอบแล้ว" ค้างอยู่
    @ViewBuilder
    private var footer: some View {
        switch kind {
        case .base:
            if answered {
                Label("feedback_thanks", systemImage: "checkmark.circle.fill")
                    .font(.wbwText(14, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.wbwGreen)
                    .padding(.top, 14)
            } else {
                // ส่งไม่สำเร็จแบบถาวร (.failed/.notCheckedIn จาก send()) — บอกตรงๆ ไม่ปล่อยให้ค้าง
                // เงียบๆ โดยไม่มีทางไปต่อ ปุ่มส่งด้านล่างยังกดซ้ำได้เสมอ (rating/comment ไม่ถูกล้าง)
                if let sendError {
                    Label(sendError, systemImage: "exclamationmark.triangle.fill")
                        .font(.wbwText(12, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(errorRed)
                        .padding(.top, 10)
                }
                sendButton.padding(.top, 14)
            }
        case .event:
            if let sendError {
                Label(sendError, systemImage: "exclamationmark.triangle.fill")
                    .font(.wbwText(12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(errorRed)
                    .padding(.top, 10)
            }
            sendButton.padding(.top, 14)
            // โผล่เฉพาะหลังส่งพังแบบถาวร — ปุ่มข้ามไม่ใช่ทางออกเด่นที่ควรมีให้กดตั้งแต่แรก
            // (ฟอร์มนี้เป็นจอสุดท้ายก่อนจบทริป ควรพยายามเก็บคำตอบก่อนเสมอ)
            if eventSendFailed {
                giveUpButton.padding(.top, 8)
            }
        }
    }

    /// หนึ่งคำถาม: หัวข้อ + คำอธิบายสั้น + ปุ่มคะแนน 1–5
    ///
    /// **สเกล 1–5 เท่าฝั่ง Android** ของเดิมเป็นสามหน้า (ไม่ชอบ/เฉย ๆ/ชอบ) ซึ่งอ่านง่ายกว่าก็จริง
    /// แต่คนละสเกลกับอีกแอปแปลว่าผู้จัดเอาคะแนนสองฝั่งมารวมกันไม่ได้เลย ทั้งที่เป็นงานเดียวกัน
    private func questionRow(_ titleKey: String, _ hintKey: String,
                             _ value: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(titleKey))
                .font(.wbwText(14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(Color.wbwInk)
            Text(LocalizedStringKey(hintKey))
                .font(.wbwText(11, relativeTo: .caption2))
                .foregroundStyle(Color.wbwInk.opacity(0.5))
            HStack(spacing: 8) {
                ForEach(Array(FeedbackDraft.scale), id: \.self) { score in
                    scaleButton(score, value)
                }
            }
            // ปลายสเกลบอกด้วยคำ ไม่ใช่ให้เดาเอาว่า 1 คือดีหรือแย่
            HStack {
                Text("feedback_scale_low")
                Spacer()
                Text("feedback_scale_high")
            }
            .font(.wbwText(10, relativeTo: .caption2))
            .foregroundStyle(Color.wbwInk.opacity(0.4))
        }
    }

    private func scaleButton(_ value: Int, _ binding: Binding<Int?>) -> some View {
        let picked = binding.wrappedValue == value
        return Button {
            guard !answered else { return }
            binding.wrappedValue = value
        } label: {
            Text("\(value)")
                .font(.wbwNumeral(16, relativeTo: .body))
                .frame(maxWidth: .infinity)
                .frame(height: Config.Tap.minTarget)
                .foregroundStyle(picked ? Color.wbwOnGreen : Color.wbwInk.opacity(0.6))
                .background(picked ? Color.wbwGreen : Color.wbwBg,
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(picked ? Color.wbwGreen : Color.wbwInk.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        // ที่เลือกอยู่ต่างกันแค่สีพื้นกับสีเส้น — VoiceOver ไม่มีทางรู้ถ้าไม่บอก
        .accessibilityAddTraits(picked ? .isSelected : [])
        .disabled(answered)
    }

    private var sendButton: some View {
        Button(action: submitTapped) {
            HStack(spacing: 6) {
                Image(systemName: "paperplane").font(.system(size: 14, weight: .semibold))
                Text("feedback_send").font(.wbwText(15, weight: .semibold, relativeTo: .subheadline))
            }
            // ปุ่มส่งใช้คู่สีเดียวกับปุ่มส่งในแชท — `wbwGold` เป็น alias ของ `wbwAccent` ซึ่งเป็น
            // #E9EEE0 ในโหมดมืด คู่กับตัวอักษรขาวตายตัวแล้วได้ปุ่มขาวบนขาว (รอยเดียวกับปุ่ม
            // "เข้ากลุ่ม" ที่เคยโดน — ดูคอมเมนต์ของ `wbwSolid` ใน Config.swift)
            // ขาปิดใช้งานใช้ `wbwSolid` ซึ่งตรึงไว้เข้มทั้งสองธีม ตัวอักษรขาวจึงอ่านออกเสมอ
            .foregroundStyle(rating == nil ? Color.white : Color.wbwOnGreen)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(rating == nil ? Color.wbwSolid : Color.wbwGreen,
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(rating == nil || isSubmitting)
    }

    /// ปุ่มรอง "ข้ามไปก่อน" — เฉพาะ `.event` ตอนส่งพังแบบถาวร ตัวหนังสือเฉยๆ ใต้ปุ่มส่ง ไม่ใช่ปุ่มเด่น
    /// แข่งกับปุ่มส่ง (ไม่มีพื้นหลัง/เส้นขอบ) แต่พื้นที่รับนิ้วยังต้องถึง Config.Tap.minTarget เหมือนปุ่มอื่น
    ///
    /// **`.contentShape(Rectangle())` จำเป็น** — ปุ่มตัวหนังสือล้วนไม่มีพื้นหลัง SwiftUI จึงนับพื้นที่แตะ
    /// จากตัวอักษรจริงเท่านั้นถ้าไม่บอกรูปทรงเอง ทำให้ frame ที่ขยายไว้ไม่มีผลกับนิ้วจริง (ตรึงรูปแบบเดียว
    /// กับปุ่ม chat_block ที่ GroupMembersView.swift)
    private var giveUpButton: some View {
        Button(action: onClose) {
            Text("feedback_give_up")
                .font(.wbwText(14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(Color.wbwInk.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: Config.Tap.minTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func submitTapped() {
        switch kind {
        case .base: send()
        case .event: sendEvent()
        }
    }

    private func send() {
        guard case .base(let checkpointId) = kind, let rating else { return }
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = FeedbackDraft(
            clientId: UUID().uuidString.lowercased(),
            checkpointId: checkpointId,
            rating: rating,
            ratingScenery: ratingScenery,
            ratingArea: ratingArea,
            ratingStaff: ratingStaff,
            comment: trimmed.isEmpty ? nil : trimmed,
            deviceTime: ISO8601DateFormatter().string(from: Date()))
        sendError = nil
        // ท่าทีมองโลกในแง่ดีเฉพาะ .saved — ครอบคลุมทั้งสำเร็จจริงและเน็ตหลุด (FeedbackStore คิวไว้เอง
        // ด้วย clientId เดิมการันตี retry ไม่ซ้ำแถว) ผลลัพธ์อื่นที่ await คืนมาด้านล่างเป็นสถานะปลายทาง
        // ที่ retry ด้วย draft เดิมไม่มีทางสำเร็จ ต้องบอกความจริง ไม่ปล่อยค้างเป็น "ส่งแล้ว" ทั้งที่ไม่จริง
        // (ดู FeedbackStoreTests.testSubmitTerminalFailureReturnsFailedAndDoesNotQueue)
        sent = true
        Task {
            let outcome = await feedback.submit(draft, token: session.token ?? "")
            switch outcome {
            case .saved:
                break   // ตั้ง sent ไว้ถูกแล้วด้านบน ไม่ต้องทำอะไรเพิ่ม
            case .alreadyAnswered:
                // มีคำตอบจริงอยู่แล้วที่ server (ส่งมาจากที่อื่น/คนละ client_id) — ของที่เพิ่งพิมพ์ตรงนี้
                // ไม่ถูกบันทึก · sent = false ไว้ก่อน แล้ว progress.load() ท้าย closure จะพา
                // syncFromServerIfNeeded (ผ่าน .onChange(of: item)) มาเติมคำตอบจริงทับให้เอง
                sent = false
            case .notCheckedIn:
                // ไม่ควรเกิดถ้า UI คุมถูก — เปิดฟอร์มนี้ได้ก็ต่อเมื่อเช็คอินฐานนี้แล้วเท่านั้น บอกตรงๆ
                // แทนที่จะกลืนเงียบๆ ให้เห็นชัดว่ามีจุดที่ตรรกะพังอยู่ที่ไหนสักที่
                sent = false
                sendError = Loc.t("feedback_not_checked_in")
            case .failed:
                sent = false
                sendError = Loc.t("feedback_send_failed")
            }
            // ทริกเกอร์ที่สองของ outbox ตาม spec (อีกตัวคือ scenePhase == .active) — เพิ่งพิสูจน์ว่า
            // เน็ตเดินอยู่ ของค้างของ "ฐานอื่น" ที่คิวไว้ตอนสัญญาณหายจึงไปได้แล้ว ไม่ต้องรอผู้ใช้สลับ
            // แอปออกแล้วกลับมา (คนเดินฐานต่อฐานอาจไม่ทำแบบนั้นเลยทั้งงาน) · เรียกทุกผลลัพธ์ไม่แยกเคส
            // เพราะ .saved เองก็คลุมทั้ง "ถึง server จริง" และ "เข้าคิวเพราะเน็ตหลุด" อยู่แล้ว
            // (FeedbackStore ตั้งใจซ่อนความต่างนั้นจาก UI) และ flush หยุดเองทันทีที่เจอ offline ตัวแรก
            // ฐานที่เปิดฟอร์มอยู่ตอนนี้ถูกข้ามเสมอ (ดู FeedbackStore.editingCheckpoint)
            await feedback.flush(token: session.token ?? "")
            await progress.load(token: session.token ?? "")
        }
        // .base โหมด blocking (gate เต็มจอ Task 5): ไม่ต้องทำอะไรเพิ่มตรงนี้ — progress.load() ด้านบน
        // ทำให้ gate อ่านค่า answered ใหม่แล้วถอยเองตามสเปก ไม่ต้องเรียก onClose() จากในนี้
    }

    /// ส่งความเห็นทั้งงาน — ต่างจาก `send()` (ต่อฐาน) เพราะไม่มี outbox ให้เก็บคิวไว้รอรอบหน้า
    /// (ดูเหตุผลที่ `EventFeedbackDraft.swift`) ต้องรู้ผลจริงเดี๋ยวนั้นเพื่อโชว์ retry/ข้ามให้ถูก
    private func sendEvent() {
        guard let rating else { return }
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        // สร้าง clientId ครั้งแรกที่กดส่งเท่านั้น รอบ retry ถัดไปใช้ตัวเดิม (ดูคอมเมนต์ที่ประกาศ @State)
        if eventClientId == nil { eventClientId = UUID().uuidString.lowercased() }
        let draft = EventFeedbackDraft(
            clientId: eventClientId!,
            rating: rating,
            ratingActivity: ratingActivity,
            comment: trimmed.isEmpty ? nil : trimmed,
            deviceTime: ISO8601DateFormatter().string(from: Date()))
        sendError = nil
        eventSubmitting = true
        Task {
            let outcome = await APIClient.shared.submitEventFeedback(token: session.token ?? "", draft: draft)
            eventSubmitting = false
            switch outcome {
            case .saved, .alreadyAnswered:
                // .alreadyAnswered แปลว่ามีคำตอบทั้งงานอยู่แล้วที่ server (เช่น retry ซ้ำที่จริงเข้าไปแล้ว
                // รอบก่อนแต่ response หลุด) ไม่ต่างจากผู้ใช้ตอบสำเร็จรอบนี้ — ปิดฟอร์มเหมือนกัน
                onClose()
            case .notCheckedIn, .failed:
                // submitEventFeedback ไม่เคยคืน .notCheckedIn จริง (ดูคอมเมนต์ที่ APIClient) แต่ enum
                // มีสี่ case ต้องครบทุกสาขา — ปฏิบัติเหมือน .failed ถ้าเกิดขึ้นจริงในอนาคต
                eventSendFailed = true
                sendError = Loc.t("feedback_send_failed")
            }
        }
    }
}
