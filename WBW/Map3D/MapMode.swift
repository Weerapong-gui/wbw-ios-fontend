import Foundation

/// โหมดของแท็บแผนที่ — **ยกปุ่มสลับมาจาก `ui/map/MapScreen.kt` ของ Android** ที่มีสวิตช์นี้อยู่แล้ว
///
/// สองโหมดตอบคนละคำถาม: 3 มิติตอบว่า "ฐานหน้าตายังไง ใกล้อะไร" (โมเดลของงานที่ปั้นมาเอง)
/// ส่วน 2 มิติตอบว่า "เส้นทางไปทางไหน ตอนนี้ฉันอยู่ตรงไหนของเส้น" ซึ่งโมเดล 3 มิติตอบไม่ได้เลย
/// เพราะไม่มีเส้นทางอยู่ในนั้น
enum MapMode: String, CaseIterable {
    case threeD = "3d"
    case flat = "2d"

    static let storageKey = "wbw.map.mode"

    /// โหมดที่ผู้ใช้เลือกไว้ · **ค่าเริ่มต้นคือ 2 มิติ** (เปลี่ยนจาก 3 มิติเมื่อ 2026-08-24)
    ///
    /// 2 มิติใช้ได้ตั้งแต่วินาทีที่เปิดแท็บ ส่วน 3 มิติต้องรอโมเดล 9.8 MB โหลดก่อน (13 วิบนเครื่องจริง
    /// กว่าจะเห็นอะไรนอกจากตัวหมุน) และสองโหมดตอบคนละคำถาม — "เส้นทางไปทางไหน ฉันอยู่ตรงไหน
    /// ของเส้น" เป็นคำถามของ 2 มิติ ส่วน "ฐานหน้าตายังไง" เป็นของ 3 มิติซึ่งกดสลับเอาได้
    /// · ผลพลอยได้: `RealityView` ไม่ถูก mount เลยจนกว่าจะกดสลับ แท็บจึงไม่โหลดโมเดลทิ้งเปล่า
    ///
    /// **ค้างอยู่: สกรีนช็อต `02-map` ที่ส่ง App Store ไปแล้วยังเป็นจอ 3 มิติ** — ต้องถ่ายใหม่
    /// ทั้งสองขนาดก่อน archive รอบหน้า ไม่งั้นคือ Guideline 2.3.3 ซ้ำรอย 1.0 (7) ที่โดนตีกลับ
    /// เพราะส่งรูปไม่ตรงกับแอป · จดไว้ในลำดับการอัปโหลดที่ `docs/appstore/connect-checklist.md`
    /// แล้ว (ดู `.claude/skills/wbw-ios/appstore.md` ประกอบ)
    static func stored(in defaults: UserDefaults = .standard) -> MapMode {
        guard let raw = defaults.string(forKey: storageKey), let mode = MapMode(rawValue: raw) else {
            return .flat
        }
        return mode
    }

    /// โหมดที่จอควรเปิดมาแสดง — ค่าที่ผู้ใช้เลือก เว้นแต่มีแฟลกถ่ายภาพสั่งทับ
    ///
    /// **ต้องอ่านตอนสร้าง state ไม่ใช่ใน `onAppear` ของแผนที่ 3 มิติ** — `.onAppear` ตัวนั้นอยู่บน
    /// `RealityView` ซึ่ง **ไม่ถูก mount เลยเมื่อเปิดมาที่โหมด 2 มิติ** แฟลกจึงถูกกลืนเงียบ ๆ:
    /// สั่ง `-uitestMapMode 3d` แล้วได้จอ 2 มิติกลับมาโดยไม่มี error ให้เห็น (เจอจริงตอนถ่ายยืนยัน
    /// หลังเปลี่ยนค่าเริ่มต้นเป็น 2 มิติ 2026-08-24 — ก่อนหน้านั้นแฟลกทำงานเพราะค่าเริ่มต้นคือ 3 มิติ
    /// จอนั้นจึงถูก mount อยู่แล้วเสมอ)
    static func initialForLaunch(in defaults: UserDefaults = .standard) -> MapMode {
        #if DEBUG
        // ถ่ายภาพโหมดใดโหมดหนึ่งโดยไม่ต้องแตะปุ่มเอง — repo นี้ไม่มี tap tooling
        // (เหตุผลเดียวกับ `-uitestMapPin`)
        if let raw = defaults.string(forKey: "uitestMapMode"), let forced = MapMode(rawValue: raw) {
            return forced
        }
        #endif
        return stored(in: defaults)
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }

    func toggled() -> MapMode { self == .threeD ? .flat : .threeD }

    /// โหมดที่ได้จริงหลังคิดสวิตช์ปิดแผนที่ 3 มิติ (`Config.map3D`) เข้าไปด้วย
    ///
    /// สวิตช์นั้นมีไว้ปิดโมเดล 10 MB บนเครื่องที่รับไม่ไหว — ก่อนมีโหมด 2 มิติ ปิดแล้วแท็บนี้
    /// เหลือแค่การ์ดข้อความว่าแผนที่ปิดอยู่ · ตอนนี้ปิดแล้วตกมาที่แผนที่ 2 มิติแทน ซึ่งเบากว่ามาก
    /// และยังตอบคำถาม "เส้นทางไปทางไหน" ได้ครบ
    static func effective(stored: MapMode, map3DEnabled: Bool) -> MapMode {
        map3DEnabled ? stored : .flat
    }

    /// ป้ายของปุ่มสลับ — **บอกโหมดที่จะไป ไม่ใช่โหมดที่อยู่** (ทรงเดียวกับ Android:
    /// `if (is3d) map_mode_2d else map_mode_3d`) · ป้ายที่บอกโหมดปัจจุบันจะอ่านเป็นสถานะ
    /// แล้วคนกดเพราะคิดว่ากดเพื่ออยู่ต่อ
    var toggleLabelKey: String {
        switch self {
        case .threeD: return "map_mode_2d"
        case .flat:   return "map_mode_3d"
        }
    }

    /// ไอคอนของปุ่มสลับ — คู่กับป้าย จึงเป็นสัญลักษณ์ของ "ที่ที่จะไป" เหมือนกัน
    var toggleSystemImage: String {
        switch self {
        case .threeD: return "map"
        case .flat:   return "mountain.2"
        }
    }
}
