import CoreLocation
import Foundation

/// ตำแหน่งผู้ใช้สำหรับจุดบนแผนที่ — บางที่สุดเท่าที่พอใช้ ไม่มี background, ไม่มี heading
///
/// ไม่ให้สิทธิ์หรือหาไม่เจอ = coordinate เป็น nil เงียบๆ จอที่เหลือใช้งานได้ปกติ
/// (คนเปิดแอปจากบ้านก่อนวันงานเป็นเรื่องปกติ ไม่ใช่ความผิดพลาดที่ต้องแจ้ง)
@MainActor
final class Map3DLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // 10 เมตร: จุดบนโมเดลกว้าง ~4 กม. ขยับถี่กว่านี้ตาไม่เห็นความต่าง แต่กินแบตเพิ่ม
        manager.distanceFilter = 10
    }

    /// **โหมดเดโม่ไม่แตะพิกัดเลย** — ทางเดียวกับที่ `SOSLocator` กันไว้
    ///
    /// ผู้รีวิว App Store เข้าทางโหมดเดโม่แล้วกดแท็บแผนที่เป็นจอที่สอง กล่องขอสิทธิ์เด้งตรงนั้น
    /// โดยที่โหมดนี้ไม่มีอะไรได้ใช้พิกัดจริงเลยสักอย่าง (ข้อมูลทั้งหมดเป็น fixture)
    /// — เจอตอนถ่ายสกรีนช็อตชุดส่ง store: กล่องค้างบัง 9 ใบจาก 10 เพราะไม่มีใครกดตอบ
    func start() {
        guard !DemoMode.active else {
            #if DEBUG
            NSLog("[loc] start() ถูกเรียกในโหมดเดโม่ — ไม่ขอสิทธิ์ ไม่อ่านพิกัด")
            #endif
            return
        }
        #if DEBUG
        NSLog("[loc] start() · สถานะสิทธิ์ตอนนี้ = %@", Self.describe(manager.authorizationStatus))
        #endif
        // **ห้ามขอสิทธิ์จากที่นี่** — จอนี้เคยเรียก `requestWhenInUseAuthorization()` เอง
        // แล้วกล่องของ iOS เด้งที่วินาที 1.4 หลังเปิดแอป **ก่อน** ที่ใครจะทันกดอะไรบน
        // `LocationPrimerSheet` ซึ่งเป็นจอที่ทำขึ้นมาเพื่ออธิบายก่อนขอโดยเฉพาะ (Guideline 5.1.1)
        // — พบจาก log บนเครื่องจริง 2026-08-22 ไม่ใช่จากการอ่านโค้ด
        //
        // เคสที่ผู้ใช้เจอจริง: กด "ไว้ทีหลัง" บนจออธิบาย แล้วเปิดแท็บแผนที่ → กล่องเด้งเปล่า ๆ
        //
        // ยังไม่เคยถูกถาม = ไม่ทำอะไรเลย รอให้จออธิบายเป็นคนขอ · จุดตำแหน่งบนแผนที่จะขึ้นเอง
        // เมื่อสิทธิ์ผ่านแล้ว (ดู `locationManagerDidChangeAuthorization` ข้างล่าง)
        guard manager.authorizationStatus != .notDetermined else { return }
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    #if DEBUG
    /// ชื่ออ่านออกของสถานะสิทธิ์ — `CLAuthorizationStatus` พิมพ์ออกมาเป็นตัวเลขดิบ ซึ่งอ่านผิดง่าย
    /// (`.notDetermined` = 0 ดูเหมือน "ปฏิเสธ" ทั้งที่แปลว่า "ยังไม่เคยถาม" ซึ่งแก้คนละทางกัน)
    nonisolated static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:       return "ยังไม่เคยถาม (notDetermined)"
        case .restricted:          return "ถูกล็อกไว้ (restricted)"
        case .denied:              return "ปฏิเสธ (denied)"
        case .authorizedAlways:    return "อนุญาตตลอด (always)"
        case .authorizedWhenInUse: return "อนุญาตระหว่างใช้แอป (whenInUse)"
        @unknown default:          return "ไม่รู้จัก (\(status.rawValue))"
        }
    }
    #endif

    /// **มี `NSLog` ครอบ `#if DEBUG` โดยตั้งใจ** — เรื่องตำแหน่งเป็นสิ่งที่ตรวจจากซิมูเลเตอร์
    /// ไม่ได้จริง (พิกัดปลอม ความแม่นปลอม) ต้องอ่านจากเครื่องจริงเท่านั้น และก่อนหน้านี้ทั้งไฟล์
    /// ไม่มี log สักบรรทัด ทำให้ตอนรันบนเครื่องจริงครั้งแรกดูไม่ออกเลยว่าสิทธิ์ผ่านไหม
    /// พิกัดมาไหม แม่นแค่ไหน — เห็นได้แค่ "จุดขึ้นหรือไม่ขึ้น" ด้วยตา
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        #if DEBUG
        NSLog("[loc] พิกัดเข้า lat=%.6f lng=%.6f ความแม่น=%.1f ม. อายุ=%.1f วิ",
              last.coordinate.latitude, last.coordinate.longitude,
              last.horizontalAccuracy, -last.timestamp.timeIntervalSinceNow)
        #endif
        Task { @MainActor in self.coordinate = last.coordinate }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        #if DEBUG
        NSLog("[loc] อ่านพิกัดไม่สำเร็จ: %@", String(describing: error))
        #endif
        Task { @MainActor in self.coordinate = nil }
    }

    /// สถานะสิทธิ์เปลี่ยน — รวมถึงตอนผู้ใช้กดตอบกล่องของระบบครั้งแรก
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        #if DEBUG
        NSLog("[loc] สถานะสิทธิ์เปลี่ยนเป็น %@", Self.describe(manager.authorizationStatus))
        #endif
        // ผู้ใช้เพิ่งกดอนุญาตบนกล่องที่ `LocationPrimerSheet` เป็นคนเรียก — เริ่มอ่านพิกัดตรงนี้
        // เพราะ `start()` ที่ถูกเรียกไปก่อนหน้าเจอสถานะ `.notDetermined` แล้วออกไปเฉย ๆ
        // ไม่มีใครมาเรียกซ้ำให้อีกจนกว่าจะสลับแท็บออกแล้วกลับเข้ามาใหม่
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: break
        }
    }
}
