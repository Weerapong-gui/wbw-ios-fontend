import XCTest
@testable import WBW

/// จอ SU RUN เคยเป็น `Color.clear` ว่างสนิทไม่มีตัวหนังสือเลยสักตัว — App Review กดครบทุกแท็บเสมอ
/// แล้วจะเจอแท็บที่ไม่ทำอะไร ซึ่งเข้าข่าย Guideline 4.2 (minimum functionality) รอบ 1.0 (7) โดนตีกลับ
/// ด้วย 2.1 กับ 2.3.3 ไปแล้ว แท็บว่างคือใบต่อไปที่รออยู่
///
/// ตอนนี้จอมีของจริงแล้ว (แผนที่เส้นทาง + จับระยะ/ก้าว) เทสชุดนี้จึงเหลือหน้าที่เดียว: กันไม่ให้ใคร
/// ถอยกลับไปเป็นจอเปล่าหรือการ์ด "เร็ว ๆ นี้" อีก โดยเห็นเทสแดงพร้อมเหตุผล แทนที่จะรู้ตอนโดนตีกลับ
final class SURunCopyTests: XCTestCase {

    func testTitleIsNotEmpty() {
        XCTAssertFalse(SURunView.title.isEmpty,
                       "แท็บ SU RUN ต้องมีข้อความบอกว่าจอนี้คืออะไร ห้ามกลับไปเป็นจอว่าง")
    }

    func testTitleNamesTheTrail() {
        XCTAssertEqual(SURunView.title, "เส้นทางเดินรอบดอย")
    }

    /// จอนี้ต้องมี "ของจริง" ให้ดูโดยไม่ต้องล็อกอินหรือรอ backend — เส้นทางมากับแอป ไม่ได้ยิงขอ
    func testTrailIsAvailableWithoutNetwork() {
        XCTAssertNotNil(TrailRoute.bundled,
                        "เส้นทางต้องอ่านได้จากไฟล์ในแอป ไม่งั้นแท็บนี้จะว่างเปล่าเมื่อไม่มีเน็ต")
    }
}
