import SwiftUI
import XCTest
@testable import WBW

/// เลย์เอาต์ที่ต้องเปลี่ยนทรงเมื่อผู้ใช้ตั้งตัวอักษรใหญ่ระดับ Accessibility
///
/// **เจอจากการรันจริง ไม่ใช่จากการอ่านโค้ด** — เปิดแอปด้วย
/// `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`
/// (สวิตช์ที่ผู้ตรวจ App Review เปิดกันจริงในหมวดการเข้าถึง) แล้วถ่ายทุกจอ:
///
/// - **จอสถานะ SOS**: แถบทางออกที่ปักไว้ท้ายจอโตจนกินเกือบทั้งจอ เหลือที่ให้เนื้อหาราวหนึ่ง
///   บรรทัด · การ์ดกรุ๊ปเลือด/เบอร์ญาติที่ทำมาให้ยื่นให้คนช่วยดูถูกดันออกนอกจอทั้งใบ
/// - **หน้า Home**: แถวอากาศ/AQI ตัดคำทิ้งจนเหลือ "27° รู้…" กับ "AQI… ดี" — ตัวเลขที่คนอ่าน
///   ต้องการหายไปทั้งสองช่อง
final class BigTextLayoutTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - กติกาว่าเมื่อไหร่ต้องเปลี่ยนทรง

    /// ขนาดปกติทุกระดับต้องได้ทรงเดิมเป๊ะ — คนส่วนใหญ่อยู่ตรงนี้ และจอพวกนี้ผ่านการถ่ายรูป
    /// ยืนยันมาแล้วทั้งชุด การเปลี่ยนทรงให้คนที่ไม่ได้ขอคือการทำของที่ดีอยู่แล้วให้พัง
    func testNothingChangesShapeAtTheEverydayTextSizes() {
        for size: DynamicTypeSize in [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge] {
            XCTAssertFalse(BigTextLayout.pinsOnlyTheCancelButton(size),
                           "ขนาด \(size) ยังไม่ใช่ระดับ Accessibility ไม่ควรเปลี่ยนทรงแถบทางออก")
            XCTAssertFalse(BigTextLayout.stacksTrailConditions(size))
        }
    }

    /// ระดับ Accessibility ทั้งห้าขั้นต้องเปลี่ยนทรงทั้งหมด ไม่ใช่เฉพาะขั้นสุดท้าย
    func testEveryAccessibilitySizeGetsTheRoomyLayout() {
        for size: DynamicTypeSize in [.accessibility1, .accessibility2, .accessibility3,
                                      .accessibility4, .accessibility5] {
            XCTAssertTrue(BigTextLayout.pinsOnlyTheCancelButton(size),
                          "ขนาด \(size) ต้องเหลือปุ่มยกเลิกปักไว้ตัวเดียว")
            XCTAssertTrue(BigTextLayout.stacksTrailConditions(size),
                          "ขนาด \(size) ต้องเรียงอากาศ/AQI เป็นสองบรรทัด ไม่ใช่ตัดคำทิ้ง")
        }
    }

    // MARK: - จอต้องต่อกติกานี้เข้าไปจริง

    /// **ปุ่มยกเลิกต้องยังปักอยู่เสมอ** — เป็นปุ่มที่แพงที่สุดบนจอนี้ถ้าหาไม่เจอ
    /// (เคสที่ยกเลิกไม่ได้แปลว่าเจ้าหน้าที่ออกเดินไปหาคนที่ไม่ได้ต้องการความช่วยเหลือแล้ว)
    /// ส่วนที่เหลือของแถบย้ายลงไปอยู่ในส่วนที่เลื่อนได้เมื่อตัวอักษรใหญ่
    func testTheSOSScreenAdaptsItsPinnedBar() throws {
        let source = try source("WBW/SOS/SOSStatusView.swift")
        XCTAssertTrue(source.contains("dynamicTypeSize"),
                      "จอสถานะ SOS ไม่ได้อ่านขนาดตัวอักษร — แถบทางออกจะกินทั้งจอที่ขนาดใหญ่")
        XCTAssertTrue(source.contains("BigTextLayout.pinsOnlyTheCancelButton"),
                      "จอสถานะ SOS ไม่ได้ใช้กติกาเดียวกับที่เทสนี้ค้ำไว้")
    }

    func testTheTrailConditionsRowAdaptsInsteadOfTruncating() throws {
        let source = try source("WBW/Conditions/TrailConditionsRow.swift")
        XCTAssertTrue(source.contains("dynamicTypeSize"),
                      "แถวอากาศ/AQI ไม่ได้อ่านขนาดตัวอักษร — ค่าจะถูกตัดด้วย … ที่ขนาดใหญ่")
        XCTAssertTrue(source.contains("BigTextLayout.stacksTrailConditions"))
    }
}
