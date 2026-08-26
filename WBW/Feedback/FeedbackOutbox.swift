import Foundation

/// ความเห็นหนึ่งอันที่รอส่ง
///
/// clientId สร้างครั้งเดียวตอนผู้ใช้กดส่ง แล้วใช้ค่าเดิมทุกครั้งที่ retry —
/// backend unique บนคอลัมน์นี้ ส่งซ้ำจึงได้แถวเดิมกลับมา ไม่เกิดแถวซ้ำ
struct FeedbackDraft: Codable, Equatable {
    let clientId: String
    let checkpointId: Int

    /// ภาพรวม — ข้อเดียวที่เซิร์ฟเวอร์บังคับ และข้อเดียวที่จอบังคับให้ตอบก่อนส่ง
    let rating: Int

    /// ข้อไม่บังคับที่ยกมาจากฝั่ง Android — **optional ทุกตัว** ทั้งฝั่งเซิร์ฟเวอร์และที่นี่
    ///
    /// เป็น optional ไม่ใช่แค่เพื่อให้ผู้ใช้ข้ามได้ แต่เพื่อให้ **draft ที่ค้างคิวอยู่ตั้งแต่
    /// เวอร์ชันก่อน decode ผ่าน** ด้วย — คิวเป็น JSON ก้อนเดียว decode ไม่ออกหนึ่งใบคือทั้งคิวหาย
    /// และคนที่ตอบไว้ตอนไม่มีสัญญาณบนดอยเสียคำตอบทั้งหมดโดยไม่มีอะไรบอก
    var ratingScenery: Int?
    /// "พื้นที่" — ที่ว่าง ร่มเงา ที่นั่ง — เซิร์ฟเวอร์ยังไม่มีคอลัมน์นี้ แต่ส่งไปก่อนแบบเดียวกับ
    /// ฝั่ง Android: decoder ฝั่งนั้นไม่ปฏิเสธฟิลด์ที่ไม่รู้จัก วัน migration ลงทุกเครื่อง
    /// ในมือผู้เข้าร่วมเริ่มเก็บทันที (แอปงานอีเวนต์ขอให้ user อัพเดทกลางงานไม่ได้)
    var ratingArea: Int? = nil
    /// ฟอร์มเลิกถามข้อนี้แล้ว (ย้ายไปถามระดับงานตอนจบตาม Android) แต่**ห้ามลบฟิลด์** —
    /// draft จากเวอร์ชันที่ยังถาม อาจค้างคิวพร้อมคำตอบข้อนี้อยู่ ลบ = คำตอบหายเงียบ
    var ratingActivity: Int?
    var ratingStaff: Int?

    let comment: String?
    let deviceTime: String

    /// **สเกลเดียวกับฝั่ง Android** — ที่นั่นถาม 1–5 ทุกข้อ · ของเดิมฝั่ง iOS เป็นสามหน้า (1–3)
    /// ปล่อยไว้คนละสเกลแปลว่าผู้จัดเอาคะแนนสองแอปมารวมกันไม่ได้ ทั้งที่เป็นงานเดียวกัน
    static let scale: ClosedRange<Int> = 1...5

    /// ส่งได้เมื่อมีคะแนนภาพรวม — อีกสามข้อไม่บังคับ
    ///
    /// บังคับครบสี่ข้อคือการเปลี่ยนแบบสอบถามให้ยาวขึ้นสามเท่าสำหรับคนที่กำลังยืนกลางแดด
    /// แล้วผลที่ได้คือคนกดข้ามทั้งฟอร์ม ไม่ใช่ตอบครบ
    static func canSubmit(overall: Int?) -> Bool { overall != nil }
}

/// คิวความเห็นที่ยังส่งไม่สำเร็จ เก็บลง UserDefaults
///
/// ทำไมไม่ใช้ SwiftData เหมือนแชท: ของค้างมีอย่างมากเท่าจำนวนฐาน (~8 ชิ้นต่อคน)
/// ไม่ต้องมี query ไม่ต้องมี index — ไฟล์ JSON ก้อนเดียวพอและพังยากกว่า
///
/// **key ผูกกับ backend** เหมือน cache ทุกตัวในแอป: checkpoint_id เดินคนละชุดต่อ
/// backend ถ้าใช้ key เดียวกัน ความเห็นจะถูกส่งไปฐานผิดตัวโดยไม่มี error
struct FeedbackOutbox {
    let backend: Backend

    init(backend: Backend = Config.backend) { self.backend = backend }

    static func key(for backend: Backend) -> String {
        "wbw.feedback.outbox.\(backend.cacheNamespace)\(CacheScope.suffix)"
    }

    func all() -> [FeedbackDraft] {
        guard let data = UserDefaults.standard.data(forKey: Self.key(for: backend)),
              let list = try? JSONDecoder().decode([FeedbackDraft].self, from: data)
        else { return [] }
        return list
    }

    /// เพิ่มเข้าคิว · ฐานเดิมที่ค้างอยู่ถูกแทนที่ (ผู้ใช้เปลี่ยนใจก่อนเน็ตกลับมา)
    func add(_ draft: FeedbackDraft) {
        var list = all().filter { $0.checkpointId != draft.checkpointId && $0.clientId != draft.clientId }
        list.append(draft)
        save(list)
    }

    func remove(clientId: String) {
        save(all().filter { $0.clientId != clientId })
    }

    /// ทิ้งของค้างของฐานนี้ทั้งหมด ไม่ว่ามาจาก clientId ไหน — ใช้ตอนผู้ใช้เพิ่งตอบฐานนี้สดๆ
    /// ของเก่าไม่มีทางกลายเป็นคำตอบสุดท้ายอยู่แล้วไม่ว่าจะเก็บไว้หรือไม่ — ฐานนี้ตอบไปแล้ว (409 กันด้วย
    /// uniq_feedback_participant_checkpoint) หรือยังไม่เช็คอิน (403) draft ไหนของฐานนี้ก็ส่งไม่ผ่านเหมือนกัน
    /// ปล่อยของเก่าไว้ = เสีย POST เปล่าตอน flush รอบหน้า (คนละ clientId กัน remove(clientId:) จึงเก็บไม่หมด)
    func remove(checkpointId: Int) {
        save(all().filter { $0.checkpointId != checkpointId })
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: Self.key(for: backend))
    }

    private func save(_ list: [FeedbackDraft]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(for: backend))
    }
}
