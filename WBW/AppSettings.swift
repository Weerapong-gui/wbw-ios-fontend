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
    private let kDark = "wbw.darkmode"
    /// คีย์เดียวกับ PushManager.notiEnabledKey — ฝั่งนั้นอ่านค่านี้ตอนตัดสินใจลงทะเบียน device token
    private let kNoti = PushManager.notiEnabledKey

    init() {
        isDark = d.bool(forKey: kDark)
        notiEnabled = d.object(forKey: kNoti) == nil ? true : d.bool(forKey: kNoti)
    }
}
