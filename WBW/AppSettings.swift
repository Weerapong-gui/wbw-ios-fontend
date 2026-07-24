import Foundation

/// ตั้งค่าแอปที่จำไว้ (dark mode / ภาษา / แจ้งเตือน)
@MainActor
final class AppSettings: ObservableObject {
    @Published var isDark: Bool { didSet { d.set(isDark, forKey: kDark) } }
    @Published var lang: String { didSet { d.set(lang, forKey: kLang) } }          // "th" | "en"
    @Published var notiEnabled: Bool { didSet { d.set(notiEnabled, forKey: kNoti) } }

    private let d = UserDefaults.standard
    private let kDark = "wbw.darkmode"
    private let kLang = "wbw.lang"
    private let kNoti = "wbw.noti.enabled"

    init() {
        isDark = d.bool(forKey: kDark)
        lang = d.string(forKey: kLang) ?? "th"
        notiEnabled = d.object(forKey: kNoti) == nil ? true : d.bool(forKey: kNoti)
    }

    /// เลือกข้อความตามภาษา (หน้า Settings สองภาษา)
    func t(_ th: String, _ en: String) -> String { lang == "en" ? en : th }
}
