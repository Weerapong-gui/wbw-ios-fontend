import XCTest
@testable import WBW

/// **โหมดเดโม่ต้องไม่ขอสิทธิ์อะไรเลยสักอย่าง**
///
/// `Session.startDemo()` เขียนเจตนานี้ไว้ตรง ๆ ตั้งแต่แรก ("โหมดนี้มีไว้ให้ผู้รีวิวเดินดูจอ
/// ไม่ใช่ให้เจอกล่องขอสิทธิ์จริง") แต่บังคับได้แค่ทางเดียวคือทางที่ตัวเองเรียก · ทางอื่นที่
/// เรียก `requestWhenInUseAuthorization()` เองยังหลุดได้หมด และหลุดจริงมาแล้วสองทาง:
/// `SOSLocator` (ผ่าน `SOSStatusView.onAppear`) และ `Map3DLocation` (ผ่านแท็บแผนที่)
///
/// อาการตอนถ่ายสกรีนช็อต App Store: กล่องขอสิทธิ์เด้งที่ใบที่สองแล้ว**ค้างบังทุกใบที่เหลือ**
/// เพราะไม่มีใครกดตอบ · อาการตอนรีวิวจริง: Guideline 5.1.1 — ขอสิทธิ์ที่ไม่มีอะไรในโหมดนั้น
/// ได้ใช้จริงเลย (โหมดเดโม่ไม่ยิงเน็ตและไม่อ่านพิกัดสักครั้ง)
///
/// เทสนี้กวาดซอร์ส ไม่ใช่เรียกฟังก์ชัน เพราะ `CLLocationManager` ตัวจริงฉีดไม่ได้ทุกที่ —
/// `Map3DLocation` กับ `SURunTracker` ถือ manager ของตัวเองไว้ข้างในตรง ๆ
final class DemoPermissionTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func testEveryPermissionRequestIsGatedOnDemoMode() throws {
        let files = try FileManager.default
            .subpathsOfDirectory(atPath: Self.repoRoot.appendingPathComponent("WBW").path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()

        var sites = 0
        for file in files {
            let text = try String(
                contentsOf: Self.repoRoot.appendingPathComponent("WBW/\(file)"), encoding: .utf8)
            let lines = text.components(separatedBy: .newlines)
            for (i, line) in lines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.contains("requestWhenInUseAuthorization()") else { continue }
                if t.hasPrefix("//") || t.hasPrefix("///") { continue }
                // การประกาศใน protocol กับตัวห่อที่ส่งต่อให้ CLLocationManager ไม่ใช่จุดตัดสินใจ
                if t.hasPrefix("func requestWhenInUseAuthorization") { continue }
                sites += 1

                // ประตูต้องอยู่ใกล้ ๆ จุดเรียก — ในฟังก์ชันเดียวกัน ไม่ใช่ที่ไหนก็ได้ในไฟล์
                let from = max(0, i - 12)
                let around = lines[from...i].joined(separator: "\n")
                XCTAssertTrue(around.contains("DemoMode.active"), """
                    WBW/\(file):\(i + 1) ขอสิทธิ์ตำแหน่งโดยไม่ได้กันโหมดเดโม่
                    ผู้รีวิว App Store เข้าทางโหมดเดโม่ ซึ่งไม่อ่านพิกัดจริงเลยสักครั้ง
                    ใส่ `guard !DemoMode.active else { return }` ก่อนเรียก
                    """)
            }
        }
        // เหลือสองจุด ทั้งคู่อยู่ใน `SOSLocator` — `Map3DLocation` เลิกขอเองแล้ว (ดู
        // `PermissionEntryPointTests` ว่าทำไม) และ `SURunTracker` ถูกลบไปพร้อมฟีเจอร์ SU RUN
        // · ตัวเลขนี้ลดลงได้อีกไม่ได้ ถ้าเหลือศูนย์แปลว่าไม่มีใครขอสิทธิ์เลย = SOS ไม่มีพิกัด
        XCTAssertGreaterThanOrEqual(sites, 2, "ตัวกวาดหาจุดขอสิทธิ์ไม่เจอ — เงื่อนไขเน่าแล้ว")
    }
}
