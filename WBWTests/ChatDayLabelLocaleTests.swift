import XCTest
@testable import WBW

/// ป้ายคั่นวันในแชทต้องพูดภาษาที่ผู้ใช้เลือกในแอป ไม่ใช่ภาษาที่ `ChatFormat` ฮาร์ดโค้ดไว้
///
/// `ChatFormat.dayFormatter` ตั้ง `Locale(identifier: "th_TH")` ตายตัว — คนที่เลือก English
/// ในหน้าตั้งค่าได้แอปอังกฤษทั้งใบ **ยกเว้นป้ายวันในแชทที่เป็นไทย** ผิดกติกาข้อ 10 ของ skill
/// ที่ว่าข้อความที่ผู้ใช้เห็นต้องเดินตามตัวเลือกในแอป และเป็นอาการเดียวกับที่ `Loc` ถูกสร้าง
/// ขึ้นมาแก้ตั้งแต่แรก (แอปครึ่งไทยครึ่งอังกฤษ)
///
/// พ.ศ. ต้องยังอยู่ฝั่งไทย — นั่นคือของที่ `th_TH` ให้มาโดยตั้งใจ ไม่ใช่ผลข้างเคียง
final class ChatDayLabelLocaleTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return c
    }()

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        return f.date(from: iso)!
    }

    override func tearDown() {
        Loc.use(.system)
        super.tearDown()
    }

    func testSameYearLabelFollowsAppLanguage() {
        let day = date("2026-08-24T00:00:00+07:00")
        let now = date("2026-09-30T12:00:00+07:00")

        Loc.use(.th)
        XCTAssertEqual(ChatFormat.dayLabel(for: day, now: now, calendar: calendar), "24 ส.ค.")

        Loc.use(.en)
        XCTAssertEqual(ChatFormat.dayLabel(for: day, now: now, calendar: calendar), "24 Aug")
    }

    /// ปีต่างกัน = โชว์ปีด้วย · ไทยต้องเป็น พ.ศ. (2026 + 543) อังกฤษต้องเป็น ค.ศ.
    func testOtherYearKeepsBuddhistEraInThaiAndGregorianInEnglish() {
        let day = date("2025-12-31T00:00:00+07:00")
        let now = date("2026-08-24T12:00:00+07:00")

        Loc.use(.th)
        let thai = ChatFormat.dayLabel(for: day, now: now, calendar: calendar)
        XCTAssertTrue(thai.contains("2568"), "ไทยต้องได้ พ.ศ. — ได้ \(thai)")

        Loc.use(.en)
        let english = ChatFormat.dayLabel(for: day, now: now, calendar: calendar)
        XCTAssertTrue(english.contains("2025"), "อังกฤษต้องได้ ค.ศ. — ได้ \(english)")
        XCTAssertTrue(english.contains("Dec"), "เดือนต้องเป็นอังกฤษ — ได้ \(english)")
    }

    /// วันนี้/เมื่อวานผ่านชุดคีย์อยู่แล้ว — ตัวกันการแก้ที่เผลอไปทับเส้นทางนั้น
    func testTodayAndYesterdayStillUseLocalisedKeys() {
        let now = date("2026-08-24T12:00:00+07:00")
        let yesterday = date("2026-08-23T09:00:00+07:00")

        Loc.use(.th)
        XCTAssertEqual(ChatFormat.dayLabel(for: now, now: now, calendar: calendar), "วันนี้")
        XCTAssertEqual(ChatFormat.dayLabel(for: yesterday, now: now, calendar: calendar), "เมื่อวาน")

        Loc.use(.en)
        XCTAssertEqual(ChatFormat.dayLabel(for: now, now: now, calendar: calendar), "Today")
        XCTAssertEqual(ChatFormat.dayLabel(for: yesterday, now: now, calendar: calendar), "Yesterday")
    }

    /// เวลาใต้ฟองต้องเป็น 24 ชม. เสมอทั้งสองภาษา (en_US_POSIX กัน AM/PM) — ห้ามเปลี่ยนตามภาษา
    func testBubbleTimeStays24HourInBothLanguages() {
        let d = date("2026-08-24T15:15:00+07:00")
        for language in [AppLanguage.th, .en] {
            Loc.use(language)
            XCTAssertEqual(ChatFormat.time(d, timeZone: TimeZone(identifier: "Asia/Bangkok")!), "15:15")
        }
    }
}
