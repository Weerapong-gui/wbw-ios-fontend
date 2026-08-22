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
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color.wbwInk)
            if let activity = item?.activityName, !activity.isEmpty {
                Text(activity)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.wbwInk.opacity(0.55))
                    .padding(.top, 2)
            }

            HStack(spacing: 10) {
                faceButton(1, "hand.thumbsdown", Loc.t("feedback_dislike"))
                faceButton(2, "minus.circle", Loc.t("feedback_neutral"))
                faceButton(3, "hand.thumbsup", Loc.t("feedback_like"))
            }
            .padding(.top, 16)

            TextEditor(text: $comment)
                .font(.system(size: 14))
                .foregroundStyle(Color.wbwInk)
                .scrollContentBackground(.hidden)
                .frame(height: 110)
                .padding(8)
                .background(Color.wbwBg, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.wbwInk.opacity(0.12), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if comment.isEmpty {
                        Text("feedback_note_hint")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.wbwInk.opacity(0.35))
                            .padding(.horizontal, 13).padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .disabled(answered)
                .padding(.top, 14)

            Text("feedback_named")
                .font(.system(size: 11))
                .foregroundStyle(Color.wbwInk.opacity(0.5))
                .padding(.top, 8)

            if answered {
                Label("feedback_thanks", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.wbwGreen)
                    .padding(.top, 14)
            } else {
                // ส่งไม่สำเร็จแบบถาวร (.failed/.notCheckedIn จาก send()) — บอกตรงๆ ไม่ปล่อยให้ค้าง
                // เงียบๆ โดยไม่มีทางไปต่อ ปุ่มส่งด้านล่างยังกดซ้ำได้เสมอ (rating/comment ไม่ถูกล้าง)
                if let sendError {
                    Label(sendError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(errorRed)
                        .padding(.top, 10)
                }
                sendButton.padding(.top, 14)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.wbwInk.opacity(0.07), lineWidth: 1))
    }

    private func faceButton(_ value: Int, _ symbol: String, _ label: String) -> some View {
        let picked = rating == value
        return Button {
            guard !answered else { return }
            rating = value
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(picked ? Color.wbwGreen : Color.wbwInk.opacity(0.5))
            .background(picked ? Color.wbwGreen.opacity(0.12) : Color.wbwBg,
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
                Text("feedback_send").font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(rating == nil ? Color.wbwInk.opacity(0.3) : Color.wbwGold,
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
