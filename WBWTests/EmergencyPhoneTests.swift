import XCTest
@testable import WBW

/// เบอร์ฉุกเฉินมาจาก **เซิร์ฟเวอร์** ไม่ใช่ค่าคงที่ในแอป (`Config.cacheEmergencyPhone` ถูกเรียก
/// ที่ `SOSStore.swift` ทันทีที่ยิงเคสสำเร็จ) — ของเดิมเก็บสตริงอะไรก็ได้ที่ไม่ว่าง แล้วจอสถานะ
/// เอาไปต่อเป็น `URL(string: "tel://\(...)")!` ตรง ๆ
///
/// สตริงอย่าง `"053 916 000"` หรือ `"1669 ต่อ 2"` ทำให้ `URL(string:)` คืน nil → **crash**
/// บนจอที่คนกำลังขอความช่วยเหลืออยู่ ซึ่งเป็นจอที่ห้ามพังที่สุดในแอปทั้งตัว
final class EmergencyPhoneTests: XCTestCase {
    private var key: String { "wbw.emergencyPhone.\(Config.backend.cacheNamespace)" }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    /// ไม่เคยคุยกับเซิร์ฟเวอร์สำเร็จเลย — ต้องได้ค่าที่ฝังมากับแอป และต้องต่อเป็น URL ได้
    func testDefaultPhoneMakesAValidTelURL() {
        XCTAssertEqual(Config.emergencyPhone, Config.emergencyPhoneDefault)
        XCTAssertNotNil(Config.emergencyPhoneURL)
    }

    /// เบอร์ที่มีช่องว่างคือรูปแบบที่คนกรอกในแดชบอร์ดกันจริง ๆ
    func testPhoneWithSpacesStillMakesAValidTelURL() {
        Config.cacheEmergencyPhone("053 916 000")
        XCTAssertNotNil(Config.emergencyPhoneURL, "เบอร์มีช่องว่างแล้วต่อ tel:// ไม่ได้ = crash ตอนกดโทร")
    }

    /// เบอร์ที่มีตัวอักษรไทยพ่วง — `URL(string:)` คืน nil ล้วน ๆ
    func testPhoneWithThaiTextStillMakesAValidTelURL() {
        Config.cacheEmergencyPhone("1669 ต่อ 2")
        XCTAssertNotNil(Config.emergencyPhoneURL)
    }

    /// เก็บได้ต้องอ่านกลับได้ — sanitize ต้องไม่กินเบอร์ปกติทิ้ง
    func testOrdinaryPhoneRoundTrips() {
        Config.cacheEmergencyPhone("053-916-111")
        XCTAssertEqual(Config.emergencyPhone, "053-916-111")
    }

    /// เบอร์ต่างประเทศขึ้นต้นด้วย + ต้องรอด
    func testInternationalPrefixSurvives() {
        Config.cacheEmergencyPhone("+66 53 916 000")
        XCTAssertTrue(Config.emergencyPhone.hasPrefix("+"))
        XCTAssertNotNil(Config.emergencyPhoneURL)
    }

    /// ค่าที่ไม่เหลือตัวเลขเลยต้องไม่ถูกเก็บ — ไม่งั้นเบอร์ default ที่ใช้ได้จะถูกกลบด้วยขยะ
    func testGarbageDoesNotOverwriteTheWorkingDefault() {
        Config.cacheEmergencyPhone("ไม่มีเบอร์")
        XCTAssertEqual(Config.emergencyPhone, Config.emergencyPhoneDefault)
    }
}
