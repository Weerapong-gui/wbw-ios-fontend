import CoreLocation
import Foundation

struct SOSFix: Equatable {
    let lat: Double
    let lng: Double
    let accuracyM: Double
}

/// ชั้นบางๆ คั่น CLLocationManager ไว้ — ไม่ใช่เพื่อความสวยงาม แต่เพราะเทสของ
/// "GPS ที่ไม่มีวันมา" เขียนด้วยฮาร์ดแวร์จริงไม่ได้ และนั่นคือกรณีที่ต้องถูกต้องที่สุด
protocol SOSLocationProviding: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var lastKnownLocation: CLLocation? { get }
    func requestWhenInUseAuthorization()
    func requestLocation(_ completion: @escaping (CLLocation?) -> Void)
}

/// ตัวกัน continuation ถูก resume ซ้ำ · ฝั่ง provider (fix มาถึง) กับฝั่ง timeout
/// (หมดเวลา) แข่งกันเรียกได้พร้อมกันจากคนละเธรด — ตัวไหนมาก่อนชนะ ตัวที่มาทีหลัง
/// ต้องเงียบ ไม่ใช่ crash "resumed multiple times" จึงต้องมีล็อกจริง ไม่ใช่แค่ธง Bool เฉยๆ
private final class OneShotResume: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SOSFix?, Never>?

    init(_ continuation: CheckedContinuation<SOSFix?, Never>) {
        self.continuation = continuation
    }

    func callAsFunction(_ fix: SOSFix?) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: fix)
    }
}

@MainActor
final class SOSLocator {
    /// ตัวที่ Session.save(_:) เรียกหลังล็อกอิน — ต้องมีคนถือ SOSLocator (และ CLLocationManager
    /// ข้างในมัน ผ่าน SystemLocationProvider) ไว้จริงจนกว่า OS จะเก็บกล่องขอสิทธิ์เสร็จ สร้าง
    /// `SOSLocator()` ลอยๆ แล้วไม่เก็บตัวแปรไว้เลย ปล่อยให้ ARC เก็บทันทีที่จบ statement จะทำให้
    /// กล่องขอสิทธิ์อาจไม่ขึ้นเลย หรือขึ้นแล้วไม่มีวันได้ผลลัพธ์กลับมา — SOS ที่ไม่มีพิกัดโดยไม่มี
    /// error ให้เห็น เหตุผลเดียวกับที่ PushManager เป็น singleton (บรรทัดถัดจากที่เรียกตัวนี้ใน
    /// Session.save เลย) · SOSStore ยังคงสร้าง SOSLocator ของตัวเองแยกต่างหาก ถือไว้ตลอดชีวิต
    /// ของเคส SOS ที่กำลังทำงานอยู่ — คนละวงจรชีวิต คนละเหตุผล ไม่ต้องมาใช้ตัวนี้ร่วมกัน
    static let shared = SOSLocator()

    private let provider: SOSLocationProviding

    init(provider: SOSLocationProviding = SystemLocationProvider()) {
        self.provider = provider
    }

    var authorization: CLAuthorizationStatus { provider.authorizationStatus }

    /// ขอสิทธิ์ · เรียกหลังล็อกอินสำเร็จ ไม่ใช่ตอนกด SOS
    /// dialog กลางเหตุฉุกเฉินคือทั้งช้าที่สุดและถูกกด "ไม่อนุญาต" มากที่สุด
    func requestPermission() { provider.requestWhenInUseAuthorization() }

    /// ยังไม่เคยถูกถามเลย — ไม่ใช่ "ถูกปฏิเสธ" · สองอย่างนี้ต้องแยกกันเพราะทางแก้คนละทาง
    /// (.notDetermined แก้ได้ด้วยกล่องขอสิทธิ์ในแอป · .denied ต้องไปที่ตั้งค่าของเครื่อง)
    var needsPermission: Bool { authorization == .notDetermined }

