import XCTest

/// **ทางขอสิทธิ์ตำแหน่งต้องมีทางเดียว และต้องเป็นทางที่มีคำอธิบายนำ**
///
/// `LocationPrimerSheet` ถูกทำขึ้นเพื่อตอบ Guideline 5.1.1 (ขอพร้อมบริบท) แต่มันกันได้เฉพาะ
/// ทางที่ตัวเองคุม · จุดอื่นที่เรียก `requestWhenInUseAuthorization()` เองยังแซงมันได้หมด
///
/// **เจอจากการรันบนเครื่องจริง 2026-08-22 ไม่ใช่จากการอ่านโค้ด** — log บนเครื่องจริงบอกว่า
/// `Map3DLocation.start()` ยิงคำขอที่วินาที 1.4 หลังเปิดแอป ก่อนใครจะทันกดอะไรบนจออธิบาย:
///
/// ```
/// 06:50:27.770 [loc] จออธิบาย: โผล่ · สิทธิ์=ยังไม่เคยถาม
/// 06:50:29.149 [loc] start() · สถานะสิทธิ์ตอนนี้ = ยังไม่เคยถาม   ← ขอเองตรงนี้
/// ```
///
/// เคสจริงที่ผู้ใช้เจอ: กด "ไว้ทีหลัง" บนจออธิบาย แล้วเปิดแท็บแผนที่ → กล่องของ iOS เด้งโดย
/// ไม่มีอะไรนำเลย ซึ่งคือสิ่งที่จออธิบายถูกสร้างมาเพื่อกันตั้งแต่แรก
final class PermissionEntryPointTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// ไฟล์เดียวที่ยิงคำขอจริงได้ · `SOSLocator` เป็นตัวห่อที่จออธิบายเรียกผ่าน
    /// (และเป็นทางสำรองบนจอสถานะ SOS ตอนฉุกเฉิน ซึ่งมีบริบทเต็มอยู่บนจอแล้ว)
    private static let allowed = ["WBW/SOS/SOSLocator.swift"]

    func testOnlyTheExplainedPathAsksForLocation() throws {
        let files = try FileManager.default
            .subpathsOfDirectory(atPath: Self.repoRoot.appendingPathComponent("WBW").path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()

        for file in files {
            let path = "WBW/\(file)"
            guard !Self.allowed.contains(path) else { continue }
            let text = try String(
                contentsOf: Self.repoRoot.appendingPathComponent(path), encoding: .utf8)
            let code = text.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            XCTAssertFalse(code.contains("requestWhenInUseAuthorization()"), """
                \(path) ขอสิทธิ์ตำแหน่งเอง — แซงจออธิบาย (`LocationPrimerSheet`)
                กล่องของ iOS จะเด้งโดยไม่มีคำอธิบายนำ ซึ่งคือ Guideline 5.1.1
                ถ้าจอนี้ต้องใช้พิกัดจริง ให้เรียก `startUpdatingLocation()` เฉย ๆ เมื่อได้สิทธิ์แล้ว
                แล้วปล่อยให้จออธิบายเป็นคนขอ
                """)
        }
    }
}
