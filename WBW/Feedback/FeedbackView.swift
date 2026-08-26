import SwiftUI

/// หน้าให้ความเห็นต่อฐานหนึ่ง
///
/// การ์ดขาวบนพื้นครีมชุดเดียวกับหน้าแจ้งเตือน · ตอบไปแล้วจะแสดงคำตอบเดิมแบบอ่านอย่างเดียว — เติมค่าแบบ
/// reactive ทุกครั้งที่ item เปลี่ยน (ดู syncFromServerIfNeeded) ไม่ใช่ sample ครั้งเดียวตอน onAppear
/// เพราะเข้าหน้านี้จากแจ้งเตือนเก่าได้ ไม่ได้มาจากการเช็คอินสดเสมอไป — ยังไม่ทัน progress โหลดเสร็จก็เปิด
/// หน้านี้ได้ (Task 11: PendingPush.consume() ทำงานก่อน progress.load() เสมอ) sample ครั้งเดียวเคยทำให้
/// เคสนี้เห็นฟอร์มเปล่าที่ยังกดส่งซ้ำได้ทั้งที่ตอบไปแล้ว — แก้ในรอบรีวิวที่ 1 ของ Task 8 (ดู task-8-report.md)
struct FeedbackView: View {
    let checkpointId: Int
    let onClose: () -> Void

    @EnvironmentObject var session: Session
    @EnvironmentObject var progress: CheckinProgressStore
    @EnvironmentObject var feedback: FeedbackStore

    @State private var rating: Int?
    /// สามข้อที่ยกมาจากฝั่ง Android — ไม่บังคับตอบ (ดู `FeedbackDraft.canSubmit`)
    @State private var ratingScenery: Int?
    @State private var ratingArea: Int?
    @State private var ratingStaff: Int?
    @State private var comment = ""
    @State private var sent = false
    // ข้อความ error ตอนส่งไม่สำเร็จแบบถาวร (retry ด้วย draft เดิมไม่มีทางสำเร็จ) — nil = ไม่มี error ค้าง
    @State private var sendError: String?
    private let errorRed = Color(red: 0.84, green: 0.27, blue: 0.27) // แดง — เฉดเดียวกับ NotificationsView (emergency)
    private var item: CheckinProgressItem? { progress.item(checkpointId: checkpointId) }
    private var answered: Bool { item?.answered == true || sent }

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("action_close", action: onClose).foregroundStyle(Color.wbwInk)
                }
            }
        }
        .onAppear {
            syncFromServerIfNeeded()
            // จองฐานนี้ไว้ตลอดที่ฟอร์มเปิด — กัน flush ส่ง draft เก่าของฐานเดียวกันขึ้นไปลับหลัง
            // แล้วคำตอบจริงจาก server ย้อนกลับมาทับสิ่งที่ผู้ใช้กำลังพิมพ์ (ดู FeedbackStore.editingCheckpoint)
            feedback.beginEditing(checkpointId: checkpointId)
        }
        .onDisappear { feedback.endEditing(checkpointId: checkpointId) }
        // progress อาจโหลดเสร็จ "หลัง" หน้านี้ปรากฏ (ดูคอมเมนต์หัวไฟล์) — เรียกซ้ำทุกครั้งที่ item
        // เปลี่ยนค่า ไม่ใช่แค่ครั้งเดียวตอน appear เพื่อจับจังหวะนั้นด้วย
        .onChange(of: item) { _, _ in syncFromServerIfNeeded() }
    }

    /// เติม rating/comment จากคำตอบจริงที่ server เก็บไว้ — เรียกซ้ำได้ปลอดภัย ไม่มีผลถ้ายังไม่ตอบ
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
            Text(item?.name ?? Loc.t("feedback_base_fallback"))
                .font(.wbwText(19, weight: .bold, relativeTo: .title3))
                .foregroundStyle(Color.wbwInk)
            if let activity = item?.activityName, !activity.isEmpty {
                Text(activity)
                    .font(.wbwText(13, relativeTo: .footnote))
                    .foregroundStyle(Color.wbwInk.opacity(0.55))
                    .padding(.top, 2)
            }

            // **สี่คำถาม ไม่ใช่คำถามเดียว** — ยกมาจากฝั่ง Android (`3011729`) พร้อมเหตุผลของมัน:
            // "ฐานนี้เป็นอย่างไรบ้าง" คำถามเดียวยุบทุกอย่างที่ฐานหนึ่งเป็นให้เหลือเลขตัวเดียว
            // แล้วผู้จัดเอาไปทำอะไรต่อไม่ได้ · ฐานที่วิวดีแต่กิจกรรมน่าเบื่อกับฐานที่ตรงข้ามกัน
            // ได้คะแนนเท่ากันทั้งที่ต้องแก้คนละเรื่อง
            //
            // ชุดคำถามต้องตรงกับ Android เป๊ะ ไม่งั้นผู้จัดรวมคะแนนสองแอปไม่ได้: ข้อกิจกรรม
            // ถูกย้ายไปถามระดับงานตอนจบ (ยืนอยู่ที่ฐานตอบเรื่องกิจกรรมทั้งวันไม่ได้จริง)
            // แล้ว "พื้นที่" — ที่ว่าง ร่มเงา ที่นั่ง — เข้ามาแทน ซึ่งเป็นคนละแกนกับวิว
            //
            // เรียงภาพรวมไว้บนสุดเพราะเป็นข้อเดียวที่บังคับ — คนที่จะตอบข้อเดียวแล้วปิดจะได้
            // เจอข้อที่ใช่ก่อน ไม่ต้องเลื่อนหาผ่านสามข้อที่ข้ามได้
            VStack(spacing: 14) {
                questionRow("feedback_q_overall", "feedback_q_overall_hint", $rating)
                questionRow("feedback_q_scenery", "feedback_q_scenery_hint", $ratingScenery)
                questionRow("feedback_q_area", "feedback_q_area_hint", $ratingArea)
                questionRow("feedback_q_staff", "feedback_q_staff_hint", $ratingStaff)
            }
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
        Button(action: send) {
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
        .disabled(rating == nil || feedback.submitting.contains(checkpointId))
    }

    private func send() {
        guard let rating else { return }
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
    }
}
