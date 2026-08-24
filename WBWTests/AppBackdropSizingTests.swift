import XCTest

/// พื้นหลังกลางของแอปต้อง **ไม่** เป็นตัวกำหนดขนาดของใคร
///
/// **มีเทสนี้เพราะบั๊กนี้ทำให้ทั้งแอปพังบน iPad โดยไม่มีอะไรฟ้องเลย** และซ่อนอยู่บน iPhone
/// มานานโดยไม่มีใครเห็น:
///
/// `AppBackdrop` เป็นลูกใบหนึ่งของ `ZStack` ใน `RootView` ส่วน `MainTabView` เป็นลูกอีกใบ ·
/// `ZStack` คิดขนาดตัวเองจากลูกที่ใหญ่ที่สุด แล้วเสนอขนาดนั้นให้ลูกทุกใบ — ถ้าพื้นหลังรายงาน
/// ขนาดตามอัตราส่วน **ของไฟล์ภาพ** (736×1471 = 1:2) แทนที่จะรายงานตามขนาดจอ ทั้ง ZStack
/// จะสูงตามภาพ แล้ว `MainTabView` ก็ถูกยืดตาม พอ ZStack จัดกึ่งกลาง เนื้อหาทุกแท็บจะถูกดัน
/// ขึ้นไปพ้นขอบบนจอ
///
/// วัดจริงบน iPad Pro 13" (จอ 1032×1376pt): TabView ได้ขนาด 1032×**2063** ที่ y = **-340**
/// ผลคือแท็บกิจกรรมว่างเปล่าสนิท หน้าบัตรโดนตัดหัวการ์ดทิ้ง หน้าแรกเหลือแต่ดอกไม้ไม่มี
/// ตัวอักษรสักบรรทัด · บน iPhone 17 บั๊กเดียวกันเบากว่ามากแต่มีจริง: 402×**803.3** ที่ y = 49.3
/// ทั้งที่ค่าที่ถูกคือ 402×778 ที่ y = 62 — ทุกจอถูกดันขึ้นไป ~12.7pt มาตลอด
///
/// `.frame(maxWidth: .infinity, maxHeight: .infinity)` **ไม่ได้** บังคับขนาดให้เท่าที่ถูกเสนอมา
/// มันแค่ยอมโตจนเต็ม — ตัวที่รายงานขนาดยังเป็น `scaledToFill` ซึ่งรายงานตามอัตราส่วนภาพอยู่ดี
final class AppBackdropSizingTests: XCTestCase {

    private static let source: String = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WBW/AppBackdrop.swift")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    private var code: String {
        Self.source.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    func testTheSizingAnchorIsAColourNotTheImage() {
        XCTAssertFalse(code.isEmpty, "อ่าน WBW/AppBackdrop.swift ไม่ได้")
        XCTAssertTrue(code.contains("Color.clear"),
                      "พื้นหลังต้องยึดขนาดจาก Color.clear (รับข้อเสนอเท่าไรรายงานเท่านั้น) ไม่ใช่จากตัวภาพ")
    }

    /// ตัวภาพต้องอยู่ใน `overlay`/`background` เท่านั้น — สองตัวนี้ไม่มีวันดันขนาดของสิ่งที่มันทับอยู่
    func testTheImageIsPaintedIntoALayerThatCannotResizeItsHost() {
        guard let imageAt = code.range(of: #"Image("bg_backdrop")"#)?.lowerBound else {
            return XCTFail("ไม่พบการวาดภาพพื้นหลังในไฟล์")
        }
        let before = String(code[code.startIndex..<imageAt])
        XCTAssertTrue(before.contains(".overlay") || before.contains(".background"),
                      "ภาพต้องถูกวาดใน overlay/background ไม่ใช่เป็นตัวรากที่กำหนดขนาดเอง")
    }

    /// รูปแบบเดิมที่พังต้องไม่กลับมา — `scaledToFill` บนตัวราก แล้วหวังให้ `frame(max…)` คุมขนาด
    func testTheOldPatternThatBrokeIPadCannotComeBack() {
        // บีบช่องว่าง **ทุกชนิดรวมขึ้นบรรทัดใหม่** ไม่ใช่แค่เว้นวรรค — ของเดิมเขียนคร่อมหลายบรรทัด
        // มีคอมเมนต์คั่นกลาง ถ้าบีบแค่เว้นวรรคจะจับไม่ติดแล้วเทสผ่านทั้งที่โค้ดยังพังอยู่
        let root = code.components(separatedBy: .whitespacesAndNewlines).joined()
        let brokenPattern = root.contains(#"Image("bg_backdrop").resizable().scaledToFill().frame(maxWidth:.infinity,maxHeight:.infinity)"#)
        XCTAssertFalse(brokenPattern,
                       "frame(max…: .infinity) ไม่ได้บังคับขนาดให้เท่าข้อเสนอ — ภาพจะรายงานขนาดตามอัตราส่วนตัวเองแล้วยืด ZStack ทั้งใบ")
    }
}
