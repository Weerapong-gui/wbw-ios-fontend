import Foundation

/// ความเห็นหนึ่งอันที่รอส่ง
///
/// clientId สร้างครั้งเดียวตอนผู้ใช้กดส่ง แล้วใช้ค่าเดิมทุกครั้งที่ retry —
/// backend unique บนคอลัมน์นี้ ส่งซ้ำจึงได้แถวเดิมกลับมา ไม่เกิดแถวซ้ำ
struct FeedbackDraft: Codable, Equatable {
    let clientId: String
    let checkpointId: Int
    let rating: Int
    let comment: String?
    let deviceTime: String
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
        "wbw.feedback.outbox.\(backend.cacheNamespace)"
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
