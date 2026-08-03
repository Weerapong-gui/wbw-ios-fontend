import Foundation

/// ความคืบหน้าเช็คอินที่ใช้ร่วมกันทั้งแอป — ต้นไม้ที่ Home อ่านตัวนี้
///
/// cache ลง UserDefaults เพื่อให้เปิดแอปมาต้นไม้ขนาดถูกทันทีโดยไม่ต้องรอเน็ต
/// **key ผูกกับ backend** เพราะแต่ละ backend เดิน checkpoint_id คนละชุด ถ้าใช้ key
/// เดียวกัน สลับ backend แล้วจะได้ต้นไม้ผิดขนาดโดยไม่มี error และไม่มี log อะไรเลย
@MainActor
final class CheckinProgressStore: ObservableObject {
    @Published private(set) var progress: CheckinProgress?

    /// ฐานที่เพิ่งกลายเป็น "รอประเมิน" ในการโหลดรอบล่าสุด — toast อ่านตัวนี้
    ///
    /// เทียบกับรอบก่อนเสมอ ไม่ใช่กับ "เคยเด้งไปหรือยัง" — poll รอบถัดไปที่ได้ข้อมูล
    /// ชุดเดิมจึงไม่เด้งซ้ำ · ตั้งเป็น [] ทุกครั้งที่ไม่มีอะไรใหม่
    @Published private(set) var newlyPending: [CheckinProgressItem] = []

    private var lastPendingIds: Set<Int> = []
    /// ได้ข้อมูลจากเน็ตมาแล้วอย่างน้อยหนึ่งรอบใน session นี้ · cache ไม่นับ — ของใน cache คือของที่
    /// เคยเห็นแล้วรอบก่อน ไม่ใช่ฐานที่เพิ่งโดนสแกน
    private var firstLoadDone = false

    // nonisolated: เป็น pure function ล้วนๆ ไม่แตะ state ของ actor เลย ทำให้เรียกจาก
    // context ที่ไม่ใช่ MainActor ได้ตรงๆ (เช่น XCTest ที่ไม่ได้ mark @MainActor)
    nonisolated static func cacheKey(for backend: Backend) -> String {
        "wbw.progress.\(backend.cacheNamespace)"
    }

    /// โหลดจาก cache ก่อน (ทันที) แล้วค่อยยิงเน็ตทับ
    func load(token: String, backend: Backend = Config.backend) async {
        if progress == nil { restoreFromCache(backend: backend) }
        guard !token.isEmpty else { return }
        guard let fresh = try? await APIClient.shared.progress(token: token) else { return }
        progress = fresh
        cache(fresh, backend: backend)

        let ids = Set(fresh.pending.map(\.checkpointId))
        // โหลดครั้งแรกของ session ไม่นับว่า "เพิ่งเกิด" — เปิดแอปมาเจอของค้างเก่า
        // ไม่ควรเด้ง toast ราวกับเพิ่งโดนสแกนเมื่อกี้
        newlyPending = firstLoadDone ? fresh.pending.filter { !lastPendingIds.contains($0.checkpointId) } : []
        lastPendingIds = ids
        firstLoadDone = true
    }

    func restoreFromCache(backend: Backend = Config.backend) {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey(for: backend)),
              let value = try? JSONDecoder().decode(CheckinProgress.self, from: data)
        else { return }
        progress = value
    }

    func cache(_ value: CheckinProgress, backend: Backend = Config.backend) {
        progress = value
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey(for: backend))
    }

    /// ล้างค่าในหน่วยความจำตอน logout — บัญชีถัดไปบนเครื่องเดียวกันต้องไม่เห็นต้นไม้ค้างของคนก่อนก่อน
    /// load เสร็จ
    ///
    /// **ไม่แตะ UserDefaults ที่นี่** — เดิมเคยลบ cache key ซ้ำกับ Session.logout() (สอง owner ของ
    /// invariant เดียวกัน) รวมเหลือเจ้าของเดียวที่ Session.logout() เพราะเป็นจุดเดียวที่ยิงทุกเส้นทาง
    /// logout จริง ทั้งบัญชี participant และ staff — staff ไม่ mount MainTabView เลย ฟังก์ชันนี้ (เรียกจาก
    /// MainTabView.onDisappear) จึงไม่ถูกเรียกด้วยซ้ำถ้า logout ตอนเป็นเจ้าหน้าที่ ถ้าเป็นเจ้าของ
    /// UserDefaults เองจะลบไม่ครบทุกเส้นทาง (ดูคอมเมนต์ที่ Session.logout())
    func clear() {
        progress = nil
        // ตัวเทียบของ newlyPending ต้องรีเซ็ตพร้อมกัน ไม่งั้นบัญชีถัดไปบนเครื่องเดียวกันจะถูกเทียบกับ
        // ฐานค้างของบัญชีก่อน: ฐานที่บังเอิญยังไม่ตอบเหมือนกันทั้งคู่จะถูกกลืนว่า "ไม่ใหม่" (toast ที่ควร
        // เด้งเลยไม่เด้ง) และ firstLoadDone ที่ค้าง true ทำให้โหลดครั้งแรกของบัญชีใหม่เด้ง toast ของ
        // ฐานค้างเก่าทั้งกองราวกับเพิ่งโดนสแกนเมื่อกี้
        newlyPending = []
        lastPendingIds = []
        firstLoadDone = false
    }

    /// หาฐานหนึ่งจาก progress ที่มีอยู่ — หน้า feedback ใช้อ่านชื่อฐาน/กิจกรรม
    /// และคำตอบเดิม (ถ้าเคยตอบแล้ว) โดยไม่ต้องยิงเน็ตซ้ำ
    func item(checkpointId: Int) -> CheckinProgressItem? {
        progress?.checkedIn.first { $0.checkpointId == checkpointId }
    }
}
