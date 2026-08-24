import XCTest
@testable import WBW

/// **ของที่ต้องทำงานในโหมด 2 มิติ ห้ามผูกไว้กับ `mapView`**
///
/// `mapView` คือ `RealityView` ของแผนที่ 3 มิติ ซึ่ง **ไม่ถูก mount เลย** เมื่อแท็บเปิดมาที่โหมด
/// 2 มิติ — และ 2 มิติคือค่าเริ่มต้นตั้งแต่ 2026-08-24 (`MapMode.stored` คืน `.flat` เมื่อยังไม่เคย
/// เลือก) · `.onAppear`/`.onChange` ที่แขวนอยู่บน `mapView` จึงถูกกลืนเงียบ ๆ ไม่มี error ให้เห็น
/// รอยเดียวกับที่ `-uitestMapMode` เคยโดนมาแล้ว (ดูคอมเมนต์ใน `MapMode.initialForLaunch`)
///
/// สองอย่างที่หลุดจริงจากรอยนี้:
///
/// - `location.start()` — เปิดแท็บแผนที่บนเครื่องที่ยังไม่เคยกดสลับโหมด แล้วจุดตำแหน่งของตัวเอง
///   ไม่ขึ้นบนแผนที่ 2 มิติ **ตลอดไป** เพราะไม่มีใครสั่งให้เริ่มอ่านพิกัด
/// - `-uitestMapPin` — การ์ดฐานไม่เปิด ทั้งที่ตัวโค้ดข้างในมีสาขาสำหรับโหมด 2 มิติอยู่แล้ว
///   ทำให้สกรีนช็อต `02-map` ที่ต้องส่ง App Store ถ่ายออกมาไม่มีการ์ด
final class Map3DScreenLifecycleTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// เนื้อของ `private var mapView: some View { ... }` — นับปีกกาเอา ไม่ได้เดาจากบรรทัด
    private func mapViewBody() throws -> String {
        let text = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("WBW/Map3D/Map3DScreen.swift"),
            encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.contains("private var mapView: some View {") })
        else {
            XCTFail("หา `mapView` ไม่เจอ — เทสนี้เน่าแล้ว")
            return ""
        }

        var depth = 0
        var collected: [String] = []
        for line in lines[start...] {
            collected.append(line)
            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth == 0 && collected.count > 1 { break }
        }
        return collected.joined(separator: "\n")
    }

    func testDefaultMapModeIsFlat() {
        let empty = UserDefaults(suiteName: "wbw.test.mapmode.\(UUID().uuidString)")!
        XCTAssertEqual(MapMode.stored(in: empty), .flat,
                       "เทสข้างล่างตั้งอยู่บนสมมติฐานว่าค่าเริ่มต้นคือ 2 มิติ")
    }

    func testLocationIsNotStartedFromTheThreeDSubtree() throws {
        XCTAssertFalse(try mapViewBody().contains("location.start()"), """
            `location.start()` อยู่ใน `mapView` ซึ่งเป็น RealityView ของโหมด 3 มิติ
            โหมดเริ่มต้นคือ 2 มิติ ซึ่งไม่ mount view นั้นเลย — จุดตำแหน่งของผู้ใช้จะไม่ขึ้น
            ย้ายไปผูกกับรากของจอ (`body`) ที่ถูกสร้างทั้งสองโหมด
            """)
    }

    func testForcedPinFlagIsNotReadFromTheThreeDSubtree() throws {
        // จับ *การอ่านค่า* ไม่ใช่ชื่อแฟลกในคอมเมนต์ — สาขาที่บินกล้องไปหาหมุดยังต้องอยู่ใน
        // `mapView` ต่อไป (มันต้องรอตำแหน่งหมุดจากโมเดล) และคอมเมนต์ตรงนั้นเอ่ยชื่อแฟลกไว้
        XCTAssertFalse(try mapViewBody().contains("forKey: \"uitestMapPin\""), """
            `-uitestMapPin` ถูกอ่านใน `mapView` ซึ่งโหมด 2 มิติไม่ mount
            การ์ดฐานจึงไม่เปิดตอนถ่าย `02-map` ทั้งที่โค้ดมีสาขาโหมด 2 มิติอยู่แล้ว
            """)
    }
}
