import Foundation

/// เก็บสภาพเส้นทางล่าสุดไว้ใน UserDefaults แล้วรีเฟรชทุก 10 นาที
///
/// **key ผูกกับ backend** เหมือน cache ทุกตัวในแอป — ค่านี้ไม่ได้มาจาก backend ของงานก็จริง
/// แต่กติกาเดียวกันครอบทุก persisted key ใน repo นี้ (`FeedbackOutbox.key(for:)`,
/// `CheckinProgressStore.cacheKey(for:)`) ยกเว้นให้ตัวเดียวแล้วครั้งหน้าจะมีตัวที่สอง
///
/// เขียนลงดิสก์ไม่ใช่เก็บใน field เพราะ 10 นาทีต้องรอดตอน process ถูกฆ่าอยู่ในกระเป๋า —
/// ซึ่งระหว่างเดินคือวิธีที่แอปนี้ถูกใช้เกือบทั้งหมด
@MainActor
final class ConditionsStore: ObservableObject {
    @Published private(set) var conditions: TrailConditions?

    private let backend: Backend
    private var loading = false

    /// Open-Meteo ขยับบล็อก `current` ทุก 15 นาที และขอให้ผู้ใช้ที่ไม่ใช่เชิงพาณิชย์อยู่ใต้
    /// 10,000 ครั้ง/วัน · 10 นาทีทำให้คนสลับไปมาระหว่าง Home กับแผนที่ไม่เปลืองครั้งละคำขอ
    /// แต่ยังสั้นกว่าจังหวะที่ข้อมูลเปลี่ยนจริง
    static let ttl: TimeInterval = 10 * 60

    init(backend: Backend = Config.backend) {
        self.backend = backend
        // อ่านของเก่ามาโชว์ในเฟรมแรกเลย ไม่สนว่าเก่าแค่ไหน — อุณหภูมิเมื่อชั่วโมงที่แล้ว
        // เป็นคำตอบที่ดีกว่าช่องว่างตรงที่ควรมีบรรทัดอยู่มาก และของใหม่กำลังตามมาแทนอยู่แล้ว
        // โหมดเดโม่ไม่ยิง Open-Meteo เลย — ต้องทำงานได้แม้ไม่มีเน็ต และสกรีนช็อตต้องซ้ำได้เป๊ะ
        conditions = DemoMode.active ? DemoData.conditions : Self.cached(backend: backend)?.value
    }

    nonisolated static func cacheKey(for backend: Backend) -> String {
        "wbw.conditions.\(backend.cacheNamespace)\(CacheScope.suffix)"
    }

    func refresh(now: Date = Date(), fetch: @escaping () async -> TrailConditions = { await OpenMeteoClient.fetch() }) async {
        guard !loading else { return }
        if DemoMode.active {
            conditions = DemoData.conditions
            return
        }
        if let cached = Self.cached(backend: backend),
           now.timeIntervalSince(cached.savedAt) < Self.ttl {
            conditions = cached.value
            return
        }
        loading = true
        defer { loading = false }

        let fresh = await fetch()
        // ยิงกลับมาแล้วได้ของว่างไม่คุ้มที่จะ cache — ปกติแปลว่าสายหลุด เก็บไว้จะทั้งซ่อนบรรทัด
        // และรีเซ็ตนาฬิกา 10 นาทีใหม่ ทำให้ซ่อนต่อไปอีกนานหลังสัญญาณกลับมาแล้ว
        guard !fresh.isEmpty else { return }
        conditions = fresh
        Self.save(fresh, at: now, backend: backend)
    }

    // MARK: - ดิสก์
    //
    // `nonisolated` ทั้งชุด — สามตัวนี้แตะแค่ UserDefaults ไม่ได้อ่าน/เขียน state ของ view เลย
    // ถ้าปล่อยให้สืบ @MainActor จาก class เทสที่เป็น sync จะเรียกไม่ได้ และจะถูกกดดันให้ไปทำ
    // เทสเป็น async ทั้งที่ไม่มีอะไร async จริง

    struct Snapshot: Codable, Equatable {
        let value: TrailConditions
        let savedAt: Date
    }

    nonisolated static func cached(backend: Backend, defaults: UserDefaults = .standard) -> Snapshot? {
        guard let data = defaults.data(forKey: cacheKey(for: backend)) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    nonisolated static func save(_ value: TrailConditions, at date: Date, backend: Backend,
                                 defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(Snapshot(value: value, savedAt: date)) else { return }
        defaults.set(data, forKey: cacheKey(for: backend))
    }

    nonisolated static func clear(backend: Backend, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: cacheKey(for: backend))
    }
}
