import XCTest
@testable import WBW

/// โหมดของแท็บแผนที่ — 3 มิติ (โมเดล `map.usdz`) กับ 2 มิติ (MapKit) · ยกปุ่มสลับมาจาก
/// `ui/map/MapScreen.kt` ของ Android ที่มีสวิตช์ตัวนี้อยู่แล้ว
final class MapModeTests: XCTestCase {

    private func freshDefaults(_ name: String = #function) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "MapModeTests.\(name)")!
        defaults.removePersistentDomain(forName: "MapModeTests.\(name)")
        return defaults
    }

    /// **ค่าเริ่มต้นต้องเป็น 3 มิติ** — สกรีนช็อต `02-map` ที่ส่ง App Store ไปแล้วเป็นจอ 3D
    /// เปลี่ยนค่านี้เมื่อไหร่ต้องถ่ายสกรีนช็อตใหม่ก่อนส่งรอบหน้า ไม่งั้นคือ Guideline 2.3.3
    /// ซ้ำรอยรอบ 1.0 (7) ที่ส่งรูปไม่ตรงกับแอป
    func testDefaultModeIsThreeDBecauseTheShippedScreenshotShowsIt() {
        XCTAssertEqual(MapMode.stored(in: freshDefaults()), .threeD)
    }

    /// เลือกแล้วต้องจำ — สลับไป 2 มิติแล้วออกจากแท็บ กลับมาต้องยังเป็น 2 มิติ
    /// ไม่ใช่เด้งกลับ 3 มิติทุกครั้งที่แตะแท็บอื่น
    func testChosenModeSurvivesLeavingTheTab() {
        let defaults = freshDefaults()
        MapMode.flat.store(in: defaults)
        XCTAssertEqual(MapMode.stored(in: defaults), .flat)

        MapMode.threeD.store(in: defaults)
        XCTAssertEqual(MapMode.stored(in: defaults), .threeD)
    }

    /// ค่าที่อ่านไม่ออก (คนแก้ด้วยมือ หรือคีย์ชนกับของเก่า) ต้องตกกลับเป็น 3 มิติ ไม่ใช่พังทั้งแท็บ
    func testUnknownStoredValueFallsBackToThreeD() {
        let defaults = freshDefaults()
        defaults.set("hologram", forKey: MapMode.storageKey)
        XCTAssertEqual(MapMode.stored(in: defaults), .threeD)
    }

    func testTogglingGoesBackAndForth() {
        XCTAssertEqual(MapMode.threeD.toggled(), .flat)
        XCTAssertEqual(MapMode.flat.toggled(), .threeD)
    }

    /// **ปุ่มบอกโหมดที่จะไป ไม่ใช่โหมดที่อยู่** — ทรงเดียวกับ Android
    /// (`if (is3d) map_mode_2d else map_mode_3d`) · ป้ายที่บอกโหมดปัจจุบันจะอ่านเป็น
    /// "ตอนนี้คุณอยู่โหมดนี้" แล้วคนกดเพราะคิดว่ากดเพื่ออยู่ต่อ
    func testToggleLabelNamesTheModeYouAreGoingTo() {
        XCTAssertEqual(MapMode.threeD.toggleLabelKey, "map_mode_2d")
        XCTAssertEqual(MapMode.flat.toggleLabelKey, "map_mode_3d")
    }

    /// คีย์ข้อความทั้งสองใบต้องมีจริงในชุดคีย์ ไม่ใช่ชื่อที่พิมพ์ลอย ๆ ในโค้ด — คีย์ที่หายไม่ทำให้
    /// build พัง ผู้ใช้จะเห็นชื่อคีย์บนปุ่มแทน (กติกาข้อ 10 ของ SKILL.md)
    func testToggleLabelKeysExistInTheStringsTable() {
        for key in [MapMode.threeD.toggleLabelKey, MapMode.flat.toggleLabelKey] {
            XCTAssertNotEqual(Loc.t(key), key, "คีย์ \(key) ไม่มีในชุดคีย์")
        }
    }
}
