import XCTest
@testable import WBW

/// วันงานบนตั๋ว — ค่าที่ผิดแล้วไม่มีอะไรฟ้อง
///
/// ช่อง Date เคยเป็น string ฮาร์ดโค้ด `"29 AUG 2026"` กลางไฟล์จอ · พอยกมาคำนวณจากวันจริง
/// กับดักที่ตามมาคือ locale: `DateFormatter` ที่ใช้ locale ของเครื่องจะได้ "29 ส.ค. 2569"
/// บนมือถือที่ตั้งภาษาไทย (พุทธศักราช) ซึ่งไม่ตรงกับดีไซน์บัตร — และเดฟที่ simulator เป็น en_US
/// จะไม่มีวันเห็นความต่างนี้เลยจนกว่าจะมีคนถือเครื่องภาษาไทยมาบอก
final class WBWEventTests: XCTestCase {

    func testTicketDateMatchesDesign() {
        XCTAssertEqual(WBWEvent.ticketDate(), "29 AUG 2026")
    }

    /// หัวใจของไฟล์นี้ — ผลลัพธ์ต้องไม่ขยับตาม locale ของเครื่อง
    func testTicketDateIgnoresDeviceLocale() {
        for id in ["th_TH", "en_US", "ja_JP", "ar_EG"] {
            XCTAssertEqual(WBWEvent.ticketDate(deviceLocale: Locale(identifier: id)), "29 AUG 2026",
                           "เครื่องตั้ง \(id) ก็ต้องได้รูปแบบเดียวกับบนบัตร")
        }
    }

    /// ปฏิทินพุทธของ th_TH ต้องไม่เล็ดลอดมาเป็นปี 2569
    func testTicketDateUsesGregorianYear() {
        let text = WBWEvent.ticketDate(deviceLocale: Locale(identifier: "th_TH"))
        XCTAssertTrue(text.contains("2026"), "ต้องเป็น ค.ศ. ไม่ใช่ พ.ศ. — ได้ \(text)")
        XCTAssertFalse(text.contains("2569"))
    }

    /// วันที่ยังต้องตรงกับที่ประกาศไว้ ไม่ใช่ค่าที่เพี้ยนไปเพราะ time zone
    func testEventDayComponents() {
        XCTAssertEqual(WBWEvent.day.year, 2026)
        XCTAssertEqual(WBWEvent.day.month, 8)
        XCTAssertEqual(WBWEvent.day.day, 29)
    }
}
