import SwiftUI

/// หน้าให้ความเห็นต่อฐานหนึ่ง
///
/// การ์ดขาวบนพื้นครีมชุดเดียวกับหน้าแจ้งเตือน · ตอบไปแล้วจะแสดงคำตอบเดิมแบบอ่านอย่างเดียว
/// ไม่ใช่ฟอร์มเปล่า (เข้าหน้านี้จากแจ้งเตือนเก่าได้ ไม่ได้มาจากการเช็คอินสดเสมอไป)
struct FeedbackView: View {
    let checkpointId: Int
    let onClose: () -> Void

    @EnvironmentObject var session: Session
    @EnvironmentObject var progress: CheckinProgressStore
    @EnvironmentObject var feedback: FeedbackStore

    @State private var rating: Int?
    @State private var comment = ""
    @State private var sent = false

    private let cream = Color(red: 250 / 255, green: 247 / 255, blue: 240 / 255)
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
        .onAppear {
            // ตอบไปแล้ว → โชว์คำตอบเดิม
            if let it = item, it.answered {
                rating = it.rating
                comment = it.comment ?? ""
            }
        }
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

            TextEditor(text: $comment)
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
        return Button { if !answered { rating = value } } label: {
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
        sent = true   // optimistic — clientId การันตีว่าส่งซ้ำไม่เกิดแถวซ้ำ
        Task {
            await feedback.submit(draft, token: session.token ?? "")
            await progress.load(token: session.token ?? "")
        }
    }
}
