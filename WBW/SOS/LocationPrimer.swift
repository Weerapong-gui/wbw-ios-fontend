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
///
/// **ประตูนี้ตัดสินแค่ว่าจะ *เปิด* จอนั้นไหม — เปิดแล้วต้องจบที่กล่องของระบบเสมอ** ใบตีกลับ
/// 1.0 (12) (2026-08-25, Guideline 5.1.1(iv)) เขียนตรง ๆ ว่า *"The user should always proceed
/// to the permission request after the message"* ปุ่ม "ไว้ทีหลัง" กับการปัดชีตทิ้งจึงหายไป
enum LocationPrimer {

    /// ธงว่า "พาไปถึงกล่องของระบบไปแล้ว" — แยกตาม backend เหมือน cache ทุกตัวในแอป
    ///
    /// เหลือกันอาการเดียวคือ **เครื่องที่ปิด Location Services ทั้งเครื่อง**: กดปุ่มแล้ว
    /// `requestPermission()` ได้แค่กล่องชวนไปเปิดใน Settings สถานะค้างที่ `.notDetermined`
    /// ตลอด · ไม่มีธงนี้ จอที่ปัดทิ้งไม่ได้แล้วจะขึ้นทับหน้า Home ทุกครั้งที่เปิดแอป
    ///
    /// **คีย์คนละใบกับธง `...Dismissed` ของเดิมโดยตั้งใจ** — ของเดิมแปลว่า "กดไว้ทีหลัง"
    /// ซึ่งเป็นปุ่มที่ถูกถอดทิ้งตามใบตีกลับ 1.0 (12) · ใช้ชื่อเดิมต่อ = คนที่เคยกดไว้ทีหลัง
    /// ไม่มีวันถูกถามอีกเลยทั้งที่ยังไม่เคยเห็นกล่องของระบบสักครั้ง ซึ่งตรงข้ามกับใบตีกลับ
    static func askedKey(for backend: Backend) -> String {
        "wbw.locationPrimerAsked.\(backend.cacheNamespace)"
    }

    static var asked: Bool {
        get { UserDefaults.standard.bool(forKey: askedKey(for: Config.backend)) }
        set { UserDefaults.standard.set(newValue, forKey: askedKey(for: Config.backend)) }
    }

    /// เขียนเป็น static func ที่รับทุกอย่างเข้ามา ไม่ใช่ property ที่อ่านของโลกเอง —
    /// เทสจึงเรียกทุกสาขาได้โดยไม่ต้องมี CLLocationManager จริง
    static func shouldShow(authorization: CLAuthorizationStatus,
                           isDemo: Bool,
                           asked: Bool) -> Bool {
        guard !isDemo, !asked else { return false }
        return authorization == .notDetermined
    }

    /// ตัวที่จอจริงเรียก — อ่านสถานะปัจจุบันของแอปแล้วส่งต่อให้ตัวข้างบน
    ///
    /// `NSLog` ครอบ `#if DEBUG` ด้วยเหตุผลเดียวกับ `Map3DLocation`: จอนี้โผล่หรือไม่โผล่ขึ้นกับ
    /// สามค่าที่มองไม่เห็นจากภายนอกเลย (สถานะสิทธิ์ · โหมดเดโม่ · ธง "พาไปกล่องระบบแล้ว") ตอนรันบน
    /// เครื่องจริงจึงแยกไม่ออกว่า "ไม่โผล่เพราะตอบไปแล้ว" กับ "ไม่โผล่เพราะพัง"
    @MainActor
    static var shouldShowNow: Bool {
        let auth = SOSLocator.shared.authorization
        let demo = DemoMode.active
        let done = asked
        let show = shouldShow(authorization: auth, isDemo: demo, asked: done)
        #if DEBUG
        NSLog("[loc] จออธิบาย: %@ · สิทธิ์=%@ เดโม่=%@ พาไปกล่องระบบแล้ว=%@",
              show ? "โผล่" : "ไม่โผล่",
              Map3DLocation.describe(auth), demo ? "ใช่" : "ไม่", done ? "ใช่" : "ไม่")
        #endif
        return show
    }
}
