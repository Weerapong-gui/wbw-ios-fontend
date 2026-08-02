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
    // ผู้ใช้เคยพิมพ์คอมเมนต์เองหรือกดเลือกคะแนนเองในเซสชันนี้แล้ว — ถ้าจริง syncFromServerIfNeeded
    // ต้องไม่ทับของที่พิมพ์/กดไว้ด้วยคำตอบจาก server (กันกรณี progress reload พื้นหลังมาทับระหว่างที่
    // กำลังพิมพ์คอมเมนต์ยาวๆ อยู่) ยกเว้นตอนได้ .alreadyAnswered กลับมาจาก send() ซึ่ง reset ตัวนี้เอง
    // เพราะตอนนั้นรู้แน่แล้วว่าของที่เพิ่งพิมพ์ไม่ถูกบันทึก คำตอบจริงจาก server ต้องชนะ
    @State private var userEdited = false
    // ข้อความ error ตอนส่งไม่สำเร็จแบบถาวร (retry ด้วย draft เดิมไม่มีทางสำเร็จ) — nil = ไม่มี error ค้าง
    @State private var sendError: String?

    private let cream = Color(red: 250 / 255, green: 247 / 255, blue: 240 / 255)
    private let errorRed = Color(red: 0.84, green: 0.27, blue: 0.27) // แดง — เฉดเดียวกับ NotificationsView (emergency)
    private var item: CheckinProgressItem? { progress.item(checkpointId: checkpointId) }
    private var answered: Bool { item?.answered == true || sent }

    var body: some View {
        NavigationStack {
            ZStack {
                cream.ignoresSafeArea()
                ScrollView {
                    card.padding(.horizontal, 16).padding(.top, 12)
                }
            }
            .navigationTitle("ประเมินฐาน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("ปิด", action: onClose).foregroundStyle(Color.wbwInk)
                }
            }
        }
        .onAppear { syncFromServerIfNeeded() }
        // progress อาจโหลดเสร็จ "หลัง" หน้านี้ปรากฏ (ดูคอมเมนต์หัวไฟล์) — เรียกซ้ำทุกครั้งที่ item
        // เปลี่ยนค่า ไม่ใช่แค่ครั้งเดียวตอน appear เพื่อจับจังหวะนั้นด้วย
        .onChange(of: item) { _, _ in syncFromServerIfNeeded() }
    }

    /// เติม rating/comment จากคำตอบจริงที่เคยส่งไว้ (ถ้ามี) — ไม่ทับของที่ผู้ใช้เพิ่งพิมพ์/กดเอง
    /// (userEdited) เรียกได้ซ้ำหลายครั้งอย่างปลอดภัย ไม่มีผลถ้ายังไม่ตอบ หรือผู้ใช้แก้เองไปแล้ว
    private func syncFromServerIfNeeded() {
        guard let it = item, it.answered, !userEdited else { return }
        rating = it.rating
        comment = it.comment ?? ""
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item?.name ?? "ฐานกิจกรรม")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color.wbwInk)
            if let activity = item?.activityName, !activity.isEmpty {
                Text(activity)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.wbwInk.opacity(0.55))
                    .padding(.top, 2)
            }

            HStack(spacing: 10) {
                faceButton(1, "hand.thumbsdown", "ไม่ชอบ")
                faceButton(2, "minus.circle", "เฉยๆ")
                faceButton(3, "hand.thumbsup", "ชอบ")
            }
            .padding(.top, 16)

            TextEditor(text: commentBinding)
                .font(.system(size: 14))
                .foregroundStyle(Color.wbwInk)
                .scrollContentBackground(.hidden)
                .frame(height: 110)
                .padding(8)
                .background(cream, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.wbwInk.opacity(0.12), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if comment.isEmpty {
                        Text("เล่าให้ฟังหน่อย… (ไม่บังคับ)")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.wbwInk.opacity(0.35))
                            .padding(.horizontal, 13).padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .disabled(answered)
                .padding(.top, 14)

            Text("ทีมงานเห็นชื่อผู้ตอบ")
                .font(.system(size: 11))
                .foregroundStyle(Color.wbwInk.opacity(0.5))
                .padding(.top, 8)

            if answered {
                Label("ส่งความเห็นแล้ว ขอบคุณ", systemImage: "checkmark.circle.fill")
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

    /// binding ที่ TextEditor ใช้จริง แยกจาก $comment ตรงๆ เพื่อจับ "ผู้ใช้พิมพ์เอง" ให้ตั้ง userEdited
    /// ได้ — syncFromServerIfNeeded เขียน comment ตรงๆ ผ่าน @State ไม่ผ่าน binding นี้ จึงไม่ติด flag
    private var commentBinding: Binding<String> {
        Binding(get: { comment }, set: { comment = $0; userEdited = true })
    }

    private func faceButton(_ value: Int, _ symbol: String, _ label: String) -> some View {
        let picked = rating == value
        return Button {
            guard !answered else { return }
            rating = value
            userEdited = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(picked ? Color.wbwGreen : Color.wbwInk.opacity(0.5))
            .background(picked ? Color.wbwGreen.opacity(0.12) : cream,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(picked ? Color.wbwGreen : Color.wbwInk.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(answered)
    }

    private var sendButton: some View {
        Button(action: send) {
            HStack(spacing: 6) {
                Image(systemName: "paperplane").font(.system(size: 14, weight: .semibold))
                Text("ส่งความเห็น").font(.system(size: 15, weight: .semibold))
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
                // ไม่ถูกบันทึก เคลียร์ userEdited ให้ syncFromServerIfNeeded (เรียกจาก onChange ด้านล่าง
                // หลัง reload) เติมคำตอบจริงทับได้ ไม่ติด guard กันทับที่ตั้งใจกันไว้กันเคสอื่น
                sent = false
                userEdited = false
            case .notCheckedIn:
                // ไม่ควรเกิดถ้า UI คุมถูก — เปิดฟอร์มนี้ได้ก็ต่อเมื่อเช็คอินฐานนี้แล้วเท่านั้น บอกตรงๆ
                // แทนที่จะกลืนเงียบๆ ให้เห็นชัดว่ามีจุดที่ตรรกะพังอยู่ที่ไหนสักที่
                sent = false
                sendError = "ระบบแจ้งว่ายังไม่ได้เช็คอินฐานนี้ (ไม่ควรเกิดขึ้น) ลองปิดแล้วเปิดฟอร์มใหม่"
            case .failed:
                sent = false
                sendError = "ส่งไม่สำเร็จ ลองอีกครั้ง"
            }
            await progress.load(token: session.token ?? "")
        }
    }
}
