import XCTest
@testable import WBW

/// สวิตช์ปิดฉากป่า 3D — ตรรกะเดียวที่ตัดสินว่าจอที่ขอฉากจะได้ฉากจริงไหม
/// (ดู docs/superpowers/specs/2026-08-07-forest-3d-off-design.md)
final class ForestSceneHostTests: XCTestCase {

    func testClaimsOnlyWhenForest3DOnAndNotUnderTest() {
        XCTAssertTrue(ForestSceneHost.shouldClaim(forest3D: true, underTest: false),
                      "ฉากเปิดและไม่ได้รันเทส — จอต้องได้ฉากจริง")
    }

    func testDoesNotClaimWhenForest3DOff() {
        XCTAssertFalse(ForestSceneHost.shouldClaim(forest3D: false, underTest: false),
                       "ฉากถูกปิดที่ Config.forest3D — ห้าม claim ไม่ว่ากรณีไหน")
    }

    func testDoesNotClaimUnderTestEvenWhenForest3DOn() {
        XCTAssertFalse(ForestSceneHost.shouldClaim(forest3D: true, underTest: true),
                       "เทสยูนิตรันในโปรเซสเดียวกับแอป โหลด usdz แล้ว exit() ทันทีจะ segfault")
    }

    func testDoesNotClaimWhenBothOff() {
        XCTAssertFalse(ForestSceneHost.shouldClaim(forest3D: false, underTest: true))
    }
}
