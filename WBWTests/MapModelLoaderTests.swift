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

    /// **ธงเมฆต้องถูกล้างพร้อมโมเดล** — `releaseIfPossible()` ทิ้ง entity ที่ถืออยู่ โมเดลรอบหน้า
    /// จึงเป็น entity ใหม่ที่ยังไม่เคยถูกสั่ง `playAnimation` เลย ถ้าธงค้าง true ข้ามมา
    /// `Map3DScreen` จะข้ามลูปสั่งแอนิเมชันไปตลอดกาล — เมฆแข็งค้างถาวรตั้งแต่ memory warning
    /// ครั้งแรก โดยไม่มี error ไม่มี log ไม่มีอะไรฟ้องเลย · ทั้งกฎนี้แขวนอยู่กับโค้ดบรรทัดเดียว
    /// ที่ใครมา refactor ก็ลบทิ้งได้โดยไม่มีอะไรแดง เทสตัวนี้คือสิ่งที่จะแดงแทน
    ///
    /// เรียก `releaseIfPossible()` ตรง ๆ ได้เพราะใต้ XCTest ทั้ง `loaded`/`loading` เป็น nil อยู่แล้ว
    /// (`preload()` ไม่เคยเริ่มงานจริง ดูเทสข้างล่าง) จึงไม่มี `Entity` ตัวไหนถูกแตะ
    @MainActor
    func testReleasingTheModelClearsTheCloudAnimationFlag() {
        let loader = MapModelLoader.shared
        // singleton ตัวเดียวกับที่เทสอื่นในโปรเซสนี้ใช้ — คืนค่าทุกตัวที่แตะ ไม่งั้นลำดับการรัน
        // เปลี่ยนเมื่อไหร่เทสอื่นพังตามแบบไล่ต้นเหตุไม่เจอ
        let wasInUse = loader.isInUse
        let hadStartedClouds = loader.hasStartedCloudAnimations
        defer {
            loader.isInUse = wasInUse
            loader.hasStartedCloudAnimations = hadStartedClouds
        }

        loader.isInUse = false
        loader.hasStartedCloudAnimations = true
        loader.releaseIfPossible()

        XCTAssertFalse(loader.hasStartedCloudAnimations,
                       "โมเดลรอบหน้าเป็น entity ใหม่ — ธงค้าง true แปลว่าเมฆแข็งค้างถาวร")
    }

    /// อีกด้านของกฎเดียวกัน: ไม่ปล่อยโมเดล = ไม่ล้างธง · entity ตัวเดิมยังอยู่และแอนิเมชันยังเล่นอยู่
    /// ล้างธงทั้งที่ไม่ได้ปล่อยจะทำให้รอบหน้าสั่ง `playAnimation` ทับของที่กำลังเล่น เมฆกระตุกกลับ
    /// เฟรม 0 ซึ่งเป็นบั๊กที่ธงตัวนี้ถูกใส่มาเพื่อแก้ตั้งแต่แรก
    @MainActor
    func testKeepingTheModelKeepsTheCloudAnimationFlag() {
        let loader = MapModelLoader.shared
        let wasInUse = loader.isInUse
        let hadStartedClouds = loader.hasStartedCloudAnimations
        defer {
            loader.isInUse = wasInUse
            loader.hasStartedCloudAnimations = hadStartedClouds
        }

        loader.isInUse = true
        loader.hasStartedCloudAnimations = true
        loader.releaseIfPossible()

        XCTAssertTrue(loader.hasStartedCloudAnimations,
                      "ไม่ได้ปล่อยโมเดล แต่ล้างธง — รอบหน้าจะสั่งแอนิเมชันทับของที่กำลังเล่นอยู่")
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
