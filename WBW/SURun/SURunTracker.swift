import CoreLocation
import CoreMotion
import Foundation

/// จับระยะเดิน/นับก้าวของแท็บ SU RUN — เดินตามแบบของ `walk/WalkTrackingService.kt` (Android)
///
/// **เจตนา: ทำงานเฉพาะตอนแอปเปิดอยู่** ไม่ขอ `UIBackgroundModes: location` และไม่ตั้ง
/// `allowsBackgroundLocationUpdates` — Android ใช้ foreground service จับต่อตอนล็อกจอได้
/// แต่ฝั่ง iOS การประกาศ background location ทำให้ App Review ต้องตรวจเพิ่มว่าทำไมถึงต้องใช้
/// ซึ่งไม่คุ้มกับรอบที่เพิ่งโดนตีกลับมาสองข้อ · จะเปิด background ค่อยทำเป็นรอบถัดไป
///
/// ตัวเลขไม่ได้ถูกส่งขึ้น backend — ทั้ง SUS และ Node ยังไม่มี endpoint รับ (Android ก็ไม่ส่ง
/// เหมือนกัน ดู `walk/WalkTracker.kt:56-58`) ค่าจึงอยู่ในหน่วยความจำอย่างเดียว หายเมื่อปิดแอป
/// **ห้ามเขียนลง UserDefaults โดยไม่ต่อ `Backend.cacheNamespace`** ตามกติกา cache ของ repo นี้
@MainActor
final class SURunTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Phase { case idle, running }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var distanceMetres: Double = 0
    @Published private(set) var elapsedSeconds: Int = 0
    /// nil = เครื่องไม่มีตัวนับก้าว หรือไม่ได้ให้สิทธิ์ — จอต้องโชว์ "—" ไม่ใช่ 0
    @Published private(set) var steps: Int?
    @Published private(set) var smoothedSpeed: Double = 0
    @Published private(set) var track: [CLLocationCoordinate2D] = []
    /// ปฏิเสธสิทธิ์ตำแหน่ง — จอยังใช้ดูเส้นทางได้ แค่จับระยะไม่ได้ ต้องบอกให้รู้ ไม่ใช่ปุ่มกดแล้วเงียบ
    @Published private(set) var locationDenied = false
    /// ให้สิทธิ์ตำแหน่งไปแล้วหรือยัง — จอใช้ตัดสินว่าจะวาดจุดตำแหน่งผู้ใช้ไหม
    ///
    /// ต้องเช็คก่อนใส่ `UserAnnotation()` ลงแผนที่: MapKit ขอสิทธิ์เองทันทีที่มีตัวนั้นอยู่ในฉาก
    /// ซึ่งจะกลายเป็น dialog เด้งขึ้นมาเองตอนที่ผู้ใช้ยังไม่ได้กด "เริ่มเดิน" ด้วยซ้ำ
    @Published private(set) var locationAuthorized = false

    private let manager = CLLocationManager()
    private let pedometer = CMPedometer()
    /// หมุดอ้างอิงของการสะสมระยะ — ขยับเมื่อเดินเกินเกณฑ์เท่านั้น (กันระยะไหลตอนยืนนิ่ง)
    private var anchor: CLLocation?
    private var startedAt: Date?
    private var ticker: Timer?

    var isRunning: Bool { phase == .running }

    override init() {
        super.init()
        manager.delegate = self
        // ต่างจาก Map3DLocation ที่ใช้ NearestTenMeters — ที่นั่นแค่วางจุดบนโมเดลกว้าง 4 กม.
        // แต่ที่นี่เอาไปสะสมเป็นระยะทาง ความหยาบ 10 ม. จะกลายเป็นความคลาดสะสมทั้งเส้น
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        syncAuthorization(manager.authorizationStatus)
    }

    private func syncAuthorization(_ status: CLAuthorizationStatus) {
        locationDenied = (status == .denied || status == .restricted)
        locationAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
    }

    // MARK: - เริ่ม / หยุด

    func start() {
        guard phase == .idle else { return }
        distanceMetres = 0
        elapsedSeconds = 0
        smoothedSpeed = 0
        steps = nil
        track = []
        anchor = nil
        startedAt = Date()
        phase = .running

        // โหมดเดโม่ไม่แตะพิกัดจริงเลย — ทางเดียวกับ `SOSLocator` และ `Map3DLocation`
        // (จอนี้ยังเข้าไม่ถึงในแอปตอนนี้ แต่ประตูต้องอยู่ก่อนที่จะมีคนต่อมันเข้าไป
        // ไม่ใช่หลังจากผู้รีวิวเจอกล่องขอสิทธิ์ไปแล้ว)
        if !DemoMode.active {
            manager.requestWhenInUseAuthorization()
            manager.startUpdatingLocation()
        }
        startPedometer()

        // นับเวลาด้วยนาฬิกาจริงทุกครั้งที่ tick ไม่ใช่ +1 สะสม — timer ถูกหน่วงตอนเครื่องงานหนัก
        // แล้วเวลาบนจอจะช้ากว่าความจริงไปเรื่อย ๆ โดยไม่มีอะไรฟ้อง
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(startedAt))
            }
        }
    }

    func stop() {
        guard phase == .running else { return }
        phase = .idle
        manager.stopUpdatingLocation()
        pedometer.stopUpdates()
        ticker?.invalidate()
        ticker = nil
        startedAt = nil
        anchor = nil
    }

    private func startPedometer() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor in self?.steps = data.numberOfSteps.intValue }
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        let fixes = locations
        Task { @MainActor in self.consume(fixes) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.syncAuthorization(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // ไม่หยุดการจับ — บนดอยเสียสัญญาณชั่วคราวเป็นเรื่องปกติ กลับมาแล้วต้องเดินต่อได้เอง
    }

    private func consume(_ fixes: [CLLocation]) {
        guard phase == .running else { return }
        for fix in fixes {
            guard SURunMath.accepts(accuracy: fix.horizontalAccuracy) else { continue }

            if let anchor {
                let moved = fix.distance(from: anchor)
                let gained = SURunMath.advance(movedFromAnchor: moved)
                if gained > 0 {
                    distanceMetres += gained
                    self.anchor = fix
                    track.append(fix.coordinate)
                }
            } else {
                self.anchor = fix
                track.append(fix.coordinate)
            }

            // ความเร็วจาก Doppler ของตัวรับเอง แม่นกว่าการหารระยะด้วยเวลาที่เราสะสมเอง
            // ค่าติดลบ = ตัวรับบอกว่าวัดไม่ได้ ต้องข้าม ไม่ใช่ปล่อยให้ลากค่าที่ปรับแล้วติดลบตาม
            if fix.speed >= 0 {
                smoothedSpeed = SURunMath.smooth(speed: fix.speed,
                                                 previous: smoothedSpeed > 0 ? smoothedSpeed : nil)
            }
        }
    }
}
