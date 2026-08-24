import XCTest

/// ทรงของบัตรผู้เข้าร่วมที่ต้องตรงกับต้นทาง Android (`ui/profile/ProfileScreen.kt`)
///
/// **เทสสแกนซอร์ส ไม่ได้เรนเดอร์จริง** — เลย์เอาต์ที่เรนเดอร์แล้วตรวจจาก unit test ไม่ได้
/// (เหตุผลเต็มอยู่หัวไฟล์ `TapTargetTests`) ที่นี่จับได้แค่ "เจตนาถูกเขียนไว้ในโค้ดไหม"
/// ส่วนผลลัพธ์จริงยืนยันด้วยสกรีนช็อตบน iPhone 17 กับ iPhone SE รุ่น 3
final class ParticipantPassLayoutTests: XCTestCase {

    private static let source: String = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WBW/ParticipantPassView.swift")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    private var code: String {
        Self.source.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    func testGroupSitsBesideTheBibNumberNotInAPillAtTheTop() {
        XCTAssertFalse(code.isEmpty, "อ่าน WBW/ParticipantPassView.swift ไม่ได้")
        XCTAssertTrue(code.contains(#"Loc.t("profile_label_group")"#), """
            หมายเลขกลุ่มต้องใช้คีย์ป้ายคู่กับ "หมายเลขบิบ" — บิบกับกลุ่มคือคำถามเดียวกัน
            ที่ถามสองครั้ง เจ้าหน้าที่ที่ถือบัตรต้องการทั้งคู่ในสายตาเดียว
            """)
        XCTAssertFalse(code.contains(#"outlinePill(String(format: Loc.t("group_number")"#),
                       "pill กลุ่มบนหัวการ์ดถูกย้ายลงไปอยู่แถวเดียวกับบิบแล้ว")
    }

    /// คีย์ `group_number` **ห้ามลบ** ถึงแม้หน้าบัตรจะเลิกใช้
    func testTheSharedGroupNumberKeyIsStillUsedElsewhere() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        var users: [String] = []
        for file in try FileManager.default
            .subpathsOfDirectory(atPath: root.appendingPathComponent("WBW").path)
            .filter({ $0.hasSuffix(".swift") }) {
            let text = try String(contentsOf: root.appendingPathComponent("WBW/\(file)"),
                                  encoding: .utf8)
            if text.contains(#"Loc.t("group_number")"#) { users.append(file) }
        }
        XCTAssertFalse(users.isEmpty, """
            ไม่มีใครใช้คีย์ group_number แล้ว — ถ้าตั้งใจลบต้องลบออกจากตารางแปลทั้งสองภาษาด้วย
            แต่ถ้ามาถึงตรงนี้เพราะเผลอ แปลว่ามีจอกลุ่มที่พังไปโดยไม่มีใครเห็น
            """)
    }

    /// ตัวเลขสองตัวต้องขนาดเท่ากันและน้ำหนักปกติ
    ///
    /// ต้นทางเคยลองให้กลุ่มเล็กกว่าด้วยเหตุผลว่าบิบเป็นพระเอก แล้วพบว่าเลขสองตัวที่นั่งข้างกัน
    /// ใต้ป้ายคู่กันอ่านเป็น "คู่" — คู่ที่ขนาดต่างกันอ่านเป็นความผิดพลาด ไม่ใช่ลำดับความสำคัญ
    func testBothNumbersShareOneStyle() {
        XCTAssertFalse(code.contains("wbwNumeral(46, weight: .bold"),
                       "เลขบนบัตรต้องเป็นน้ำหนักปกติ ให้ตรงกับต้นทาง")
        let occurrences = code.components(separatedBy: "wbwNumeral(46, relativeTo: .largeTitle)").count - 1
        XCTAssertEqual(occurrences, 1, """
            ทั้งบิบและกลุ่มต้องวาดผ่านตัวช่วยตัวเดียวกัน (`numberColumn`) ไม่ใช่ก๊อปสไตล์
            ไปวางสองที่ — สองที่จะเพี้ยนจากกันวันที่มีคนแก้ทีละอัน
            """)
    }

    /// บิบเลขสี่หลัก + ชิปเช็คอิน กินกว้างเกินการ์ดบนมือถือแคบ ต้องมีทรงสำรอง
    ///
    /// ผลของการไม่มีทรงสำรองไม่ใช่แค่แถวนี้ล้น แต่ไปบีบทั้งการ์ดจนชื่อสำนักวิชากับผู้ติดต่อ
    /// ฉุกเฉินถูกตัดท้ายด้วย "..." — เจอจากสกรีนช็อตเทียบก่อน/หลัง ไม่ใช่จากการอ่านโค้ด
    func testThereIsADesignedFallbackForNarrowScreens() {
        XCTAssertTrue(code.contains("ViewThatFits"), """
            ต้องมีทรงสำรองตอนแถวบิบ|กลุ่ม|ชิป ใส่ไม่ลง — ต้นทาง Android ออกแบบทรงแถวเดียวไว้
            กับบิบเลขหลักเดียว แต่บิบจริงของงานนี้เป็นเลขสี่หลัก
            """)
    }
}
