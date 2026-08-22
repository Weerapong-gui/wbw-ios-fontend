import XCTest

/// SU RUN ถูกถอดออกจากโปรเจกต์ทั้งฟีเจอร์ (เจ้าของงานตัดสินใจ 2026-08-22 ว่างานจะไม่มีกิจกรรมนี้)
///
/// **มีเทสนี้เพราะการถอดฟีเจอร์ทิ้งร่องรอยได้หลายที่พร้อมกัน** และร่องรอยที่แพงที่สุดคือ
/// `NSMotionUsageDescription` — สิทธิ์ที่ขอไว้โดยไม่มีโค้ดไหนได้ใช้จริง คือเหตุให้ App Review
/// ตีกลับตรง ๆ (Guideline 5.1.1) และเป็นรอยเดียวกับที่เพิ่งถอด `PhotosorVideos` ออกจาก
/// privacy manifest ไปด้วยเหตุผลเดียวกันเป๊ะ
///
/// อีกด้านหนึ่งของเหรียญก็จริงเหมือนกัน: วันไหนมีคนเอา `CMPedometer` กลับเข้ามาโดยไม่ใส่คีย์
/// แอปจะ **crash ทันที** ที่เรียก (CoreMotion บังคับ ไม่ใช่แค่เตือน) เทสนี้จึงผูกสองอย่างเข้าด้วยกัน
/// ไม่ใช่แค่ยืนยันว่าคีย์หายไปแล้ว
final class SURunRemovalTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func swiftSources() throws -> [String] {
        try FileManager.default
            .subpathsOfDirectory(atPath: Self.repoRoot.appendingPathComponent("WBW").path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
    }

    /// การ์ด "แข่งนับก้าว" ต้องหายไปพร้อมฟีเจอร์
    ///
    /// การ์ดโฆษณาว่า "สะสมก้าวให้ได้มากที่สุด แล้วไต่อันดับกระดานผู้นำ" ซึ่งแอปทำไม่ได้แล้ว —
    /// โฆษณาความสามารถที่ไม่มีคือเหตุตีกลับตรง ๆ ไม่ต่างจากปุ่มที่กดไม่ได้
    func testTheStepCompetitionCardIsGoneToo() throws {
        let view = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("WBW/ActivitiesView.swift"),
            encoding: .utf8)
        let code = view.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertFalse(code.contains("event_step_comp"),
                       "การ์ดแข่งนับก้ายังอยู่ ทั้งที่แอปนับก้าวไม่ได้แล้ว")

