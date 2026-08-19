import Foundation

/// ตั้งค่าแอปที่จำไว้ (dark mode / แจ้งเตือน)
///
/// เคยมีตัวเลือกภาษาด้วย แต่มีแค่หน้าตั้งค่าหน้าเดียวที่แปลจริง (ข้อความไทยอีก 259 จุดใน 32 ไฟล์
/// ไม่ได้ผ่าน t()) กด English แล้วแทบไม่มีอะไรเปลี่ยน เอาออกไปก่อนจนกว่าจะทำ i18n เต็มจริง —
/// ปุ่มที่กดแล้วไม่เกิดอะไรแย่กว่าไม่มีปุ่ม
@MainActor
final class AppSettings: ObservableObject {
    @Published var isDark: Bool { didSet { d.set(isDark, forKey: kDark) } }
    @Published var notiEnabled: Bool { didSet { d.set(notiEnabled, forKey: kNoti) } }

    private let d = UserDefaults.standard
    /// nonisolated เพราะ AppSettings ทั้งคลาสเป็น @MainActor แต่คีย์กับการอ่านค่าปริยาย
    /// ไม่ได้แตะ state ของมันเลย — เทสกับ PushManager เรียกจากนอก main actor ได้
    nonisolated static var darkModeKey: String { "wbw.darkmode" }
    private var kDark: String { Self.darkModeKey }
    /// คีย์เดียวกับ PushManager.notiEnabledKey — ฝั่งนั้นอ่านค่านี้ตอนตัดสินใจลงทะเบียน device token
    private let kNoti = PushManager.notiEnabledKey

    /// ยังไม่เคยแตะสวิตช์ = **โหมดมืด**
    ///
    /// `WBWApp` ส่งค่านี้ต่อเป็น `.preferredColorScheme` ซึ่งคุมสีนาฬิกา/แบตของ status bar ด้วย
    /// ค่าเดิม (`d.bool` = false) ทำให้ได้ status bar ตัวดำทับภาพป่ากลางคืนของ `AppBackdrop`
    /// ทั้ง 7 จอที่ใช้พื้นนั้น มองแทบไม่เห็นเลย
    ///
    /// **ผลข้างเคียงที่ยอมรับแล้ว:** ผู้ใช้เดิมที่ไม่เคยแตะสวิตช์จะเห็นจอที่ใช้ `wbwBg`/`wbwSurface`
    /// (แชท กลุ่ม ประกาศ ความเห็นต่อฐาน) พลิกเป็นโทนมืดไปด้วย — สลับกลับเองได้ที่หน้าตั้งค่า
    /// ทางเลือกอื่นที่พิจารณาแล้วไม่เอา: บังคับ status bar ขาวผ่าน plist หรือ
    /// `overrideUserInterfaceStyle` รายจอ — ทั้งคู่ทำให้จอพื้นสว่างกลายเป็นขาวบนขาว
    /// (ดู `docs/app-backdrop-open-questions.md` หัวข้อ "ค้าง 5")
    nonisolated static func darkModePreference(_ d: UserDefaults = .standard) -> Bool {
        d.object(forKey: darkModeKey) == nil ? true : d.bool(forKey: darkModeKey)
    }

    init() {
        isDark = Self.darkModePreference(d)
        notiEnabled = d.object(forKey: kNoti) == nil ? true : d.bool(forKey: kNoti)
    }
}
