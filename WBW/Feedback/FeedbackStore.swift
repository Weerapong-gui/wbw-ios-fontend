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

    /// เรียกเน็ตจริง แยกเป็น property ฉีดแทนได้ตอนเทส — repo นี้ไม่มี protocol ใช้เลยสักที่
    /// (chat/progress ก็เรียก APIClient.shared ตรงๆ เหมือนกัน) closure ตรงๆ แบบนี้เลยเป็นทางที่ฉีด
    /// ของปลอมเข้าได้โดยไม่ต้องเพิ่ม abstraction ใหม่ทั้งก้อน ค่าเริ่มต้นคือของจริงเสมอ โค้ด
    /// production เรียก FeedbackStore() เฉยๆ ไม่ต้องรู้เรื่องนี้เลย
    private let submitCall: (String, FeedbackDraft) async throws -> APIClient.FeedbackSubmitOutcome

    init(submitCall: @escaping (String, FeedbackDraft) async throws -> APIClient.FeedbackSubmitOutcome
         = APIClient.shared.submitFeedback) {
        self.submitCall = submitCall
    }

    /// ส่งหนึ่งอัน · แยกสองเคสตามแบบ ChatSession.flushOutbox (WBW/Chat/ChatSession.swift):
    /// - AppError.offline (เน็ตหลุดจริง) = retry ได้ → เข้า outbox เงียบๆ แล้วคืน .saved (ผู้ใช้ไม่ต้อง
    ///   รู้ว่ายังไม่ถึงเซิร์ฟเวอร์ ระบบรับผิดชอบ retry เอง ด้วย clientId เดิมการันตีไม่ซ้ำแถว)
    /// - error อื่นทุกตัว (400 rating ผิด, 401 token หมดอายุ, 500 ฯลฯ) = ส่งซ้ำด้วย draft เดิมยังไงก็
    ///   ไม่มีทางสำเร็จ ห้ามเข้า outbox (ของพังค้างคิวถาวรจะบล็อกของหลังมันตอน flush) คืน .failed
    ///   ให้ฟอร์มบอกความจริงกับผู้ใช้ แทนที่จะโกหกว่า "ส่งแล้ว"
    @discardableResult
    func submit(_ draft: FeedbackDraft, token: String) async -> APIClient.FeedbackSubmitOutcome {
        submitting.insert(draft.checkpointId)
        defer { submitting.remove(draft.checkpointId) }

        do {
            let outcome = try await submitCall(token, draft)
            // 409/403 เป็นสถานะปลายทาง ไม่ต้อง retry — เอาออกจากคิวเหมือนสำเร็จ
            outbox.remove(clientId: draft.clientId)
            return outcome
        } catch AppError.offline {
            outbox.add(draft)
            return .saved
        } catch {
            // retry ไม่ได้แล้ว — เอาออกจากคิวด้วย เผื่อเคยค้างอยู่จาก attempt ก่อนหน้าที่เจอ offline
            // (ไม่งั้นจะมีของพังค้างคิวถาวรจากการ submit ตรงๆ รอบนี้ ทั้งที่ไม่เคยผ่าน flush เลย)
            outbox.remove(clientId: draft.clientId)
            return .failed
        }
    }

    /// ส่งของค้างทั้งหมด — เรียกตอนแอปกลับมา active และหลังส่งสำเร็จรอบถัดไป
    ///
    /// แยกสองเคสเหมือน submit: AppError.offline หยุดทั้งรอบ (เน็ตยังไม่กลับมา ไล่ยิงตัวที่เหลือ
    /// เปลืองเปล่า) ส่วน error อื่นทิ้ง draft ตัวนั้นแล้วไปต่อ — กันของพังหนึ่งชิ้นบล็อกทั้งคิวถาวร
    /// (คิวมีได้ถึง ~8 ชิ้นต่อคน ตามจำนวนฐาน ถ้าหยุดที่ตัวแรกที่พัง ตัวที่ดีข้างหลังจะไม่มีวันถูกส่ง)
    func flush(token: String) async {
        guard !token.isEmpty else { return }
        for draft in outbox.all() {
            do {
                _ = try await submitCall(token, draft)
                outbox.remove(clientId: draft.clientId)
            } catch AppError.offline {
                return
            } catch {
                outbox.remove(clientId: draft.clientId)
            }
        }
    }

    /// ล้างคิวตอน logout — ความเห็นของบัญชีก่อนต้องไม่ถูกส่งด้วย token ของบัญชีใหม่
    func clearForLogout() {
        outbox.clear()
    }
}
