import XCTest
@testable import WBW

/// **พื้นขาวตายตัว ต้องมาคู่กับตัวอักษรที่ตายตัวด้วย**
///
/// `Color.wbwInk` กับ `.primary` พลิกเป็น **ขาวเกือบขาว** (#E9EEE0) ในโหมดมืด — วางไว้บนพื้นที่
/// ทาขาวตายตัวเมื่อไหร่ ทั้งการ์ดกลายเป็นขาวบนขาว อ่านไม่ออกสักตัว และไม่มีอะไรฟ้อง เพราะโค้ด
/// ถูกทุกบรรทัด · `StaffSOSView` เจอมาก่อนแล้วและแก้ด้วยการตรึง `foregroundStyle`/`tint`
/// เป็น `wbwForestVoid` (ดูคอมเมนต์ในไฟล์นั้น)
///
/// รอบนี้จับได้จากสกรีนช็อต `08-feedback` ที่ต้องส่ง App Store: การ์ดให้ความเห็นเป็นแผ่นขาว
/// หัวข้อ "จุดปลูก" กับปุ่มส่งหายไปกับพื้น
///
/// จอที่ **ตั้งใจ** ไม่ปรับตามธีมอยู่ในรายชื่อยกเว้น (ดู `.claude/skills/wbw-ios/ui-conventions.md`)
final class FixedWhiteSurfaceTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// จอที่ดีไซน์ตรึงไว้ทั้งใบอยู่แล้ว — บัตรกระดาษ, จอสแกนพื้นมืด, ฉากป่า
    private let pinnedByDesign = ["WBW/TicketView.swift", "WBW/StaffScanView.swift"]

    func testFixedWhiteSurfacesPinTheirInk() throws {
        let files = try FileManager.default
            .subpathsOfDirectory(atPath: Self.repoRoot.appendingPathComponent("WBW").path)
            .filter { $0.hasSuffix(".swift") }
            .map { "WBW/\($0)" }
            .filter { !pinnedByDesign.contains($0) && !$0.hasPrefix("WBW/Scene3D/") }
            .sorted()

        for path in files {
            let lines = try String(contentsOf: Self.repoRoot.appendingPathComponent(path),
                                   encoding: .utf8).components(separatedBy: .newlines)
            for (i, line) in lines.enumerated() {
                // เฉพาะพื้นขาว **ทึบ** — `.white.opacity(...)` เป็นฟิล์มบางบนของที่มืดอยู่แล้ว
                guard line.contains(".background(.white)") || line.contains(".background(.white,") else { continue }
                let after = lines[i..<min(i + 8, lines.count)].joined(separator: "\n")
                XCTAssertTrue(after.contains("foregroundStyle(Color.wbwForestVoid)")
                                || after.contains("foregroundStyle(Color.wbwInkFixed)"), """
                    \(path):\(i + 1) ทาพื้นขาวตายตัวโดยไม่ตรึงสีตัวอักษรตามไปด้วย
                    ในโหมดมืด `wbwInk`/`.primary` เป็นขาวเกือบขาว การ์ดจะกลายเป็นขาวบนขาว
                    ถ้าการ์ดใบนี้ไม่ได้ตั้งใจให้เป็นกระดาษ ให้ใช้ `Color.wbwSurface` แทนสีขาว
                    """)
            }
        }
    }
}
