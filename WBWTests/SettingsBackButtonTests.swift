import XCTest
@testable import WBW

/// **ปุ่มย้อนกลับต้องมีใบเดียวบนหัวจอตั้งค่า**
///
/// `SettingsView` วาดปุ่มย้อนกลับของตัวเองใน `.toolbar` เพราะทางที่เปิดมันเป็น **sheet**
/// (`HomeView`, `ParticipantPassView` ครอบด้วย `NavigationStack` ของตัวเอง) ไม่มีใครวาดให้
///
/// แต่ `TicketView` เปิดมันด้วย `.navigationDestination` — เป็นการ **push** เข้า stack ที่มีอยู่แล้ว
/// ซึ่งวาดปุ่มย้อนกลับของระบบให้เองอยู่แล้ว หัวจอจึงมีปุ่มย้อนกลับสองใบเรียงกัน (chevron ของระบบ
/// กับลูกศรของเรา) — เห็นจริงตอนถ่ายหน้าตั้งค่าผ่าน `-uitestProfile -uitestSettings`
///
/// กติกา: จุดที่ **push** ต้องสั่ง `drawsOwnBackButton: false` · จุดที่เปิดเป็น **sheet** ห้ามสั่ง
final class SettingsBackButtonTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    func testPushedSettingsHidesItsOwnBackButton() throws {
        let ticket = try source("WBW/TicketView.swift")
        guard let line = ticket.components(separatedBy: .newlines)
            .first(where: { $0.contains(".navigationDestination") && $0.contains("SettingsView(") })
        else {
            return XCTFail("หาจุดที่ push SettingsView ใน TicketView ไม่เจอ — เทสนี้เน่าแล้ว")
        }
        XCTAssertTrue(line.contains("drawsOwnBackButton: false"), """
            \(line.trimmingCharacters(in: .whitespaces))
            จุดนี้ push เข้า stack ที่มีปุ่มย้อนกลับของระบบอยู่แล้ว — ถ้า SettingsView วาดของตัวเองด้วย
            หัวจอจะมีปุ่มย้อนกลับสองใบ
            """)
    }

    func testSheetPresentedSettingsKeepsItsOwnBackButton() throws {
        for path in ["WBW/HomeView.swift", "WBW/ParticipantPassView.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("NavigationStack { SettingsView() }"), """
                \(path) เปิดหน้าตั้งค่าเป็น sheet ของตัวเอง จึงต้องปล่อยให้ SettingsView
                วาดปุ่มย้อนกลับเอง — ไม่มี stack เดิมวาดให้
                """)
        }
    }
}
