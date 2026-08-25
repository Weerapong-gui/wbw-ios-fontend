import Foundation

/// การเดินหนึ่งรอบที่ยังไม่จบ — **จำลงเครื่องเพื่อให้ข้ามการปิดแอปได้**
///
/// **ขัดกับบรรทัด "ไม่เก็บลงดิสก์" ที่เคยเขียนไว้หัว `WalkTracker` โดยตั้งใจ** — ของเดิมหมายถึง
/// *ประวัติการเดินที่เดินจบแล้ว* ซึ่งไม่มีปลายทางฝั่ง SUS ให้ส่ง เก็บไว้ในเครื่องเฉย ๆ แล้วหาย
/// ตอนลบแอปคือของที่ผู้ใช้เข้าใจผิดว่าถูกบันทึกไว้ · ส่วนตัวนี้คือ *รอบที่ยังเดินอยู่* ซึ่งต้อง
/// รอดจากการปิดแอปให้ได้ตามที่เจ้าของงานสั่ง ไม่งั้นกดเริ่มเดินแล้วสลับไปแอปอื่นสิบนาที
/// กลับมาเจอเลขศูนย์
struct WalkSession: Codable, Equatable {
    /// เวลาที่กดเริ่มเดิน — เป็นจุดอ้างอิงเดียวของการถามชิปนับก้าวย้อนหลัง
    let startedAt: Date

    /// ระยะที่ GPS วัดได้ **เฉพาะช่วงที่แอปอยู่หน้าจอ**
    var gpsDistanceMetres: Double = 0

    /// ระยะที่ชิปนับก้าวให้มา **เฉพาะช่วงที่แอปไม่ได้อยู่หน้าจอ** — คนละช่วงเวลากับข้างบน
    /// จึงบวกกันได้โดยไม่ทับ (ดู `WalkMath.totalDistance`)
    var awayDistanceMetres: Double = 0

    /// ออกจากหน้าจอไปตั้งแต่เมื่อไหร่ — `nil` = ตอนนี้อยู่หน้าจอ
    var awaySince: Date?

    /// ก้าวล่าสุดที่ถามชิปได้ทั้งรอบ (ไม่ใช่ผลบวกทีละช่วง ดู `WalkMath.mergedSteps`)
    var steps: Int?
}

/// ที่เก็บรอบที่ยังไม่จบ
///
/// ไม่ผูกกับ backend เหมือน cache ตัวอื่นในแอป (`CacheScope`/`cacheNamespace`) โดยตั้งใจ —
/// การเดินเป็นของเครื่อง ไม่ได้มาจากเซิร์ฟเวอร์ไหน สลับ backend แล้วรอบที่กำลังเดินอยู่ก็ยังเป็น
/// รอบเดิมของคนเดิม
enum WalkSessionStore {

    static let key = "wbw.walk.session"

    /// รอบที่เริ่มมานานเกินนี้ถือว่า **ลืมกดหยุด** ไม่ใช่ยังเดินอยู่
    ///
    /// ฟื้นรอบข้ามคืนขึ้นมาแล้ว backfill จากชิปจะได้ระยะทั้งวันรวมตอนขับรถกลับบ้านติดมาด้วย
    /// — ตัวเลขที่ผิดแบบที่ผู้ใช้จับได้ทันทีและเลิกเชื่อทั้งฟีเจอร์ · งานเดินจริงยาวราวครึ่งวัน
    /// จึงตั้งเพดานไว้ 12 ชั่วโมง
    static let maxAge: TimeInterval = 12 * 3600

    static func load(from defaults: UserDefaults = .standard) -> WalkSession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WalkSession.self, from: data)
    }

    static func save(_ session: WalkSession, into defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    static func isStale(_ session: WalkSession, now: Date) -> Bool {
        now.timeIntervalSince(session.startedAt) > maxAge
    }
}
