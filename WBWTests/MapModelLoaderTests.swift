import XCTest
@testable import WBW

/// เงื่อนไขการคืนหน่วยความจำของโมเดลแผนที่ 10 MB
///
/// ไม่แตะตัว `Entity` จริงเลย — เทสยูนิตรันในโปรเซสเดียวกับแอปและโหลด usdz แล้ว `exit()` ทันที
/// เสี่ยง segfault (เหตุผลเดียวกับที่ `Map3DScreen.shouldRender` กันไว้ ดู Map3DConfigTests)
/// ที่ทดสอบได้คือกฎว่า "ตอนไหนปล่อยได้" ซึ่งเป็นข้อที่ผิดแล้วเห็นเป็นจอว่างโดยไม่มี error
final class MapModelLoaderTests: XCTestCase {

    /// ปล่อยตอนแท็บแผนที่เปิดอยู่ = entity ที่แขวนอยู่ในฉากที่กำลังเรนเดอร์หายไปกลางคัน
    /// บนจอเห็นเป็นแผนที่หายเฉย ๆ ไม่มี error ไม่มี log ไม่มีอะไรฟ้อง
    func testNeverReleasesWhileTheMapTabIsOnScreen() {
        XCTAssertFalse(MapModelLoader.shouldRelease(inUse: true),
                       "ปล่อยตอนจอเปิดอยู่แล้วแผนที่จะหายไปเฉย ๆ")
    }

    /// ระบบเตือนความจำตอนผู้ใช้อยู่แท็บอื่น = จังหวะที่ปล่อยได้จริง รอบหน้าที่เข้าแท็บ
    /// จอโหลด (`isLoading` ใน Map3DScreen) รับหน้าที่ต่อเองอยู่แล้ว
    func testReleasesWhenNobodyIsLookingAtTheMap() {
        XCTAssertTrue(MapModelLoader.shouldRelease(inUse: false))
    }

    /// **เทสถดถอยของ crash จริง (2026-08-20)** — `preload()` เคยโหลด map.usdz ตอนรันเทสด้วย
    /// พอเทสจบโปรเซส exit() ขณะที่คิว live-scene-update ของ RealityKit ยังไล่ USD stage อยู่
    /// ได้ EXC_BAD_ACCESS ใน `TfToken` · โปรเซสตายหลังรายงานผลเทสไปแล้ว มันจึงไม่ทำให้เทสแดง
    /// สักตัว เห็นได้จาก crash report อย่างเดียว
    @MainActor
    func testPreloadDoesNothingWhileUnitTestsAreRunning() {
        XCTAssertTrue(Map3DScreen.isRunningUnderXCTest,
                      "เทสชุดนี้ต้องมองเห็นตัวเองว่ารันอยู่ใต้ XCTest ไม่งั้นข้อล่างไม่ได้พิสูจน์อะไร")
        MapModelLoader.shared.preload()
        XCTAssertFalse(MapModelLoader.shared.isBusy,
                       "preload() เริ่มโหลด usdz ระหว่างเทส — โปรเซสจะ segfault ตอน exit")
    }
}