        for language in ["th", "en"] {
            let table = try String(
                contentsOf: Self.repoRoot
                    .appendingPathComponent("WBW/\(language).lproj/Localizable.strings"),
                encoding: .utf8)
            XCTAssertFalse(table.contains("event_step_comp"),
                           "\(language) ยังมีคีย์ของการ์ดที่ถอดไปแล้ว")
        }
    }

    /// จอ QR เต็มจอถูกลบไปด้วย (โค้ดตาย ไม่มีใครอ้างถึง) แต่ **ตัวสร้าง QR ต้องอยู่ต่อ** —
    /// หน้าบัตรผู้เข้าร่วมเรียกใช้จริง จึงถูกแยกออกมาเป็น `WBW/QRCode.swift`
    func testQRGeneratorSurvivedTheScreenItLivedIn() throws {
        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath:
            Self.repoRoot.appendingPathComponent("WBW/MyQRCodeView.swift").path),
            "MyQRCodeView ยังอยู่")
        XCTAssertTrue(fm.fileExists(atPath:
            Self.repoRoot.appendingPathComponent("WBW/QRCode.swift").path),
            "ตัวสร้าง QR หายไปด้วย — หน้าบัตรผู้เข้าร่วมจะคอมไพล์ไม่ผ่าน")
    }

    /// ไฟล์กับโฟลเดอร์ต้องไม่เหลืออยู่จริง ไม่ใช่แค่ไม่มีใครเรียก
    func testNoSURunFilesRemain() throws {
        for path in ["WBW/SURun", "WBW/SURunView.swift", "WBW/Resources/route_wbw.json"] {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: Self.repoRoot.appendingPathComponent(path).path),
                "\(path) ยังอยู่ — ลบให้ครบแล้วรัน `xcodegen generate`")
        }
    }

    /// สิทธิ์เซ็นเซอร์ความเคลื่อนไหวต้องหายไปพร้อมกัน — `CMPedometer` เป็นผู้ใช้รายเดียว
    ///
    /// `CMMotionManager` ที่ `Scene3D/GyroParallax.swift` ใช้ **ไม่ต้องขอสิทธิ์นี้** (ไจโรกับ
    /// device-motion ไม่ใช่ข้อมูลกิจกรรม) จึงไม่ต้องเก็บคีย์ไว้เผื่อมัน
    func testMotionPermissionRemovedTogetherWithItsOnlyUser() throws {
        for file in ["WBW/Info.plist", "WBW/Info-Debug.plist"] {
            let data = try Data(contentsOf: Self.repoRoot.appendingPathComponent(file))
            let dict = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            XCTAssertNil(dict["NSMotionUsageDescription"], """
                \(file) ยังขอสิทธิ์เซ็นเซอร์ความเคลื่อนไหว ทั้งที่ไม่มีโค้ดไหนใช้ CMPedometer แล้ว
                สิทธิ์ที่ขอโดยไม่มีอะไรได้ใช้คือเหตุตีกลับตรง ๆ ตาม Guideline 5.1.1
                """)
        }
        for file in ["WBW/th.lproj/InfoPlist.strings", "WBW/en.lproj/InfoPlist.strings"] {
            let text = try String(
                contentsOf: Self.repoRoot.appendingPathComponent(file), encoding: .utf8)
            XCTAssertFalse(text.contains("NSMotionUsageDescription"),
                           "\(file) ยังมีคำแปลของสิทธิ์ที่ถอดไปแล้ว")
        }
    }

    /// ค้ำอีกทาง — เอา CMPedometer กลับมาเมื่อไหร่ ต้องเอาคีย์กลับมาด้วย ไม่งั้น crash
    func testNothingUsesPedometerAnyMore() throws {
        for file in try swiftSources() {
            let text = try String(
                contentsOf: Self.repoRoot.appendingPathComponent("WBW/\(file)"), encoding: .utf8)
            XCTAssertFalse(text.contains("CMPedometer"), """
                WBW/\(file) ใช้ CMPedometer — ต้องใส่ NSMotionUsageDescription กลับเข้า plist
                ทั้งสองใบก่อน ไม่งั้นแอปแครชทันทีที่เรียก (CoreMotion บังคับ ไม่ใช่แค่เตือน)
                แล้วแก้เทสนี้ให้ตรงกับความจริงใหม่
                """)
            XCTAssertFalse(text.contains("SURun"),
                           "WBW/\(file) ยังอ้างถึง SU RUN ที่ถอดออกไปแล้ว")
        }
    }

    // MARK: - ข้อความที่ผู้ใช้กับผู้ตรวจอ่าน

    /// ค่าของคีย์หนึ่งในไฟล์ `.strings` — เทียบเฉพาะบรรทัดนั้น ไม่ใช่ทั้งไฟล์
    /// (ไฟล์ `Localizable.strings` มีคำว่า distance อยู่ในคีย์อื่นด้วยได้)
    private func value(of key: String, inStringsFile path: String) throws -> String {
        let text = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(path), encoding: .utf8)
        let line = text.components(separatedBy: .newlines)
            .first { $0.hasPrefix("\"\(key)\"") }
        return try XCTUnwrap(line, "ไม่มีคีย์ \(key) ใน \(path)")
    }

    /// ข้อความขอสิทธิ์ตำแหน่งต้องเล่าเฉพาะสิ่งที่แอปทำจริง
    ///
    /// ทั้งสามที่เคยเขียนว่าใช้ตำแหน่ง "จับระยะทางกับความเร็วตอนกดเริ่มเดิน" ซึ่งคือ SU RUN
    /// ที่ถอดไปแล้ว · ผู้ตรวจกดหาแล้วไม่เจอ = Guideline 5.1.1 ตรง ๆ และยังขัดกับหน้านโยบาย
    /// บนเว็บ (URL ที่กรอกใน App Store Connect) ที่บอกว่าใช้สองอย่าง — Apple เทียบสองที่นี้เอง
    func testLocationPurposeStringsOnlyPromiseWhatTheAppStillDoes() throws {
        let banned = ["จับระยะทาง", "ความเร็ว", "distance", "pace"]

        for file in ["WBW/Info.plist", "WBW/Info-Debug.plist"] {
            let data = try Data(contentsOf: Self.repoRoot.appendingPathComponent(file))
            let dict = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            let purpose = try XCTUnwrap(
                dict["NSLocationWhenInUseUsageDescription"] as? String,
                "\(file) ไม่มีข้อความขอสิทธิ์ตำแหน่ง")
            for word in banned {
                XCTAssertFalse(purpose.contains(word), """
                    \(file) ยังบอกผู้ใช้ว่าตำแหน่งใช้ "\(word)" ทั้งที่ฟีเจอร์นั้นไปพร้อม SU RUN
                    เหลือสองอย่างที่ทำจริง: แผนที่พื้นที่งาน กับพิกัดตอนกด SOS
                    """)
            }
        }

        for file in ["WBW/th.lproj/InfoPlist.strings", "WBW/en.lproj/InfoPlist.strings"] {
            let line = try value(of: "NSLocationWhenInUseUsageDescription", inStringsFile: file)
            for word in banned {
                XCTAssertFalse(line.contains(word),
                               "\(file) ยังแปลข้อความขอสิทธิ์แบบเก่าที่มีคำว่า \"\(word)\"")
            }
        }

        // จออธิบายก่อนกล่องของระบบ (LocationPrimer) — ผู้ตรวจเห็นก่อนกล่องขอสิทธิ์เสมอ
        for file in ["WBW/th.lproj/Localizable.strings", "WBW/en.lproj/Localizable.strings"] {
            let line = try value(of: "location_primer_body", inStringsFile: file)
            for word in banned {
                XCTAssertFalse(line.contains(word),
                               "\(file): จออธิบายยังบอกว่าจับ \"\(word)\" ให้ตรงกับ plist ด้วย")
            }
            XCTAssertFalse(line.contains("3 อย่าง") || line.contains("three things"),
                           "\(file): เหลือสองอย่างแล้ว ตัวเลขในประโยคต้องตามไปด้วย")
        }
    }

    /// คีย์ที่ตายไปพร้อมฟีเจอร์ — ไม่มีโค้ดไหนเรียก แต่ยังนอนอยู่ในตารางแปลทั้งสองภาษา
    func testDeadDistanceCopyIsGone() throws {
        for language in ["th", "en"] {
            let table = try String(
                contentsOf: Self.repoRoot
                    .appendingPathComponent("WBW/\(language).lproj/Localizable.strings"),
                encoding: .utf8)
            XCTAssertFalse(table.contains("home_base_distance"),
                           "\(language) ยังมีคีย์ระยะทางที่ไม่มีโค้ดไหนใช้แล้ว")
        }
    }
}
