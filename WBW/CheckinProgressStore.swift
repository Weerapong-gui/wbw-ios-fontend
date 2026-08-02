import Foundation

/// ความคืบหน้าเช็คอินที่ใช้ร่วมกันทั้งแอป — ต้นไม้ที่ Home อ่านตัวนี้
///
/// cache ลง UserDefaults เพื่อให้เปิดแอปมาต้นไม้ขนาดถูกทันทีโดยไม่ต้องรอเน็ต
/// **key ผูกกับ backend** เพราะแต่ละ backend เดิน checkpoint_id คนละชุด ถ้าใช้ key
/// เดียวกัน สลับ backend แล้วจะได้ต้นไม้ผิดขนาดโดยไม่มี error และไม่มี log อะไรเลย
@MainActor
final class CheckinProgressStore: ObservableObject {
    @Published private(set) var progress: CheckinProgress?

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
    }

    /// หาฐานหนึ่งจาก progress ที่มีอยู่ — หน้า feedback ใช้อ่านชื่อฐาน/กิจกรรม
    /// และคำตอบเดิม (ถ้าเคยตอบแล้ว) โดยไม่ต้องยิงเน็ตซ้ำ
    func item(checkpointId: Int) -> CheckinProgressItem? {
        progress?.checkedIn.first { $0.checkpointId == checkpointId }
    }
}
