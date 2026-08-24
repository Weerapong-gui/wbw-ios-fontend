import XCTest
@testable import WBW

/// ช่องกรอกหมายเลข BIB สำรอง — ทางเดียวที่เช็คอินได้เมื่อกล้องใช้ไม่ได้
///
/// **บั๊กที่จับได้จากการอ่าน**: ตัวกรองเดิมเป็น `v.filter(\.isNumber)` ซึ่ง
/// `Character.isNumber` เป็น **true กับตัวเลขทุกภาษาในยูนิโคด** แต่ `Int(String)` อ่านได้
/// เฉพาะเลขอารบิกล้วน ๆ · เลขไทยจึงผ่านตัวกรองเข้าไปนั่งในช่อง ปุ่มเช็คอินเปิดให้กด
/// (เงื่อนไขคือ `bib.isEmpty` ซึ่งไม่ว่าง) แล้ว `Int(bib)` คืน nil
///
/// ผลคือ `staffCheckin` ถูกยิงด้วย body ที่**ไม่มีทั้ง `qr_token` และ `bib`** — เจ้าหน้าที่
/// เห็นแต่ "เช็คอินไม่สำเร็จ" ลอย ๆ โดยที่ตัวเลขในช่องยังดูเหมือนเลขที่ถูกต้องทุกประการ
///
/// เข้ามาได้จริงทางวาง (paste), การพิมพ์ตามคำบอก, และคีย์บอร์ดของบางค่าย
final class StaffBibInputTests: XCTestCase {

    /// เลขไทยต้องไม่รอดผ่านตัวกรอง
    func testThaiDigitsAreStrippedNotAccepted() {
        XCTAssertEqual(StaffBibInput.sanitise("๑๒๓"), "")
        XCTAssertEqual(StaffBibInput.sanitise("12๓4"), "124")
    }

    /// ยืนยันสมมติฐานของบั๊กเอง — ถ้าวันหนึ่ง `Character.isNumber` เปลี่ยนพฤติกรรม
    /// เทสนี้จะบอกว่าเหตุผลที่เขียนไว้ข้างบนไม่จริงอีกต่อไป
    func testTheAssumptionBehindThisBugStillHolds() {
        XCTAssertTrue("๑๒๓".allSatisfy(\.isNumber), "เลขไทยยังนับเป็นตัวเลขในยูนิโคด")
        XCTAssertNil(Int("๑๒๓"), "แต่ Int() ยังอ่านไม่ได้ — ช่องว่างตรงนี้คือตัวบั๊ก")
    }

    func testArabicIndicAndFractionFormsAreStrippedToo() {
        XCTAssertEqual(StaffBibInput.sanitise("١٢٣"), "")
        XCTAssertEqual(StaffBibInput.sanitise("½"), "")
        XCTAssertEqual(StaffBibInput.sanitise("²"), "")
    }

    func testOrdinaryDigitsSurvive() {
        XCTAssertEqual(StaffBibInput.sanitise("1042"), "1042")
    }

    func testLettersAndSpacesAreStripped() {
        XCTAssertEqual(StaffBibInput.sanitise(" 10 4a2 "), "1042")
    }

    /// **ทุกอย่างที่ผ่านตัวกรองต้องแปลงเป็นตัวเลขได้จริง** — นี่คือสัญญาที่ของเดิมผิด
    /// และเป็นข้อเดียวที่ทำให้ปุ่มกับ request ตรงกันเสมอ
    func testAnythingThatSurvivesCanAlwaysBecomeANumber() {
        for raw in ["๑๒๓", "12๓4", "abc", "", "  ", "½7", "1042", "١٢٣9"] {
            let clean = StaffBibInput.sanitise(raw)
            if !clean.isEmpty {
                XCTAssertNotNil(Int(clean), "\"\(raw)\" ผ่านมาเป็น \"\(clean)\" แต่แปลงเป็นเลขไม่ได้")
            }
        }
    }

    /// ยาวเกินถูกตัด — แต่ต้องตัดหลังกรองแล้ว ไม่ใช่ก่อน ไม่งั้นตัวอักษรขยะกินโควตาหลักไป
    func testTooLongIsTruncatedAfterFilteringNotBefore() {
        XCTAssertEqual(StaffBibInput.sanitise("aaaa12345"), "12345")
        XCTAssertEqual(StaffBibInput.sanitise("123456789"), "12345")
    }
}
