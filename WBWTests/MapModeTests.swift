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

    /// **ค่าเริ่มต้นคือ 2 มิติ** — โหมดที่เปิดแท็บมาแล้วใช้ได้ทันที
    ///
    /// 3 มิติต้องรอโมเดล 9.8 MB โหลดก่อนถึงจะเห็นอะไรนอกจากตัวหมุน (13 วิบนเครื่องจริง) และมันตอบ
    /// คำถามคนละข้อกับที่คนเปิดแท็บแผนที่ถาม — "เส้นทางไปทางไหน ฉันอยู่ตรงไหนของเส้น" เป็นคำถาม
    /// ของแผนที่ 2 มิติ ส่วน "ฐานหน้าตายังไง" เป็นของ 3 มิติซึ่งกดสลับเอาได้
    ///
    /// **สกรีนช็อต `02-map` ที่ส่ง App Store ไปแล้วยังเป็นจอ 3 มิติ** — ต้องถ่ายใหม่ก่อน archive
    /// รอบหน้า ไม่งั้นคือ Guideline 2.3.3 ซ้ำรอย 1.0 (7) ที่ส่งรูปไม่ตรงกับแอป · จดค้างไว้แล้วที่
    /// `docs/appstore/connect-checklist.md`
    func testDefaultModeIsFlatSoTheTabIsUsableTheMomentItOpens() {
        XCTAssertEqual(MapMode.stored(in: freshDefaults()), .flat)
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

    /// ค่าที่อ่านไม่ออก (คนแก้ด้วยมือ หรือคีย์ชนกับของเก่า) ต้องตกกลับเป็นค่าเริ่มต้น ไม่ใช่พังทั้งแท็บ
    func testUnknownStoredValueFallsBackToTheDefault() {
        let defaults = freshDefaults()
        defaults.set("hologram", forKey: MapMode.storageKey)
        XCTAssertEqual(MapMode.stored(in: defaults), .flat)
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

    /// แฟลกถ่ายภาพต้องชนะค่าที่ผู้ใช้เลือกไว้ — ไม่งั้นเครื่องที่เคยกดสลับโหมดจะถ่ายได้แต่โหมดนั้น
    ///
    /// เคยพังจริง: แฟลกถูกอ่านใน `onAppear` ของแผนที่ 3 มิติ ซึ่งไม่ถูก mount เมื่อเปิดมาที่ 2 มิติ
    /// สั่ง `-uitestMapMode 3d` แล้วได้ 2 มิติกลับมาเงียบ ๆ
    func testLaunchArgumentBeatsTheStoredChoice() {
        let defaults = freshDefaults()
        MapMode.flat.store(in: defaults)
        defaults.set("3d", forKey: "uitestMapMode")
        XCTAssertEqual(MapMode.initialForLaunch(in: defaults), .threeD)
    }

    /// แฟลกที่พิมพ์ผิดต้องถูกมองข้าม ไม่ใช่ลากทั้งจอไปโหมดที่ไม่มีอยู่
    func testUnknownLaunchArgumentFallsBackToTheStoredChoice() {
        let defaults = freshDefaults()
        MapMode.threeD.store(in: defaults)
        defaults.set("isometric", forKey: "uitestMapMode")
        XCTAssertEqual(MapMode.initialForLaunch(in: defaults), .threeD)
    }
}
