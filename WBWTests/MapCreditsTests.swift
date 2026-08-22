import XCTest
@testable import WBW

/// หน้าเครดิตในตั้งค่า — **ตัวเดียวที่กั้นระหว่างการจัดหน้าใหม่กับการผิดสัญญาอนุญาต**
///
/// เดิมเครดิตแผนที่เป็นข้อความฮาร์ดโค้ดวางทับอยู่บนจอแผนที่ พอย้ายมาเป็นแถวหนึ่งในหน้าตั้งค่า
/// มันก็กลายเป็นของที่ลบทิ้งได้ด้วยการแก้ SwiftUI สองบรรทัดโดยไม่มีอะไรฟ้อง — ทั้งที่
/// โมเดลแผนที่มาจาก maps3d.io ที่ใช้ภาพ `satlas-superes-2023` ของ Allen Institute for AI
/// กับข้อมูล OpenStreetMap ซึ่งทั้งคู่บังคับให้แสดงเครดิต
///
/// `scripts/check-localization.sh` ช่วยไม่ได้ที่นี่สองชั้น: regex ของมันจับ `Text("key")`
/// กับ `Loc.t("key")` แต่ **ไม่จับ `DocView(titleKey:bodyKey:)`** ที่หน้านี้ใช้ · และต่อให้คีย์มีอยู่
/// มันก็ไม่รู้ว่าข้างในเขียนอะไร คีย์ที่มีเนื้อหาว่างเปล่าก็ผ่านสคริปต์
final class MapCreditsTests: XCTestCase {

    /// ชื่อที่สัญญาอนุญาตบังคับให้ปรากฏ — ที่มาอยู่ใน
    /// `docs/superpowers/specs/2026-07-31-map3d-glb-design.md:23-25`
    private let mapAttribution = ["Satlas", "Allen Institute for AI", "OpenStreetMap"]

    /// ผู้สร้างโมเดล CC BY 4.0 จาก `WBW/Resources/models/CREDITS.md`
    ///
    /// ไฟล์ `.glb` แปดชิ้นอยู่ใน `WBW/Resources/models/` ซึ่ง XcodeGen เก็บเป็น resource ให้เอง
    /// = **ถูกแพ็กไปกับ .ipa จริง** ต่อให้ฉากป่าจะถูกปิดอยู่ (`Config.forest3D = false`)
    /// CC BY 4.0 ผูกกับการเผยแพร่ ไม่ใช่แค่การแสดงผล เครดิตจึงต้องมีไม่ว่าฉากจะเปิดหรือปิด
    private let modelAuthors = ["Poly by Google", "Matthew Creighton", "Nebel", "Jarlan Perez"]

    func testCreditsBodyNamesEveryPartyTheMapLicenceRequires() {
        defer { Loc.use(.system) }
        for language in [AppLanguage.th, .en] {
            Loc.use(language)
            let body = Loc.t(CreditsView.bodyKey)
            XCTAssertNotEqual(body, CreditsView.bodyKey,
                              "ไม่มีคีย์ \(CreditsView.bodyKey) ในภาษา \(language) — ผู้ใช้จะเห็นชื่อคีย์บนจอ")
            for party in mapAttribution {
                XCTAssertTrue(body.contains(party),
                              "ภาษา \(language): เครดิตขาด \"\(party)\" — ผิดเงื่อนไขสัญญาอนุญาตของ maps3d.io")
            }
        }
    }

    func testCreditsBodyNamesTheCCBYModelAuthors() {
        defer { Loc.use(.system) }
        for language in [AppLanguage.th, .en] {
            Loc.use(language)
            let body = Loc.t(CreditsView.bodyKey)
            for author in modelAuthors {
                XCTAssertTrue(body.contains(author),
                              "ภาษา \(language): เครดิตขาด \"\(author)\" — โมเดลของเขาเป็น CC BY 4.0 และไปกับ .ipa")
            }
        }
    }

    /// ชื่อแถวในหน้าตั้งค่าต้องมีจริงทั้งสองภาษา · `DocView` รับ `LocalizedStringKey` ซึ่งพิมพ์ผิดแล้ว
    /// เรนเดอร์เป็นชื่อคีย์เฉย ๆ ไม่มี error ไม่มี build warning
    func testCreditsRowTitleExistsInBothLanguages() {
        defer { Loc.use(.system) }
        for language in [AppLanguage.th, .en] {
            Loc.use(language)
            let title = Loc.t(CreditsView.titleKey)
            XCTAssertNotEqual(title, CreditsView.titleKey, "ไม่มีคีย์ \(CreditsView.titleKey) ในภาษา \(language)")
            XCTAssertFalse(title.isEmpty)
        }
    }

    /// ไทยกับอังกฤษต้องเป็นคนละข้อความจริง ๆ — คัดลอกอังกฤษไปวางในไฟล์ไทยเป็นความผิดพลาด
    /// ที่ผ่านทั้ง build และสคริปต์ตรวจคีย์ เพราะคีย์มีอยู่ครบทั้งสองฝั่ง
    func testCreditsAreActuallyTranslated() {
        defer { Loc.use(.system) }
        Loc.use(.th)
        let thai = Loc.t(CreditsView.bodyKey)
        Loc.use(.en)
        let english = Loc.t(CreditsView.bodyKey)
        XCTAssertNotEqual(thai, english, "เครดิตสองภาษาเหมือนกันเป๊ะ — น่าจะลืมแปลฝั่งใดฝั่งหนึ่ง")
    }
}
