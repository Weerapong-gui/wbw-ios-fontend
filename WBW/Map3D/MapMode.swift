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

    /// โหมดที่ผู้ใช้เลือกไว้ · ค่าเริ่มต้นคือ 3 มิติ
    ///
    /// **ห้ามเปลี่ยนค่าเริ่มต้นโดยไม่ถ่ายสกรีนช็อตใหม่** — `02-map` ในชุดที่ส่ง App Store ไปแล้ว
    /// เป็นจอ 3 มิติ ส่งรูปที่ไม่ตรงกับสิ่งที่ผู้ตรวจเปิดมาเจอคือ Guideline 2.3.3 ซึ่งรอบ 1.0 (7)
    /// โดนตีกลับมาแล้วด้วยเหตุนี้ตรง ๆ (ดู `.claude/skills/wbw-ios/appstore.md`)
    static func stored(in defaults: UserDefaults = .standard) -> MapMode {
        guard let raw = defaults.string(forKey: storageKey), let mode = MapMode(rawValue: raw) else {
            return .threeD
        }
        return mode
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
