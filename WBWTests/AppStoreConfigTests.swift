import XCTest

/// คุมค่าที่ผิดแล้ว "ไม่มีอะไรฟ้อง" จนกว่าจะสายเกินแก้
///
/// ทั้งสามอย่างในไฟล์นี้พังแบบเงียบทั้งหมด: build ที่ขึ้น store พร้อม
/// aps-environment ผิดจะไม่ได้ push สักอันโดยไม่มี error, plist สองตัวที่เพี้ยนกันจะรู้ตัว
/// ตอนของหลุดขึ้น store ไปแล้ว, และ privacy manifest ที่หายไปจะโดนตีกลับตอน validate
/// ซึ่งกว่าจะรู้ก็ตอนกำลังจะส่งจริง
///
/// อ่านไฟล์จาก source tree ผ่าน #filePath ไม่ใช่จาก bundle เพราะต้องเทียบ **ทั้งสอง**
/// config พร้อมกัน ขณะที่ bundle ที่รันเทสอยู่มีแค่ config เดียว
final class AppStoreConfigTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // WBWTests
        .deletingLastPathComponent()   // repo root

    private func plist(_ relativePath: String) throws -> [String: Any] {
        let url = Self.repoRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        guard let dict = try PropertyListSerialization.propertyList(
            from: data, format: nil) as? [String: Any]
        else {
            XCTFail("อ่าน \(relativePath) เป็น dictionary ไม่ได้")
            return [:]
        }
        return dict
    }

    /// คีย์ที่ยอมให้มีเฉพาะฝั่ง Debug — มีไว้ยิง backend ที่รันบนเครื่อง Mac ผ่านวง LAN
    /// (Config.backend = .susLan) ห้ามหลุดขึ้น store เด็ดขาด
    private static let debugOnlyKeys: Set<String> = [
        "NSAppTransportSecurity",
        "NSLocalNetworkUsageDescription",
    ]

    func testDebugPlistDiffersFromReleaseOnlyByTheAllowedKeys() throws {
        let release = try plist("WBW/Info.plist")
        let debug = try plist("WBW/Info-Debug.plist")

        let extra = Set(debug.keys).subtracting(release.keys)
        XCTAssertEqual(extra, Self.debugOnlyKeys,
                       "Info-Debug.plist มีคีย์เกินจากที่อนุญาต หรือขาดคีย์ที่ควรมี")

        let missing = Set(release.keys).subtracting(debug.keys)
        XCTAssertTrue(missing.isEmpty,
                      "เติมคีย์ใน Info.plist แล้วลืมเติมใน Info-Debug.plist: \(missing.sorted())")

        for key in release.keys {
            XCTAssertEqual(release[key] as? NSObject, debug[key] as? NSObject,
                           "คีย์ \(key) ค่าไม่ตรงกันระหว่างสอง config")
        }
    }

    func testReleasePlistCarriesNoDevOnlyKeys() throws {
        let release = try plist("WBW/Info.plist")
        for key in Self.debugOnlyKeys {
            XCTAssertNil(release[key], "\(key) เป็นของ dev ห้ามอยู่ใน plist ที่ส่งขึ้น store")
        }
    }

    /// เหลือแค่ครึ่งเดียว — ครึ่งตำแหน่งกลับทิศไปแล้วที่
    /// testLocationPermissionStringExistsInBothPlistsBecauseSOSUsesIt เพราะตอนนี้ SOS
    /// ใช้ CoreLocation จริง (ดูคอมเมนต์ที่นั่น) ที่ยังอยู่ตรงนี้คือคลังรูป ซึ่งใช้ PhotosPicker
    /// แล้วไม่ต้องขอสิทธิ์เลย ถ้าเห็นคีย์นี้แปลว่ามีคนใส่เกินมา
    func testNoUsageDescriptionForFrameworksTheAppDoesNotUse() throws {
        for path in ["WBW/Info.plist", "WBW/Info-Debug.plist"] {
            let dict = try plist(path)
            XCTAssertNil(dict["NSPhotoLibraryUsageDescription"],
                         "\(path) ขอสิทธิ์คลังรูปทั้งที่ใช้ PhotosPicker ซึ่งไม่ต้องขอ")
            // แท็บ SU RUN เรียก CMPedometer จริงตั้งแต่ 2026-08-19 — ไม่มีคีย์นี้แล้วแอปจะ
            // แครชทันทีที่กด "เริ่มเดิน" บนเครื่องจริง (CoreMotion บังคับ ไม่ใช่แค่เตือน)
            let motion = dict["NSMotionUsageDescription"] as? String
            XCTAssertFalse((motion ?? "").isEmpty,
                           "\(path) ขาดคำอธิบายสิทธิ์เซ็นเซอร์ความเคลื่อนไหว ทั้งที่ SURunTracker ใช้ CMPedometer")
        }
    }

    /// เคยไม่มีคีย์นี้เพราะไม่มีฟีเจอร์ไหนใช้ — ตอนนี้ SOS ใช้จริง คีย์จึงต้องมี **และ**
    /// ต้องมีโค้ดที่ import CoreLocation จริง · เทสนี้ค้ำทั้งสองทาง: คีย์ที่ไม่มีฟีเจอร์
    /// รองรับคือเหตุให้ App Review ตีกลับ ส่วนฟีเจอร์ที่ไม่มีคีย์คือ SOS ที่ไม่มีพิกัด
    /// โดยไม่มี error ให้เห็น
    func testLocationPermissionStringExistsInBothPlistsBecauseSOSUsesIt() throws {
        for path in ["WBW/Info.plist", "WBW/Info-Debug.plist"] {
            let dict = try plist(path)
            let value = dict["NSLocationWhenInUseUsageDescription"] as? String
            XCTAssertNotNil(value, "\(path) ขาดข้อความขอสิทธิ์ตำแหน่ง ทั้งที่ SOS ใช้")
            XCTAssertFalse((value ?? "").isEmpty)
            XCTAssertTrue((value ?? "").contains("ฉุกเฉิน"),
                          "ข้อความต้องบอกว่าใช้ทำอะไร ไม่ใช่ข้อความกลางๆ")
        }
    }

    func testPrivacyManifestDeclaresPreciseLocation() throws {
        let manifest = try plist("WBW/PrivacyInfo.xcprivacy")
        let types = manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? []
        let location = types.first { ($0["NSPrivacyCollectedDataType"] as? String)
            == "NSPrivacyCollectedDataTypePreciseLocation" }
        XCTAssertNotNil(location, "เก็บพิกัดแล้วต้องประกาศใน privacy manifest")
        XCTAssertEqual(location?["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
        XCTAssertEqual(location?["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
    }

    /// คีย์กับการใช้งานจริงต้องมาคู่กันเสมอ — ค้ำอีกทางหนึ่งของเทสด้านบน
    func testTheProjectActuallyImportsCoreLocation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let sources = FileManager.default.enumerator(at: root.appendingPathComponent("WBW"),
                                                     includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        let importsCoreLocation = sources.contains {
            (try? String(contentsOf: $0, encoding: .utf8))?.contains("import CoreLocation") == true
        }
        XCTAssertTrue(importsCoreLocation, "มีคีย์ขอตำแหน่งแต่ไม่มีไฟล์ไหน import CoreLocation")
    }

    func testEncryptionDeclarationPresentSoEveryUploadDoesNotAskAgain() throws {
        for path in ["WBW/Info.plist", "WBW/Info-Debug.plist"] {
            let dict = try plist(path)
            XCTAssertEqual(dict["ITSAppUsesNonExemptEncryption"] as? Bool, false,
                           "\(path) ขาด ITSAppUsesNonExemptEncryption")
        }
    }

    func testApsEnvironmentMatchesItsConfiguration() throws {
        XCTAssertEqual(try plist("WBW/WBW-Debug.entitlements")["aps-environment"] as? String,
                       "development")
        XCTAssertEqual(try plist("WBW/WBW-Release.entitlements")["aps-environment"] as? String,
                       "production",
                       "build ที่ขึ้น store ถ้าเป็น development จะไม่ได้ push สักอันโดยไม่มี error")
    }

    /// UserDefaults อยู่ในรายการ required-reason API ของ Apple และแอปนี้ใช้ 13 ไฟล์
    /// ถ้าไม่ประกาศ App Store Connect ตีกลับตั้งแต่ validate ยังไม่ทันเข้ารีวิว
    func testPrivacyManifestDeclaresUserDefaults() throws {
        let manifest = try plist("WBW/PrivacyInfo.xcprivacy")

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)

        let apis = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let userDefaults = apis.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
        XCTAssertNotNil(userDefaults, "privacy manifest ไม่ได้ประกาศ UserDefaults")
        XCTAssertEqual(userDefaults?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
    }
}
