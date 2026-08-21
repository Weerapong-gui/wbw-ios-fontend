import Foundation

/// เคสที่ยังส่งไม่สำเร็จ เก็บลง UserDefaults
///
/// ทำไมไม่ใช้ SwiftData เหมือนแชท: คนหนึ่งมีเคสเปิดได้ทีละหนึ่ง (server บังคับด้วย
/// partial unique index) ไม่มีอะไรให้ query ไฟล์ JSON ก้อนเดียวพอและพังยากกว่า
///
/// **key ผูกกับ backend** เหมือน cache ทุกตัวในแอป — sos id เดินคนละชุดต่อ backend
struct SOSOutbox {
    let backend: Backend

    init(backend: Backend = Config.backend) { self.backend = backend }

    static func key(for backend: Backend) -> String {
        "wbw.sos.outbox.\(backend.cacheNamespace)"
    }

    /// nil มีสองความหมายที่ต้องแยกกันจริง — "ไม่มีอะไรเก็บไว้เลย" (ไม่ต้องทำอะไรต่อ) กับ "มีของเก็บไว้
    /// แต่อ่านไม่ออก" (ต้องล้างทิ้ง ไม่ปล่อยขยะค้างจนกว่า save() ครั้งหน้าจะทับ) — แยกด้วยการเช็คว่ามี
    /// data ที่คีย์นี้ก่อนเลยไหม แทนที่จะดูแค่ผลของการ decode (พบจากรีวิว Task 14 รอบสี่)
    ///
    /// decode ไม่ผ่านหลัง SOSDraft.init(from:) ยอมรับ ownerId ที่หายไปแล้ว (decodeIfPresent) เหลือแค่
    /// ไบต์ที่เสียหายจริงๆ เท่านั้น (ไม่ใช่ JSON เลย, หรือคีย์อื่นที่ไม่ใช่ ownerId หายไป) — กรณีนั้นล้าง
    /// ทิ้งตรงนี้เลย ไม่ปล่อยให้ผู้เรียก (SOSStore.init) ต้องแยกแยะเอง เพราะ nil ที่คืนไปดูเหมือนกันทุก
    /// ประการกับ "ไม่มีเคสเลย" อยู่ดี
    func current() -> SOSDraft? {
        guard let data = UserDefaults.standard.data(forKey: Self.key(for: backend)) else { return nil }
        if let draft = try? JSONDecoder().decode(SOSDraft.self, from: data) { return draft }
        clear()
        return nil
    }

    /// เขียนทับเสมอ — เคสมีได้ทีละหนึ่ง ไม่มีคิวให้ต่อท้าย
    func save(_ draft: SOSDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(for: backend))
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: Self.key(for: backend))
    }
}
