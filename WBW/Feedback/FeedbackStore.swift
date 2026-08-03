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

    /// ฐานที่ฟอร์มกำลังเปิดค้างอยู่ตอนนี้ (nil = ไม่มีฟอร์มเปิด) — flush ข้ามคิวของฐานนี้ไป
    ///
    /// เคสจริงที่ต้องกัน: มี draft เก่าของฐาน X ค้างคิวอยู่ (เน็ตหลุดรอบก่อน) → เปิดแอปใหม่แล้ว push
    /// พาเข้าฟอร์มของ X ทันที (PendingPush.consume() ทำงานก่อน progress.load() เสมอ ฟอร์มจึงว่างเปล่า
    /// แก้ไขได้) → ผู้ใช้พิมพ์คำตอบใหม่ → flush ตอน mount ส่ง draft "เก่า" ขึ้นไปเงียบๆ → poll รอบถัดไป
    /// เห็น answered = true → ฟอร์มกลายเป็นอ่านอย่างเดียวพร้อมป้าย "ส่งความเห็นแล้ว ขอบคุณ" ที่แสดง
    /// คำตอบเก่า คำตอบที่เพิ่งพิมพ์หายไปทั้งที่บอกว่าบันทึกแล้ว
    ///
    /// ฟอร์มเป็นเจ้าของฐานที่มันเปิดอยู่ ตราบใดที่ยังเปิด — ของค้างของฐานนั้นรอได้ ฐานอื่นไม่ถูกกระทบ
    private var editingCheckpoint: Int?

    /// flush รอบหนึ่งกำลังวิ่งอยู่ไหม — flush อ่าน outbox.all() เป็น snapshot แล้วค่อยๆ remove ทีละตัว
    /// ซึ่งเป็น read-modify-write บน UserDefaults สองรอบที่คาบกัน (mount + scenePhase .active ตอน cold
    /// launch, หรือ .active + หลังส่งสำเร็จ) จึงเขียนทับกันจนของที่ส่งไปแล้วฟื้นกลับเข้าคิวได้
    private var flushing = false

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
            // ล้างทั้ง "ฐาน" ไม่ใช่แค่ clientId นี้: draft เก่าของฐานเดียวกันที่ค้างคิวไว้ตอนเน็ตหลุด
            // รอบก่อนถือคนละ clientId ถ้าเก็บไม่หมด flush รอบหน้าจะส่งคำตอบเก่าตามขึ้นไปทีหลัง
            outbox.remove(checkpointId: draft.checkpointId)
            return outcome
        } catch AppError.offline {
            outbox.add(draft)   // add แทนที่ของเดิมของฐานเดียวกันให้อยู่แล้ว
            return .saved
        } catch {
            // retry ไม่ได้แล้ว — เอาออกจากคิวด้วย เผื่อเคยค้างอยู่จาก attempt ก่อนหน้าที่เจอ offline
            // (ไม่งั้นจะมีของพังค้างคิวถาวรจากการ submit ตรงๆ รอบนี้ ทั้งที่ไม่เคยผ่าน flush เลย)
            // ล้างทั้งฐานด้วยเหตุผลเดียวกับทางสำเร็จ — ผู้ใช้เพิ่งแสดงเจตนาใหม่ต่อฐานนี้แล้ว ของเก่า
            // ที่ค้างอยู่ไม่ใช่คำตอบที่เขาต้องการอีกต่อไป ต่อให้รอบนี้ส่งไม่ผ่านก็ตาม
            outbox.remove(checkpointId: draft.checkpointId)
            return .failed
        }
    }

    /// ฟอร์มของฐานนี้เปิดแล้ว — กัน flush ไม่ให้ส่งของค้างของฐานนี้ลับหลังผู้ใช้ (ดู editingCheckpoint)
    func beginEditing(checkpointId: Int) {
        editingCheckpoint = checkpointId
    }

    /// ฟอร์มปิดแล้ว — เช็คว่าเป็นฐานเดิมก่อนล้าง เผื่อ onDisappear ของฟอร์มเก่ามาถึงหลัง onAppear ของ
    /// ฟอร์มใหม่ (สลับฐานตอนชีตยังเปิดอยู่) ล้างมั่วจะเปิดช่องเดิมให้ฐานที่กำลังเปิดอยู่
    func endEditing(checkpointId: Int) {
        guard editingCheckpoint == checkpointId else { return }
        editingCheckpoint = nil
    }

    /// ส่งของค้างทั้งหมด — เรียกตอน mount, ตอนแอปกลับมา active และหลังส่งสำเร็จทุกครั้ง
    ///
    /// แยกสองเคสเหมือน submit: AppError.offline หยุดทั้งรอบ (เน็ตยังไม่กลับมา ไล่ยิงตัวที่เหลือ
    /// เปลืองเปล่า) ส่วน error อื่นทิ้ง draft ตัวนั้นแล้วไปต่อ — กันของพังหนึ่งชิ้นบล็อกทั้งคิวถาวร
    /// (คิวมีได้ถึง ~8 ชิ้นต่อคน ตามจำนวนฐาน ถ้าหยุดที่ตัวแรกที่พัง ตัวที่ดีข้างหลังจะไม่มีวันถูกส่ง)
    ///
    /// ข้ามฐานที่ฟอร์มเปิดค้างอยู่ (ดู editingCheckpoint) และรอบเดียวเท่านั้นที่วิ่งได้พร้อมกัน
    /// (ดู flushing) — ทั้งสองอย่างกันคิวเก่าเขียนทับเจตนาใหม่ของผู้ใช้
    func flush(token: String) async {
        guard !token.isEmpty, !flushing else { return }
        flushing = true
        defer { flushing = false }

        for draft in outbox.all() where draft.checkpointId != editingCheckpoint {
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
}
