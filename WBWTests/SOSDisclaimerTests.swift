import XCTest
@testable import WBW

/// คำเตือนว่าปุ่ม SOS **ไม่ใช่การเรียกหน่วยกู้ชีพ** ต้องอยู่ตรงที่ผู้ใช้กำลังจะกด
///
/// แอปอยู่หมวด Health & Fitness ซึ่ง App Review อ่านละเอียดที่สุดเรื่องการอ้างความสามารถ
/// ทางการแพทย์/ฉุกเฉิน · เดิมข้อความนี้อยู่แค่ใน `SOSStatusView` = **หลังกดไปแล้ว**
/// ซึ่งช้าไปสำหรับคนที่กำลังตัดสินใจว่าจะพึ่งปุ่มนี้แทนการโทร 1669 หรือไม่
///
/// ข้อความเดียวกันนี้ต้องตรงกับสามที่: จอนี้ · ประโยคใน App description · หน้า /support
/// บนเว็บ (Support URL) — Apple เทียบเอง
final class SOSDisclaimerTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    /// จอที่ปุ่มอยู่ (ฝั่งผู้เข้าร่วม — จอที่บัญชีรีวิวของ Apple เห็น)
    func testPassScreenWarnsBeforeTheButtonIsPressed() throws {
        let view = try source("WBW/ParticipantPassView.swift")
        XCTAssertTrue(view.contains("sos_not_emergency_service"), """
            จอบัตรผู้เข้าร่วมยังไม่มีคำเตือนใต้ปุ่ม SOS — ผู้ใช้เห็นคำเตือนก็ต่อเมื่อกดไปแล้ว
            """)
    }

    /// จอสถานะยังต้องเตือนเหมือนเดิม (ค้ำไม่ให้ "ย้าย" กลายเป็นการถอดออกจากที่เดิม)
    func testStatusScreenStillWarnsToo() throws {
        let view = try source("WBW/SOS/SOSStatusView.swift")
        XCTAssertTrue(view.contains("sos_not_emergency_service"),
                      "จอสถานะ SOS ต้องเตือนด้วย ไม่ใช่ย้ายคำเตือนไปจอเดียว")
    }

    /// ข้อความต้องบอกเบอร์จริงทั้งสองภาษา ไม่ใช่คำเตือนกลาง ๆ
    func testWarningNamesTheRealEmergencyNumber() {
        defer { Loc.use(.system) }
        for language in [AppLanguage.th, .en] {
            Loc.use(language)
            let text = Loc.t("sos_not_emergency_service")
            XCTAssertNotEqual(text, "sos_not_emergency_service",
                              "ไม่มีคีย์คำเตือนในภาษา \(language)")
            XCTAssertTrue(text.contains("1669"),
                          "ภาษา \(language): คำเตือนต้องบอกเบอร์ 1669 ตรง ๆ")
        }
    }
}
