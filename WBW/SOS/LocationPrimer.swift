import Foundation
import CoreLocation

/// ประตูของจออธิบายที่คั่นก่อนกล่องขอสิทธิ์ตำแหน่งของระบบ
///
/// **มีเพราะ `Session.save(_:)` เคยเรียก `requestPermission()` ตรง ๆ ทันทีที่ล็อกอินสำเร็จ** —
/// กล่องของระบบเด้งใส่คนที่เพิ่งเห็นหน้า Home เป็นครั้งแรก โดยไม่มีอะไรบนจอบอกว่าเอาไปทำอะไร
/// Guideline 5.1.1 เขียนเรื่องนี้ตรง ๆ ว่าต้องขอพร้อมบริบท และ repo นี้เพิ่งแก้อาการหน้าตา
/// เหมือนกันเป๊ะไปรอบหนึ่งแล้ว (แท็บ SU RUN ขอสิทธิ์เองตอน `TabView` mount ทุกแท็บพร้อมกัน —
/// ดู `docs/appstore-1.0-8-verification.md` §5)
///
/// เจตนาเดิมของการขอตั้งแต่ล็อกอินยังอยู่ครบ: ขอตอนกด SOS คือทั้งช้าที่สุดและถูกปฏิเสธมากที่สุด
/// สิ่งที่เปลี่ยนคือ **มีจอของเราอธิบายก่อน** แล้วกล่องของระบบค่อยตามมาเมื่อผู้ใช้กดปุ่มบนจอนั้น
enum LocationPrimer {

    /// ธงว่า "กด *ไว้ทีหลัง* ไปแล้ว" — แยกตาม backend เหมือน cache ทุกตัวในแอป
    ///
    /// ต้องมีธงของเราเองเพราะสถานะฝั่งระบบยังเป็น `.notDetermined` อยู่หลังกดไว้ทีหลัง
    /// ถ้าดูจากสถานะอย่างเดียวจอนี้จะเด้งใส่หน้าเดิมทุกครั้งที่เปิดแอป
    static func dismissKey(for backend: Backend) -> String {
        "wbw.locationPrimerDismissed.\(backend.cacheNamespace)"
    }

    static var dismissed: Bool {
        get { UserDefaults.standard.bool(forKey: dismissKey(for: Config.backend)) }
        set { UserDefaults.standard.set(newValue, forKey: dismissKey(for: Config.backend)) }
    }

    /// เขียนเป็น static func ที่รับทุกอย่างเข้ามา ไม่ใช่ property ที่อ่านของโลกเอง —
    /// เทสจึงเรียกทุกสาขาได้โดยไม่ต้องมี CLLocationManager จริง
    static func shouldShow(authorization: CLAuthorizationStatus,
                           isDemo: Bool,
                           dismissed: Bool) -> Bool {
        guard !isDemo, !dismissed else { return false }
        return authorization == .notDetermined
    }

    /// ตัวที่จอจริงเรียก — อ่านสถานะปัจจุบันของแอปแล้วส่งต่อให้ตัวข้างบน
    @MainActor
    static var shouldShowNow: Bool {
        shouldShow(authorization: SOSLocator.shared.authorization,
                   isDemo: DemoMode.active,
                   dismissed: dismissed)
    }
}
