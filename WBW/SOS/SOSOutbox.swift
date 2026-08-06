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

    func current() -> SOSDraft? {
        guard let data = UserDefaults.standard.data(forKey: Self.key(for: backend)) else { return nil }
        return try? JSONDecoder().decode(SOSDraft.self, from: data)
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
