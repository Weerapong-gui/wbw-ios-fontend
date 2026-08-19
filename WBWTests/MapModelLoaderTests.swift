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
}
