import XCTest
import CoreLocation
@testable import WBW

private final class FakeLocationProvider: SOSLocationProviding {
    var status: CLAuthorizationStatus = .authorizedWhenInUse
    var cached: CLLocation?
    var deliver: CLLocation?
    var deliverAfter: Duration = .milliseconds(10)
    private(set) var requestedPermission = false
    private(set) var startedUpdating = false

    var authorizationStatus: CLAuthorizationStatus { status }
    var lastKnownLocation: CLLocation? { cached }
    func requestWhenInUseAuthorization() { requestedPermission = true }
    func requestLocation(_ completion: @escaping (CLLocation?) -> Void) {
        startedUpdating = true
        guard let deliver else { return }        // ไม่ส่งอะไรเลย = จำลอง fix ที่ไม่มีวันมา
        Task { try? await Task.sleep(for: deliverAfter); completion(deliver) }
    }
}

@MainActor
final class SOSLocatorTests: XCTestCase {

    override func tearDown() {
        DemoMode.forcedActive = nil
        super.tearDown()
    }

    /// โหมดเดโม่ห้ามเด้งกล่องขอสิทธิ์ของจริงใส่ผู้รีวิว
    ///
    /// `Session.startDemo()` ตั้งใจไม่เรียก `requestPermission()` ด้วยเหตุผลนี้ตรง ๆ แต่
    /// `SOSStatusView.onAppear` เรียก `requestPermissionIfNeeded()` เองอีกทาง — ผู้รีวิวที่กด
    /// ปุ่ม SOS ในโหมดเดโม่จึงยังเจอกล่องขอตำแหน่งอยู่ดี ทั้งที่โหมดนี้ไม่ยิงเน็ตและไม่ใช้พิกัดจริง
    /// เลยสักครั้ง (`DemoSOS` สร้างเคสในหน่วยความจำล้วน) · Guideline 5.1.1 อ่านเรื่องนี้ตรง ๆ:
    /// ขอสิทธิ์ที่ไม่มีอะไรในแอปได้ใช้จริง
    func testDemoModeNeverAsksForLocation() {
        // ตั้งผ่าน seam ที่มีไว้สำหรับเรื่องนี้อยู่แล้ว ไม่ใช่ไปยัด token ลงที่เก็บ —
        // ตั้งแต่ JWT ย้ายเข้า Keychain (TokenStore) การเขียน UserDefaults ตรง ๆ ไม่มีผลอีกแล้ว
        DemoMode.forcedActive = true
        let p = FakeLocationProvider()
        p.status = .notDetermined
        let locator = SOSLocator(provider: p)

        locator.requestPermission()
        XCTAssertFalse(p.requestedPermission, "โหมดเดโม่เด้งกล่องขอสิทธิ์ตำแหน่งใส่ผู้รีวิว")

        XCTAssertFalse(locator.requestPermissionIfNeeded())
        XCTAssertFalse(p.requestedPermission)
    }

    /// อีกด้านของเทสข้างบน — บัญชีจริงต้องยังถูกถามเหมือนเดิม
    func testRealSessionStillAsksForLocation() {
        DemoMode.forcedActive = false
        let p = FakeLocationProvider()
        p.status = .notDetermined
        let locator = SOSLocator(provider: p)

        XCTAssertTrue(locator.requestPermissionIfNeeded())
        XCTAssertTrue(p.requestedPermission)
    }

    func testAFreshCachedFixIsUsedWithoutWaitingForGPS() async {
        let p = FakeLocationProvider()
        p.cached = CLLocation(coordinate: .init(latitude: 20.0439, longitude: 99.899),
                              altitude: 0, horizontalAccuracy: 15, verticalAccuracy: 0,
                              timestamp: Date())
        let fix = SOSLocator(provider: p).cachedFix(maxAge: 60)
        XCTAssertEqual(fix?.lat ?? 0, 20.0439, accuracy: 0.0001)
        XCTAssertFalse(p.startedUpdating, "ค่าที่ยังสดต้องใช้ได้เลย ไม่ต้องขอ fix ใหม่")
    }

    func testAStaleCachedFixIsRejected() {
        let p = FakeLocationProvider()
        p.cached = CLLocation(coordinate: .init(latitude: 20.0439, longitude: 99.899),
                              altitude: 0, horizontalAccuracy: 15, verticalAccuracy: 0,
                              timestamp: Date(timeIntervalSinceNow: -300))
        XCTAssertNil(SOSLocator(provider: p).cachedFix(maxAge: 60))
    }

