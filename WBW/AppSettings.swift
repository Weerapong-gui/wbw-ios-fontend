import Foundation

/// โหมดรูปลักษณ์ — **ยกมาจาก `ThemeMode` ใน `ui/theme/Theme.kt` ของ Android**
///
/// `auto` เดินตามระบบ ซึ่งต้นทางใช้เป็นตัวแทนของวงจรกลางวัน-กลางคืนของงาน
enum ThemeMode: String, CaseIterable {
    case light, dark, auto
}

/// ภาษาที่แสดง — `system` เดินตามเครื่อง ที่เหลือบังคับทับ
///
/// ต้องมี `system` ด้วย ไม่ใช่แค่ th/en: คนที่ไม่เคยแตะสวิตช์ควรได้ภาษาที่เครื่องตั้งไว้
/// ไม่ใช่ภาษาที่แอปเดาแทน
enum AppLanguage: String, CaseIterable {
    case system, th, en

    /// nil = ปล่อยให้ระบบเลือกเอง
    var locale: Locale? {
        switch self {
        case .system: return nil
        case .th: return Locale(identifier: "th")
        case .en: return Locale(identifier: "en")
        }
    }
}

/// ตั้งค่าแอปที่จำไว้ (รูปลักษณ์ / ภาษา / แจ้งเตือน)
///
/// **ตัวเลือกภาษากลับมาแล้ว (2026-08-20)** — เคยถูกถอดออกเพราะมีแค่หน้าตั้งค่าหน้าเดียวที่แปลจริง
/// ("ปุ่มที่กดแล้วไม่เกิดอะไรแย่กว่าไม่มีปุ่ม") ตอนนี้แอปมี `en.lproj`/`th.lproj` ครบทั้งชุดคีย์
/// ที่ยกมาจาก `strings.xml` ของ Android แล้ว ปุ่มจึงมีของจริงให้เปลี่ยน
@MainActor
final class AppSettings: ObservableObject {
    @Published var themeMode: ThemeMode { didSet { d.set(themeMode.rawValue, forKey: Self.themeModeKey) } }
    @Published var language: AppLanguage { didSet { d.set(language.rawValue, forKey: Self.languageKey) } }
    @Published var notiEnabled: Bool { didSet { d.set(notiEnabled, forKey: kNoti) } }

    // แจ้งเตือนรายหมวดตามที่ Android มี · **สามตัวล่างยังไม่ได้ต่อกับอะไร** — backend ส่งเฉพาะ
    // ประกาศอยู่ตอนนี้ เก็บค่าไว้ก่อนเพื่อให้หน้าตาตรงกับต้นทางและพร้อมตอนมีหมวดเพิ่ม
    @Published var notiNearby: Bool { didSet { d.set(notiNearby, forKey: "wbw.noti.nearby") } }
    @Published var notiChat: Bool { didSet { d.set(notiChat, forKey: "wbw.noti.chat") } }
    @Published var notiDaily: Bool { didSet { d.set(notiDaily, forKey: "wbw.noti.daily") } }

    private let d = UserDefaults.standard

    nonisolated static var themeModeKey: String { "wbw.thememode" }
    nonisolated static var languageKey: String { "wbw.language" }
    /// คีย์เดิมของสวิตช์โหมดมืดแบบสองสถานะ — อ่านครั้งเดียวเพื่อย้ายคนที่เคยตั้งค่าไว้
    nonisolated static var darkModeKey: String { "wbw.darkmode" }
    private var kNoti: String { PushManager.notiEnabledKey }

    /// ยังไม่เคยแตะสวิตช์ = **โหมดมืด** ไม่ใช่ `auto`
    ///
    /// ต่างจากต้นทางที่ตั้ง `AUTO` ไว้โดยตั้งใจ — `WBWApp` ส่งค่านี้ต่อเป็น `.preferredColorScheme`
    /// ซึ่งคุมสีนาฬิกา/แบตของ status bar ด้วย · `auto` บนเครื่องที่ตั้งโหมดสว่างจะได้ status bar
    /// ตัวดำทับพื้นภาพป่าที่มืดอยู่ดี ซึ่งเป็นบั๊กที่เพิ่งแก้ไปเมื่อเช้า
    ///
    /// ย้ายค่าเดิม: คนที่เคยตั้งสวิตช์สองสถานะไว้ได้ `.light`/`.dark` ตามที่เลือก ไม่ถูกทับ
    nonisolated static func themeModePreference(_ d: UserDefaults = .standard) -> ThemeMode {
        if let raw = d.string(forKey: themeModeKey), let mode = ThemeMode(rawValue: raw) { return mode }
        if d.object(forKey: darkModeKey) != nil { return d.bool(forKey: darkModeKey) ? .dark : .light }
        return .dark
    }

    nonisolated static func languagePreference(_ d: UserDefaults = .standard) -> AppLanguage {
        guard let raw = d.string(forKey: languageKey), let lang = AppLanguage(rawValue: raw) else { return .system }
        return lang
    }

    init() {
        themeMode = Self.themeModePreference(d)
        language = Self.languagePreference(d)
        notiEnabled = d.object(forKey: PushManager.notiEnabledKey) == nil ? true : d.bool(forKey: PushManager.notiEnabledKey)
        notiNearby = d.object(forKey: "wbw.noti.nearby") == nil ? true : d.bool(forKey: "wbw.noti.nearby")
        notiChat = d.object(forKey: "wbw.noti.chat") == nil ? true : d.bool(forKey: "wbw.noti.chat")
        notiDaily = d.object(forKey: "wbw.noti.daily") == nil ? true : d.bool(forKey: "wbw.noti.daily")
    }
}
