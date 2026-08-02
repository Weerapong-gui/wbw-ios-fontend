import Foundation

/// ส่งความเห็น + คิวของที่ยังส่งไม่สำเร็จ
///
/// UI ตอบว่า "ส่งแล้ว" ทันทีแบบ optimistic ได้ เพราะ clientId การันตีว่าส่งซ้ำ
/// ไม่เกิดแถวซ้ำ — ที่เหลือเป็นเรื่องของ outbox กับ flush รอบหน้า
@MainActor
final class FeedbackStore: ObservableObject {
    /// checkpointId ที่กำลังส่งอยู่ — ปุ่มส่งของฐานนั้นกดซ้ำไม่ได้
    @Published private(set) var submitting: Set<Int> = []

    private var outbox: FeedbackOutbox { FeedbackOutbox() }

    /// ส่งหนึ่งอัน · ส่งไม่ผ่านเพราะเน็ต = เข้า outbox เงียบๆ แล้วคืน .saved
    /// (ผู้ใช้ไม่ต้องรู้ว่ามันยังไม่ถึงเซิร์ฟเวอร์ ระบบรับผิดชอบเอง)
    @discardableResult
    func submit(_ draft: FeedbackDraft, token: String) async -> APIClient.FeedbackSubmitOutcome {
        submitting.insert(draft.checkpointId)
        defer { submitting.remove(draft.checkpointId) }

        do {
            let outcome = try await APIClient.shared.submitFeedback(token: token, draft: draft)
            // 409/403 เป็นสถานะปลายทาง ไม่ต้อง retry — เอาออกจากคิวเหมือนสำเร็จ
            outbox.remove(clientId: draft.clientId)
            return outcome
        } catch {
            outbox.add(draft)
            return .saved
        }
    }

    /// ส่งของค้างทั้งหมด — เรียกตอนแอปกลับมา active และหลังส่งสำเร็จรอบถัดไป
    func flush(token: String) async {
        guard !token.isEmpty else { return }
        for draft in outbox.all() {
            do {
                _ = try await APIClient.shared.submitFeedback(token: token, draft: draft)
                outbox.remove(clientId: draft.clientId)
            } catch {
                // เน็ตยังไม่กลับมา — หยุดทั้งรอบ ไม่ต้องไล่ยิงตัวที่เหลือให้เปลืองเปล่า
                return
            }
        }
    }

    /// ล้างคิวตอน logout — ความเห็นของบัญชีก่อนต้องไม่ถูกส่งด้วย token ของบัญชีใหม่
    func clearForLogout() {
        outbox.clear()
    }
}
