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

    // MARK: - ตัวตนของแอปบน App Store

    /// **bundle id ตัดสินว่า build ไปลง record ไหนบน App Store** — ไม่ใช่ชื่อโปรเจกต์ ไม่ใช่ scheme
    ///
    /// ตั้งแต่ 2026-08-25 แอปนี้ส่งขึ้น record `th.ac.mfu.su.clubfair` (Apple ID 6802118399)
    /// ซึ่งเป็นรายการที่ผ่านรีวิวไปแล้วที่ 1.0 · ค่าเดิม `th.ac.mfu.wbwSwift` เป็นอีก record หนึ่ง
    ///
    /// พลาดตรงนี้แล้ว **ไม่มีอะไรฟ้องตอน build เลย** — จะรู้ตอนอัปขึ้น ASC แล้ว build ไปโผล่ผิด
    /// รายการ (หรือถูกปฏิเสธเพราะเลข build ซ้ำกับของรายการนั้น) ซึ่งเสียรอบไปแล้ว
    func testTheBundleIdentifierPointsAtTheIntendedAppStoreRecord() throws {
        let yml = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertTrue(yml.contains("PRODUCT_BUNDLE_IDENTIFIER: th.ac.mfu.su.clubfair\n"),
                      "bundle id ของ app target ไม่ใช่ของ record ที่ตั้งใจส่ง")
    }

    /// Keychain service **ต้องไม่เท่ากับ bundle id**
    ///
    /// ของที่นอนอยู่ใน Keychain ใต้ service ชื่อเดียวกับ bundle นั้นคือ JWT ของแอป Club Fair
    /// ซึ่งเป็นคนละระบบผู้ใช้กัน (คนละ route prefix บน SUS) · ใช้ชื่อเดียวกันแล้วแอปจะหยิบ token
    /// ของแอปเก่ามายิง ได้ 401 แล้วเด้งผู้ใช้ออกทันทีที่เปิดครั้งแรกหลังอัปเดต
    func testTheKeychainServiceCannotCollideWithTheAppItReplaces() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("WBW/TokenStore.swift"), encoding: .utf8)
        let code = source.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertFalse(code.contains(#"service: String = "th.ac.mfu.su.clubfair""#),
                       "Keychain service ชนกับของแอปเดิมที่ bundle นี้เคยเป็น")
    }

    // MARK: - รองรับ iPad

    /// แอปประกาศตัวว่ารองรับ iPad จริง
    ///
    /// **แยกเป็นเทสเพราะค่านี้เปลี่ยนกลับได้ง่ายและไม่มีอะไรฟ้อง** — `project.yml` เป็น
    /// source of truth ส่วน `.xcodeproj` ถูก gitignore ไว้ ใครสร้างโปรเจกต์ใหม่จากไฟล์ที่
    /// ถูกแก้กลับเป็น "1" จะได้แอป iPhone-only กลับมาโดยที่โค้ดจอทั้งหมดยังดูรองรับ iPad อยู่
    func testProjectBuildsForIPadNotJustIPhone() throws {
        let yml = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertTrue(yml.contains(#"TARGETED_DEVICE_FAMILY: "1,2""#),
                      "device family ไม่ใช่ 1,2 — แอปจะรันบน iPad ในโหมดย่อส่วนของ iPhone")
    }

    /// `LSRequiresIPhoneOS` ต้องเป็น true **และนี่ถูกแล้ว**
    ///
    /// ชื่อคีย์หลอก: มันไม่ได้แปลว่า "iPhone เท่านั้น" แต่แปลว่า "บันเดิลนี้เป็นแอป iOS
    /// ไม่ใช่ Catalyst/macOS" แอป universal ทุกตัวมีคีย์นี้ · สิ่งที่คุมไอดิอมจริงคือ
    /// `UIDeviceFamily` ซึ่ง XcodeGen สร้างจาก `TARGETED_DEVICE_FAMILY`
    ///
    /// มีเทสนี้เพื่อกันคนที่มาเปิด iPad แล้วเห็นชื่อคีย์นี้แล้วลบทิ้งเพราะเข้าใจว่ามันขวางอยู่ —
    /// ผลของการลบคือแอปไปโผล่เป็น "Designed for iPad" บน Mac ชิป Apple ซึ่งไม่มีใครต้องการ
    /// (ฉาก RealityKit กับกล้องสแกน QR บนแทร็กแพด Mac คือภาระซัพพอร์ตล้วน ๆ)
    func testLSRequiresIPhoneOSStaysTrueBecauseItDoesNotMeanWhatItSounds() throws {
        for path in ["WBW/Info.plist", "WBW/Info-Debug.plist"] {
            XCTAssertEqual(try plist(path)["LSRequiresIPhoneOS"] as? Bool, true,
                           "\(path): คีย์นี้ไม่ได้จำกัดแอปไว้ที่ iPhone — ลบแล้วแอปจะไปโผล่บน Mac")
        }
    }

    /// หน้าต่างเดียวต่อแอปเท่านั้น
    ///
    /// ค่านี้ **ไม่ได้** บล็อก Split View ข้างแอปอื่น และไม่ได้บล็อกการย่อขยายหน้าต่างบน
    /// iPadOS 26 — มันบล็อกแค่ "หลายหน้าต่างของ WBW เอง" ซึ่งต้องบล็อก:
    /// `WBWApp` ประกาศ `@StateObject` เจ็ดตัวที่ระดับ App ซึ่ง SwiftUI แชร์ข้ามทุก scene
    /// สองหน้าต่างจะแชร์ `ForestSceneHost` ใบเดียวกัน ซึ่งเป็นโมเดล claim-token เจ้าเดียว
    /// (ดูคอมเมนต์ยาวที่ `claimScene()`) บวก `AVCaptureSession` สองตัวและ `RealityView` สองตัว
    func testOnlyOneWindowPerAppBecauseAppScopeStateIsSharedAcrossScenes() throws {
        for path in ["WBW/Info.plist", "WBW/Info-Debug.plist"] {
            let manifest = try plist(path)["UIApplicationSceneManifest"] as? [String: Any]
            XCTAssertEqual(manifest?["UIApplicationSupportsMultipleScenes"] as? Bool, false,
                           "\(path): เปิดหลายหน้าต่างแล้ว store ที่ระดับ App จะถูกแชร์ข้ามหน้าต่าง")
        }
    }

    /// `UIRequiresFullScreen` ต้องไม่มี
    ///
    /// ถูกเลิกใช้และถูกเมินบน iPadOS 26 (ทุกแอปย่อขยายหน้าต่างได้อยู่ดี) ใส่ไว้จึงไม่มีผล
    /// อะไรนอกจากเป็นคำถามที่ผู้ตรวจ App Review หยิบขึ้นมาถามฟรี ๆ
    func testNoDeprecatedFullScreenRequirement() throws {
        for path in ["WBW/Info.plist", "WBW/Info-Debug.plist"] {
            XCTAssertNil(try plist(path)["UIRequiresFullScreen"],
                         "\(path): คีย์นี้ถูกเลิกใช้แล้ว มีแต่ทำให้ถูกถาม")
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
            // **คีย์ `NSMotionUsageDescription` ย้ายออกจากเทสนี้แล้ว ไม่ได้หายไปเฉย ๆ**
            // มันกลับทิศมาสองรอบ: เคยต้องมี (แท็บ SU RUN ใช้ CMPedometer) → ต้องไม่มี
            // (SU RUN ถูกถอด 2026-08-22) → ต้องมีอีกครั้ง (ฟีเจอร์นับก้าวกลับมา 2026-08-25)
            // · ที่นี่เป็นรายการของ "สิทธิ์ที่แอปไม่ได้ใช้" คีย์ที่แอปใช้จริงจึงไม่ควรอยู่ใน
            // รายการนี้ตั้งแต่แรก — ตัวค้ำอยู่ที่ `WalkTrackingContractTests` ซึ่งผูกคีย์นี้
            // เข้ากับผู้ใช้รายเดียวของมันทั้งสองทิศ (มีโค้ด = ต้องมีคีย์ครบสี่ที่)
        }
    }

    /// เลขเวอร์ชันอยู่สามที่ ต้องขยับพร้อมกันเสมอ
    ///
    /// `project.yml` เป็นต้นทางของ build setting ส่วนสอง plist คือค่าที่ฝังไปกับ .ipa จริง
    /// (`GENERATE_INFOPLIST_FILE: NO` — Xcode ไม่ได้เขียนให้) · บั๊มไม่ครบแล้ว**ไม่มีอะไรฟ้อง**
    /// ตอน build: จะรู้ตอนอัปขึ้น ASC แล้วโดนปฏิเสธว่าเลขซ้ำ ซึ่งเสียรอบไปแล้ว
    func testBuildNumberIsTheSameInProjectYmlAndBothPlists() throws {
        let projectYml = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("project.yml"), encoding: .utf8)

        func setting(_ key: String) throws -> String {
            let line = try XCTUnwrap(
                projectYml.components(separatedBy: .newlines)
                    .first { $0.contains("\(key):") },
                "project.yml ไม่มี \(key)")
            return line.components(separatedBy: ":").last?
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"")) ?? ""
        }

        let build = try setting("CURRENT_PROJECT_VERSION")
        let marketing = try setting("MARKETING_VERSION")

        for path in ["WBW/Info.plist", "WBW/Info-Debug.plist"] {
            let dict = try plist(path)
            XCTAssertEqual(dict["CFBundleVersion"] as? String, build, """
                \(path): CFBundleVersion ไม่ตรงกับ CURRENT_PROJECT_VERSION ใน project.yml
                (\(build)) — บั๊มไม่ครบทุกที่ ASC จะปฏิเสธไฟล์ตอนอัปว่าเลขซ้ำ
                """)
            XCTAssertEqual(dict["CFBundleShortVersionString"] as? String, marketing,
                           "\(path): CFBundleShortVersionString ไม่ตรงกับ MARKETING_VERSION (\(marketing))")
        }
    }

    /// background mode ต้องมีคู่กับโค้ดที่รับมันจริง — Guideline 2.5.4
    ///
    /// `remote-notification` มีความหมายเดียวคือ "แอปตื่นขึ้นมาทำงานตอนได้ push แบบเงียบ"
    /// ซึ่งต้องมี `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` รับ ·
    /// push ที่ผู้ใช้เห็น (alert) ส่งถึงเครื่องได้โดยไม่ต้องประกาศ mode นี้เลย — เส้นทางนั้น
    /// อยู่ที่ `UNUserNotificationCenterDelegate` (`willPresent` / `didReceive`) ·
    /// ประกาศ mode ที่ไม่มีใครรับคือของที่ผู้ตรวจถามกลับได้ตรง ๆ
    ///
    /// ค้ำสองทาง: วันไหนมีคนเพิ่ม handler เข้ามาจริง ต้องเอา mode กลับเข้า plist ด้วย
    /// ไม่งั้น push เงียบจะไม่ปลุกแอปเลยโดยไม่มี error ให้เห็น
    func testBackgroundModesMatchWhatTheAppActuallyHandles() throws {
        let appDelegate = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("WBW/AppDelegate.swift"),
            encoding: .utf8)
        let handlesSilentPush = appDelegate.contains("didReceiveRemoteNotification")

        for path in ["WBW/Info.plist", "WBW/Info-Debug.plist"] {
            let modes = try plist(path)["UIBackgroundModes"] as? [String] ?? []
            XCTAssertEqual(modes.contains("remote-notification"), handlesSilentPush, """
                \(path): background mode `remote-notification` กับ handler ใน AppDelegate
                ต้องมีหรือไม่มีพร้อมกัน · ตอนนี้ plist \(modes.contains("remote-notification") ? "ประกาศไว้" : "ไม่ประกาศ")
                แต่โค้ด \(handlesSilentPush ? "มี handler" : "ไม่มี handler")
                """)
            XCTAssertTrue(modes.allSatisfy { $0 == "remote-notification" }, """
                \(path) ประกาศ background mode อื่นเพิ่ม (\(modes)) — ทุกตัวต้องมีโค้ดที่ใช้จริง
                ไม่งั้นเป็นเหตุตีกลับตาม Guideline 2.5.4
                """)
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

    /// คีย์ทุกตัวที่ต้องแปล — สามใบเป็นกล่องขอสิทธิ์ที่ผู้รีวิวเห็นแน่นอน ส่วน
    /// `CFBundleDisplayName` คือชื่อใต้ไอคอนบนจอโฮม
    private static let infoPlistKeysNeedingTranslation = [
        "CFBundleDisplayName",
        "NSCameraUsageDescription",
        "NSLocationWhenInUseUsageDescription",
    ]

    /// **แอปประกาศว่ารองรับอังกฤษ แต่กล่องขอสิทธิ์เป็นไทยล้วน**
    ///
    /// `CFBundleLocalizations = [th, en]` แต่ค่าของ `NS*UsageDescription` เป็นลิเทอรัลไทย
    /// ฝังอยู่ใน plist ตรง ๆ และไม่มี `InfoPlist.strings` ที่ไหนเลยใน repo — iOS จึงไม่มีอะไรให้
    /// เลือกมาแสดง ผู้รีวิว App Store บนเครื่องภาษาอังกฤษเห็นกล่องขอกล้อง/ตำแหน่ง/เซ็นเซอร์
    /// เป็นภาษาไทยทั้งสามใบ ซึ่ง Guideline 5.1.1 บังคับว่าต้องอธิบายให้ผู้ใช้เข้าใจ
    ///
    /// ตรวจว่ามีครบ **ทั้งสองภาษา** และ **ครบทุกคีย์** — ขาดคีย์เดียวคือกล่องนั้นตกกลับไปเป็น
    /// ค่าใน plist (ไทย) เงียบ ๆ โดยไม่มี error ไม่มี warning ตอน build
    func testPermissionPromptsAreTranslatedForEveryDeclaredLanguage() throws {
        let declared = try plist("WBW/Info.plist")["CFBundleLocalizations"] as? [String] ?? []
        XCTAssertEqual(Set(declared), ["th", "en"], "รายชื่อภาษาเปลี่ยนไป ต้องแก้เทสนี้ด้วย")

        for language in declared {
            let path = "WBW/\(language).lproj/InfoPlist.strings"
            let url = Self.repoRoot.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: url),
                  let table = try? PropertyListSerialization.propertyList(from: data, format: nil)
                    as? [String: String]
            else {
                XCTFail("""
                    ไม่มี \(path) หรืออ่านไม่ออก
                    แอปประกาศว่ารองรับ \(language) แต่กล่องขอสิทธิ์จะขึ้นภาษาที่ฝังใน Info.plist แทน
                    """)
                continue
            }
            for key in Self.infoPlistKeysNeedingTranslation {
                let value = table[key] ?? ""
                XCTAssertFalse(value.isEmpty, "\(path) ขาดคีย์ \(key)")
            }
        }
    }

    /// อีกครึ่งของเทสด้านบน — ไฟล์แปลที่ **อยู่ใน repo แต่ไม่ถูกแพ็กเข้า .app** ก็เท่ากับไม่มี
    ///
    /// `project.yml` ระบุ `sources: [WBW]` ทั้งโฟลเดอร์ ไฟล์ใหม่จึงเข้ามาเอง **หลังรัน
    /// `xcodegen generate` แล้วเท่านั้น** ซึ่งเป็นขั้นที่ลืมได้ง่ายที่สุดใน repo นี้ (กติกาข้อ 1)
    /// และลืมแล้วไม่มีอะไรฟ้อง — build ผ่านปกติ กล่องขอสิทธิ์แค่ตกกลับไปเป็นไทยเงียบ ๆ
    ///
    /// อ่านจาก `Bundle.main` ไม่ใช่ `project.pbxproj` เพราะ `WBW.xcodeproj` ถูก gitignore ไว้
    /// (เป็นของที่ xcodegen สร้าง) — เทสที่อ่านไฟล์นั้นจะพังทันทีบน clone ใหม่ · เทสรันอยู่ใน
    /// โปรเซสของแอปเอง `Bundle.main` จึงเป็น .app ตัวจริงที่จะถูกส่งขึ้น store
    func testInfoPlistStringsAreBundledForEveryLanguage() throws {
        for language in ["th", "en"] {
            let path = Bundle.main.path(forResource: "InfoPlist", ofType: "strings",
                                        inDirectory: nil, forLocalization: language)
            XCTAssertNotNil(path, """
                .app ที่ build ออกมาไม่มี \(language).lproj/InfoPlist.strings
                ถ้าไฟล์อยู่ใน repo แล้วแต่ยังไม่มีตรงนี้ แปลว่ายังไม่ได้รัน `xcodegen generate`
                """)
        }
    }

    /// **ประกาศเกินก็เป็นเหตุให้ถูกตีกลับ ไม่ใช่แค่ประกาศขาด**
    ///
    /// manifest เคยประกาศ `PhotosorVideos` โดยคอมเมนต์บอกว่ามาจาก "รูปโปรไฟล์ที่ผู้ใช้เลือกเอง
    /// ผ่าน PhotosPicker" — แต่ `PhotosUI` / `PhotosPicker` / `PHPicker` ไม่มีอยู่ในโค้ดแอปเลย
    /// สักบรรทัด รูปโปรไฟล์อ่านจาก URL ของเซิร์ฟเวอร์อย่างเดียว (`ProfileStore.photoUrl`)
    ///
    /// Apple เทียบ manifest กับ Privacy Nutrition Label ที่กรอกใน App Store Connect เอง
    /// สองอันไม่ตรงกันเมื่อไหร่ก็เป็นคำถามกลับมาทันที
    func testPrivacyManifestDoesNotDeclareDataTheAppNeverCollects() throws {
        let manifest = try plist("WBW/PrivacyInfo.xcprivacy")
        let declared = (manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? [])
            .compactMap { $0["NSPrivacyCollectedDataType"] as? String }

        XCTAssertFalse(declared.contains("NSPrivacyCollectedDataTypePhotosorVideos"), """
            manifest ประกาศว่าเก็บรูป/วิดีโอ แต่แอปไม่มีตัวเลือกรูปเลยสักตัว
            """)

        // ค้ำอีกทาง: ถ้ามีคนเพิ่ม PhotosPicker เข้ามาจริงในอนาคต เทสข้างบนต้องถูกแก้พร้อมกัน
        //
        // **ตัดบรรทัดคอมเมนต์ทิ้งก่อนตรวจ** — เดิมค้นสตริงบนซอร์สดิบ คอมเมนต์ที่อธิบายว่า
        // "แอปนี้ไม่มี PhotosPicker" จึงทำให้เทสแดงเอง (เจอจริงตอนถอด `APIClient.updatePhoto`
        // แล้วเขียนคอมเมนต์บอกเหตุผลไว้แทน) · คอมเมนต์เลือกรูปไม่ได้ ตัดทิ้งไม่ได้ทำให้ค้ำหลวมลง
        // — ทรงเดียวกับที่ `SURunRemovalTests` กับ `PhotoUploadRemovalTests` ทำอยู่แล้ว
        let sources = try FileManager.default
            .subpathsOfDirectory(atPath: Self.repoRoot.appendingPathComponent("WBW").path)
            .filter { $0.hasSuffix(".swift") }
        let usesPhotos = try sources.contains { path in
            let text = try String(
                contentsOf: Self.repoRoot.appendingPathComponent("WBW/\(path)"), encoding: .utf8)
            let code = text.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            return code.contains("import PhotosUI") || code.contains("PhotosPicker")
        }
        XCTAssertFalse(usesPhotos, """
            มีโค้ดเลือกรูปเข้ามาแล้ว — ต้องประกาศ PhotosorVideos กลับเข้า manifest และแก้เทสนี้
            """)
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
