import XCTest
@testable import WBW

/// ตัวเลขของงานที่พูดไว้สองที่ — ในแอปกับบนเว็บ **ผู้ตรวจของ Apple เปิดทั้งสองที่**
///
/// เจอจริงเมื่อ 2026-08-23: จอ "เกี่ยวกับงาน" เขียนว่าเดิน 8.36 กม. ส่วนเว็บ (`/about`,
/// `SITE_DESCRIPTION` และหน้า `/support` ที่เป็น Support URL) เขียน 6 กม. มาตลอด ·
/// เลือกยึด 6 กม. ตามเว็บ เพราะเป็นตัวเลขที่ผู้เข้าร่วมเห็นตอนสมัคร
///
/// เทสนี้ไม่ได้รู้ว่าตัวเลขไหนถูก มันกันแค่ไม่ให้ตัวเลขเก่ากลับมาโดยไม่มีใครเห็น
final class EventFactsTests: XCTestCase {

    func testAboutEventBodyUsesTheDistanceTheWebsiteUses() {
        defer { Loc.use(.system) }
        let expected: [AppLanguage: String] = [.th: "6 กม.", .en: "6 km"]

        for (language, distance) in expected {
            Loc.use(language)
            let body = Loc.t(AboutEventView.bodyKey)

            XCTAssertNotEqual(body, AboutEventView.bodyKey,
                              "ไม่มีคีย์ \(AboutEventView.bodyKey) ในภาษา \(language)")
            XCTAssertTrue(body.contains(distance),
                          "ภาษา \(language): จอเกี่ยวกับงานต้องบอก \(distance) เท่ากับเว็บ")
            XCTAssertFalse(body.contains("8.36"),
                           "ภาษา \(language): 8.36 กม. เป็นตัวเลขเก่าที่ขัดกับเว็บ")
        }
    }
}
