import XCTest

/// ไม่มีจอไหนอ้าง `ForestSceneHost.tabBarClearance` ตรง ๆ อีกแล้ว — ต้องผ่าน `.tabBarClearance()`
///
/// **มีเทสนี้เพราะค่านั้นถูกบนไอดิอมเดียว** ใครก็ตามที่เขียน
/// `.padding(.bottom, ForestSceneHost.tabBarClearance)` ในจอใหม่จะได้ที่ว่างตาย 89pt ก้นจอ
/// บน iPad (แถบแท็บอยู่ข้างบน) โดยจอยังดูถูกต้องสมบูรณ์บน simulator iPhone ที่เขาเปิดทดสอบอยู่
/// — พังเงียบสนิท ไม่มี build error ไม่มีเทสไหนแดง จนกว่าจะมีคนหยิบ iPad ขึ้นมาเปิด
///
/// **ต้องกรองคอมเมนต์ทิ้งก่อนเสมอ** — `ForestSceneHost.swift` กับ `ForestOverlay.swift`
/// เอ่ยชื่อค่านี้ในคอมเมนต์ยาวที่อธิบายที่มาของเลข 89 เทสที่ไม่กรองจะแดงกับเอกสารของตัวเอง
/// (รอยเดียวกับที่ `SURunRemovalTests` กับ `AppStoreConfigTests` เคยเจ็บมาแล้วทั้งคู่)
final class TabBarClearanceUsageTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// สองไฟล์ที่อ้างค่าดิบได้: ที่ประกาศมัน กับที่แปลงมันเป็นค่าตามขนาดจอ
    private static let mayReferenceRawConstant: Set<String> = [
        "Layout.swift",
        "Scene3D/ForestSceneHost.swift",
    ]

    func testNoScreenReachesForTheRawPhoneConstant() throws {
        let root = Self.repoRoot.appendingPathComponent("WBW")
        let swiftFiles = try FileManager.default
            .subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()

        var offenders: [String] = []
        for relative in swiftFiles where !Self.mayReferenceRawConstant.contains(relative) {
            let source = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            let code = source.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            if code.contains("ForestSceneHost.tabBarClearance") { offenders.append(relative) }
        }

        XCTAssertEqual(offenders, [],
                       "จอพวกนี้อ้างค่าของ iPhone ตรง ๆ — ใช้ `.tabBarClearance()` แทน ไม่งั้นได้ที่ว่างตาย 89pt ก้นจอบน iPad")
    }
}
