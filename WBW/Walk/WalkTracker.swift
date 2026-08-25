import CoreLocation
import CoreMotion
import Foundation
import UIKit

/// เจ้าของเซ็นเซอร์ของการเดินหนึ่งรอบ — **ที่เดียวในแอปที่แตะ `CMPedometer`**
/// (`WalkTrackingContractTests` ค้ำไว้ว่าต้องไม่มีไฟล์อื่นเรียก)
///
/// ยกพฤติกรรมมาจาก `walk/WalkTracker.kt` + `walk/WalkTrackingService.kt` ของ Android แต่
/// **ยังไม่ยก foreground service มา** — ฝั่งนั้นประกาศ `FOREGROUND_SERVICE_LOCATION` ได้ตรง ๆ
/// ส่วน iOS ต้องขอ `UIBackgroundModes: location` ซึ่ง App Review ถามหาเหตุผลตาม Guideline 2.5.4
/// และกินแบตหนักตลอดงาน
///
/// **แต่การเดินไม่หยุดนับตอนแอปลงหลังอีกแล้ว (2026-08-25)** — แทนที่จะให้ GPS วิ่งเบื้องหลัง
/// ใช้ **ชิปนับก้าวของเครื่อง** เป็นแหล่งความจริงของช่วงที่แอปไม่ได้อยู่หน้าจอ แล้ว
/// `queryPedometerData(from:to:)` ย้อนหลังตอนกลับมา · ชิปนับให้อยู่แล้วโดยแอปไม่ต้องรัน
/// ข้อมูลจึงอยู่ครบแม้ผู้ใช้ปิดแอปทิ้ง และไม่ต้องประกาศ background mode สักตัว
/// · สิ่งที่แลกไป: ช่วงนอกหน้าจอได้ระยะจากชิป (หยาบกว่า GPS) และไม่มีเพซ
///
/// **จำรอบที่ยังไม่จบลงเครื่อง** (`WalkSession`) เพื่อให้ข้ามการปิดแอปได้ — ต่างจากบรรทัดเดิม
/// ที่เขียนว่า "ไม่เก็บลงดิสก์" ซึ่งหมายถึง *ประวัติการเดินที่จบแล้ว* ที่ยังไม่มีปลายทางฝั่ง SUS
/// ให้ส่ง (`WbwApi.kt` ฝั่ง Android ก็ไม่มี endpoint นี้) · รอบที่ยังเดินอยู่เป็นคนละเรื่องกัน
@MainActor
final class WalkTracker: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published private(set) var stats = WalkStats()

    private let manager = CLLocationManager()
    private let pedometer = CMPedometer()

    /// หมุดอ้างอิงของการวัดระยะ — ขยับเฉพาะตอนขยับเกินเกณฑ์จริง (ดู `WalkMath.advance`)
    private var anchor: CLLocation?

    /// รอบที่กำลังเดินอยู่ — แหล่งความจริงที่รอดจากการปิดแอป (ดู `WalkSession`)
    private var session: WalkSession?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        manager.delegate = self
        // `BestForNavigation` ไม่ใช่ `NearestTenMetres` แบบจุดบนแผนที่ — ที่นี่วัดระยะสะสม
        // ความคลาดเคลื่อนทุกช่วงจะถูกบวกทบกันไปเรื่อย ๆ ไม่ใช่แค่ทำให้จุดสั่นอยู่กับที่
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness

        // **ผูกกับวงจรของแอปที่นี่ ไม่ใช่ที่จอ** — จอแผนที่เป็นเจ้าของ tracker ก็จริง แต่การเดิน
        // ต้องรอดแม้ผู้ใช้สลับแท็บหรือปิดแอปทิ้ง ผูกไว้กับจอแล้วมันจะหยุดตามจอ
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.handleLeftForeground() } }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.handleReturnedToForeground() } }

        restoreUnfinishedWalk()
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

        // รอบใหม่เริ่มนับจากวินาทีนี้ — เวลานี้คือจุดอ้างอิงเดียวของการถามชิปย้อนหลังทั้งรอบ
        var fresh = WalkSession(startedAt: Date())
        fresh.steps = nil
        session = fresh
        WalkSessionStore.save(fresh, into: defaults)

        manager.startUpdatingLocation()

        startLivePedometer()
    }

    /// ตัวนับสด ๆ ตอนอยู่หน้าจอ — ช่วงที่ไม่ได้อยู่หน้าจอใช้การถามย้อนหลังแทน
    /// (`backfillFromPedometer`) เพราะ `startUpdates` ไม่ทำงานตอนแอปถูกพัก
    private func startLivePedometer() {
        // เครื่องนับก้าวไม่ได้ = ปล่อย `steps` เป็น nil ไว้อย่างนั้น จอจะโชว์ `—` เอง
        // ไม่ใช่ตั้งเป็น 0 ซึ่งอ่านว่า "นับได้ และได้ศูนย์ก้าว"
        guard CMPedometer.isStepCountingAvailable(), let from = session?.startedAt else { return }

        // นับจาก **ตอนกดเริ่มรอบนี้** ไม่ใช่ตั้งแต่บูตเครื่อง — ต่างจาก Android ที่
        // `TYPE_STEP_COUNTER` เป็นตัวนับสะสมตั้งแต่บูต จึงต้องเก็บค่าตั้งต้นไว้ลบเอง
        // (`stepBaseline` ที่ `WalkTrackingService.kt`) ฝั่งนี้ระบบทำให้แล้ว ไม่ต้องลบเอง
        // · ใช้ `startedAt` ของรอบ ไม่ใช่ `Date()` ตอนนี้ ไม่งั้นกลับเข้าแอปแล้วก้าวจะเริ่มนับใหม่
        pedometer.startUpdates(from: from) { [weak self] data, _ in
            guard let data else { return }
            let steps = data.numberOfSteps.intValue
            // callback ของ CoreMotion มาจากคิวเบื้องหลัง ต้องข้ามกลับ main actor ก่อนแตะ
            // `@Published` ไม่งั้นเป็นการแก้ state ของ View จากนอกเธรดหลัก
            Task { @MainActor [weak self] in
                guard let self, self.stats.active else { return }
                self.stats.steps = WalkMath.mergedSteps(queried: steps, previous: self.stats.steps)
                self.session?.steps = self.stats.steps
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
        // ล้างรอบทิ้ง **ที่นี่ที่เดียว** — เหลือค้างไว้แล้วเปิดแอปวันหลังจะฟื้นรอบผีที่นับต่อ
        // จากเมื่อวาน (กันอีกชั้นด้วยเพดานอายุที่ `WalkSessionStore.isStale`)
        session = nil
        WalkSessionStore.clear(from: defaults)
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
        session?.gpsDistanceMetres += moved
        stats.distanceMetres = WalkMath.totalDistance(
            foregroundGPS: session?.gpsDistanceMetres ?? stats.distanceMetres + moved,
            awayPedometer: session?.awayDistanceMetres ?? 0)
        self.anchor = fix
        persist()
    }

    // MARK: - ข้ามการออกจากหน้าจอ / ปิดแอป

    /// แอปลงหลัง — **ดับ GPS ทิ้ง** (ไม่มี background mode และไม่ควรมี) แล้วจดว่าออกไปตอนไหน
    private func handleLeftForeground() {
        guard stats.active, var current = session else { return }
        manager.stopUpdatingLocation()
        pedometer.stopUpdates()
        anchor = nil
        current.awaySince = Date()
        session = current
        WalkSessionStore.save(current, into: defaults)
    }

    /// กลับเข้าหน้าจอ — ถามชิปว่าช่วงที่หายไปเดินได้เท่าไร แล้วเดินเครื่อง GPS ต่อ
    private func handleReturnedToForeground() {
        guard stats.active, session != nil else { return }
        backfillFromPedometer { [weak self] in
            guard let self, self.stats.active else { return }
            self.resumeLocationIfPermitted()
            self.startLivePedometer()
        }
    }

    /// ฟื้นรอบที่ค้างจากการปิดแอป — เรียกจาก `init` ทุกครั้ง
    private func restoreUnfinishedWalk() {
        guard let saved = WalkSessionStore.load(from: defaults) else { return }
        guard !WalkSessionStore.isStale(saved, now: Date()) else {
            WalkSessionStore.clear(from: defaults)
            return
        }
        guard !DemoMode.active else { return }

        // **ฟื้นรอบได้ แต่ห้ามเป็นเหตุให้กล่องขอสิทธิ์ตำแหน่งเด้งตอนเปิดแอป** — `startUpdatingLocation()`
        // บนเครื่องที่ยัง `.notDetermined` จะเด้งกล่องของระบบทันทีโดยไม่มีบริบทอะไรเลย ซึ่งเป็น
        // รอยเดียวกับที่ `LocationPrimer` ถูกสร้างมาแก้ และเป็นข้อที่เพิ่งโดนตีกลับสองรอบติด
        // · ยังไม่ให้สิทธิ์ = ฟื้นเฉพาะตัวเลขจากชิปนับก้าว ไม่แตะ GPS
        session = saved
        stats = WalkStats(active: true,
                          distanceMetres: WalkMath.totalDistance(foregroundGPS: saved.gpsDistanceMetres,
                                                                 awayPedometer: saved.awayDistanceMetres),
                          steps: saved.steps,
                          speedMps: 0)
        // แอปถูกปิดไปแปลว่าไม่ได้อยู่หน้าจอมาตลอด — ช่วงที่หายไปเริ่มจาก `awaySince` ที่จดไว้
        // ตอนลงหลัง หรือจากตอนกดเริ่มเดินถ้าโดนฆ่าทิ้งก่อนจะจดทัน
        if session?.awaySince == nil { session?.awaySince = saved.startedAt }
        backfillFromPedometer { [weak self] in
            guard let self, self.stats.active else { return }
            self.resumeLocationIfPermitted()
            self.startLivePedometer()
        }
    }

    /// เริ่ม GPS ต่อ **เฉพาะเมื่อเคยได้สิทธิ์แล้ว** — ดูเหตุผลที่ `restoreUnfinishedWalk`
    private func resumeLocationIfPermitted() {
        guard manager.authorizationStatus != .notDetermined else { return }
        manager.startUpdatingLocation()
    }

    /// ถามชิปนับก้าวย้อนหลังสองคำถาม: ระยะเฉพาะช่วงที่หายไป กับก้าวรวมทั้งรอบ
    ///
    /// เครื่องที่ไม่มีชิป (simulator ทุกตัว) หรือคนที่ไม่ให้สิทธิ์ Motion จะได้ `nil` กลับมา —
    /// ตัวเลขเดิมต้องอยู่ครบ ไม่ใช่ถูกล้างเป็นศูนย์ (ดู `WalkMath.mergedSteps`)
    private func backfillFromPedometer(then finish: @escaping () -> Void) {
        guard var current = session, CMPedometer.isStepCountingAvailable() else { finish(); return }
        let now = Date()
        let awayFrom = current.awaySince

        let group = DispatchGroup()
        var awayDistance: Double = 0
        var totalSteps: Int?

        if let awayFrom, awayFrom < now, CMPedometer.isDistanceAvailable() {
            group.enter()
            pedometer.queryPedometerData(from: awayFrom, to: now) { data, _ in
                awayDistance = data?.distance?.doubleValue ?? 0
                group.leave()
            }
        }
        group.enter()
        pedometer.queryPedometerData(from: current.startedAt, to: now) { data, _ in
            totalSteps = data?.numberOfSteps.intValue
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            current.awayDistanceMetres += max(0, awayDistance)
            current.steps = WalkMath.mergedSteps(queried: totalSteps, previous: current.steps)
            current.awaySince = nil
            self.session = current
            self.stats.distanceMetres = WalkMath.totalDistance(
                foregroundGPS: current.gpsDistanceMetres, awayPedometer: current.awayDistanceMetres)
            self.stats.steps = current.steps
            WalkSessionStore.save(current, into: self.defaults)
            finish()
        }
    }

    private func persist() {
        guard let session else { return }
        WalkSessionStore.save(session, into: defaults)
    }
}
