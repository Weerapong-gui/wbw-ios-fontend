import XCTest

/// สัญญาของฟีเจอร์นับก้าว — **ไฟล์นี้คือ `SURunRemovalTests` ที่ถูกกลับทิศสามข้อ**
///
/// เดิมไฟล์นี้บังคับว่า "ห้ามมี `CMPedometer` และห้ามมี `NSMotionUsageDescription`" เพราะ
/// SU RUN ถูกถอดทั้งชุดเมื่อ 2026-08-22 · **เทสเดิมไม่ได้ผิด เจตนางานเปลี่ยน** — 2026-08-25
/// เจ้าของงานสั่งให้เอาการนับก้าวกลับมาที่แท็บแผนที่ แบบเดียวกับที่ฝั่ง Android มีอยู่แล้ว
/// (`walk/WalkTracker.kt` + `walk/WalkTrackingService.kt`)
///
/// **สามข้อที่กลับทิศ** (ห้ามมี → ต้องมี): ใครใช้ `CMPedometer` ได้บ้าง, สิทธิ์
/// `NSMotionUsageDescription` ต้องครบกี่ที่, และคำอธิบายสิทธิ์ตำแหน่งพูดถึงการจับระยะทางได้แล้ว
///
/// **สามข้อที่คงไว้เหมือนเดิม**: ไฟล์/โฟลเดอร์ `SURun` ต้องไม่กลับมา, การ์ด "แข่งนับก้าว"
/// ต้องไม่กลับมา, คีย์ `home_base_distance` ที่ตายแล้วต้องไม่กลับมา — ของใหม่ไม่ใช่ SU RUN
/// ไม่มีกระดานผู้นำ ไม่มีการแข่ง ไม่มีการส่งอะไรขึ้น backend (ฝั่ง Android ก็ไม่ส่ง
/// — `WbwApi.kt` ไม่มี endpoint เรื่องเดินสักตัว)
///
/// สิ่งที่ยังจริงเหมือนเดิมและเป็นเหตุผลที่ไฟล์นี้ต้องมีอยู่ต่อ: `CMPedometer` กับ
/// `NSMotionUsageDescription` **ผูกกันตายตัว** — เรียก `CMPedometer` โดยไม่มีคีย์ในสอง plist
/// แอปจะ **crash ทันที** ไม่ใช่แค่เตือน (CoreMotion บังคับ) · และคีย์ที่ประกาศไว้โดยไม่มีโค้ดไหน
/// ได้ใช้จริงคือเหตุตีกลับตรง ๆ ตาม Guideline 5.1.1 · เทสนี้ค้ำทั้งสองทิศพร้อมกัน
final class WalkTrackingContractTests: XCTestCase {


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
    ///
    /// **`WBW/Resources/route_wbw.json` ถูกถอดออกจากรายการนี้เมื่อ 2026-08-24** — ไฟล์กลับเข้ามา
    /// จริง แต่คนละหน้าที่กับตอนที่มันถูกลบ: ตอนนั้นมันเป็นข้อมูลของ SU RUN (จับระยะที่เดินไปแล้ว)
    /// ตอนนี้มันคือ **เส้นทางที่วาดบนแผนที่ 2 มิติ** (`TrailRoute`) ซึ่งไม่ได้จับอะไรเลย ไม่แตะ
    /// เซ็นเซอร์ ไม่มี background location · ของที่ห้ามกลับมาจริง ๆ คือโค้ดนับก้าว ซึ่งถูกค้ำไว้ที่
    /// `testNothingUsesPedometerAnyMore` กับ `testMotionPermissionRemovedTogetherWithItsOnlyUser`
    /// ในไฟล์นี้อยู่แล้ว — สองข้อนั้นคือหัวใจของการถอด SU RUN ไม่ใช่ชื่อไฟล์ข้อมูล
    func testNoSURunFilesRemain() throws {
        for path in ["WBW/SURun", "WBW/SURunView.swift"] {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: Self.repoRoot.appendingPathComponent(path).path),
                "\(path) ยังอยู่ — ลบให้ครบแล้วรัน `xcodegen generate`")
        }
    }

    /// สิทธิ์เซ็นเซอร์ความเคลื่อนไหวต้องครบ **สี่ที่ ไม่ใช่สองที่**
    ///
    /// สอง plist ทำให้แอปไม่แครชตอนเรียก `CMPedometer` · **อีกสองไฟล์แปลคือส่วนที่ลืมกันบ่อย**
    /// และเป็นรอยที่ทำให้โดนตีกลับจริง: ขาดคำแปลแล้วผู้ตรวจที่เปิดเครื่องเป็นภาษาอังกฤษจะเห็น
    /// กล่องขอสิทธิ์เป็นภาษาไทย = Guideline 5.1.1
    ///
    /// `CMMotionManager` ที่ `Scene3D/GyroParallax.swift` ใช้ **ไม่ต้องขอสิทธิ์นี้** (ไจโรกับ
    /// device-motion ไม่ใช่ข้อมูลกิจกรรม) — คีย์นี้มีไว้ให้ `CMPedometer` รายเดียว
    func testMotionPermissionIsDeclaredEverywhereItHasToBe() throws {
        for file in ["WBW/Info.plist", "WBW/Info-Debug.plist"] {
            let data = try Data(contentsOf: Self.repoRoot.appendingPathComponent(file))
            let dict = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            let purpose = dict["NSMotionUsageDescription"] as? String
            XCTAssertNotNil(purpose, """
                \(file) ไม่มี NSMotionUsageDescription แต่มีโค้ดเรียก CMPedometer อยู่
                แอปจะแครชทันทีที่เรียก (CoreMotion บังคับ ไม่ใช่แค่เตือน)
                """)
            XCTAssertFalse((purpose ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(file): ข้อความว่างเปล่าเท่ากับไม่มี ผู้ใช้จะเห็นกล่องเปล่า")
        }
        for file in ["WBW/th.lproj/InfoPlist.strings", "WBW/en.lproj/InfoPlist.strings"] {
            let text = try String(
                contentsOf: Self.repoRoot.appendingPathComponent(file), encoding: .utf8)
            XCTAssertTrue(text.contains("NSMotionUsageDescription"), """
                \(file) ไม่มีคำแปลของสิทธิ์เซ็นเซอร์ความเคลื่อนไหว
                ผู้ตรวจบนเครื่องภาษาอังกฤษจะเห็นกล่องเป็นภาษาไทย = Guideline 5.1.1
                """)
        }
    }

    /// `CMPedometer` อยู่ได้ **ไฟล์เดียว** คือตัว tracker
    ///
    /// ไม่ได้ห้ามใช้แล้ว แต่ห้ามกระจาย — เซ็นเซอร์ที่ถูกเรียกจากหลายที่แปลว่ามีหลายที่ที่ต้อง
    /// จำกันเองว่าปิดหรือยัง และมีหลายที่ที่ต้องผ่านประตูโหมดเดโม่ · ให้มีเจ้าของคนเดียว
    /// แล้วจอไปอ่าน `@Published` ของมันเอา
    ///
    /// ชื่อ `SURun` ยัง **ห้ามกลับมา** — ของใหม่ไม่ใช่ฟีเจอร์นั้น (ดูคอมเมนต์หัวไฟล์)
    func testOnlyTheTrackerTouchesThePedometer() throws {
        var users: [String] = []
        for file in try swiftSources() {
            let text = try String(
                contentsOf: Self.repoRoot.appendingPathComponent("WBW/\(file)"), encoding: .utf8)
            let code = text.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            if code.contains("CMPedometer") { users.append(file) }
            XCTAssertFalse(code.contains("SURun"),
                           "WBW/\(file) อ้างถึง SU RUN ที่ถอดออกไปแล้ว — ของใหม่ไม่ใช่ฟีเจอร์นั้น")
        }
        XCTAssertEqual(users, ["Walk/WalkTracker.swift"], """
            CMPedometer ต้องถูกเรียกจาก Walk/WalkTracker.swift ที่เดียว
            เจอที่: \(users.isEmpty ? "ไม่เจอเลย" : users.joined(separator: ", "))
            """)
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

    /// ข้อความขอสิทธิ์ตำแหน่งต้องเล่าสิ่งที่แอปทำจริง — **ตอนนี้จับระยะทางแล้ว**
    ///
    /// เทสข้อนี้เคย **แบน** คำว่า `จับระยะทาง`/`distance` เพราะฟีเจอร์นั้นไปพร้อม SU RUN
    /// ตอนนี้กลับทิศ: แอปสะสมระยะจาก GPS ระหว่างเดินจริง คำอธิบายจึงต้องพูดถึงมัน
    ///
    /// เหตุผลเดิมยังใช้ได้ทุกตัวอักษร แค่กลับด้าน — สิ่งที่ผิดคือ "ข้อความไม่ตรงกับสิ่งที่แอปทำ"
    /// ไม่ว่าจะขาดหรือเกิน · Apple เทียบข้อความนี้กับหน้านโยบายบนเว็บ (URL ที่กรอกใน ASC) เอง
    ///
    /// เช็คทั้งสอง plist, ทั้งสองไฟล์แปล และจออธิบายก่อนกล่องของระบบ (`location_primer_body`)
    /// ซึ่งผู้ตรวจเห็นก่อนกล่องขอสิทธิ์เสมอ — สามที่นี้ต้องเล่าเรื่องเดียวกัน
    func testLocationPurposeStringsMentionTheDistanceTrackingItNowDoes() throws {
        /// คำที่ยืนยันว่า "พูดถึงระยะทางแล้ว" แยกตามภาษาของไฟล์
        func distanceWord(for path: String) -> String {
            path.contains("/en.lproj/") ? "distance" : "ระยะ"
        }

        for file in ["WBW/Info.plist", "WBW/Info-Debug.plist"] {
            let data = try Data(contentsOf: Self.repoRoot.appendingPathComponent(file))
            let dict = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            let purpose = try XCTUnwrap(
                dict["NSLocationWhenInUseUsageDescription"] as? String,
                "\(file) ไม่มีข้อความขอสิทธิ์ตำแหน่ง")
            XCTAssertTrue(purpose.contains("ระยะ"), """
                \(file) ไม่ได้บอกผู้ใช้ว่าตำแหน่งถูกใช้จับระยะทางระหว่างเดินด้วย
                ตอนนี้แอปทำสามอย่าง: แผนที่พื้นที่งาน · พิกัดตอนกด SOS · ระยะทางตอนกดเริ่มเดิน
                """)
        }

        for file in ["WBW/th.lproj/InfoPlist.strings", "WBW/en.lproj/InfoPlist.strings"] {
            let line = try value(of: "NSLocationWhenInUseUsageDescription", inStringsFile: file)
            XCTAssertTrue(line.contains(distanceWord(for: file)),
                          "\(file): คำแปลยังไม่พูดถึงการจับระยะทาง ให้ตรงกับ plist")
        }

        for file in ["WBW/th.lproj/Localizable.strings", "WBW/en.lproj/Localizable.strings"] {
            let line = try value(of: "location_primer_body", inStringsFile: file)
            XCTAssertTrue(line.contains(distanceWord(for: file)),
                          "\(file): จออธิบายก่อนกล่องขอสิทธิ์ยังไม่พูดถึงระยะทาง ให้ตรงกับ plist")
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
