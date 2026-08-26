import XCTest
@testable import WBW

/// กล่องยืนยันออกจากระบบต้องเป็น `.alert` ไม่ใช่ `.confirmationDialog`
///
/// ของเดิมเป็น `confirmationDialog` ที่ผูกกับ `ScrollView` ทั้งจอ ไม่ใช่กับปุ่มที่กด — พอมันกลายร่าง
/// เป็น popover (เกิดได้ทั้งบน iPad ที่เปิดตั้งแต่ 2026-08-25 และกับ action sheet ของ iOS 26
/// ที่ยึดกับ source view แบบเมนู) หัวลูกศรไปโผล่กลางจอทับแถวอื่น **และระบบตัดปุ่มยกเลิกทิ้งทั้งปุ่ม**
/// เหลือแต่ปุ่มแดง "ออกจากระบบ" ลอยอยู่ ซึ่งอ่านเหมือนแอปพัง (เจ้าของงานส่งภาพมาเอง 2026-08-26)
///
/// `.alert` แสดงกลางจอเหมือนกันทุกขนาดจอ/ทุกเวอร์ชัน และเก็บปุ่มยกเลิกไว้เสมอ — ของจริงที่ทำแบบนี้
/// อยู่แล้วคือกล่องเข้ากลุ่มที่ `GroupJoinView`
final class LogoutConfirmTests: XCTestCase {

    private func settingsSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WBWTests/
            .deletingLastPathComponent()   // ราก repo
            .appendingPathComponent("WBW/SettingsView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testLogoutUsesAnAlertNotAConfirmationDialog() throws {
        let source = try settingsSource()
        // ตรวจ "การเรียกใช้" (มีวงเล็บ) ไม่ใช่คำเปล่า — คอมเมนต์ในโค้ดพูดถึงชื่อนี้อยู่ด้วยโดยตั้งใจ
        // เพื่ออธิบายว่าทำไมถึงเลิกใช้ ถ้าห้ามทั้งคำก็เท่ากับห้ามอธิบายเหตุผลไว้ให้คนอ่านรอบหน้า
        XCTAssertFalse(source.contains(".confirmationDialog("), """
            confirmationDialog กลายร่างเป็น popover ได้ แล้วปุ่มยกเลิกจะหายไปทั้งปุ่ม —
            จอนี้ต้องใช้ .alert ที่แสดงเหมือนกันทุกเครื่อง
            """)
        XCTAssertTrue(source.contains(".alert("), "ต้องยังมีกล่องยืนยันอยู่ ไม่ใช่ถอดทิ้งไปเฉย ๆ")
    }

    /// ปุ่มยกเลิกต้องมีจริงในโค้ด **และ** ต้องมีคีย์แปลครบสองภาษา — ปุ่มออกจากระบบที่ไม่มีทางถอย
    /// คือปุ่มที่กดพลาดแล้วเสียการเดินทั้งรอบ (ต้องล็อกอินใหม่กลางดอย)
    func testTheDialogKeepsAWayOut() throws {
        let source = try settingsSource()
        for key in ["settings_logout_confirm", "settings_logout", "settings_logout_cancel"] {
            XCTAssertTrue(source.contains(key), "จอตั้งค่าต้องเรียกคีย์ \(key)")
            XCTAssertFalse(Loc.t(key).isEmpty, "คีย์ \(key) ต้องมีคำแปล")
            XCTAssertNotEqual(Loc.t(key), key, "คีย์ \(key) ยังไม่มีคำแปล — ผู้ใช้จะเห็นชื่อคีย์บนปุ่ม")
        }
    }

    /// ต้องมีทางเปิดกล่องนี้ตรง ๆ ไม่งั้นยืนยันด้วยภาพไม่ได้เลยว่ามันแสดงถูก — ทรงเดียวกับ
    /// `-uitestLeaveConfirm` ของกล่องออกจากกลุ่ม (เครื่องนี้ไม่มีตัวกดจอ)
    func testThereIsAFlagToOpenTheDialogForScreenshots() throws {
        let source = try settingsSource()
        XCTAssertTrue(source.contains("uitestLogoutConfirm"),
                      "ไม่มีแฟลกเปิดกล่องนี้ = ถ่ายรูปยืนยันว่าแก้แล้วจริงไม่ได้")
    }
}