    /// สำคัญที่สุดในไฟล์นี้: GPS ที่ไม่มีวันมาต้องไม่ค้างการส่ง SOS ไว้ตลอดกาล
    ///
    /// **ห้าม `await oneShot(...)` ตรงๆ ในเทสนี้** — ถ้าโค้ดถอยกลับไปเป็นทรงที่ค้าง (ซึ่งเกิดขึ้นมาแล้ว
    /// จริงบนกิ่งนี้: `withTaskGroup` รอ child ทุกตัวจบต่อให้ cancelAll ไปแล้ว ดูคอมเมนต์ที่ oneShot)
    /// เทสจะไม่แดง มันจะ "ค้าง" — xcodebuild จอดอยู่ที่ 0% CPU ไปเรื่อยๆ จนกว่าจะมีคนไปฆ่าเอง ซึ่งใน CI
    /// แปลว่างานค้างทั้งคิวโดยไม่มีข้อความบอกสาเหตุสักบรรทัด · ให้ผลลัพธ์วิ่งผ่าน expectation ที่มี
    /// deadline ของ XCTest แทน — ทรงที่ค้างจะกลายเป็นความล้มเหลวที่อ่านออกภายใน 5 วิ
    func testOneShotGivesUpAtTheTimeoutInsteadOfHangingForever() async {
        let p = FakeLocationProvider()
        p.deliver = nil
        let locator = SOSLocator(provider: p)
        let started = Date()
        let returned = expectation(description: "oneShot ต้องคืนค่าเอง ไม่ค้างรอ fix ที่ไม่มีวันมา")
        var fix: SOSFix?
        Task {
            fix = await locator.oneShot(timeout: .milliseconds(200))
            returned.fulfill()
        }
        await fulfillment(of: [returned], timeout: 5)
        XCTAssertNil(fix)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.0, "ต้องยอมแพ้ตามเวลาที่ตั้ง")
    }

    func testOneShotReturnsTheFixWhenItArrivesInTime() async {
        let p = FakeLocationProvider()
        p.deliver = CLLocation(coordinate: .init(latitude: 20.05, longitude: 99.90),
                               altitude: 0, horizontalAccuracy: 30, verticalAccuracy: 0,
                               timestamp: Date())
        let fix = await SOSLocator(provider: p).oneShot(timeout: .seconds(2))
        XCTAssertEqual(fix?.accuracyM ?? 0, 30, accuracy: 0.1)
    }

    func testDeniedPermissionYieldsNoFixAndNoCrash() async {
        let p = FakeLocationProvider()
        p.status = .denied
        let locator = SOSLocator(provider: p)
        XCTAssertNil(locator.cachedFix(maxAge: 60))
        let fix = await locator.oneShot(timeout: .milliseconds(200))
        XCTAssertNil(fix)
    }

    /// `SOSLocator().requestPermission()` ลอยๆ (ไม่มีตัวแปรถือ) ให้ ARC เก็บทั้งอินสแตนซ์รวมถึง
    /// CLLocationManager ข้างในทันทีที่จบ statement — กล่องขอสิทธิ์อาจไม่ขึ้นเลย หรือขึ้นแล้วไม่มีวัน
    /// ได้ผลลัพธ์กลับมา (Session.save เรียกผ่าน .shared เพื่อเลี่ยงเรื่องนี้) เทสนี้ค้ำแค่ว่า .shared
    /// เป็นอินสแตนซ์เดียวกันทุกครั้งที่เรียก ไม่ใช่ factory ที่คืนของใหม่ทุกครั้ง (ซึ่งจะพา
    /// CLLocationManager ตัวเก่ากลับไปให้ ARC เก็บเหมือนเดิม) — พิสูจน์แค่ property ระดับโค้ด
    /// ไม่ได้พิสูจน์ว่ากล่องขึ้นจริงบนเครื่อง ยังต้องเทสบนเครื่องจริงอยู่ดี
    func testSharedIsTheSameRetainedInstanceEveryTime() {
        XCTAssertTrue(SOSLocator.shared === SOSLocator.shared,
                      "ถ้า .shared คืนอินสแตนซ์ใหม่ทุกครั้ง CLLocationManager จะไม่มีใครถือไว้เลย")
    }
}
