import XCTest
@testable import WBW

/// ปุ่มเปิด/ปิดกล้องของจอเจ้าหน้าที่ — ค่าที่จำไว้ข้ามการเปิดแอป
///
/// ทรงเดียวกับ `MapMode.stored` ทุกประการ (ดู `WBW/Map3D/MapMode.swift`) — ใช้แพทเทิร์นที่
/// repo พิสูจน์มาแล้ว ไม่คิดใหม่
final class ScannerPowerTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // suite แยก ไม่แตะค่าจริงของเครื่องที่รันเทส
        defaults = UserDefaults(suiteName: "ScannerPowerTests")!
        defaults.removePersistentDomain(forName: "ScannerPowerTests")
    }

    /// **ค่าเริ่มต้นต้องเป็นเปิด** — เจ้าหน้าที่ที่เปิดแอปครั้งแรกที่ฐานต้องสแกนได้เลย
    /// ไม่ใช่ต้องหาปุ่มเปิดก่อนถึงจะเริ่มทำงานได้
    func testCameraIsOnUntilSomeoneTurnsItOff() {
        XCTAssertEqual(ScannerPower.stored(in: defaults), .on)
    }

    func testTheChoiceSurvivesBeingStoredAndReadBack() {
        ScannerPower.off.store(in: defaults)
        XCTAssertEqual(ScannerPower.stored(in: defaults), .off)
        ScannerPower.on.store(in: defaults)
        XCTAssertEqual(ScannerPower.stored(in: defaults), .on)
    }

    /// ค่าขยะ (เวอร์ชันเก่า, คนแก้ด้วยมือ) ต้องตกมาที่ค่าเริ่มต้น ไม่ใช่ crash
    /// และไม่ใช่ตกไปทาง "ปิด" ซึ่งจะทำให้จอสแกนดูเหมือนพัง
    func testGarbageInStorageFallsBackToOnNotToOff() {
        defaults.set("ปิดมั้ง", forKey: ScannerPower.storageKey)
        XCTAssertEqual(ScannerPower.stored(in: defaults), .on)
    }
}