    /// ขอสิทธิ์ก็ต่อเมื่อยังไม่เคยถูกถาม — เรียกซ้ำได้ปลอดภัย ไม่มีกล่องเด้งซ้ำให้คนรำคาญ
    /// (iOS ไม่แสดงกล่องอีกเลยหลังตอบครั้งแรก แต่การเรียกโดยไม่เช็คก็ยังสับสนสำหรับคนอ่านโค้ด)
    ///
    /// **มีอยู่เพราะ Session.save(_:) ไม่พอ** — มันเป็นทางเดียวที่เคยเรียก requestPermission()
    /// ซึ่งแปลว่ามีแต่คน "ที่เพิ่งล็อกอิน" เท่านั้นที่ถูกถาม คนที่ล็อกอินค้างอยู่ก่อนอัปเดตมาเป็น
    /// build นี้ (คือเกือบทุกคนในวันงาน) ไม่มีทางถูกถามเลยสักครั้ง แล้ว oneShot/cachedFix ทั้งคู่
    /// return nil เงียบๆ เมื่อสถานะเป็น .notDetermined โดยไม่ขอสิทธิ์ให้ ผลคือกด SOS ไปโดยไม่มี
    /// พิกัดติดไปด้วยเลย และไม่มีอะไรบอกว่าเสียอะไรไป
    @discardableResult
    func requestPermissionIfNeeded() -> Bool {
        guard needsPermission else { return false }
        provider.requestWhenInUseAuthorization()
        return true
    }

    /// ค่าล่าสุดที่ระบบมีอยู่แล้ว ถ้ายังไม่เก่าเกิน maxAge วินาที
    func cachedFix(maxAge: TimeInterval) -> SOSFix? {
        guard authorization == .authorizedWhenInUse || authorization == .authorizedAlways,
              let loc = provider.lastKnownLocation,
              loc.horizontalAccuracy >= 0,
              Date().timeIntervalSince(loc.timestamp) <= maxAge
        else { return nil }
        return SOSFix(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude,
                      accuracyM: loc.horizontalAccuracy)
    }

    /// ขอ fix ใหม่หนึ่งครั้ง · คืน nil เมื่อหมดเวลาหรือไม่มีสิทธิ์
    ///
    /// **ผู้เรียกต้องไม่ await ตัวนี้ก่อนยิง SOS** — มันวิ่งคู่ขนานกับการส่ง
    /// fix แรกใต้ร่มไม้ใช้เวลาได้ถึง 30 วิ ซึ่งเป็นเวลาที่แพงที่สุดในเหตุการณ์ทั้งหมด
    ///
    /// จงใจไม่ใช้ withTaskGroup: group จะรอ child task ทุกตัวจบก่อนคืนค่าเสมอ ต่อให้
    /// cancelAll() ไปแล้วก็ตาม แต่ checked continuation ที่รอ callback ของ provider อยู่
    /// ไม่ตอบสนอง cancel เอง — ถ้า timeout ชนะ การรอ fix ที่ไม่มีวันมาจะค้าง oneShot
    /// ทั้งฟังก์ชันไว้ตลอดกาล (ยืนยันจากการรันจริง: SWIFT TASK CONTINUATION MISUSE
    /// leaked ตอน timeout ชนะ ไม่ใช่แค่ทฤษฎี) แทนที่จะรอ ให้ทั้งสองฝั่งแข่งกัน resume
    /// continuation เดียวกันเอง ใครถึงก่อนชนะ ฝั่งที่แพ้กลายเป็น no-op เงียบๆ ไม่ค้างใคร
    func oneShot(timeout: Duration) async -> SOSFix? {
        guard authorization == .authorizedWhenInUse || authorization == .authorizedAlways
        else { return nil }

        return await withCheckedContinuation { cont in
            let resume = OneShotResume(cont)

            provider.requestLocation { loc in
                guard let loc, loc.horizontalAccuracy >= 0 else { resume(nil); return }
                resume(SOSFix(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude,
                              accuracyM: loc.horizontalAccuracy))
            }

            Task {
                try? await Task.sleep(for: timeout)
                resume(nil)
            }
        }
    }
}

/// ตัวจริงที่คุยกับ CoreLocation
///
/// desiredAccuracy เป็น NearestTenMeters ไม่ใช่ Best โดยตั้งใจ — ใต้ร่มไม้ Best ใช้เวลา
/// นานกว่ามากเพื่อความแม่นที่ไม่เปลี่ยนว่าฐานไหนใกล้ที่สุด และไม่ทำให้ทีมหาคนเจอเร็วขึ้น
final class SystemLocationProvider: NSObject, SOSLocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pending: ((CLLocation?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }
    var lastKnownLocation: CLLocation? { manager.location }
    func requestWhenInUseAuthorization() { manager.requestWhenInUseAuthorization() }

    func requestLocation(_ completion: @escaping (CLLocation?) -> Void) {
        pending = completion
        manager.requestLocation()
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        pending?(locations.last); pending = nil
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        pending?(nil); pending = nil
    }
}
