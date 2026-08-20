import XCTest
@testable import WBW

/// สวิตช์เปิด/ปิดโมเดลแผนที่ 3D — ตรรกะเดียวที่ตัดสินว่าแท็บ Map จะโหลดโมเดลจริงไหม
/// (ทรงเดียวกับ ForestSceneHost.shouldClaim ดู WBWTests/ForestSceneHostTests.swift)
final class Map3DConfigTests: XCTestCase {

    func testRendersWhenOnAndNotUnderTest() {
        XCTAssertTrue(Map3DScreen.shouldRender(map3D: true, underTest: false),
                      "เปิดสวิตช์และไม่ได้รันเทส — ต้องโหลดโมเดลจริง")
    }

    func testDoesNotRenderWhenSwitchedOff() {
        XCTAssertFalse(Map3DScreen.shouldRender(map3D: false, underTest: false),
                       "ปิดที่ Config.map3D — ห้ามโหลดโมเดลไม่ว่ากรณีไหน")
    }

    func testDoesNotRenderUnderTestEvenWhenOn() {
        XCTAssertFalse(Map3DScreen.shouldRender(map3D: true, underTest: true),
                       "เทสยูนิตรันในโปรเซสเดียวกับแอป โหลด usdz 9.8 MB แล้ว exit() ทันทีเสี่ยง segfault")
    }

    func testDoesNotRenderWhenBothOff() {
        XCTAssertFalse(Map3DScreen.shouldRender(map3D: false, underTest: true))
    }
}
