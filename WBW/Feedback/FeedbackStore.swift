import Foundation

/// ส่งความเห็น + คิวของที่ยังส่งไม่สำเร็จ
///
/// UI ตอบว่า "ส่งแล้ว" ทันทีแบบ optimistic ได้ เพราะ clientId การันตีว่าส่งซ้ำ
/// ไม่เกิดแถวซ้ำ — ที่เหลือเป็นเรื่องของ outbox กับ flush รอบหน้า
@MainActor
final class FeedbackStore: ObservableObject {
    /// checkpointId ที่กำลังส่งอยู่ — ปุ่มส่งของฐานนั้นกดซ้ำไม่ได้
    @Published private(set) var submitting: Set<Int> = []

    /// ฐานที่มีคำตอบค้างอยู่ในคิวตอนนี้ — **gate ให้คะแนนอ่านตัวนี้แล้วนับว่า "ตอบแล้ว"**
    /// (ดูเหตุผลเต็มที่ `FeedbackGateState.decide`: ไม่นับ = จอที่ปิดไม่ได้เลยตอนไม่มีสัญญาณ)
    ///
    /// เริ่มจาก `outbox.all()` ตั้งแต่ init ไม่ใช่เซ็ตว่าง — เคสจริงคือตอบตอนเน็ตหลุด ปิดแอป
    /// แล้วเปิดใหม่ตอนยังไม่มีสัญญาณ ถ้าเริ่มจากศูนย์ gate จะยกฐานที่ตอบไปแล้วขึ้นมาใหม่ทันที
    /// ตั้งแต่วินาทีแรก
    @Published private(set) var queued: Set<Int> = []

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
        refreshQueued()
    }

    /// อ่านคิวใหม่ทั้งชุดจาก outbox แทนที่จะ insert/remove เอาเองตามแต่ละสาขา — outbox เป็นเจ้าของ
    /// ความจริง และมันมีกติกาของตัวเองที่เดาจากข้างนอกไม่ได้ (`add` แทนที่ของฐานเดิม,
    /// `remove(checkpointId:)` ล้างทั้งฐานไม่ใช่ draft เดียว) เดาเองเมื่อไหร่ก็มีวันที่ธงค้างไม่ตรง
    /// กับคิวจริง แล้ว gate จะปิดค้างทั้งที่ยังไม่มีคำตอบอยู่ที่ไหนเลย
    private func refreshQueued() {
        queued = Set(outbox.all().map(\.checkpointId))
    }

    /// ส่งหนึ่งอัน · แยกตาม "ส่งซ้ำด้วย draft เดิมมีโอกาสสำเร็จไหม" ไม่ใช่ตาม "มี error ไหม":
    /// - **retry ได้** — AppError.offline (เน็ตหลุด ไปไม่ถึงเซิร์ฟเวอร์) และ AppError.retryable
    ///   (ถึงแล้วแต่ได้ status ที่ไม่ได้อยู่ในรายชื่อ terminal กลับมา — 429/5xx, 408/425 ของ
    ///   Cloudflare, หรือแม้แต่ 403/409 ที่ body ไม่ใช่ของ origin เรา ดู APIClient.submitFeedback)
    ///   → เข้า outbox เงียบๆ แล้วคืน .saved · ผู้ใช้ไม่ต้องรู้ว่ายังไม่
    ///   ถึงเซิร์ฟเวอร์ ระบบรับผิดชอบ retry เอง ด้วย clientId เดิมการันตีไม่ซ้ำแถว
    /// - **retry ไม่ได้** — 400 rating ผิด, 401 token หมดอายุ ฯลฯ → ส่งซ้ำยังไงก็ไม่ผ่าน ห้ามเข้า
    ///   outbox คืน .failed ให้ฟอร์มบอกความจริงกับผู้ใช้ แทนที่จะโกหกว่า "ส่งแล้ว"
    ///
    /// **ทำไม 5xx ต้องอยู่ฝั่ง retry**: เดิม 5xx ถูกเหมารวมเป็น "retry ไม่ได้" ทำให้กดส่งครั้งแรกตอน
    /// origin ล้น (503) ได้ .failed โดยไม่เก็บอะไรไว้เลย · ตอนงานจริงมี 2,000 คนเข้าฐานพร้อมกันและมี
    /// Cloudflare คั่นหน้า api.studentunion.social ซึ่งตอบ 502/503/524 แทน origin ได้เอง — ทางนี้
    /// ไม่ใช่ทางทฤษฎี (ดู AppError.retryable)
    @discardableResult
    func submit(_ draft: FeedbackDraft, token: String) async -> APIClient.FeedbackSubmitOutcome {
        submitting.insert(draft.checkpointId)
        defer { submitting.remove(draft.checkpointId) }

        do {
            let outcome = try await submitCall(token, draft)
            // 409/403 เป็นสถานะปลายทาง ไม่ต้อง retry — เอาออกจากคิวเหมือนสำเร็จ
            // (มาถึงตรงนี้ได้เฉพาะเมื่อ body ยืนยันแล้วว่ามาจาก origin เราจริง ไม่ใช่ WAF ที่ขวางหน้าอยู่
            // ดู APIClient.submitFeedback — ตรงนี้คือจุดที่ 403 ปลอมเคยล้างคิวทั้งฐานทิ้ง)
            // ล้างทั้ง "ฐาน" ไม่ใช่แค่ clientId นี้: draft เก่าของฐานเดียวกันที่ค้างคิวไว้ตอนเน็ตหลุดรอบก่อน
            // ถือคนละ clientId เก็บไม่หมดไม่ได้ทำให้คำตอบเพี้ยน (409 มีแถวอยู่แล้ว ทับไม่ได้เพราะ uniq
            // constraint, 403 ยังไม่เช็คอิน draft ไหนของฐานนี้ก็ส่งไม่ผ่านเหมือนกัน) แค่เสีย POST เปล่าตอน
            // flush รอบหน้าไปยิงของที่ตายอยู่แล้ว
            outbox.remove(checkpointId: draft.checkpointId)
            refreshQueued()
            return outcome
        } catch AppError.offline {
            outbox.add(draft)   // add แทนที่ของเดิมของฐานเดียวกันให้อยู่แล้ว
            refreshQueued()     // ← จุดที่ปลด gate ให้ผู้ใช้เดินต่อได้ทั้งที่เน็ตยังไม่กลับมา
            return .saved
        } catch AppError.retryable {
            outbox.add(draft)   // เหมือน offline ทุกอย่าง — เซิร์ฟเวอร์แค่ยังไม่พร้อม ไม่ได้ปฏิเสธ payload
            refreshQueued()
            return .saved
        } catch {
            // retry ไม่ได้แล้ว (400/401 ฯลฯ) — คืน .failed ตรงๆ ห้ามแตะคิว: draft ของ attempt นี้เอง
            // ไม่เคยถูก add (add เกิดเฉพาะสองสาขาด้านบน) ส่วนของที่อาจค้างอยู่ก่อนหน้าเป็น
            // คำตอบที่เคยบอกผู้ใช้ว่า "บันทึกแล้ว" จริง ฐานนี้ยังไม่มีคำตอบไหนไปถึงเซิร์ฟเวอร์สำเร็จเลย —
            // ลบตรงนี้มีแต่เสียของที่เคยบันทึกไว้ฟรีๆ ทั้งที่ attempt นี้เองก็ไม่รอด
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
    /// สี่ทางออกต่อ draft หนึ่งชิ้น แยกตามว่า "ส่งซ้ำมีโอกาสสำเร็จไหม" เหมือน submit:
    /// - **สำเร็จ / 409 / 403** = สถานะปลายทาง → ทิ้งจากคิว ไปต่อ
    /// - **AppError.offline** = เน็ตยังไม่กลับมา → หยุดทั้งรอบทันที เก็บทุกอย่างไว้ (ไล่ยิงตัวที่เหลือ
    ///   เปลืองเปล่า เพราะพังเหมือนกันหมดแน่ๆ)
    /// - **AppError.retryable** (429/5xx, 408/425 และทุก status ที่ไม่ได้อยู่ในรายชื่อ terminal
    ///   รวมถึง 403/409 ที่ไม่ได้ออกจาก origin เรา) = เก็บ draft ไว้ แล้ว**ไปต่อตัวถัดไป**
    /// - **error อื่น (400/401)** = ส่งซ้ำไม่มีวันผ่าน → ทิ้ง ไปต่อ
    ///
    /// **ทำไม 5xx ต้อง "เก็บแล้วไปต่อ" ไม่ใช่ "ทิ้ง" และไม่ใช่ "หยุด"**
    ///
    /// เดิมโค้ดนี้ทิ้ง draft ทุกตัวที่ไม่ใช่ offline ซึ่งลบคำตอบของผู้ใช้ทิ้งถาวรโดยไม่มีสัญญาณอะไรเลย:
    /// ตอบฐาน 3 ตอนไม่มีสัญญาณ → เข้าคิว → ฟอร์มบอก "ส่งความเห็นแล้ว ขอบคุณ" → เดินไปฐาน 4 ปลดล็อก
    /// เครื่อง → flush → origin ล้นตอบ 503 → คำตอบหายไปเฉยๆ ไม่มี error ไม่มี toast ไม่มี badge
    /// (spec สั่งตรงข้ามไว้ชัดเจน: "success drops the item, 409/403 drop the item, other errors keep it")
    ///
    /// แต่การกลับไป "เก็บทุก error" ก็ผิดอีกทาง — นั่นคืออันตรายจริงที่ Task 6 แก้ไว้: draft ที่พังถาวร
    /// (rating ผิดจากบั๊กเก่า) จะค้างหัวคิวและบล็อกของที่ดีข้างหลังไปตลอดกาล
    ///
    /// ทางออกคือแยกให้ถูกว่า error ไหน retry ได้ **แล้วไปต่อ** แทนที่จะหยุด: การ "ไปต่อ" คือสิ่งที่
    /// รักษาการกันหัวคิวบล็อกของ Task 6 ไว้ ไม่ใช่การ "ทิ้ง" — ของที่ retry ได้จึงไม่ต้องถูกทิ้งเพื่อ
    /// ปกป้องคิวอีกต่อไป
    ///
    /// **จงใจไม่ใส่ตัวนับ attempt**: ประโยชน์เดียวของมันคือกำจัด draft ที่ 5xx ถาวร ซึ่งราคาที่ต้องจ่าย
    /// คือ POST เปล่ารอบละหนึ่งครั้งต่อชิ้น (คิวยาวสุด ~8 ชิ้นตามจำนวนฐาน และ flush วิ่งเฉพาะตอน
    /// mount/.active/ส่งสำเร็จ) — ถูกกว่าการเสี่ยงทิ้งคำตอบจริงของผู้เข้าร่วมเมื่อเพดานถูกใช้หมดระหว่าง
    /// เซิร์ฟเวอร์ล่มยาว ซึ่งเป็นบั๊กเดิมกลับมาในรูปแบบที่เกิดยากขึ้นแต่เงียบเท่าเดิม
    ///
    /// ข้ามฐานที่ฟอร์มเปิดค้างอยู่ (ดู editingCheckpoint) และรอบเดียวเท่านั้นที่วิ่งได้พร้อมกัน
    /// (ดู flushing) — ทั้งสองอย่างกันคิวเก่าเขียนทับเจตนาใหม่ของผู้ใช้
    ///
    /// **คืน true เมื่อมีของหลุดออกจากคิวจริงในรอบนี้ — ผู้เรียกต้องโหลด `progress` ใหม่ทันที**
    ///
    /// คิวคือสิ่งเดียวที่กัน gate ไว้ระหว่างที่ server ยังไม่รู้คำตอบ (ดู `queued`) การล้างคิว
    /// สำเร็จจึงเปิดช่องว่างขึ้นมาช่วงหนึ่ง: ตอบฐาน 3 ตอนไม่มีสัญญาณ → กลับมามีสัญญาณ →
    /// `scenePhase .active` โหลด progress (ยัง answered = false เพราะ server เพิ่งจะได้รู้เดี๋ยวนี้)
    /// แล้วค่อย flush → คิวว่างลงแต่ progress ยังเป็นของเก่า → gate ยกฟอร์มฐาน 3 ขึ้นมาให้ตอบซ้ำ
    /// ทั้งที่ผู้ใช้ตอบไปแล้ว · คืนค่าให้ผู้เรียกไปปิดช่องนั้นเอง แทนที่จะโหลด progress ทิ้ง ๆ ทุกรอบ
    /// ที่แอปกลับมา foreground (งานจริงมีคนพร้อมกันหลักพัน request ที่ไม่มีใครต้องการมีราคาจริง)
    @discardableResult
    func flush(token: String) async -> Bool {
        guard !token.isEmpty, !flushing else { return false }
        flushing = true
        defer { flushing = false }

        // อ่านจาก outbox ไม่ใช่จาก `queued` — เทียบ "คิวจริงก่อน/หลัง" ต้องอ่านจากเจ้าของความจริง
        // ตัวเดียวกันทั้งสองครั้ง
        let before = Set(outbox.all().map(\.checkpointId))
        for draft in outbox.all() where draft.checkpointId != editingCheckpoint {
            do {
                _ = try await submitCall(token, draft)
                outbox.remove(clientId: draft.clientId)
            } catch AppError.offline {
                break   // เน็ตยังไม่กลับมา — ที่เหลือพังเหมือนกันแน่ ๆ (break ไม่ใช่ return เพื่อให้
                        // ตกไปอัปเดต queued ข้างล่างด้วย: ตัวที่ส่งไปแล้วก่อนหน้าต้องหลุดจากธง)
            } catch AppError.retryable {
                continue   // เก็บไว้รอบหน้า · ไปต่อ เพื่อไม่ให้ตัวนี้บล็อกของที่เหลือ
            } catch {
                outbox.remove(clientId: draft.clientId)
            }
        }
        refreshQueued()
        return queued != before
    }
}
