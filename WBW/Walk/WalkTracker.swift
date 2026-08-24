import CoreLocation
import CoreMotion
import Foundation

/// เจ้าของเซ็นเซอร์ของการเดินหนึ่งรอบ — **ที่เดียวในแอปที่แตะ `CMPedometer`**
/// (`WalkTrackingContractTests` ค้ำไว้ว่าต้องไม่มีไฟล์อื่นเรียก)
///
/// ยกพฤติกรรมมาจาก `walk/WalkTracker.kt` + `walk/WalkTrackingService.kt` ของ Android แต่
/// **ตั้งใจไม่ยกอย่างหนึ่ง: foreground service ที่เดินต่อตอนล็อกจอ** — ฝั่งนั้นประกาศ
/// `FOREGROUND_SERVICE_LOCATION` ได้ตรง ๆ ส่วน iOS ต้องขอ `UIBackgroundModes: location`
/// ซึ่ง App Review จะถามหาเหตุผลตาม Guideline 2.5.4 และกินแบตหนักตลอดงาน · เจ้าของงาน
/// เลือกให้จับเฉพาะตอนเปิดแอป การเดินจึงหยุดนับเมื่อแอปลงหลัง และนั่นคือการแลกที่ตั้งใจ
///
/// **ไม่เก็บลงดิสก์ ไม่ยิงขึ้น backend** เหมือน Android ทุกประการ — `WbwApi.kt` ฝั่งนั้นไม่มี
/// endpoint เรื่องเดินสักตัว และ SUS ก็ไม่มี · จะเก็บได้ต้องมีปลายทางก่อน ไม่ใช่เก็บไว้ในเครื่อง
/// เฉย ๆ แล้วหายไปตอนปิดแอป ซึ่งแย่กว่าไม่เก็บเพราะผู้ใช้เข้าใจว่ามันถูกบันทึกไว้แล้ว
@MainActor
final class WalkTracker: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published private(set) var stats = WalkStats()

    private let manager = CLLocationManager()
    private let pedometer = CMPedometer()

    /// หมุดอ้างอิงของการวัดระยะ — ขยับเฉพาะตอนขยับเกินเกณฑ์จริง (ดู `WalkMath.advance`)
    private var anchor: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        // `BestForNavigation` ไม่ใช่ `NearestTenMetres` แบบจุดบนแผนที่ — ที่นี่วัดระยะสะสม
        // ความคลาดเคลื่อนทุกช่วงจะถูกบวกทบกันไปเรื่อย ๆ ไม่ใช่แค่ทำให้จุดสั่นอยู่กับที่
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
    }

    // MARK: - เริ่ม / หยุด

    /// เริ่มเดินรอบใหม่ — ล้างตัวเลขรอบก่อนทิ้งตรงนี้ ไม่ใช่ตอนกดหยุด
    func start() {
        // **โหมดเดโม่ห้ามแตะเซ็นเซอร์เลย** — ทางเดียวกับ `Map3DLocation` กับ `SOSLocator`
        // กล่องขอสิทธิ์ที่เด้งขึ้นมาโดยไม่มีใครกดตอบจะค้างบังสกรีนช็อตทุกใบที่ถ่ายหลังจากนั้น
        // (เคยเสียไป 9 ใบจาก 10 · `DemoPermissionTests` กวาดทั้ง repo กันรอยนี้)
        guard !DemoMode.active else { return }

        anchor = nil
        stats = WalkStats(active: true)

        manager.startUpdatingLocation()

        // เครื่องนับก้าวไม่ได้ = ปล่อย `steps` เป็น nil ไว้อย่างนั้น จอจะโชว์ `—` เอง
        // ไม่ใช่ตั้งเป็น 0 ซึ่งอ่านว่า "นับได้ และได้ศูนย์ก้าว"
        guard CMPedometer.isStepCountingAvailable() else { return }

        // นับจาก **ตอนกดเริ่ม** ไม่ใช่ตั้งแต่บูตเครื่อง — ต่างจาก Android ที่
        // `TYPE_STEP_COUNTER` เป็นตัวนับสะสมตั้งแต่บูต จึงต้องเก็บค่าตั้งต้นไว้ลบเอง
        // (`stepBaseline` ที่ `WalkTrackingService.kt`) ฝั่งนี้ระบบทำให้แล้ว ไม่ต้องลบเอง
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let data else { return }
            let steps = data.numberOfSteps.intValue
            // callback ของ CoreMotion มาจากคิวเบื้องหลัง ต้องข้ามกลับ main actor ก่อนแตะ
            // `@Published` ไม่งั้นเป็นการแก้ state ของ View จากนอกเธรดหลัก
            Task { @MainActor [weak self] in
                guard let self, self.stats.active else { return }
                self.stats.steps = steps
            }
        }
    }

    /// หยุดเดิน — **ตัวเลขค้างไว้ให้อ่านต่อ ไม่ล้าง** (ตรงกับ `onDestroy` ของ Android)
    ///
    /// คนกดหยุดเพราะเดินจบ สิ่งแรกที่เขาอยากรู้คือ "ได้เท่าไร" — ล้างทิ้งตรงนี้คือเอาคำตอบ
    /// ไปพร้อมกับคำถาม · รอบใหม่ค่อยล้างใน `start()`
    func stop() {
        manager.stopUpdatingLocation()
        pedometer.stopUpdates()
        anchor = nil
        stats.active = false
    }

    func toggle() {
        stats.active ? stop() : start()
    }

    #if DEBUG
    /// ใส่ตัวเลขจำลองให้ถ่ายรูปได้ — ทรงเดียวกับ `SOSStore.raiseForScreenshot()`
    ///
    /// ทางเข้าจริงคือแตะปุ่มแล้วเดินจริง ซึ่งถ่ายไม่ได้เลยในสภาพแวดล้อมนี้: simulator
    /// ไม่มีเซ็นเซอร์นับก้าว (`isStepCountingAvailable()` คืน false) และไม่มีตัวกดจอ
    /// · จอที่จะขึ้นชุดสกรีนช็อต App Store ต้องมีรูปยืนยันว่ามันเรนเดอร์จริง ไม่ใช่เชื่อว่า
    /// เทสผ่านแล้วแปลว่าวาดถูก
    func fillForScreenshot() {
        stats = WalkStats(active: true, distanceMetres: 1240, steps: 1683, speedMps: 1.32)
    }
    #endif

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        Task { @MainActor [weak self] in self?.consume(fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // เงียบโดยตั้งใจ — fix หลุดเป็นช่วง ๆ ใต้ร่มไม้เป็นเรื่องปกติของงานนี้ ไม่ใช่ความผิดพลาด
        // ที่ต้องแจ้ง · ตัวเลขจะหยุดเดินเองจนกว่าสัญญาณจะกลับมา
    }

    private func consume(_ fix: CLLocation) {
        guard stats.active, WalkMath.isTrustworthy(fix) else { return }

        stats.speedMps = WalkMath.smoothSpeed(previous: stats.speedMps, sample: fix.speed)

        guard let anchor else {
            self.anchor = fix
            return
        }
        // ขยับไม่ถึงเกณฑ์ = **ไม่ขยับหมุดด้วย** ดูคอมเมนต์ที่ `WalkMath.advance`
        guard let moved = WalkMath.advance(from: anchor, to: fix) else { return }
        stats.distanceMetres += moved
        self.anchor = fix
    }
}
