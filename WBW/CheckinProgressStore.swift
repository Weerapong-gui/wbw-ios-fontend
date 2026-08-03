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

    /// ตัวแจกลำดับให้ load แต่ละรอบ — คำตอบที่กลับมาช้ากว่ารอบที่ใหม่กว่า **ที่ลงไปแล้ว** ถูกทิ้ง
    ///
    /// load() ถูกเรียกจากห้าที่โดยไม่มีใครคุมลำดับ: poll 60 วิ, scenePhase == .active,
    /// .checkinFeedbackArrived ทุกครั้งที่มี push, FeedbackView.send และตอน mount · สอง GET ที่คาบกัน
    /// บนเน็ตแย่ๆ กลับมาสลับลำดับได้ตามปกติ (คนละ connection กัน) แล้วรอบเก่าจะเขียนทับรอบใหม่:
    /// ต้นไม้หน้า Home หดกลับไปหนึ่งขั้นให้เห็นกับตา, ฐาน B หลุดจาก lastPendingIds ทำให้ toast ที่
    /// กำลังโชว์อยู่หายกลางคัน แล้ว poll รอบถัดไปเด้ง toast ฐาน B ซ้ำอีกครั้งราวกับเพิ่งโดนสแกน
    /// (เกิดได้ทุกครั้งที่สแกนสองฐานติดกันเร็วๆ = เคสวันงานจริง)
    ///
    /// แก้ด้วย "รอบใหม่สุดชนะ" แทนที่จะใส่ guard แบบ flushing — guard จะ **ทิ้งคำขอ** ที่มาระหว่าง
    /// รอบก่อนยังไม่จบ ซึ่งฆ่าเส้น push ทิ้ง (.checkinFeedbackArrived มาตอน poll ค้างอยู่ = ฐานที่เพิ่ง
    /// สแกนจะไม่โผล่จนกว่าจะถึง poll รอบถัดไป นานสุด 60 วิ) วิธีนี้ทุกคำขอยังยิงจริง แค่ผลลัพธ์ที่
    /// เก่ากว่าไม่ถูกนำมาใช้ · state จึงไม่มีทางถอยหลัง
    private var loadGeneration = 0

    /// ลำดับของรอบล่าสุดที่ **มีคำตอบมาถึงจริงและถูกใช้ไปแล้ว** — ตัวตัดสินว่ารอบไหน "เก่ากว่า"
    ///
    /// ต้องแยกจาก loadGeneration เพราะรอบที่ "เริ่มทีหลัง" ไม่เท่ากับ "ได้ของใหม่กว่า": ถ้ารอบใหม่ยิงแล้ว
    /// พัง (เน็ตหลุดกลางทาง = เรื่องปกติบนภูเขา) มันไม่ได้พาอะไรมาเลย การให้มันไปดันตัวนับก็เท่ากับ
    /// ทิ้งของดีของรอบก่อนโดยไม่มีอะไรมาแทน
    ///
    /// เคสจริงที่ต้องกัน: FeedbackView.send ยิง refresh (รอบ N) → poll 60 วิ เริ่มถัดมาเสี้ยววินาที (N+1)
    /// แล้ว GET พัง → payload ของรอบ N ที่มี answered = true ถูกทิ้งทั้งที่ไม่มีอะไรใหม่กว่าลงไปเลย →
    /// ผู้ใช้เห็นฟอร์มยังแก้ไขได้ต่ออีกนานสุด 60 วิ ทั้งที่เพิ่งส่งสำเร็จไปเมื่อกี้
    private var acceptedGeneration = 0

    /// เรียกเน็ตจริง แยกเป็น property ฉีดแทนได้ตอนเทส — ทรงเดียวกับ FeedbackStore.submitCall
    /// (repo นี้ไม่มี protocol ใช้เลยสักที่ closure ตรงๆ จึงเป็นทางที่ฉีดของปลอมเข้าได้โดยไม่ต้อง
    /// เพิ่ม abstraction ใหม่ทั้งก้อน) ค่าเริ่มต้นคือของจริงเสมอ โค้ด production เรียก
    /// CheckinProgressStore() เฉยๆ ไม่ต้องรู้เรื่องนี้เลย
    ///
    /// มีไว้เพราะ newlyPending — หัวใจของ poll 60 วิ ซึ่งเป็นทางเข้าเดียวที่เหลือใน build ที่ไม่มี
    /// GoogleService-Info.plist (push ปิดทั้งอัน) — เขียนได้ทางเดียวคือผ่าน load() ที่ต้องมีเน็ต
    /// ตัว diff จึงไม่เคยถูกเทสเลยสักบรรทัด
    private let progressCall: (String) async throws -> CheckinProgress

    init(progressCall: @escaping (String) async throws -> CheckinProgress
         = APIClient.shared.progress) {
        self.progressCall = progressCall
    }

    // nonisolated: เป็น pure function ล้วนๆ ไม่แตะ state ของ actor เลย ทำให้เรียกจาก
    // context ที่ไม่ใช่ MainActor ได้ตรงๆ (เช่น XCTest ที่ไม่ได้ mark @MainActor)
    nonisolated static func cacheKey(for backend: Backend) -> String {
        "wbw.progress.\(backend.cacheNamespace)"
    }

    /// โหลดจาก cache ก่อน (ทันที) แล้วค่อยยิงเน็ตทับ
    func load(token: String, backend: Backend = Config.backend) async {
        if progress == nil { restoreFromCache(backend: backend) }
        guard !token.isEmpty else { return }

        loadGeneration += 1
        let generation = loadGeneration
        // พังก็แค่ไม่ทำอะไร — ห้ามแตะ acceptedGeneration เด็ดขาด รอบที่ไม่มีคำตอบไม่ใช่ "ของใหม่กว่า"
        guard let fresh = try? await progressCall(token) else { return }
        // มีรอบที่ใหม่กว่า **ลงไปจริง** ก่อนแล้ว — ของรอบนี้เก่ากว่า ทิ้งทั้งก้อน (ทั้ง progress, cache
        // และตัวเทียบของ newlyPending) ห้ามเขียนบางส่วน ไม่งั้น state จะไม่ตรงกันเองยิ่งกว่าเดิม
        guard generation > acceptedGeneration else { return }
        acceptedGeneration = generation

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
