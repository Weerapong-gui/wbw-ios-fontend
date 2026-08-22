import Foundation

/// รายการฐานทั้งงานจาก `GET /wbw/checkpoints`
///
/// **ทำไมต้องมี** ก่อนหน้านี้แอปรู้ชื่อฐานเฉพาะฐานที่ผู้ใช้เช็คอินไปแล้ว เพราะ `/me/progress`
/// คืนแค่ `checked_in` — คนที่ยังไม่ได้เดินจึงเห็นหมุดแปดอันชื่อ "ฐานที่ 1"…"ฐานที่ 8" ทั้งแผนที่
/// และแอดมินแก้ชื่อฐานบนแดชบอร์ดแล้วแอปก็ไม่รู้เรื่องจนกว่าจะมีคนไปเช็คอินฐานนั้น
///
/// โครงยกมาจาก `CheckinProgressStore` ทั้งดุ้นโดยตั้งใจ — กับดักชุดเดียวกันเป๊ะ และเป็นกับดัก
/// ที่เคยเสียเวลาจริงมาแล้วทั้งหมด ไม่ใช่การเผื่อ:
///
/// - คีย์แคชต้องต่อทั้ง `Backend.cacheNamespace` และ `CacheScope.suffix`
/// - คำตอบที่มาช้าห้ามทับของที่ใหม่กว่า (`load()` ถูกเรียกจากหลายที่โดยไม่มีใครคุมลำดับ)
/// - ยิงพลาดต้องเงียบ ไม่ใช่ล้างของเก่าทิ้ง — ออฟไลน์กลางเขาคือสภาพปกติของงานนี้
///
/// ต่างจาก `CheckinProgressStore` อยู่อย่างเดียวคือ **ไม่ poll** ข้อมูลฐานเปลี่ยนตอนแอดมินแก้
/// ซึ่งนาน ๆ ครั้ง ไม่ใช่ทุกนาทีเหมือนความคืบหน้าของผู้ใช้
@MainActor
final class CheckpointStore: ObservableObject {
    @Published private(set) var checkpoints: [Checkpoint] = []

    private let checkpointCall: (String) async throws -> [Checkpoint]

    /// นับตอน "ส่งคำขอ" — ทุกครั้งที่เริ่มโหลด
    private var loadGeneration = 0
    /// นับตอน "คำตอบมาถึงจริง" — รอบที่ล้มเหลวห้ามแตะค่านี้ ไม่งั้นคำตอบใหม่ที่พังจะไปทิ้ง
    /// คำตอบเก่าที่สำเร็จ
    private var acceptedGeneration = 0

    init(checkpointCall: @escaping (String) async throws -> [Checkpoint]
         = APIClient.shared.checkpoints) {
        self.checkpointCall = checkpointCall
    }

    /// `nonisolated` เพื่อให้เทสแบบ sync เรียกได้ (ฟังก์ชันนี้ไม่แตะ state ใด)
    nonisolated static func cacheKey(for backend: Backend) -> String {
        "wbw.checkpoints.\(backend.cacheNamespace)\(CacheScope.suffix)"
    }

    /// โหลดจากแคชก่อน (ทันที) แล้วค่อยยิงเน็ตทับ
    func load(token: String, backend: Backend = Config.backend) async {
        if checkpoints.isEmpty { restoreFromCache(backend: backend) }
        guard !token.isEmpty else { return }

        loadGeneration += 1
        let generation = loadGeneration
        // พังก็แค่ไม่ทำอะไร — ห้ามแตะ acceptedGeneration และห้ามล้างของเก่า
        guard let fresh = try? await checkpointCall(token) else { return }
        guard generation > acceptedGeneration else { return }
        acceptedGeneration = generation

        checkpoints = fresh
        cache(fresh, backend: backend)
    }

    func restoreFromCache(backend: Backend = Config.backend) {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey(for: backend)),
              let value = try? JSONDecoder().decode([Checkpoint].self, from: data)
        else { return }
        checkpoints = value
    }

    /// แคชเป็น camelCase (`JSONEncoder` เปล่า) ส่วนสายเน็ตเป็น snake_case — ความไม่สมมาตรนี้
    /// มีอยู่แล้วใน `CheckinProgressStore` และเทสของมันตรึงไว้ ทำตามให้เหมือนกันจะได้ไม่มีสองแบบ
    func cache(_ value: [Checkpoint], backend: Backend = Config.backend) {
        checkpoints = value
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey(for: backend))
    }

    /// ล้างเฉพาะของในหน่วยความจำ · การลบ `UserDefaults` เป็นหน้าที่ของ `Session.logout()`
    /// ที่เดียว (แพทเทิร์นเดียวกับ `CheckinProgressStore.clear`)
    func clear() {
        checkpoints = []
        acceptedGeneration = loadGeneration
    }

    /// ฐานลำดับที่ N — แผนที่ใช้ตัวนี้ เพราะหมุดในโมเดลรู้จักแค่ลำดับ
    ///
    /// จุดบริการมี `sequence` เป็น nil จึงไม่มีวันแมตช์ ซึ่งถูกแล้ว
    func checkpoint(sequence: Int) -> Checkpoint? {
        checkpoints.first { $0.sequence == sequence }
    }

    /// ฐานตาม id — ฟอร์มความเห็นใช้ตัวนี้ เพราะ push กับ notification ส่ง `checkpoint_id` มา
    func checkpoint(checkpointId: Int) -> Checkpoint? {
        checkpoints.first { $0.id == checkpointId }
    }
}
